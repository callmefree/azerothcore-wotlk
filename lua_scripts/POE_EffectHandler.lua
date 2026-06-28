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

-- 通用光环效果
POE_EffectHandler.RegisterEffect("TalentEffect_StatPlus", function(player, e, isApply)
    if e.spell_id == 0 then
        print("[POE] 警告: 效果缺少 spell_id")
        return
    end
    if isApply then
        local success = player:AddAura(e.spell_id, player)
        if not success then
            print("[POE] 添加光环失败: spell_id=" .. e.spell_id)
        end
    else
        player:RemoveAura(e.spell_id)
    end
end)

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
