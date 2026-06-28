-- POEStarMap.lua
-- 流放艾泽拉斯星盘客户端插件
-- WoW 3.3.5a (WotLK)
-- 与服务端 POE_AddonComm.lua 配合使用

POEStarMapDB = POEStarMapDB or {}

local frame = _G.POEStarMapFrame
local nodesContainer = _G.POEStarMapNodes
local PREFIX_SEND = "POE_SCMD"  -- Client -> Server
local PREFIX_RECV = "POE_SMAP"  -- Server -> Client

-- 星盘状态
local state = {
    nodes = {},          -- nodeId -> {id, name, x, y, type, cost, conns, icon, classMask}
    learned = {},        -- nodeId -> rank
    points = 0,
    buttons = {},        -- nodeId -> Button
    lines = {},          -- {fromButton, toButton, texture}
    initialized = false,
}

-- 节点颜色
local COLORS = {
    learned = { r = 0.2, g = 1.0, b = 0.2 },      -- 绿色已学
    canLearn = { r = 1.0, g = 0.8, b = 0.0 },      -- 金色可加
    locked = { r = 0.4, g = 0.4, b = 0.4 },         -- 灰色锁定
    start = { r = 0.3, g = 0.8, b = 1.0 },          -- 蓝色起点
    skill = { r = 1.0, g = 0.4, b = 0.4 },          -- 红色技能
    notable = { r = 1.0, g = 0.6, b = 0.0 },         -- 橙色核心
    keystone = { r = 1.0, g = 0.2, b = 0.8 },        -- 紫色基石
    lineLearned = { r = 0.2, g = 1.0, b = 0.2, a = 0.6 },
    lineLocked = { r = 0.3, g = 0.3, b = 0.3, a = 0.4 },
}

-- ===== 工具函数 =====

local function GetNodeColor(nodeId, nodeType, isLearned, canLearn)
    if isLearned then
        return COLORS.learned
    end
    if canLearn then
        return COLORS.canLearn
    end
    if nodeType == "start" then return COLORS.start end
    if nodeType == "skill" then return COLORS.skill end
    if nodeType == "notable" then return COLORS.notable end
    if nodeType == "keystone" then return COLORS.keystone end
    return COLORS.locked
end

local function GetNodeSize(nodeType)
    if nodeType == "keystone" then return 32 end
    if nodeType == "notable" then return 26 end
    if nodeType == "skill" then return 24 end
    if nodeType == "start" then return 28 end
    return 18  -- small
end

-- ===== 绘制连线 =====

local function DrawLines()
    for _, line in ipairs(state.lines) do
        line.texture:Hide()
        line.texture:SetParent(nil)
    end
    state.lines = {}

    for nodeId, node in pairs(state.nodes) do
        local btnA = state.buttons[nodeId]
        if not btnA then return end
        for _, connId in ipairs(node.conns or {}) do
            local btnB = state.buttons[connId]
            if btnB and nodeId < connId then  -- 每条线只画一次
                local tex = nodesContainer:CreateTexture(nil, "OVERLAY")
                tex:SetTexture(1, 1)  -- 纯色纹理
                local isLearned = state.learned[nodeId] and state.learned[connId]
                local color = isLearned and COLORS.lineLearned or COLORS.lineLocked
                tex:SetVertexColor(color.r, color.g, color.b, color.a)

                local x1, y1 = btnA:GetCenter()
                local x2, y2 = btnB:GetCenter()
                local dx, dy = x2 - x1, y2 - y1
                local len = math.sqrt(dx * dx + dy * dy)

                tex:SetPoint("CENTER", btnA, "CENTER", dx / 2, dy / 2)
                tex:SetWidth(len)
                tex:SetHeight(3)

                local angle = math.atan2(dy, dx)
                tex:SetRotation(angle)

                tinsert(state.lines, { texture = tex, from = nodeId, to = connId })
            end
        end
    end
end

-- ===== 创建节点按钮 =====

local function CreateNodeButton(node, isLearned, canLearn)
    local color = GetNodeColor(node.id, node.node_type, isLearned, canLearn)
    local size = GetNodeSize(node.node_type)

    local btn = CreateFrame("Button", nil, nodesContainer)
    btn:SetWidth(size)
    btn:SetHeight(size)

    -- 实际坐标映射：node.pos_x * 100 + 50, node.pos_y * 100 + 50
    local px = node.x * 80 + 100
    local py = node.y * 80 + 100
    btn:SetPoint("CENTER", nodesContainer, "BOTTOMLEFT", px, py)

    -- 圆形背景
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\UI-RaidFrame-PVP-Alliance")

    -- 节点名字标签
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetText(node.name)
    label:SetPoint("BOTTOM", btn, "TOP", 0, 2)

    -- 节点类型标记
    btn.nodeId = node.id
    btn.nodeType = node.node_type

    -- 点击学习
    btn:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            -- 发送加点请求
            SendAddonMessage(PREFIX_SEND, "LEARN|" .. self.nodeId, "GUILD")
        end
    end)

    -- 右键重置
    btn:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            SendAddonMessage(PREFIX_SEND, "RESET|" .. self.nodeId, "GUILD")
        end
    end)

    -- Tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(node.name, 1, 1, 1)
        if node.desc then
            GameTooltip:AddLine(node.desc, 0.8, 0.8, 0.8, 1)
        end
        GameTooltip:AddLine("")
        local status = isLearned and "|cff00ff00已激活|r" or (canLearn and "|cffffff00可加点 (左键)|r" or "|cff888888未解锁|r")
        GameTooltip:AddLine(status)
        GameTooltip:AddLine("|cff888888右键重置 (需后悔石)|r")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    state.buttons[node.id] = btn
    return btn
