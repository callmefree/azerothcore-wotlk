-- POE_TalentManager.lua
-- 星盘系统总机：Gossip菜单/加点/移除/登录恢复

local NPC_ENTRY = 200000  -- 星盘NPC的entry ID

-- ===== 天赋点工具函数 =====

local function GetTalentPoints(player)
    local result = CharDBQuery("SELECT poe_talent_points FROM characters WHERE guid = " .. player:GetGUID())
    if result then return result:GetUInt16("poe_talent_points") else return 0 end
end

local function SetTalentPoints(player, points)
    CharDBExecute("UPDATE characters SET poe_talent_points = " .. points .. " WHERE guid = " .. player:GetGUID())
end

local function SaveTalent(player, nodeId)
    CharDBExecute("INSERT INTO character_poe_talents (character_guid, node_id, points_spent) VALUES (" .. player:GetGUID() .. ", " .. nodeId .. ", 1) ON DUPLICATE KEY UPDATE points_spent = points_spent + 1")
end

local function RemoveTalent(player, nodeId)
    CharDBExecute("DELETE FROM character_poe_talents WHERE character_guid = " .. player:GetGUID() .. " AND node_id = " .. nodeId)
end

-- ===== 验证逻辑 =====

local function CanLearn(player, nodeId, learnedTalents)
    local node = POE_Data.GetNodeData(nodeId)
    if not node then return false, "节点不存在" end

    -- 起点：未学习时可免费激活
    if node.node_type == "start" and not learnedTalents[nodeId] then
        return true, ""
    end

    -- 已满级不可再点
    if learnedTalents[nodeId] and learnedTalents[nodeId] >= node.max_rank then
        return false, "该节点已满级"
    end

    -- 连接有效性：与任一已激活节点相连即可
    local connected = false
    for _, connId in ipairs(node.connections) do
        if learnedTalents[connId] then
            connected = true
            break
        end
    end
    if not connected then
        return false, "节点未解锁（需要相邻节点已点亮）"
    end

    -- 天赋点足够
    local points = GetTalentPoints(player)
    if points < node.cost then
        return false, "天赋点不足"
    end

    return true, ""
end

-- ===== Gossip 菜单 =====

local function OpenTalentMenu(player)
    local learned = POE_Data.LoadPlayerTalents(player:GetGUID())
    local points = GetTalentPoints(player)

    local gossip = player:CreateGossipMenu()
    gossip:AddText("|cffffcc00【星盘天赋系统】|r")
    gossip:AddText("剩余天赋点: |cff00ff00" .. points .. "|r")
    gossip:AddText("------------------")

    -- 遍历所有节点
    for id, node in pairs(POE_Data.Nodes) do
        local status = "|cff888888未解锁|r"
        if learned[id] then
            status = "|cff00ff00已激活|r"
        else
            local can, _ = CanLearn(player, id, learned)
            if can then status = "|cffffff00[可加点]|r" end
        end
        gossip:AddMenuItem(id, node.name .. " " .. status, 0)
    end

    gossip:AddMenuItem(999, "|cffff4444【重置所有天赋点】（测试用）|r", 1)
    gossip:SendToPlayer(player)
end

-- ===== 事件回调 =====

local function OnGossipHello(event, player, creature)
    if creature:GetEntry() ~= NPC_ENTRY then return false end
    OpenTalentMenu(player)
    return true
end

local function OnGossipSelect(event, player, creature, sender, action, gossipId)
    if creature:GetEntry() ~= NPC_ENTRY then return false end

    -- 全量重置（测试专用）
    if action == 999 then
        local learned = POE_Data.LoadPlayerTalents(player:GetGUID())
        for nodeId, _ in pairs(learned) do
            POE_EffectHandler.RemoveEffects(player, nodeId)
            RemoveTalent(player, nodeId)
        end
        SetTalentPoints(player, 10)
        player:SendBroadcastMessage("|cffff4444已重置所有天赋点，获得10点天赋点|r")
        OpenTalentMenu(player)
        return true
    end

    local nodeId = action
    local learned = POE_Data.LoadPlayerTalents(player:GetGUID())
    local can, reason = CanLearn(player, nodeId, learned)

    if can then
        local node = POE_Data.GetNodeData(nodeId)
        local cost = node.cost
        -- 先写库（优先确保数据持久化）
        SaveTalent(player, nodeId)
        -- 应用效果
        POE_EffectHandler.ApplyEffects(player, nodeId)
        -- 扣天赋点（起点 cost=0 不扣）
        if cost > 0 then
            SetTalentPoints(player, GetTalentPoints(player) - cost)
        end
        player:SendBroadcastMessage("|cff00ff00[星盘] 已点亮节点: |r" .. node.name)
    else
        player:SendBroadcastMessage("|cffff4444[星盘] |r" .. reason)
    end

    OpenTalentMenu(player)
    return true
end

-- 玩家登录时恢复已点效果
local function OnPlayerLogin(event, player)
    local learned = POE_Data.LoadPlayerTalents(player:GetGUID())
    local count = 0
    for nodeId, _ in pairs(learned) do
        POE_EffectHandler.ApplyEffects(player, nodeId)
        count = count + 1
    end
    if count > 0 then
        player:SendBroadcastMessage("|cff00ff00[星盘] 已恢复 " .. count .. " 个节点效果|r")
    end
end

-- ===== 注册事件 =====
RegisterCreatureGossipEvent(NPC_ENTRY, 1, OnGossipHello)
RegisterCreatureGossipEvent(NPC_ENTRY, 2, OnGossipSelect)
RegisterPlayerEvent(3, OnPlayerLogin)
