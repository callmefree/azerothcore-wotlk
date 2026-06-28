-- POE_ResetItem.lua
-- 后悔石：单节点重置消耗品

local ITEM_ID = 70000

local function OnResetItemUse(event, player, item, target)
    local learned = POE_Data.LoadPlayerTalents(player:GetGUID())
    local count = 0
    for nodeId, _ in pairs(learned) do
        local node = POE_Data.GetNodeData(nodeId)
        if node and node.node_type ~= "start" then
            count = count + 1
        end
    end

    if count == 0 then
        player:SendBroadcastMessage("|cffff4444[星盘] 你还没有可以重置的非起点节点|r")
        return true
    end

    local gossip = player:CreateGossipMenu(ITEM_ID)
    gossip:AddText("|cffffcc00选择要重置的节点:|r")
    for _, nodeId in ipairs(POE_Data.NodeList) do
        if learned[nodeId] then
            local node = POE_Data.GetNodeData(nodeId)
            if node and node.node_type ~= "start" then
                gossip:AddMenuItem(nodeId, node.name .. "（当前已激活）", 0)
            end
        end
    end
    gossip:SendToPlayer(player)
    return true
end

local function OnPlayerGossipSelect(event, player, sender, action, gossipId)
    if gossipId ~= ITEM_ID then return false end

    local nodeId = tonumber(action) or 0
    local node = POE_Data.GetNodeData(nodeId)
    if not node or node.node_type == "start" then
        player:SendBroadcastMessage("|cffff4444[星盘] 起点节点不可重置|r")
        player:GossipComplete()
        return true
    end

    -- 先消耗物品（防白嫖）
    if not player:RemoveItem(ITEM_ID, 1) then
        player:SendBroadcastMessage("|cffff4444[星盘] 物品消耗失败|r")
        player:GossipComplete()
        return true
    end

    -- 移除该节点效果
    POE_EffectHandler.RemoveEffects(player, nodeId)

    -- 删除数据库记录
    CharDBExecute("DELETE FROM character_poe_talents WHERE character_guid = " .. player:GetGUID() .. " AND node_id = " .. nodeId)

    -- 返还天赋点
    local currentPoints = POE_Data.GetTalentPoints(player) or 0
    POE_Data.SetTalentPoints(player, currentPoints + node.cost)

    player:SendBroadcastMessage("|cff00ff00[星盘] 节点 " .. node.name .. " 已重置，返还 " .. node.cost .. " 天赋点|r")
    player:GossipComplete()
    return true
end

RegisterItemEvent(ITEM_ID, 2, OnResetItemUse)
RegisterPlayerGossipEvent(ITEM_ID, 1, OnPlayerGossipSelect)
