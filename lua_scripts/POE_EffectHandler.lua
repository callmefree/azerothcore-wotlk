-- POE_EffectHandler.lua
-- 星盘效果执行器：注册、应用、移除效果

local POE_EffectHandler = {}
local EffectRegistry = {}

-- 注册一个效果函数
function POE_EffectHandler.RegisterEffect(name, func)
    EffectRegistry[name] = func
end

-- 应用节点效果（正向）
function POE_EffectHandler.ApplyEffects(player, nodeId)
    local effects = POE_Data.GetNodeEffects(nodeId)
    for _, e in ipairs(effects) do
        local func = EffectRegistry[e.script]
        if func then
            func(player, e.param1, e.param2)
        else
            print("[POE] 警告: 未注册的效果脚本 " .. e.script)
        end
    end
end

-- 移除节点效果（参数取反）
function POE_EffectHandler.RemoveEffects(player, nodeId)
    local effects = POE_Data.GetNodeEffects(nodeId)
    for _, e in ipairs(effects) do
        local func = EffectRegistry[e.script]
        if func then
            func(player, e.param1, -e.param2) -- param2 取反
        else
            print("[POE] 警告: 未注册的效果脚本 " .. e.script)
        end
    end
end

-- ===== 效果函数实现 =====

-- 通用属性加成效果（STAT_STRENGTH=1, STAT_AGILITY=2, STAT_STAMINA=3, STAT_INTELLECT=4, STAT_SPIRIT=5）
-- amount 为正数时加属性，负数时减属性
POE_EffectHandler.RegisterEffect("TalentEffect_StatPlus", function(player, statId, amount)
    if amount == 0 then return end
    local current = player:GetBaseStat(statId)
    local newVal = current + amount
    -- 防止负值
    if newVal < 0 then newVal = 0 end
    player:SetBaseStat(statId, newVal)
    if amount > 0 then
        player:SendBroadcastMessage("|cff00ff00[星盘] 属性 +" .. amount .. "|r")
    else
        player:SendBroadcastMessage("|cffff4444[星盘] 属性 " .. amount .. "|r")
    end
end)

-- TODO: 后续迁移到隐藏光环系统（Player:AddAura / RemoveAura），
--       避免 ModifyStat/SetBaseStat 与其他系统叠加时产生误差。

return POE_EffectHandler
