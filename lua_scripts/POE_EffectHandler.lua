-- POE_EffectHandler.lua
-- 采用 "全局重算" 模式：每次变更时重新汇总所有节点加成
-- 彻底解决 "移除顺序导致属性错误" 问题

local POE_EffectHandler = {}
local EffectRegistry = {}

function POE_EffectHandler.RegisterEffect(name, func)
    EffectRegistry[name] = func
end

-- 核心：根据当前已激活节点，计算并应用所有属性变化
function POE_EffectHandler.RefreshAllStats(player)
    local guid = player:GetGUID()
    local learned = POE_Data.LoadPlayerTalents(guid)
    local statMods = {}

    -- 1. 遍历所有已点节点，汇总效果
    for nodeId, _ in pairs(learned) do
        local effects = POE_Data.GetNodeEffects(nodeId)
        for _, e in ipairs(effects) do
            if e.script == "TalentEffect_StatPlus" then
                local statId = e.param1
                local amount = e.param2
                statMods[statId] = (statMods[statId] or 0) + amount
            end
        end
    end

    -- 2. 将属性变动应用到角色身上（一次性覆盖）
    for statId, totalBonus in pairs(statMods) do
        local base = player:GetBaseStat(statId)
        player:SetBaseStat(statId, base + totalBonus)
    end
end

-- 兼容旧接口：调用 ApplyEffects 或 RemoveEffects 时，统一触发重算
function POE_EffectHandler.ApplyEffects(player, nodeId)
    POE_EffectHandler.RefreshAllStats(player)
    player:SendBroadcastMessage("|cff00ff00[星盘] 节点效果已应用，属性已重算|r")
end

function POE_EffectHandler.RemoveEffects(player, nodeId)
    POE_EffectHandler.RefreshAllStats(player)
    player:SendBroadcastMessage("|cffff4444[星盘] 节点已移除，属性已重算|r")
end

-- 注册基础属性加成效果（保留以供查询，实际逻辑由 RefreshAllStats 统一处理）
POE_EffectHandler.RegisterEffect("TalentEffect_StatPlus", function(player, statId, amount)
    -- 此函数不再直接修改属性，由 RefreshAllStats 统一处理
end)

return POE_EffectHandler
