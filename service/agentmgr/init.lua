local skynet = require "skynet"
local s = require "service"

-- 玩家状态
STATUS = {
    LOGIN = 2,     --登录中
    GAME = 3,      --游戏中
    LOGOUT = 4     --登出中
}

--玩家列表
local players = {}
--玩家类
function mgrplayer()
    local m = {
        playerid = nil, --玩家id
        node = nil,     --玩家对应的gateway和agent所在的节点
        agent = nil,    --玩家对应的agent服务的id
        status = nil,   --玩家状态
        gate = nil,     --玩家对应的gateway服务的id
    }
    return m
end

--注册远程调用-login服务向agentmgr请求登录（reqlogin）
s.resp.reqlogin = function(source, playerid, node, gate)
    local mplayer = players[playerid]
    --登录中状态或者登出中状态禁止登录
    if mplayer and mplayer.status == STATUS.LOGOUT then
        skynet.error("reqlogin fail, at status LOGOUT " .. playerid)
        return false
    end
    if mplayer and mplayer.status == STATUS.LOGIN then
        skynet.error("reqlogin fail, at status LOGIN " .. playerid)
        return false        
    end
    --如果已经在线，旧客户端下线，新客户端进行顶替
    if mplayer then  --等价mplayer and mplayer.status == STATUS.GAME
        local pnode = mplayer.node
        local pagent = mplayer.agent
        local pgate = mplayer.gate
        mplayer.status = STATUS.LOGOUT
        s.call(pnode, pagent, "kick")
        s.send(pnode, pagent, "exit")
        s.send(pnode, pgate, "send", playerid, {"kick","顶替下线"})
        s.call(pnode, pgate, "kick", playerid)
    end
    --上线
    local player = mgrplayer()
    player.playerid = playerid
    player.node = node
    player.gate = gate
    player.agent = nil            --agent需要请求nodemgr
    player.status = STATUS.LOGIN
    players[playerid] = player
    local agent = s.call(node, "nodemgr", "newservice", "agent", "agent", playerid) --等待nodemgr请求完成
    player.agent = agent
    player.status = STATUS.GAME
    return true, agent
end

--注册远程调用-由gateway服务向agentmgr发出请求，agentmgr会先发送kick让agent处理保存数据等事情，再发送exit让agent退出服务。由于保存数据需要一小段时间，因此mgrplayer会保留一小段时间的LOGOUT状态。
s.resp.reqkick = function(source, playerid, reason)
    local mplayer = players[playerid]
    if not mplayer then
        return false
    end
    
    if mplayer.status ~= STATUS.GAME then
        return false
    end

    local pnode = mplayer.node
    local pagent = mplayer.agent
    local pgate = mplayer.gate
    mplayer.status = STATUS.LOGOUT

    s.call(pnode, pagent, "kick") --等待agent处理保存数据等事情
    s.send(pnode, pagent, "exit") --让agent退出服务
    s.send(pnode, pgate, "kick", playerid) --请求gateway踢掉玩家
    players[playerid] = nil

    return true
end

s.start(...)