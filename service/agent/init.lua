local skynet = require "skynet"
local s = require "service"

s.client = {}
s.gate = nil

require "scene"

s.resp.client = function (source, cmd, msg)
    s.gate = source
    if s.client[cmd] then
        local ret_msg = s.client[cmd](msg, source)
        if ret_msg then
            skynet.send(source, "lua", "send", s.id, ret_msg)
        end
    else
        skynet.error("s.resp.client fail", cmd)
    end
end

--服务创建之后要数据加载
s.init = function ()
    --此处加载数据 - 可改为从数据库加载
    skynet.sleep(200) --模拟加载数据
    --保存
    s.data = {
        coin = 100,
        hp = 200
    }
end

--退出前保存数据
s.resp.kick = function (source)
    s.leave_scene()
    --此处保存数据 - 可改为保存到数据库
    skynet.sleep(200) --模拟保存数据   
end

--agent服务退出
s.resp.exit = function (source)
    skynet.exit()
end

--测试协议work
s.client.work = function (msg)
    s.data.coin = s.data.coin + 1
    return {"work", s.data.coin}
end

--scene调用agent的远程调用方法send给客户端发送消息
s.resp.send = function(source, msg)
    skynet.send(s.gate, "lua", "send", s.id, msg)
end

s.start(...)