# 流放艾泽拉斯 — 完整开发计划书

> **代号**: 流放艾泽拉斯 (Flow Exile Azeros)
> **基础项目**: AzerothCore + Eluna 引擎 (fork: callmefree/azerothcore-wotlk)
> **编写日期**: 2026-06-28
> **当前阶段**: Phase 1（已完成）→ Phase 2（开始）

---

## Phase 1: 地基重构 — 星盘数据与交互框架（已完成 ✅）

### 1.1 数据库核心表
- [x] `poe_talent_nodes` — 节点定义（node_id, pos_x/y, icon_id, max_rank, connections, node_type, talent_group）
- [x] `poe_talent_effects` — 效果定义（effect_id, script_name, param1, param2, spell_id）
- [x] `poe_node_effect_binding` — 节点↔效果 M:N 绑定
- [x] `character_poe_talents` — 角色已学节点
- [x] `characters.poe_talent_points` — 角色可用天赋点

### 1.2 Eluna 交互框架
- [x] POE_TalentManager.lua — Gossip 菜单、加点/重置/登录恢复
- [x] POE_Data.lua — 数据层加载缓存
- [x] POE_EffectHandler.lua — v2 隐藏光环（AddAura/RemoveAura）
- [x] POE_ResetItem.lua — 后悔石消耗品
- [x] GM 命令：`.poe reload`、`.poe addpoints N`
- [x] bug 修复：连接验证、pcall 回滚、操作顺序、NPC 模型等 12 项

### 1.3 遗留/待优化
- [ ] DBC 法术 50000/50001 创建（手动，用 MyDBCEditor）
- [ ] SQL 更新文件规范（移到 `data/sql/updates/pending_db_*`）

---

## Phase 2: 核心融合 — 职业法术与天赋技能一体化（开始）

### 2.1 技能节点（node_type='skill'）

**目标**：把职业技能作为星盘节点，点了才能学会。

**改动清单**：

#### 2.1a POE_EffectHandler.lua 扩展
注册新效果类型 `TalentEffect_LearnSpell`：
- `param1` = spell_id（要学的法术 ID）
- `isApply=true` → `player:LearnSpell(spell_id)`
- `isApply=false`（重置时）→ `player:RemoveSpell(spell_id)`

```lua
POE_EffectHandler.RegisterEffect("TalentEffect_LearnSpell", function(player, e, isApply)
    if e.spell_id == 0 then return end
    if isApply then
        player:LearnSpell(e.spell_id)
    else
        player:RemoveSpell(e.spell_id)
    end
end)
```

#### 2.1b poe_talent_nodes 扩展
在 `node_type` ENUM 增加 `'skill'`：
```sql
ALTER TABLE `poe_talent_nodes` MODIFY COLUMN `node_type` ENUM('small','notable','keystone','start','skill') NOT NULL DEFAULT 'small';
```

#### 2.1c POE_TalentManager.lua 更新
- `CanLearn()` 对 `skill` 类型节点按技能等级/职业做额外校验
- `OpenTalentMenu()` 对技能节点显示不同颜色/标记

#### 2.1d 种子数据 — 示例技能线
```
(4) 火焰系起点 → (5) 火球术(skill, spell=133) → (6) 强化火焰(小点, 火伤+5%)
                                                → (7) 点燃几率(小点, 几率+10%)
```

### 2.2 多职业起点

**目标**：不同职业从不同的星盘位置开始。

**改动**：
- `poe_talent_nodes` 增加 `class_mask` 列（TINYINT UNSIGNED，位掩码标记职业）
- 起点节点按 `class_mask` 过滤，只显示当前职业可用的起点
- 种子数据中为每个职业设计不同的起始区域

```sql
ALTER TABLE `poe_talent_nodes` ADD COLUMN `class_mask` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '职业掩码(1=战士,2=圣骑,4=猎人,8=盗贼,16=牧师,32=死骑,64=萨满,128=法师,256=术士,512=小德,1024=武僧,2048=恶魔猎手)';
```

### 2.3 辅助/强化节点

**目标**：围绕技能节点放置强化被动，形成 PoE 风格的技能树。

类型：
- **伤害加成**：`TalentEffect_ModDamagePercent` — param1=伤害类型掩码, param2=百分比
- **范围扩大**：`TalentEffect_ModAOERadius` — 通过光环修改法术范围
- **触发机制**：注册 `PLAYER_EVENT_ON_DAMAGE_DEALT` 实现"几率点燃"、"击中诅咒"等
- **转换机制**：`TalentEffect_DamageConversion` — param1=源类型, param2=目标类型, param3=百分比

### 2.4 Phase 2 种子数据设计

#### 战士力量线（已存在 → 扩展）
```
(1) 力量起点(start, class=1)
  → (2) 力量+5(small) → (3) 力量+10(small)
  → (8) 英勇打击(skill, spell=78) → (9) 强化英勇(small, 伤害+5%)
                                   → (10) 破甲加成(small, 破甲+10%)
```

#### 法师火焰线（新增）
```
(11) 火焰起点(start, class=256)
  → (12) 智力+5(small) → (13) 智力+10(small)
  → (14) 火球术(skill, spell=133) → (15) 火焰伤害+5%(small)
                                   → (16) 点燃几率(small, 10%几率)
                                   → (17) 多重投射(notable, 额外1投射物)
```

---

## Phase 3: 装备革命 — 词缀与制作系统（规划中）

### 3.1 装备重构
- `poe_item_bases` — 白装底材
- `poe_affix_pools` — 词缀池
- `character_items_instanced.affix_list` — 实例词缀

### 3.2 制作通货
- 蜕变/改造/富豪/崇高石 Lua 脚本

### 3.3 词缀效果
- `POE_ItemEffectHandler.lua` — 装备/卸下时动态 AddAura

---

## 执行路线

| 步骤 | 内容 | 预计耗时 |
|------|------|---------|
| 1 | ENUM 扩展 + LearnSpell 效果 | ~15min |
| 2 | 种子数据：技能节点示例 | ~15min |
| 3 | CanLearn 技能校验 + 菜单颜色 | ~10min |
| 4 | class_mask 字段 + 职业起点过滤 | ~20min |
| 5 | 多职业种子数据 | ~20min |
| 6 | 辅助节点效果实现 | ~30min |
| 7 | 测试验证 | ~20min |

---

## 验证方式

1. 法师角色对话 NPC → 看到火焰起点，看不到战士起点
2. 点火焰起点 → 成功（cost=0，不消耗点数）
3. 点火球术节点 → 学会火球术，技能书出现
4. 重置火球术 → 法术从技能书移除
5. 战士兵器同理解锁英勇打击
6. 强化节点正确叠加属性/光环
