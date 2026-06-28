-- POE_EffectHandler.lua
-- 基于隐藏光环（Passive Aura）的效果执行器
-- 属性叠加由魔兽引擎原生管理，Lua 只做 AddAura/RemoveAura

POE_EffectHandler = {}
local EffectRegistry = {}

function POE_EffectHandler.RegisterEffect(name, func)
    EffectRegistry[name] = func
end

-- 应用节点效果（正向：添加光环）
function POE_EffectHandler.ApplyEffects(player, nodeId)
    local effects = POE_Data.GetNodeEffects(nodeId)
    for _, e in ipairs(effects) do
        local func = EffectRegistry[e.script]
        if func then
            func(player, e, true)
        else
            print("[POE] 警告: 未注册的效果脚本 " .. e.script)
        end
    end
end

-- 移除节点效果（反向：移除光环）
function POE_EffectHandler.RemoveEffects(player, nodeId)
    local effects = POE_Data.GetNodeEffects(nodeId)
    for _, e in ipairs(effects) do
        local func = EffectRegistry[e.script]
        if func then
            func(player, e, false)
        else
            print("[POE] 警告: 未注册的效果脚本 " .. e.script)
        end
    end
end

-- 通用属性加成（支持 DBC 光环和直接修改两种模式）
POE_EffectHandler.RegisterEffect("TalentEffect_StatPlus", function(player, e, isApply)
    if e.spell_id and e.spell_id > 0 then
        -- v2 模式：DBC 隐藏光环（需手动创建 spell.dbc 条目）
        if isApply then
            local success = player:AddAura(e.spell_id, player)
            if not success then
                print("[POE] 添加光环失败: spell_id=" .. e.spell_id)
            end
        else
            player:RemoveAura(e.spell_id)
        end
    else
        -- 回退模式：直接修改基础属性（无需 DBC）
        local statId = e.param1  -- 1=STR, 2=AGI, 3=STA, 5=INT, 6=SPI
        local amount = e.param2
        local current = player:GetBaseStat(statId)
        if isApply then
            player:SetBaseStat(statId, current + amount)
        else
            player:SetBaseStat(statId, current - amount)
        end
    end
end)

-- 学习/移除技能（node_type='skill'）
POE_EffectHandler.RegisterEffect("TalentEffect_LearnSpell", function(player, e, isApply)
    if e.spell_id == 0 then
        print("[POE] 警告: LearnSpell 缺少 spell_id")
        return
    end
    if isApply then
        player:LearnSpell(e.spell_id)
    else
        player:RemoveSpell(e.spell_id)
    end
end)

-- ===== 事件驱动的伤害/效果修正系统 =====

POE_EffectHandler.PlayerMods = {}  -- guid -> {schoolMods={}, igniteChance=0}

-- 伤害百分比修正（param1=学派掩码, param2=百分比）
POE_EffectHandler.RegisterEffect("TalentEffect_ModDamagePercent", function(player, e, isApply)
    local guid = player:GetGUID()
    if not POE_EffectHandler.PlayerMods[guid] then
        POE_EffectHandler.PlayerMods[guid] = { schoolMods = {}, igniteChance = 0 }
    end
    local mods = POE_EffectHandler.PlayerMods[guid]
    local school = e.param1
    local pct = e.param2
    if isApply then
        mods.schoolMods[school] = (mods.schoolMods[school] or 0) + pct
    else
        mods.schoolMods[school] = (mods.schoolMods[school] or 0) - pct
        if mods.schoolMods[school] <= 0 then mods.schoolMods[school] = nil end
    end
end)

-- 点燃几率（param1=几率百分比, param2=预留）
POE_EffectHandler.RegisterEffect("TalentEffect_IgniteChance", function(player, e, isApply)
    local guid = player:GetGUID()
    if not POE_EffectHandler.PlayerMods[guid] then
        POE_EffectHandler.PlayerMods[guid] = { schoolMods = {}, igniteChance = 0 }
    end
    if isApply then
        POE_EffectHandler.PlayerMods[guid].igniteChance = (POE_EffectHandler.PlayerMods[guid].igniteChance or 0) + e.param1
    else
        POE_EffectHandler.PlayerMods[guid].igniteChance = math.max(0, (POE_EffectHandler.PlayerMods[guid].igniteChance or 0) - e.param1)
    end
end)

-- 玩家造成伤害事件 — 应用伤害修正
local function OnDamageDealt(event, player, victim, damage, damageType, school)
    local guid = player:GetGUID()
    local mods = POE_EffectHandler.PlayerMods[guid]
    if not mods then return damage end

    local modified = damage
    -- 各学派伤害修正（school 是学派掩码，param1 是单个学派ID）
    for s, pct in pairs(mods.schoolMods) do
        modified = modified + math.floor(damage * pct / 100)
    end

    -- 点燃触发（仅对法术伤害生效）
    if mods.igniteChance and mods.igniteChance > 0 and school > 0 then
        if math.random(1, 100) <= mods.igniteChance then
            -- 对目标施加点燃 DOT
            victim:SetAuraStack(23267, victim, 1)
        end
    end

    return modified
end

-- 玩家登出时清理缓存
local function OnPlayerLogout(event, player)
    POE_EffectHandler.PlayerMods[player:GetGUID()] = nil
end

-- 注册全局事件
RegisterPlayerEvent(7, OnDamageDealt)   -- 7 = PLAYER_EVENT_ON_DAMAGE_DEALT
RegisterPlayerEvent(4, OnPlayerLogout)  -- 4 = PLAYER_EVENT_ON_LOGOUT

-- 登录恢复：遍历已点节点，统一应用光环
function POE_EffectHandler.RestoreOnLogin(player)
    local learned = POE_Data.LoadPlayerTalents(player:GetGUID())
    local count = 0
    for nodeId, _ in pairs(learned) do
        POE_EffectHandler.ApplyEffects(player, nodeId)
        count = count + 1
    end
    if count > 0 then
        player:SendBroadcastMessage("|cff00ff00[星盘] 已恢复 " .. count .. " 个节点光环效果|r")
    end
end
