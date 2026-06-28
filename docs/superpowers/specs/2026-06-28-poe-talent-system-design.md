# 流放艾泽拉斯 — 星盘天赋系统设计规格 v1

> **代号**: 流放艾泽拉斯 (Flow Exile Azeros)  
> **基础项目**: AzerothCore + Eluna 引擎 (fork: callmefree/azerothcore-wotlk)  
> **编写日期**: 2026-06-28  
> **阶段**: Phase 1 — 星盘数据与交互框架

---

## 1. 设计目标

在 AzerothCore 服务端上实现《流放之路》风格的天赋星盘系统，完全取代魔兽原版的天赋面板。以 Eluna Lua 引擎作为主要实现手段，数据库作为持久化层。

### 成功标准

- 玩家可通过 Gossip 菜单打开天赋星盘
- 星盘节点可点击、加点、保存、移除
- 加点后效果实时生效（如力量+5）
- 登录后自动恢复所有已点效果
- 后悔石道具可单节点重置
- 全链路可跑通 3 节点 Demo

---

## 2. 数据库设计

### 2.1 表结构

#### world 库：poe_talent_nodes（天赋节点定义）

```sql
CREATE TABLE `poe_talent_nodes` (
  `node_id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(128) NOT NULL DEFAULT '' COMMENT '节点显示名',
  `description` TEXT COMMENT '节点效果描述',
  `pos_x` SMALLINT NOT NULL DEFAULT 0,
  `pos_y` SMALLINT NOT NULL DEFAULT 0,
  `icon_id` INT UNSIGNED NOT NULL DEFAULT 0,
  `max_rank` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `cost` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '消耗天赋点数，起点为0',
  `connections` TEXT COMMENT '相连node_id列表，逗号分隔，如 "101,102,103"',
  `node_type` ENUM('small','notable','keystone','start') NOT NULL DEFAULT 'small',
  `talent_group` VARCHAR(64) DEFAULT NULL COMMENT '集群标签，如 "cluster_physical"',
  PRIMARY KEY (`node_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

#### world 库：poe_talent_effects（天赋效果定义）

```sql
CREATE TABLE `poe_talent_effects` (
  `effect_id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `effect_name` VARCHAR(100) DEFAULT NULL COMMENT '备注名',
  `script_name` VARCHAR(128) NOT NULL COMMENT 'Lua函数名，如 "TalentEffect_StatPlus"',
  `param1` INT DEFAULT 0 COMMENT '参数1，如 STAT_STRENGTH',
  `param2` INT DEFAULT 0 COMMENT '参数2，如 5（表示+5力量）',
  PRIMARY KEY (`effect_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

#### world 库：poe_node_effect_binding（节点-效果绑定）

```sql
CREATE TABLE `poe_node_effect_binding` (
  `node_id` INT UNSIGNED NOT NULL,
  `effect_id` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`node_id`, `effect_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

#### world 库：character_poe_talents（角色星盘数据）

```sql
CREATE TABLE `character_poe_talents` (
  `character_guid` INT UNSIGNED NOT NULL,
  `node_id` INT UNSIGNED NOT NULL,
  `points_spent` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  PRIMARY KEY (`character_guid`, `node_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

#### characters 库：扩展字段

```sql
ALTER TABLE `characters` ADD COLUMN `poe_talent_points` SMALLINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '可用天赋点数';
```

### 2.2 Demo 种子数据

```sql
-- 3 节点 Demo
INSERT INTO `poe_talent_nodes` (`node_id`, `name`, `description`, `pos_x`, `pos_y`, `cost`, `connections`, `node_type`) VALUES
(1, '力量起点', '战士的天赋起点', 0, 0, 0, '2', 'start'),
(2, '力量+5', '增加5点力量', 1, 0, 1, '1,3', 'small'),
(3, '力量+10', '增加10点力量', 2, 0, 1, '2', 'small');

INSERT INTO `poe_talent_effects` (`effect_id`, `effect_name`, `script_name`, `param1`, `param2`) VALUES
(1, '力量+5', 'TalentEffect_StatPlus', 1, 5),   -- STAT_STRENGTH = 1
(2, '力量+10', 'TalentEffect_StatPlus', 1, 10);

INSERT INTO `poe_node_effect_binding` (`node_id`, `effect_id`) VALUES
(2, 1),
(3, 2);
```

---

## 3. Lua 脚本架构

### 3.1 文件结构

```
lua_scripts/
├── POE_TalentManager.lua    -- 总机：Gossip 菜单、加点/移除/登录恢复
├── POE_EffectHandler.lua    -- 效果执行器：所有 TalentEffect_* 函数
├── POE_Data.lua             -- 数据层：从 DB 缓存到内存表
└── POE_ResetItem.lua        -- 后悔石（物品使用事件）
```

### 3.2 数据层（POE_Data.lua）

```
职责：
- 启动时从 world 库加载 poe_talent_nodes、poe_effects、poe_bindings 到 Lua 表
- 提供 GetNodeData(id)、GetNodeEffects(id)、LoadPlayerTalents(guid) 等查询
- connecions 字段在加载时解析为 {2, 3} 数字表
- 运行时从 character_poe_talents 读写玩家数据
```

### 3.3 总机层（POE_TalentManager.lua）

```
注册事件：
- RegisterCreatureGossipEvent(NPC_ENTRY, 1, OnGossipHello)  — 打开星盘
- RegisterCreatureGossipEvent(NPC_ENTRY, 2, OnGossipSelect) — 菜单选择
- RegisterPlayerEvent(3, OnPlayerLogin)                       — 登录恢复

加点流程：
  玩家选择节点 → canLearn() 验证（起点跳过 / 已点不可重复 / 节点连接有效性）
  → 扣除天赋点 → SaveTalent() 写库 → ApplyTalentEffects() → 关菜单

TODO: 加入失败回滚保护。先确保天赋数据成功写入，再扣点并应用效果。
```

### 3.4 效果层（POE_EffectHandler.lua）

```
TalentEffect_StatPlus(player, node_id, stat, amount)
  → player:ModifyStat(stat, amount)  — 支持正负值
  → Demo 阶段用 ModifyStat，后续迁移到隐藏光环

RemoveTalentEffects(player, node_id)
  → 遍历该节点绑定的效果
  → 调用同名效果函数，param 全部取反
  → 注意：修改属性类效果支持负值，光环类用 RemoveAura

TODO: 后续迁移到隐藏光环系统（Player:AddAura / RemoveAura），
      避免 ModifyStat 与其他系统叠加时产生误差。
```

### 3.5 后悔石（POE_ResetItem.lua）

```
物品 ID: 70000（临时 Demo 用）
触发：RegisterItemEvent(70000, ITEM_EVENT_ON_USE, OnResetItemUse)

流程：
  使用后悔石 → 列出已点节点（来自 character_poe_talents）
  → 玩家选择要重置的节点
  → ① 从 character_poe_talents DELETE 该行
  → ② RemoveTalentEffects(player, node_id)
  → ③ poe_talent_points + 1
  → ④ 消耗 1 个后悔石
  → ⑤ 显示成功消息
```

---

## 4. 验证链

### 4.1 正向路径：加点

```
1. 玩家点击星盘 NPC
2. 显示 3 个节点菜单（节点1 显示"已激活不可加"）
3. 玩家点击节点2
4. ✅ canLearn 检查通过（与节点1相连、cost=1、有天赋点）
5. 扣除 1 天赋点
6. 写入 character_poe_talents (guid=123, node_id=2, points=1)
7. ApplyTalentEffects: ModifyStat(STR, +5)
8. 关闭菜单，显示"✅ 已点亮节点！"
9. 验证：.stat 查看力量 +5
```

### 4.2 正向路径：登录恢复

```
1. 玩家下线，上线
2. OnPlayerLogin 触发
3. 从 character_poe_talents 读取 (guid=123, node_id=2)
4. ApplyTalentEffects: ModifyStat(STR, +5)
5. 验证：力量仍为 +5 状态
```

### 4.3 正向路径：后悔石重置

```
1. 玩家使用后悔石
2. 显示已点节点列表（节点2）
3. 选择节点2
4. DELETE character_poe_talents WHERE guid=123 AND node_id=2
5. RemoveTalentEffects: ModifyStat(STR, -5)
6. poe_talent_points + 1
7. 消耗 1 个后悔石
8. 验证：力量回到原始值，天赋点 +1
```

### 4.4 异常路径

| 场景 | 预期行为 |
|------|---------|
| 节点不可达（未连任何已激活节点） | canLearn 返回 false，提示"节点未解锁" |
| 天赋点不足 | 提示"天赋点不足" |
| 点已点过的节点 | canLearn 返回 false |
| 后悔石不在背包 | 物品事件不会被触发 |
| 已点节点列表为空 | 提示"还没有点亮任何节点" |

---

## 5. Demo 范围界定

### Phase 1 Demo 包含

- ✅ 4 张数据库表 + characters 字段扩展
- ✅ 3 个 Demo 种子节点
- ✅ 4 个 Lua 脚本文件
- ✅ 后悔石物品（硬编码 ID）
- ✅ 加点/移除/登录恢复/重置 全链路

### 不在 Demo 范围内（后续阶段再做）

- ❌ 客户端插件（纯 Gossip 菜单）
- ❌ 技能节点（node_type='skill'，Phase 2）
- ❌ 集群珠宝系统
- ❌ 多职业起点
- ❌ 属性光环系统（当前用 ModifyStat 替代）
- ❌ 客户端显示优化

---

## 6. 实现顺序

1. **建表 + 种子数据**（SQL 脚本）
2. **POE_Data.lua**（数据加载和缓存）
3. **POE_EffectHandler.lua**（效果执行）
4. **POE_TalentManager.lua**（总机和 Gossip 交互）
5. **POE_ResetItem.lua**（后悔石）
6. **启动服务端，全链路验证**
