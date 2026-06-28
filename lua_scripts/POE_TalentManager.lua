-- POE_TalentManager.lua
-- 星盘系统总机：Gossip菜单/加点/移除/登录恢复/GM命令

local NPC_ENTRY = 200000  -- 星盘NPC的entry ID

-- 职业掩码映射（WoW 职业ID → 位掩码）
local CLASS_MASK = {
    [1] = 1,      -- 战士
    [2] = 2,      -- 圣骑
    [3] = 4,      -- 猎人
    [4] = 8,      -- 盗贼
    [5] = 16,     -- 牧师
    [6] = 32,     -- 死骑
    [7] = 64,     -- 萨满
    [8] = 128,    -- 法师
    [9] = 256,    -- 术士
    [10] = 512,   -- 小德
    [11] = 1024,  -- 武僧
    [12] = 2048,  -- 恶魔猎手
}

local function GetPlayerClassMask(player)
    local classId = player:GetClass()
    return CLASS_MASK[classId] or 0
end

-- ===== 天赋点工具函数 =====

local function GetTalentPoints(player)
    return POE_Data.GetTalentPoints(player) or 0
end

local function SetTalentPoints(player, points)
    POE_Data.SetTalentPoints(player, points)
end

local function SaveTalent(player, nodeId)
    local nid = tonumber(nodeId) or 0
    CharDBExecute("INSERT INTO character_poe_talents (character_guid, node_id, points_spent) VALUES (" .. player:GetGUID() .. ", " .. nid .. ", 1) ON DUPLICATE KEY UPDATE points_spent = points_spent + 1")
end

local function RemoveTalent(player, nodeId)
    local nid = tonumber(nodeId) or 0
    CharDBExecute("DELETE FROM character_poe_talents WHERE character_guid = " .. player:GetGUID() .. " AND node_id = " .. nid)
end

-- ===== 验证逻辑 =====

local function CanLearn(player, nodeId, learnedTalents)
    local node = POE_Data.GetNodeData(nodeId)
    if not node then return false, "节点不存在" end

    -- 职业限制：class_mask>0 的节点仅对对应职业可见/可学
    if node.class_mask and node.class_mask > 0 then
        if node.class_mask ~= GetPlayerClassMask(player) then
            return false, "职业不符"
        end
    end

    -- 起点：未学习时可免费激活
    if node.node_type == "start" and not learnedTalents[nodeId] then
        return true, ""
    end

    -- 已满级不可再点
    if learnedTalents[nodeId] and learnedTalents[nodeId] >= node.max_rank then
        return false, "该节点已满级"
    end

    -- 连接有效性：起点节点首次免费激活跳过，其他节点必须与已激活节点相连
    if node.node_type ~= "start" or learnedTalents[nodeId] then
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

    -- 遍历所有节点（按 NodeList 有序遍历，按职业过滤）
    local playerMask = GetPlayerClassMask(player)
    for _, id in ipairs(POE_Data.NodeList) do
        local node = POE_Data.Nodes[id]
        -- 过滤职业专属节点
        if node.class_mask and node.class_mask > 0 and node.class_mask ~= playerMask then
            -- 跳过
        else
            local status = "|cff888888未解锁|r"
            if learned[id] then
                status = "|cff00ff00已激活|r"
            else
                local can, _ = CanLearn(player, id, learned)
                if can then status = "|cffffff00[可加点]|r" end
            end
            local icon = ""
            if node.node_type == "skill" then icon = "|T135128:0|t " end
            if node.node_type == "start" then icon = "|T132347:0|t " end
            gossip:AddMenuItem(id, icon .. node.name .. " " .. status, 0)
        end
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

    -- 强制转换 action 为数字，防止 SQL 注入
    local nodeId = tonumber(action) or 0
    if nodeId == 0 then return true end

    -- 全量重置（测试专用）
    if nodeId == 999 then
        local learned = POE_Data.LoadPlayerTalents(player:GetGUID())
        local spentPoints = 0
        for nid, _ in pairs(learned) do
            local node = POE_Data.GetNodeData(nid)
            if node then spentPoints = spentPoints + node.cost end
            POE_EffectHandler.RemoveEffects(player, nid)
            RemoveTalent(player, nid)
        end
        -- 动态计算：当前可用点 = 已有点数 + 已花点数
        local currentPoints = GetTalentPoints(player)
        SetTalentPoints(player, currentPoints + spentPoints)
        player:SendBroadcastMessage("|cffff4444已重置所有天赋点，返还 " .. spentPoints .. " 点|r")
        OpenTalentMenu(player)
        return true
    end

    -- 加点事务（pcall 保护）
    local learned = POE_Data.LoadPlayerTalents(player:GetGUID())
    local can, reason = CanLearn(player, nodeId, learned)

    if not can then
        player:SendBroadcastMessage("|cffff4444[星盘] |r" .. reason)
        OpenTalentMenu(player)
        return true
    end

    local node = POE_Data.GetNodeData(nodeId)
    if not node then return true end

    local pointsBefore = GetTalentPoints(player)

    local success, err = pcall(function()
        SaveTalent(player, nodeId)
        local newPoints = pointsBefore - node.cost
        if newPoints < 0 then
            error("天赋点不足（事务内检查）")
        end
        SetTalentPoints(player, newPoints)
        POE_EffectHandler.ApplyEffects(player, nodeId)
    end)

    if not success then
        -- 递减等级回滚（非直接删除，避免 max_rank>1 时丢失早期等级）
        CharDBExecute("UPDATE character_poe_talents SET points_spent = points_spent - 1 WHERE character_guid = " .. player:GetGUID() .. " AND node_id = " .. nodeId)
        CharDBExecute("DELETE FROM character_poe_talents WHERE character_guid = " .. player:GetGUID() .. " AND node_id = " .. nodeId .. " AND points_spent <= 0")
        SetTalentPoints(player, pointsBefore)
        player:SendBroadcastMessage("|cffff4444[星盘] 加点失败，系统已自动回滚。|r")
        print("[POE] 加点错误: " .. tostring(err))
    else
        player:SendBroadcastMessage("|cff00ff00[星盘] 已点亮节点: |r" .. node.name)
    end

    OpenTalentMenu(player)
    return true
