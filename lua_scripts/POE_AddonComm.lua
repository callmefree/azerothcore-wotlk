-- POE_AddonComm.lua
-- 星盘客户端插件通信层
-- 通过 SendAddonMessage 与 WoW 客户端插件 POEStarMap 交互
-- 加载顺序：最后加载（依赖 POE_TalentManager 导出的函数）

local PREFIX_SMAP = "POE_SMAP"  -- Server -> Client 星盘数据
local PREFIX_SCMD = "POE_SCMD"  -- Client -> Server 玩家操作

-- 序列化节点数据为紧凑字符串
-- 格式: id|name|x|y|type|cost|conns|icon|classMask
local function SerializeNode(node)
    local connStr = #(node.connections or {}) > 0 and table.concat(node.connections, ",") or ""
    return string.format("%d|%s|%d|%d|%s|%d|%s|%d|%d",
        node.id, node.name or "", node.pos_x or 0, node.pos_y or 0,
        node.node_type or "small", node.cost or 1, connStr,
        node.icon_id or 0, node.class_mask or 0)
end

-- 发送完整星盘数据给客户端
function SendStarMap(player)
    -- 按 ID 顺序发送节点定义（每包20个）
    local batch, count = {}, 0
    for _, id in ipairs(POE_Data.NodeList) do
        local node = POE_Data.Nodes[id]
        if node then
            table.insert(batch, SerializeNode(node))
            count = count + 1
            if count % 20 == 0 then
                player:SendAddonMessage(PREFIX_SMAP, "NODES|" .. table.concat(batch, "\n"), 0)
                batch = {}
            end
        end
    end
    if #batch > 0 then
        player:SendAddonMessage(PREFIX_SMAP, "NODES|" .. table.concat(batch, "\n"), 0)
    end

    -- 玩家已学节点
    local learnedStr = ""
    for nid, rank in pairs(POE_Data.LoadPlayerTalents(player:GetGUID())) do
        learnedStr = learnedStr .. nid .. ":" .. rank .. ","
    end
    player:SendAddonMessage(PREFIX_SMAP, "LEARNED|" .. learnedStr, 0)

    -- 天赋点数
    player:SendAddonMessage(PREFIX_SMAP, "POINTS|" .. (POE_Data.GetTalentPoints(player) or 0), 0)
    player:SendAddonMessage(PREFIX_SMAP, "INIT_DONE|" .. count, 0)
end

-- 接收客户端命令
local function OnAddonMessage(event, player, prefix, message, channel, sender)
    if prefix ~= PREFIX_SCMD then return end

    local cmd, arg = message:match("^(%w+)%|?(.*)$")
    if not cmd then return end

    if cmd == "OPEN" then
        SendStarMap(player)
        return
    end

    if cmd == "LEARN" then
        local nodeId = tonumber(arg)
        if not nodeId then return end

        local learned = POE_Data.LoadPlayerTalents(player:GetGUID())
        local can, reason = POE_TalentManager.CanLearn(player, nodeId, learned)
        if not can then
            player:SendAddonMessage(PREFIX_SMAP, "LEARN_FAIL|" .. nodeId .. "|" .. reason, 0)
            return
        end

        local node = POE_Data.GetNodeData(nodeId)
        if not node then return end

        local pointsBefore = POE_Data.GetTalentPoints(player)
        local ok, err = pcall(function()
            POE_TalentManager.SaveTalent(player, nodeId)
            local newPoints = pointsBefore - node.cost
            if newPoints < 0 then error("天赋点不足") end
            POE_Data.SetTalentPoints(player, newPoints)
            POE_EffectHandler.ApplyEffects(player, nodeId)
        end)

        if ok then
            player:SendAddonMessage(PREFIX_SMAP, "LEARN_OK|" .. nodeId .. "|" .. node.name, 0)
            player:SendAddonMessage(PREFIX_SMAP, "POINTS|" .. POE_Data.GetTalentPoints(player), 0)
        else
            CharDBExecute("UPDATE character_poe_talents SET points_spent = points_spent - 1 WHERE character_guid = " .. player:GetGUID() .. " AND node_id = " .. nodeId)
            CharDBExecute("DELETE FROM character_poe_talents WHERE character_guid = " .. player:GetGUID() .. " AND node_id = " .. nodeId .. " AND points_spent <= 0")
            POE_Data.SetTalentPoints(player, pointsBefore)
            player:SendAddonMessage(PREFIX_SMAP, "LEARN_FAIL|" .. nodeId .. "|" .. tostring(err), 0)
        end
        return
    end

    if cmd == "RESET" then
        local nodeId = tonumber(arg)
        if not nodeId then return end

        local node = POE_Data.GetNodeData(nodeId)
        if not node or node.node_type == "start" then
            player:SendAddonMessage(PREFIX_SMAP, "RESET_FAIL|起点节点不可重置", 0)
            return
        end
        if not player:HasItem(70000, 1) then
            player:SendAddonMessage(PREFIX_SMAP, "RESET_FAIL|需要后悔石", 0)
            return
        end

        player:RemoveItem(70000, 1)
        POE_EffectHandler.RemoveEffects(player, nodeId)
        CharDBExecute("DELETE FROM character_poe_talents WHERE character_guid = " .. player:GetGUID() .. " AND node_id = " .. nodeId)
        local currentPoints = POE_Data.GetTalentPoints(player) or 0
        POE_Data.SetTalentPoints(player, currentPoints + node.cost)
        player:SendAddonMessage(PREFIX_SMAP, "RESET_OK|" .. nodeId .. "|" .. node.name, 0)
        player:SendAddonMessage(PREFIX_SMAP, "POINTS|" .. POE_Data.GetTalentPoints(player), 0)
        return
    end
end

-- 注册客户端消息事件
RegisterPlayerEvent(50, OnAddonMessage)
