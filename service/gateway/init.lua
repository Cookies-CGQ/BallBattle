local skynet = require "skynet"
local s = require "service"
local socket = require "skynet.socket"
local runconfig = require "runconfig"

--连接信息
conns = {}   --fd : conn
--玩家信息
players = {} --playerid : gateplayer

--连接类
function conn()
    local m = {
        fd = nil,
        playerid = nil
    }
    return m
end

--玩家类
function gateplayer()
    local m = {
        playerid = nil,
        agent = nil,
        conn = nil
    }
    return m
end

--消息解码（消息字符串 -> 表）
local str_unpack = function(msgstr)
    local msg = {}

    while true do
        local arg, rest = string.match(msgstr, "(.-),(.*)")
        if arg then
            msgstr = rest
            table.insert(msg, arg)
        else
            table.insert(msg, msgstr)
            break
        end
    end

    return msg[1], msg
end

--消息编码（表 -> 消息字符串）
local str_pack = function(cmd, msg)
    return table.concat(msg, ",") .. "\r\n"
end

--注册远程调用-用于login服务的消息转发，功能是将消息发送到指定fd的客户端
s.resp.send_by_fd = function(source, fd, msg)
    if not conns[fd] then
        return
    end

    local buff = str_pack(msg[1], msg)
    skynet.error("send "..fd.." ["..msg[1].."] {"..table.concat(msg, ",").."}")
    socket.write(fd, buff)
end

--注册远程调用-用于agent的消息转发，功能是将消息发送给指定玩家id的客户端
s.resp.send = function(source, playerid, msg)
    local gplayer = players[playerid]
    if gplayer == nil then
        return
    end
    local c = gplayer.conn
    if c == nil then
        return
    end
    
    s.resp.send_by_fd(nil, c.fd, msg)
end

--注册远程调用-在完成了登录流程后，login会通知gateway，让它把客户端连接和新agent关联起来
s.resp.sure_agent = function(source, fd, playerid, agent) --playerid和agent只有login通知之后gateway才知道
    local conn = conns[fd]
    if not conn then --登录过程中已经下线
        skynet.call("agentmgr", "lua", "reqkick", playerid, "未完成登录即下线")
        return false
    end
 
    --确认玩家id
    conn.playerid = playerid
    --创建gateplayer对象
    local gplayer = gateplayer()
    gplayer.playerid = playerid
    gplayer.agent = agent
    gplayer.conn = conn
    players[playerid] = gplayer

    return true
end

--客户端掉线处理
local disconnect = function (fd)
    local c = conns[fd]
    if not c then
        return
    end

    local playerid = c.playerid
    --还没完成登录
    if not playerid then
        return
    --已在游戏中
    else
        players[playerid] = nil
        local reason = "断线"
        skynet.call("agentmgr", "lua", "reqkick", playerid, reason) --由agentmgr仲裁
    end
end

--注册远程调用-用于agentmgr通知gateway，让gateway把指定玩家id的客户端断开连接
s.resp.kick = function(source, playerid)
    --处理conns，players，close(fd)
    local gplayer = players[playerid]
    if not gplayer then
        return
    end

    local c = gplayer.conn
    players[playerid] = nil --删除
    
    if not c then
        return
    end
    conns[c.fd] = nil       --删除
    disconnect(c.fd)        --冗余，调用了没什么效果
    socket.close(c.fd)      --关闭连接
end

--消息处理
local process_msg = function(fd, msgstr)
    local cmd, msg = str_unpack(msgstr)
    skynet.error("recv " .. fd .. " [" .. cmd .. "] {" .. table.concat(msg, ",") .. "}")

    local conn = conns[fd]
    local playerid = conn.playerid
    --尚未完成登录流程
    if not playerid then
        local node = skynet.getenv("node")
        local nodecfg = runconfig[node]
        local loginid = math.random(1, #nodecfg.login) -- 随机选择一个login服务编号
        local login = "login" .. loginid -- login服务
        skynet.send(login, "lua", "client", fd, cmd, msg)
    --已经完成登录流程
    else
        local gplayer = players[playerid]
        local agent = gplayer.agent
        skynet.send(agent, "lua", "client", cmd, msg)
    end
end

--拆包处理消息
local process_buff = function(fd, readbuff)
    while true do
        local msgstr, rest = string.match(readbuff, "(.-)\r\n(.*)")
        if msgstr then
            readbuff = rest
            process_msg(fd, msgstr)
        else
            return readbuff
        end
    end
end

--每一条连接接收数据处理
--协议格式 cmd,arg1,arg2,...#
local recv_loop = function(fd)
    socket.start(fd)
    skynet.error("socket connected " .. fd)
    local readbuff = ""
    while true do
        local recvstr = socket.read(fd)
        if recvstr then
            readbuff = readbuff .. recvstr
            readbuff = process_buff(fd, readbuff)
        else
            skynet.error("socket close " .. fd)
            disconnect(fd)
            socket.close(fd)
            return
        end
    end
end

--当客户端新连接过来时
local connect = function(fd, addr)
    print("connect from " .. addr .. " fd-" .. fd)
    local c = conn()
    conns[fd] = c
    c.fd = fd
    skynet.fork(recv_loop, fd)
    --skynet.fork(func, ...) 的功能：在当前 Skynet 服务内创建一个新的 Lua 协程，并把它放入 fork 队列等待调度执行。它不是 Linux/Unix 的 fork()，不会创建新进程，也不会创建新的 Skynet 服务。
end

function s.init()
    skynet.error("[start]" .. s.name .. " " .. s.id)
    --获取配置信息
    local node = skynet.getenv("node")
    local nodecfg = runconfig[node]
    local port = nodecfg.gateway[s.id].port
    --gateway开启监听
    local listenfd = socket.listen("0.0.0.0", port)
    skynet.error("Listen socket: ", "0.0.0.0 ", port)
    socket.start(listenfd, connect)
end

s.start(...)