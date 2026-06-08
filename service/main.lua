local skynet = require "skynet"
local skynet_manager = require "skynet.manager" -- skynet.name()
local runconfig = require "runconfig"
local cluster = require "skynet.cluster"

skynet.start(function ()
    --确认节点
    local mynode = skynet.getenv("node")
    local nodecfg = runconfig[mynode]
    --节点管理服务
    local nodemgr = skynet.newservice("nodemgr", "nodemgr", 0)
    skynet.name("nodemgr", nodemgr)
    --集群
    cluster.reload(runconfig.cluster)
    cluster.open(mynode)
    --gate服务
    for i,v in pairs(nodecfg.gateway or {}) do
        local srv = skynet.newservice("gateway", "gateway", i)
        skynet.name("gateway"..i, srv)
    end
    --login服务
    for i,v in pairs(nodecfg.login or {}) do
        local srv = skynet.newservice("login", "login", i)
        skynet.name("login"..i, srv)
    end
    --agentmgr服务
    local anode = runconfig.agentmgr.node --agentmgr服务所在的节点
    --如果agentmgr服务在本节点
    if mynode == anode then
        local srv = skynet.newservice("agentmgr", "agentmgr", 0)
        skynet.name("agentmgr", srv)
    --如果agentmgr服务不在本节点，那就创建代理服务
    else
        local proxy = cluster.proxy(anode, "agentmgr")
        skynet.name("agentmgr", proxy)
    end
    --退出自身服务
    skynet.exit()
end)