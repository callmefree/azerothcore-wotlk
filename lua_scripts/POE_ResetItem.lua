-- POE_ResetItem.lua
-- 后悔石：单节点重置道具
-- 物品ID 70000，玩家使用后列出已点节点，选择后重置

local ITEM_ID = 70000  -- 后悔石物品ID（临时Demo用）

-- 右键使用后悔石
local function OnResetItemUse(event, player, item, target)
    local learned = POE_Data.LoadPlayerTalents(player:GetGUID())
    
    -- 统计已点节点数
    local count = 0
    for _ in pairs(learned) do count = count + 1 end

    if count == 0 then
        player:SendBroadcastMessage("|cffff4444[星盘] 你还没有点亮任何节点|r")
        return true
    end

    -- 显示已点节点菜单
    local gossip = player:CreateGossipMenu()
    gossip:AddText("|cffffcc00选择要重置的节点:|r")
    for nodeId, _ in pairs(learned) do
        local node = POE_Data.GetNodeData(nodeId)
        if node then
            gossip:AddMenuItem(nodeId, node.name .. "（当前已激活）", 0)
        end
    end
    gossip:SendToPlayer(player)
    return true
end

-- 从重置菜单中选择节点后的回调
local function OnPlayerGossipSelect(event, player, sender, action, gossipId)
    -- gossipId 等于 ITEM_ID 时说明这是从后悔石触发的菜单
    if gossipId ~= ITEM_ID then return false end

    local nodeId = action
    local node = POE_Data.GetNodeData(nodeId)
    if not node then return true end

    -- 1. 移除效果
    POE_EffectHandler.RemoveEffects(player, nodeId)
    -- 2. 删除数据库记录
    CharDBExecute("DELETE FROM character_poe_talents WHERE character_guid = " .. player:GetGUID() .. " AND node_id = " .. nodeId)
    -- 3. 归还天赋点
    local currentPoints = 0
    local result = CharDBQuery("SELECT poe_talent_points FROM characters WHERE guid = " .. player:GetGUID())
    if result then currentPoints = result:GetUInt16("poe_talent_points") end
    CharDBExecute("UPDATE characters SET poe_talent_points = " .. (currentPoints + node.cost) .. " WHERE guid = " .. player:GetGUID())
    -- 4. 消耗物品
    if player:RemoveItem(ITEM_ID, 1) then
        player:SendBroadcastMessage("|cff00ff00[星盘] 节点 " .. node.name .. " 已重置，返还 " .. node.cost .. " 天赋点|r")
    else
        player:SendBroadcastMessage("|cffff4444[星盘] 物品消耗失败|r")
    end
    player:GossipComplete()
    return true
end

-- 注册物品使用事件（2 = ITEM_EVENT_ON_USE）
RegisterItemEvent(ITEM_ID, 2, OnResetItemUse)
-- 注册玩家Gossip选择事件
RegisterPlayerGossipEvent(ITEM_ID, 1, OnPlayerGossipSelect)