end

-- ===== 渲染星盘 =====

local function RenderStarMap()
    -- 清除旧按钮
    for _, btn in pairs(state.buttons) do
        btn:Hide()
        btn:SetParent(nil)
    end
    state.buttons = {}

    -- 遍历节点创建按钮
    for nodeId, node in pairs(state.nodes) do
        local isLearned = state.learned[nodeId] ~= nil
        -- 简化判断能否学习（客户端估算，实际由服务端校验）
        local canLearn = not isLearned and state.points >= (node.cost or 1)
        CreateNodeButton(node, isLearned, canLearn)
    end

    -- 绘制连线
    DrawLines()

    -- 更新标题
    _G.POEStarMapTitle:SetText("|cffffcc00流放艾泽拉斯 — 天赋星盘|r")
    _G.POEStarMapPoints:SetText("|cff00ff00剩余天赋点: " .. state.points .. "|r    |cff888888左键加点 / 右键重置|r")
end

-- ===== 通信处理 =====

function POEStarMap_OnEvent(event, arg1, arg2, arg3, arg4, arg5)
    if event == "CHAT_MSG_ADDON" then
        local prefix, msg, channel, sender = arg1, arg2, arg3, arg4
        if prefix ~= PREFIX_RECV then return end

        local cmd, data = msg:match("^(%w+)%|?(.*)$")
        if not cmd then return end

        if cmd == "NODES" then
            -- 解析节点数据
            for line in data:gmatch("([^\n]+)") do
                local id, name, x, y, ntype, cost, conns, icon, cmask = line:match("^(%d+)%|([^|]*)%|(-?%d+)%|(-?%d+)%|([^|]*)%|(%d+)%|([^|]*)%|(%d+)%|(%d+)$")
                if id then
                    local connList = {}
                    if conns and conns ~= "" then
                        for cid in conns:gmatch("(%d+)") do
                            tinsert(connList, tonumber(cid))
                        end
                    end
                    state.nodes[tonumber(id)] = {
                        id = tonumber(id),
                        name = name,
                        x = tonumber(x),
                        y = tonumber(y),
                        node_type = ntype,
                        cost = tonumber(cost),
                        conns = connList,
                        icon = tonumber(icon),
                        classMask = tonumber(cmask),
                    }
                end
            end

        elseif cmd == "LEARNED" then
            -- 解析已学节点
            state.learned = {}
            for pair in data:gmatch("(%d+:%d+),?") do
                local nid, rank = pair:match("(%d+):(%d+)")
                if nid then
                    state.learned[tonumber(nid)] = tonumber(rank)
                end
            end

        elseif cmd == "POINTS" then
            state.points = tonumber(data) or 0

        elseif cmd == "INIT_DONE" then
            state.initialized = true
            RenderStarMap()

        elseif cmd == "LEARN_OK" then
            local nid, name = data:match("^(%d+)%|(.+)$")
            if nid then
                state.learned[tonumber(nid)] = 1
                RenderStarMap()
            end

        elseif cmd == "LEARN_FAIL" then
            local nid, reason = data:match("^(%d+)%|(.+)$")
            if reason then
                UIErrorsFrame:AddMessage("|cffff4444[星盘] " .. reason, 1, 0, 0)
            end

        elseif cmd == "RESET_OK" then
            local nid = data:match("^(%d+)")
            if nid then
                state.learned[tonumber(nid)] = nil
                RenderStarMap()
            end

        elseif cmd == "RESET_FAIL" then
            UIErrorsFrame:AddMessage("|cffff4444[星盘] " .. data, 1, 0, 0)
        end
    end
end

-- ===== 开关星盘 =====

function POEStarMap_Toggle()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

-- ===== 初始化 =====

function POEStarMap_OnLoad()
    frame:RegisterEvent("CHAT_MSG_ADDON")
    -- 注册通信前缀（WotLK 3.3.5a+）
    RegisterAddonMessagePrefix(PREFIX_SEND)
    RegisterAddonMessagePrefix(PREFIX_RECV)

    -- 快捷键：Alt+S 打开星盘
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "S" and IsAltKeyDown() then
            POEStarMap_Toggle()
        end
    end)

    -- 请求服务端数据
    C_Timer.After(2, function()
        SendAddonMessage(PREFIX_SEND, "OPEN", "GUILD")
    end)

    -- 创建聊天命令
    SLASH_POE1 = "/poemap"
    SlashCmdList["POE"] = function()
        POEStarMap_Toggle()
    end
    SLASH_POESTAR1 = "/poestar"
    SlashCmdList["POESTAR"] = function()
        POEStarMap_Toggle()
    end

    frame:SetPropagateKeyboardInput(true)
    frame:EnableKeyboard(true)
    print("|cff00ff00[星盘] 已加载 — 输入 /poemap 或按 Alt+S 打开星盘|r")
end
