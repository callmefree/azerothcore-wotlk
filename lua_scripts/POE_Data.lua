-- POE_Data.lua
-- 星盘系统数据层：从DB加载节点/效果/绑定到内存缓存
-- v2: 加载 spell_id 用于隐藏光环系统

POE_Data = {}
POE_Data.Nodes = {}
POE_Data.NodeList = {}
POE_Data.Effects = {}
POE_Data.Bindings = {}

function POE_Data.LoadAllNodes()
    local nodeResult = WorldDBQuery("SELECT node_id, name, description, pos_x, pos_y, icon_id, max_rank, cost, connections, node_type, class_mask FROM poe_talent_nodes")
    POE_Data.Nodes = {}
    POE_Data.NodeList = {}
    if nodeResult then
        repeat
            local connStr = nodeResult:GetString(8)       -- connections (col 8, 0-indexed)
            local connections = {}
            if connStr and connStr ~= "" then
                for id in string.gmatch(connStr, "(%d+)") do
                    table.insert(connections, tonumber(id))
                end
            end
            local nodeId = nodeResult:GetUInt32(0)        -- node_id (col 0)
            POE_Data.Nodes[nodeId] = {
                id = nodeId,
                name = nodeResult:GetString(1),           -- name
                desc = nodeResult:GetString(2),           -- description
                cost = nodeResult:GetUInt8(7),            -- cost
                connections = connections,
                node_type = nodeResult:GetString(9),      -- node_type
                max_rank = nodeResult:GetUInt8(6),        -- max_rank
                class_mask = nodeResult:GetUInt32(10) or 0 -- class_mask
            }
            table.insert(POE_Data.NodeList, nodeId)
        until not nodeResult:NextRow()
    end
end

function POE_Data.LoadAllEffects()
    local effectResult = WorldDBQuery("SELECT effect_id, script_name, param1, param2, spell_id FROM poe_talent_effects")
    POE_Data.Effects = {}
    if effectResult then
        repeat
            POE_Data.Effects[effectResult:GetUInt32(0)] = {        -- effect_id
                script = effectResult:GetString(1),                 -- script_name
                param1 = effectResult:GetInt32(2),                  -- param1
                param2 = effectResult:GetInt32(3),                  -- param2
                spell_id = effectResult:GetUInt32(4)                -- spell_id
            }
        until not effectResult:NextRow()
    end
end

function POE_Data.LoadAllBindings()
    local bindResult = WorldDBQuery("SELECT node_id, effect_id FROM poe_node_effect_binding")
    POE_Data.Bindings = {}
    if bindResult then
        repeat
            local nodeId = bindResult:GetUInt32(0)          -- node_id
            local effectId = bindResult:GetUInt32(1)         -- effect_id
            if not POE_Data.Bindings[nodeId] then POE_Data.Bindings[nodeId] = {} end
            table.insert(POE_Data.Bindings[nodeId], effectId)
        until not bindResult:NextRow()
    end
end

function POE_Data.LoadCache()
    POE_Data.LoadAllNodes()
    POE_Data.LoadAllEffects()
    POE_Data.LoadAllBindings()
end

function POE_Data.LoadPlayerTalents(guid)
    local result = CharDBQuery("SELECT node_id, points_spent FROM character_poe_talents WHERE character_guid = " .. guid)
    local learned = {}
    if result then
        repeat
            learned[result:GetUInt32(0)] = result:GetUInt8(1)
        until not result:NextRow()
    end
    return learned
end

function POE_Data.GetTalentPoints(player)
    local result = CharDBQuery("SELECT poe_talent_points FROM characters WHERE guid = " .. player:GetGUID())
    if result then return result:GetUInt16(0) end
    return 0
end

function POE_Data.SetTalentPoints(player, points)
    points = math.max(0, tonumber(points) or 0)
    CharDBExecute("UPDATE characters SET poe_talent_points = " .. points .. " WHERE guid = " .. player:GetGUID())
end
