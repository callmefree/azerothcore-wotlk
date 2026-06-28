-- POE_Data.lua
-- 星盘系统数据层：从DB加载节点/效果/绑定到内存缓存
-- 全局表，供其他模块引用
POE_Data = {}
POE_Data.Nodes = {}
POE_Data.Effects = {}
POE_Data.Bindings = {}

-- 从 world 库加载全部节点定义
function POE_Data.LoadCache()
    -- 加载节点表 poe_talent_nodes
    local nodeResult = WorldDBQuery("SELECT node_id, name, description, pos_x, pos_y, icon_id, max_rank, cost, connections, node_type FROM poe_talent_nodes")
    POE_Data.Nodes = {}
    if nodeResult then
        repeat
            -- 解析 connections 逗号分隔字符串为数字表
            local connStr = nodeResult:GetString("connections")
            local connections = {}
            if connStr and connStr ~= "" then
                for id in string.gmatch(connStr, "(%d+)") do
                    table.insert(connections, tonumber(id))
                end
            end
            POE_Data.Nodes[nodeResult:GetUInt32("node_id")] = {
                id = nodeResult:GetUInt32("node_id"),
                name = nodeResult:GetString("name"),
                desc = nodeResult:GetString("description"),
                cost = nodeResult:GetUInt8("cost"),
                connections = connections,
                node_type = nodeResult:GetString("node_type"),
                max_rank = nodeResult:GetUInt8("max_rank")
            }
        until not nodeResult:NextRow()
    end

    -- 加载效果定义表 poe_talent_effects
    local effectResult = WorldDBQuery("SELECT effect_id, script_name, param1, param2 FROM poe_talent_effects")
    POE_Data.Effects = {}
    if effectResult then
        repeat
            POE_Data.Effects[effectResult:GetUInt32("effect_id")] = {
                script = effectResult:GetString("script_name"),
                param1 = effectResult:GetInt32("param1"),
                param2 = effectResult:GetInt32("param2")
            }
        until not effectResult:NextRow()
    end

    -- 加载绑定关系表 poe_node_effect_binding
    local bindResult = WorldDBQuery("SELECT node_id, effect_id FROM poe_node_effect_binding")
    POE_Data.Bindings = {}
    if bindResult then
        repeat
            local nodeId = bindResult:GetUInt32("node_id")
            local effectId = bindResult:GetUInt32("effect_id")
            if not POE_Data.Bindings[nodeId] then POE_Data.Bindings[nodeId] = {} end
            table.insert(POE_Data.Bindings[nodeId], effectId)
        until not bindResult:NextRow()
    end
end

-- 获取单个节点数据
function POE_Data.GetNodeData(nodeId)
    return POE_Data.Nodes[nodeId]
end

-- 获取节点绑定的所有效果
function POE_Data.GetNodeEffects(nodeId)
    local ids = POE_Data.Bindings[nodeId]
    if not ids then return {} end
    local effects = {}
    for _, eId in ipairs(ids) do
        if POE_Data.Effects[eId] then
            table.insert(effects, POE_Data.Effects[eId])
        end
    end
    return effects
end

-- 从 characters 库加载玩家已点节点
function POE_Data.LoadPlayerTalents(guid)
    local result = CharDBQuery("SELECT node_id, points_spent FROM character_poe_talents WHERE character_guid = " .. guid)
    local learned = {}
    if result then
        repeat
            learned[result:GetUInt32("node_id")] = result:GetUInt8("points_spent")
        until not result:NextRow()
    end
    return learned
end

-- 热重载入口（服务器运行中重新加载缓存）
function POE_Data.ReloadCache()
    POE_Data.LoadCache()
    print("[POE] 星盘数据缓存已重载")
end

-- 启动时初始化缓存
POE_Data.LoadCache()
