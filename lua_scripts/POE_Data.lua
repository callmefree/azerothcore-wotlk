-- POE_Data.lua
-- 星盘系统数据层：从DB加载节点/效果/绑定到内存缓存
-- v2: 加载 spell_id 用于隐藏光环系统

POE_Data = {}
POE_Data.Nodes = {}
POE_Data.Effects = {}
POE_Data.Bindings = {}

function POE_Data.LoadCache()
    -- 加载 poe_talent_nodes，connections 字段自动解析为数字表
    local nodeResult = WorldDBQuery("SELECT node_id, name, description, pos_x, pos_y, icon_id, max_rank, cost, connections, node_type FROM poe_talent_nodes")
    POE_Data.Nodes = {}
    if nodeResult then
        repeat
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

    -- 加载 poe_talent_effects（含 spell_id）
    local effectResult = WorldDBQuery("SELECT effect_id, script_name, param1, param2, spell_id FROM poe_talent_effects")
    POE_Data.Effects = {}
    if effectResult then
        repeat
            POE_Data.Effects[effectResult:GetUInt32("effect_id")] = {
                script = effectResult:GetString("script_name"),
                param1 = effectResult:GetInt32("param1"),
                param2 = effectResult:GetInt32("param2"),
                spell_id = effectResult:GetUInt32("spell_id")
            }
        until not effectResult:NextRow()
    end

    -- 加载 poe_node_effect_binding
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

function POE_Data.GetNodeData(nodeId)
    return POE_Data.Nodes[nodeId]
end

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

function POE_Data.ReloadCache()
    POE_Data.LoadCache()
    print("[POE] 星盘数据缓存已重载")
end

POE_Data.LoadCache()
