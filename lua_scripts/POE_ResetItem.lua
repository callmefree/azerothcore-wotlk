-- POE_ResetItem.lua
-- 修复：菜单ID显式设置 + 过滤掉起点节点 + SQL注入防御

local ITEM_ID = 70000

local function GetTalentPoints(player)
    local result = CharDBQuery("SELECT poe_talent_points FROM characters WHERE guid = " .. player:GetGUID())
    return (result and result:GetUInt16("poe_talent_points")) or 0
end

local function SetTalentPoints(player, points)
    CharDBExecute("UPDATE characters SET poe_talent_points = " .. tonumber(points) .. " WHERE guid = " .. player:GetGUID())
end

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

    -- 显式设置 gossipId 为 ITEM_ID，确保 OnPlayerGossipSelect 能正确匹配
    local gossip = player:CreateGossipMenu(ITEM_ID)
    gossip:AddText("|cffffcc00选择要重置的节点:|r")
    for nodeId, _ in pairs(learned) do
        local node = POE_Data.GetNodeData(nodeId)
        if node and node.node_type ~= "start" then
            gossip:AddMenuItem(nodeId, node.name .. "（当前已激活）", 0)
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

    -- 重算属性（移除节点效果）
    POE_EffectHandler.RefreshAllStats(player)

    -- 删除数据库记录
    CharDBExecute("DELETE FROM character_poe_talents WHERE character_guid = " .. player:GetGUID() .. " AND node_id = " .. nodeId)

    -- 返还天赋点
    SetTalentPoints(player, GetTalentPoints(player) + node.cost)

    -- 消耗物品
    if player:RemoveItem(ITEM_ID, 1) then
        player:SendBroadcastMessage("|cff00ff00[星盘] 节点 " .. node.name .. " 已重置，返还 " .. node.cost .. " 天赋点|r")
    else
        player:SendBroadcastMessage("|cffff4444[星盘] 物品消耗失败|r")
    end
    player:GossipComplete()
    return true
end

RegisterItemEvent(ITEM_ID, 2, OnResetItemUse)
RegisterPlayerGossipEvent(ITEM_ID, 1, OnPlayerGossipSelect)
