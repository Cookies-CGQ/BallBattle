local skynet = require "skynet"
local s = require "service"

--balls表
local balls = {} --key: playerid; value：ball对象

--ball类
function ball()
    local m = {
        playerid = nil,              --玩家id
        node = nil,                  --agent所在节点
        agent = nil,                 --玩家关联的agent
        x = math.random(0, 100),     --进入战斗场景随机x坐标
        y = math.random(0, 100),     --进入战斗场景随机y坐标
        size = 2,                    --初始化球大小
        speedx = 0,                  --球x方向速度
        speedy = 0                   --球y方向速度
    }
    return m
end

--球列表-收集战场中的所有小球，并构建balllist协议
--协议："balllist",playerid,x,y,size,playerid,x,y,size,...
local function balllist_msg()
    local msg = {"balllist"}
    for i,v in pairs(balls) do
        table.insert(msg, v.playerid)
        table.insert(msg, v.x)
        table.insert(msg, v.y)
        table.insert(msg, v.size)
    end
    return msg
end

--foods表
local foods = {} --key: id； value：food对象
local food_maxid = 0
local food_count = 0

--food类
function food()
    local m = {
        id = nil,
        x = math.random(0, 100),
        y = math.random(0, 100)
    }
    return m
end

--食物列表-收集战场中的所有食物，并构建foodlist协议
--协议："foodlist",id,x,y,id,x,y,...
local function foodlist_msg()
    local msg = {"foodlist"}
    for i,v in pairs(foods) do
        table.insert(msg, v.id)
        table.insert(msg, v.x)
        table.insert(msg, v.y)
    end
    return msg
end

--广播
function broadcast(msg)
    for i, v in pairs(balls) do
        s.send(v.node, v.agent, "send", msg)
    end
end

--注册远程调用-agent服务向scene服务发起请求，玩家进入战斗场景
s.resp.enter = function (source, playerid, agent, node)
    --判断能否进入战斗场景，如果已经在当前战斗场景，就不可再次加入，返回进入失败信息
    if balls[playerid] then
        return false
    end    
    --创建ball对象并关联玩家agent
    local b = ball()
    b.playerid = playerid
    b.agent = agent
    b.node = node
    --向战场内的其他玩家广播enter协议，说明新的玩家到来
    local entermsg = {"enter", playerid, b.x, b.y, b.size}
    broadcast(entermsg)
    --将ball对象加入balls表 
    balls[playerid] = b
    --向请求进入的玩家回应成功进入的信息
    local ret_msg = {"enter", 0, "进入成功"}
    s.send(node, b.agent, "send", ret_msg)
    --向请求进入的玩家发送战场信息
    s.send(node, b.agent, "send", balllist_msg())
    s.send(node, b.agent, "send", foodlist_msg())
    
    return true
end

--注册远程调用-agent服务向scene服务发起请求，玩家掉线退出战斗场景
s.resp.leave = function (source, playerid)
    if not balls[playerid] then
        return false
    end
    --删除ball对象
    balls[playerid] = nil
    --广播leave协议，说明玩家离开战场
    local leavemsg = {"leave", playerid}
    broadcast(leavemsg)
end

--注册远程调用-agent服务向scene服务发起请求，玩家请求改变移动方向
s.resp.shift = function (source, playerid, x, y)
    local b = balls[playerid]
    if not b then
        return false
    end
    b.speedx = x
    b.speedy = y
end

--位置更新
function move_update()
    for i,v in pairs(balls) do
        v.x = v.x + v.speedx * 0.2
        v.y = v.y + v.speedy * 0.2
        if v.speedx ~= 0 or v.speedy ~= 0 then
            local msg = {"move", v.playerid, v.x, v.y}
            broadcast(msg)
        end
    end
end

--生成食物
function food_update()
    --需要对食物总量进行限制 - 最多50
    if food_count > 50 then
        return
    end
    --控制生成时间-概率生成，统计平均下来每10秒生成一个食物
    if math.random(1,100) < 98 then
        return
    end
    --生成食物
    food_maxid = food_maxid + 1
    food_count = food_count + 1
    local f = food()    --坐标已经随机生成
    f.id = food_maxid 
    foods[f.id] = f

    local msg = {"addfood", f.id, f.x, f.y}
    broadcast(msg)
end

--碰撞检测-吞下食物
function eat_update()
    for pid, b in pairs(balls) do
        for fid, f in pairs(foods) do
            --吃掉
            if (b.x - f.x) ^ 2 + (b.y - f.y) ^ 2 < b.size ^ 2 then
                b.size = b.size + 1
                food_count = food_count - 1
                foods[fid] = nil
                local msg = {"eat", b.playerid, fid, b.size}
                broadcast(msg)
            end
        end
    end
end

--服务端主循环单次状态更新-每隔0.2s调用更新状态。
--frame表示当前的帧数，每一次执行update后frame+1
function update(frame)
    food_update()    --食物生成
    move_update()    --位置更新
    eat_update()     --碰撞检测
end

--服务初始化时开启一个死循环协程，协程中调用updat，定时器功能使用协程搭配skynet.sleep实现让他等待一小段时间
s.init = function ()
    --保持帧率执行
    local stime = skynet.now()
    local frame = 0
    while true do
        frame = frame + 1
        local isok, err = pcall(update, frame)
        if not isok then
            skynet.error(err)
        end
        local etime = skynet.now()
        local waittime = frame * 20 - (etime - stime)
        if waittime <= 0 then
            waittime = 2
        end
        skynet.sleep(waittime)
    end
end