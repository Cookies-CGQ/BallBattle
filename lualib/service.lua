local skynet = require "skynet"
local cluster = require "skynet.cluster"

local M = {
    --类型和id
    name = "",
    id = 0,
    --回调函数
    exit = nil,
    init = nil,
    --分发方法
    resp = {},
}

--输出错误信息回调
function traceback(err)
    skynet.error(tostring(err))         -- 输出错误信息
    skynet.error(debug.traceback())     -- 输出调用栈信息
end

--消息分发回调
local dispatch = function (session, address, cmd, ...)
    local fun = M.resp[cmd]
    --如果没找到cmd直接返回
    if not fun then         
        skynet.ret() --skynet.ret(msg, sz) 是 Skynet 底层回包接口，用于把一段已经打包好的消息返回给当前 skynet.call 的调用方。
        return
    end
    --安全调用cmd并将返回值打包成表
    local ret = table.pack(xpcall(fun, traceback, address, ...))
    local isok = ret[1]
    --如果调用失败直接返回
    if not isok then
        skynet.ret()
        return
    end
    --调用成功
    skynet.retpack(table.unpack(ret,2)) --skynet.retpack(...) 的作用是：把多个 Lua 返回值打包成 Skynet 消息包，并作为当前请求的响应返回给调用方（skynet.call）。skynet.retpack(...) 等价于 skynet.ret(skynet.pack(...))
end

--初始化回调
function init()
    skynet.dispatch("lua", dispatch)
    if M.init then
        M.init()
    end
end

-- 开启服务，对skynet.start的简易封装。服务启动后，Skynet会调用init方法，由它调用skynet.dispatch实现消息的路由，再调用上层的M.init()。
function M.start(name, id)
    M.name = name
    M.id = tonumber(id)
    skynet.start(init)
end

--封装skynet.call，屏蔽同一节点和不同节点服务之间的通信。程序先用skynet.getenv获取当前节点，如果接收方在同个节点，则调用skynet.call；如果在不同节点，则调用cluster.call。
--参数 node: 服务所在节点；srv：服务
function M.call(node, srv, ...)
    local mynode = skynet.getenv("node")
    --同节点内服务通信
    if node == mynode then
       return skynet.call(srv, "lua", ...)
    --不同节点服务通信
    else
       return cluster.call(node, srv, ...)        
    end
end

--封装skynet.send，屏蔽同一节点和不同节点服务之间的通信。程序先用skynet.getenv获取当前节点，如果接收方在同个节点，则调用skynet.send；如果在不同节点，则调用cluster.send。
--参数 node: 服务所在节点；srv：服务
function M.send(node, srv, ...)
    local mynode = skynet.getenv("node")
    if node == mynode then
        return skynet.send(srv, "lua", ...)
    else
        return cluster.send(node, srv, ...)
    end
end

return M