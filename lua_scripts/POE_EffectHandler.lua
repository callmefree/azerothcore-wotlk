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

-- 初始化/获取玩家修饰表
function POE_EffectHandler.GetMods(player)
    local guid = player:GetGUID()
    if not POE_EffectHandler.PlayerMods[guid] then
        POE_EffectHandler.PlayerMods[guid] = {
            schoolMods = {},
            igniteChance = 0,
            onKillBuffs = {},
            moveSpeedPct = 0,
            castSpeedPct = 0,
        }
    end
    return POE_EffectHandler.PlayerMods[guid]
end

-- 伤害百分比修正（param1=学派ID, param2=百分比）
POE_EffectHandler.RegisterEffect("TalentEffect_ModDamagePercent", function(player, e, isApply)
    local mods = POE_EffectHandler.GetMods(player)
    local school = e.param1
    local pct = e.param2
    if isApply then
        mods.schoolMods[school] = (mods.schoolMods[school] or 0) + pct
    else
        mods.schoolMods[school] = (mods.schoolMods[school] or 0) - pct
        if mods.schoolMods[school] <= 0 then mods.schoolMods[school] = nil end
    end
end)

-- 点燃几率（param1=几率百分比）
POE_EffectHandler.RegisterEffect("TalentEffect_IgniteChance", function(player, e, isApply)
    local mods = POE_EffectHandler.GetMods(player)
    if isApply then
        mods.igniteChance = (mods.igniteChance or 0) + e.param1
    else
        mods.igniteChance = math.max(0, (mods.igniteChance or 0) - e.param1)
    end
end)

-- 击杀触发：击杀怪物时概率获得增益（param1=法术ID, param2=几率%）
POE_EffectHandler.RegisterEffect("TalentEffect_OnKillTrigger", function(player, e, isApply)
    local mods = POE_EffectHandler.GetMods(player)
    if not mods.onKillBuffs then mods.onKillBuffs = {} end
    if isApply then
        table.insert(mods.onKillBuffs, { spellId = e.param1, chance = e.param2 })
    end
end)

-- 移动速度修正（param1=百分比）
POE_EffectHandler.RegisterEffect("TalentEffect_ModMoveSpeed", function(player, e, isApply)
    local mods = POE_EffectHandler.GetMods(player)
    local pct = e.param1 or 5
    if isApply then
        mods.moveSpeedPct = (mods.moveSpeedPct or 0) + pct
    else
        mods.moveSpeedPct = math.max(0, (mods.moveSpeedPct or 0) - pct)
    end
    -- 应用移动速度改变
    local currentSpeed = player:GetSpeed(1)  -- 1 = RUN
    local rate = player:GetSpeedRate(1)
    player:SetSpeedRate(1, rate + (isApply and pct / 100 or -pct / 100))
end)

-- 登录恢复：遍历已点节点，统一应用所有效果
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
