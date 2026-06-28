-- POE_CombatEvents.lua
-- 战斗事件钩子：处理伤害修正、触发机制、击杀效果
-- 依赖: POE_EffectHandler.PlayerMods
-- 加载顺序: 应在 POE_EffectHandler.lua 之后、POE_TalentManager.lua 之前

-- 伤害修正事件：应用各种伤害加成、转化、触发
local function OnDamageDealt(event, player, victim, damage, damageType, school)
    local mods = POE_EffectHandler.PlayerMods[player:GetGUID()]
    if not mods then return damage end

    local modified = damage

    -- 1. 学派伤害百分比修正（TalentEffect_ModDamagePercent）
    for s, pct in pairs(mods.schoolMods or {}) do
        modified = modified + math.floor(damage * pct / 100)
    end

    -- 2. 点燃触发（TalentEffect_IgniteChance）
    if (mods.igniteChance or 0) > 0 and school > 0 then
        if math.random(1, 100) <= mods.igniteChance then
            victim:SetAuraStack(23267, victim, 1)
        end
    end

    -- 3. 击杀触发效果累积
    if mods._killCounter then
        mods._killCounter = mods._killCounter + 1
    end

    return modified
end

-- 玩家击杀怪物 — 触发类效果
local function OnPlayerKill(event, player, victim)
    local mods = POE_EffectHandler.PlayerMods[player:GetGUID()]
    if not mods then return end

    -- 重置击杀计数器
    mods._killCounter = 0

    -- 检查是否有击杀触发类效果
    if mods.onKillBuffs then
        for _, trigger in ipairs(mods.onKillBuffs) do
            if math.random(1, 100) <= trigger.chance then
                player:AddAura(trigger.spellId, player)
            end
        end
    end

    -- "近期击杀" 标记（用于 condition: OnRecentKill）
    mods._lastKillTime = os.time()
end

-- 玩家登出清理缓存
local function OnPlayerLogout(event, player)
    POE_EffectHandler.PlayerMods[player:GetGUID()] = nil
end

-- 注册战斗事件
RegisterPlayerEvent(7, OnDamageDealt)   -- PLAYER_EVENT_ON_DAMAGE_DEALT
RegisterPlayerEvent(9, OnPlayerKill)    -- PLAYER_EVENT_ON_KILL
RegisterPlayerEvent(4, OnPlayerLogout)  -- PLAYER_EVENT_ON_LOGOUT