end

-- 玩家登录时恢复已点光环
local function OnPlayerLogin(event, player)
    POE_EffectHandler.RestoreOnLogin(player)
end

-- 玩家升级时自动获得天赋点
local function OnPlayerLevelUp(event, player, oldLevel)
    local points = oldLevel or player:GetLevel() - 1
    -- 每级获得1点天赋，累计
    local current = GetTalentPoints(player)
    SetTalentPoints(player, current + 1)
    player:SendBroadcastMessage("|cff00ff00[星盘] 升级奖励：获得1点天赋（当前: " .. (current + 1) .. "）|r")
end

-- ===== GM 命令（合并分发器）=====

local function OnCommand(event, player, command)
    -- .poe reload — 热重载天赋数据
    if string.find(command, "poe reload") then
        POE_Data.LoadAllNodes()
        POE_Data.LoadAllEffects()
        POE_Data.LoadAllBindings()
        print("[POE] 天赋数据已热重载")
        player:SendBroadcastMessage("|cff00ff00[星盘] 数据已重载|r")
        return true
    end

    -- .poe addpoints N — 给当前玩家加天赋点
    if string.find(command, "^poe addpoints ") then
        local amount = tonumber(string.match(command, "^poe addpoints (%d+)"))
        if not amount or amount <= 0 then
            player:SendBroadcastMessage("|cffff4444用法: .poe addpoints <数量>|r")
            return true
        end
        local current = GetTalentPoints(player)
        SetTalentPoints(player, current + amount)
        player:SendBroadcastMessage("|cff00ff00[星盘] 已添加 " .. amount .. " 天赋点（当前: " .. (current + amount) .. "）|r")
        return true
    end

    return false
end

-- ===== 注册事件 =====
RegisterCreatureGossipEvent(NPC_ENTRY, 1, OnGossipHello)
RegisterCreatureGossipEvent(NPC_ENTRY, 2, OnGossipSelect)
RegisterPlayerEvent(3, OnPlayerLogin)
RegisterPlayerEvent(12, OnPlayerLevelUp)  -- 12 = PLAYER_EVENT_ON_LEVEL_CHANGE
RegisterPlayerEvent(42, OnCommand)
