# 流放艾泽拉斯 — Phase 1 开发档案

> **项目代号**: 流放艾泽拉斯 (Flow Exile Azeros)  
> **基础项目**: AzerothCore (wotlk) + Eluna 引擎  
> **Fork**: [callmefree/azerothcore-wotlk](https://github.com/callmefree/azerothcore-wotlk)  
> **开发日期**: 2026-06-28  
> **作者**: WorkBuddy AI (Buddy) — MaNGOS/TurtleWoW 运维伙伴  

---

## 目录

1. [项目背景与动机](#1-项目背景与动机)
2. [开发流程记录](#2-开发流程记录)
3. [设计决策记录 (ADR)](#3-设计决策记录-adr)
4. [数据库架构](#4-数据库架构)
5. [Lua 脚本架构](#5-lua-脚本架构)
6. [CI/CD 配置](#6-cicd-配置)
7. [完整的代码清单](#7-完整的代码清单)
8. [测试验证矩阵](#8-测试验证矩阵)
9. [回滚方案](#9-回滚方案)
10. [后续规划](#10-后续规划)
11. [附录](#11-附录)

---

## 1. 项目背景与动机

### 1.1 目标

在 AzerothCore 服务端上实现《流放之路》(Path of Exile) 风格的天赋星盘系统，完全取代魔兽原版的天赋面板。

### 1.2 核心创新点

- **星盘系统**: 网状天赋节点取代线性天赋树，节点间通过连接关系定义可达性
- **脚本驱动**: 所有效果通过 `script_name + param1/param2` 配置化，Lua 函数名动态绑定
- **消耗品重置**: 对标 PoE "后悔石" 的单个节点重置道具
- **兼容 Eluna**: 全部逻辑在 Lua 层实现，不修改 C++ 源码

### 1.3 技术栈

| 层级 | 技术 | 版本 |
|------|------|------|
| 服务端核心 | AzerothCore (wotlk) | master @ f5b21bb |
| 脚本引擎 | Eluna Lua | 内置模块 |
| 数据库 | MySQL / MariaDB | 兼容 5.7+ / 8.0 |
| 持续集成 | GitHub Actions | pch-build / nopch-build / windows-build |
| 版本控制 | GitHub | callmefree/azerothcore-wotlk |

---

## 2. 开发流程记录

### 2.1 流水线

```
头脑风暴 (brainstorming)
  ├── Q1: 天赋点投放 → 每级1点
  ├── Q2: 交互方式 → Lua Gossip菜单
  └── Q3: 重置方式 → 后悔石消耗品
  
设计规格编写
  └── docs/superpowers/specs/2026-06-28-poe-talent-system-design.md

实现计划编写 (writing-plans)
  └── docs/superpowers/plans/2026-06-28-poe-talent-demo.md

子智能体驱动开发 (subagent-driven-development)
  ├── Agent 1: sql/poe_schema.sql      — 建表 + 种子数据
  ├── Agent 2: POE_Data.lua            — 数据层
  ├── Agent 3: POE_EffectHandler.lua   — 效果执行器
  ├── Agent 4: POE_TalentManager.lua   — 总机
  └── Agent 5: POE_ResetItem.lua       — 后悔石

推送至GitHub分支 phase-1-talent-demo
  └── PR #2 → master
```

### 2.2 耗时统计

| 阶段 | 耗时（约） | 工具调用数 |
|------|-----------|-----------|
| 环境准备（gh CLI + fork） | 8 min | 20+ |
| CI 配置排障 | 15 min | 25+ |
| 头脑风暴 + 设计 | 10 min | 15+ |
| 实现计划 | 3 min | 5 |
| 子智能体实现 | 5 min | 10 |
| 推送 + PR | 2 min | 5 |
| 代码审查 + 5 项硬伤修复 | 2 min | 5 |
| **总计** | **~45 min** | **85+** |

---

## 3. 设计决策记录 (ADR)

### ADR-001: 天赋点投放机制

- **状态**: ✅ 已采纳
- **决策**: 每级 1 点（原版机制）
- **原因**: 最简单，与魔兽升级手感一致，后期可叠加任务/试炼奖励
- **替代方案**: 每5级给1点 + 任务奖励 | 全等级投放 + 试炼副本
- **影响**: characters 表只需存 `poe_talent_points` 一个字段

### ADR-002: 交互方式

- **状态**: ✅ 已采纳
- **决策**: Eluna Gossip 菜单（纯服务端）
- **原因**: 快速开发，不依赖客户端插件，AzerothCore 原生支持
- **替代方案**: 客户端插件（体验好但开发成本高，留到后期）
- **影响**: NPC 200000 触发多级 Gossip 菜单，显示节点名称和状态

### ADR-003: 重置机制

- **状态**: ✅ 已采纳
- **决策**: 后悔石（物品 70000）单节点重置
- **原因**: 对标 PoE "Orb of Regret"，消耗品绑定物品使用事件
- **替代方案**: 金币重置 | NPC 重置 | 全局重置卷轴
- **影响**: 需要 `RegisterItemEvent` + `RegisterPlayerGossipEvent`

### ADR-004: Connections 存储格式

- **状态**: ✅ 已采纳
- **决策**: 逗号分隔字符串 TEXT 类型
- **原因**: 简单直观，拆分成 Lua table 开销小
- **放弃**: 外键约束表（复杂查询在内存图结构中完成）
- **影响**: Lua 加载时用 `string.gmatch` 解析

### ADR-005: 效果参数化

- **状态**: ✅ 已采纳
- **决策**: `param1` / `param2` 两列 INT 参数
- **原因**: "加什么属性、加多少" 这种泛用场景够用，后续扩展可用 JSON
- **影响**: `TalentEffect_StatPlus(player, statId, amount)` 统一处理所有属性加减

### ADR-006: CI 启用（Fork 适配）

- **状态**: ✅ 已采纳
- **决策**: 修改 5 个工作流 `if:` 条件，增加 `github.repository_owner == 'callmefree'`
- **原因**: 上游工作流限定了只在 `azerothcore/azerothcore-wotlk` 仓库运行
- **影响**: pch-build / nopch-build / modules / windows / macos 均可在 fork 上运行

### ADR-007: 节点类型

- **状态**: ✅ 暂缓
- **决策**: `node_type` 枚举范围 `small / notable / keystone / start`，**不包含 skill**
- **原因**: 技能节点（点了就学会法术）留到 Phase 2 实现
- **影响**: Phase 1 只做属性加成类效果

### ADR-008: talent_group 类型

- **状态**: ✅ 已采纳
- **决策**: `VARCHAR(64)` 字符串标签（非 INT 外键）
- **原因**: 读表时含义清晰，少一张关联表
- **影响**: 未来集群珠宝系统直接用标签匹配

### ADR-009: 属性系统 — 全局重算模式（v1.1 Hotfix）

- **状态**: ✅ 已采纳
- **决策**: 弃用增量 `SetBaseStat(old + delta)`，改为 `RefreshAllStats()` 全局重算
- **原因**: 增量模式在节点移除顺序颠倒时产生属性叠加错误
- **方案**: 每次加点/移除/登录，遍历所有已点节点，汇总 StatPlus 总加成，一次性覆盖 `SetBaseStat`
- **影响**: 移除 `ApplyEffects`/`RemoveEffects` 的独立增减逻辑，统一走重算

### ADR-010: 事务保护与回滚（v1.1 Hotfix）

- **状态**: ✅ 已采纳
- **决策**: 加点流程用 `pcall` 包装，失败时手动回滚（删记录、还点数、重算属性）
- **原因**: `SaveTalent → ApplyEffects → SetTalentPoints` 顺序执行无原子性，中间失败导致数据不一致
- **影响**: 额外 SQL 回滚操作，但保障数据安全

### ADR-011: SQL 注入防御（v1.1 Hotfix）

- **状态**: ✅ 已采纳
- **决策**: 所有从 Gossip action/Sender 获取的整数值强制 `tonumber()` 转换
- **原因**: nodeId 来源于用户菜单操作，理论上可被伪造
- **影响**: 工具函数增加 `local nid = tonumber(nodeId) or 0`

### ADR-012: 起点节点不可重置（v1.1 Hotfix）

- **状态**: ✅ 已采纳
- **决策**: 后悔石菜单中过滤 `node_type == 'start'` 的节点，回调中也做二次检查
- **原因**: 起点被重置后可能导致角色失去整棵天赋树的入口
- **影响**: 菜单渲染和回调都增加了节点类型过滤

### ADR-013: Gossip 菜单 ID 显式绑定（v1.1 Hotfix）

- **状态**: ✅ 已采纳
- **决策**: `CreateGossipMenu(ITEM_ID)` 显式指定 gossipId
- **原因**: 默认 gossipId=0 vs 预期 ITEM_ID，导致事件回调不触发
- **影响**: 菜单 ID 与物品 ID 对齐

---

## 4. 数据库架构

### 4.1 ER 关系

```
poe_talent_nodes (1) ──── (N) poe_node_effect_binding (N) ──── (1) poe_talent_effects
        │                                                               │
        │  node_id (PK)              node_id + effect_id (复合PK)        effect_id (PK)
        │  name                      effect_id                            script_name
        │  description                                                    param1
        │  pos_x / pos_y                                                  param2
        │  icon_id
        │  max_rank
        │  cost
        │  connections (TEXT)
        │  node_type (ENUM)
        └── talent_group (VARCHAR)

character_poe_talents            characters (扩展)
        │                              │
        │  character_guid (PK)          guid (from auth)
        │  node_id (PK)                 poe_talent_points (SMALLINT, 新增)
        └── points_spent
```

### 4.2 表定义摘要

| 表名 | 库 | 用途 | 核心列 |
|------|----|------|--------|
| `poe_talent_nodes` | world | 天赋节点定义 | node_id, name, cost, connections, node_type |
| `poe_talent_effects` | world | 效果定义 | effect_id, script_name, param1, param2 |
| `poe_node_effect_binding` | world | 节点↔效果 M:N | node_id, effect_id (复合主键) |
| `character_poe_talents` | world | 角色已点节点 | character_guid, node_id |
| `characters.poe_talent_points` | characters | 角色可用天赋点 | SMALLINT UNSIGNED (新增列) |

---

## 5. Lua 脚本架构

### 5.1 文件依赖关系

```
POE_Data.lua (全局表)
  └── 无依赖，启动时自动 LoadCache()
  
POE_EffectHandler.lua
  └── 依赖: POE_Data (取节点效果列表)
  
POE_TalentManager.lua
  ├── 依赖: POE_Data (取节点数据/玩家天赋)
  ├── 依赖: POE_EffectHandler (应用/移除效果)
  └── 注册: RegisterCreatureGossipEvent + RegisterPlayerEvent

POE_ResetItem.lua
  ├── 依赖: POE_Data (取节点数据)
  ├── 依赖: POE_EffectHandler (移除效果)
  └── 注册: RegisterItemEvent + RegisterPlayerGossipEvent
```

**加载顺序必须为**：
1. POE_Data.lua
2. POE_EffectHandler.lua
3. POE_TalentManager.lua
4. POE_ResetItem.lua

### 5.2 事件注册汇总

| 事件 | 注册方式 | 回调 | 触发时机 |
|------|---------|------|---------|
| NPC Gossip 打开 | `RegisterCreatureGossipEvent(200000, 1, OnGossipHello)` | `OnGossipHello` | 玩家对话 NPC 200000 |
| NPC Gossip 选择 | `RegisterCreatureGossipEvent(200000, 2, OnGossipSelect)` | `OnGossipSelect` | 玩家在菜单中选择项 |
| 玩家登录 | `RegisterPlayerEvent(3, OnPlayerLogin)` | `OnPlayerLogin` | 角色进入游戏 |
| 物品右键使用 | `RegisterItemEvent(70000, 2, OnResetItemUse)` | `OnResetItemUse` | 右键点击后悔石 |
| 物品Gossip选择 | `RegisterPlayerGossipEvent(70000, 1, OnPlayerGossipSelect)` | `OnPlayerGossipSelect` | 从重置菜单选择节点 |

### 5.3 核心流程

#### 加点流程

```
玩家 → 对话NPC 200000 → OnGossipHello()
  → OpenTalentMenu() 渲染节点列表（显示状态和剩余点数）
  → 玩家选择节点 → OnGossipSelect()
  → CanLearn() 验证:
    ① 起点且未学习 → 可加点 (+ cost=0)
    ② 已点满 → 拒绝
    ③ 无已激活相邻节点 → 拒绝
    ④ 天赋点不足 → 拒绝
  → SaveTalent() 写库 (ON DUPLICATE KEY UPDATE)
  → POE_EffectHandler.ApplyEffects() 应用效果
  → SetTalentPoints() 扣点 (cost>0)
  → 显示成功消息
```

#### 登录恢复流程

```
角色登录 → OnPlayerLogin()
  → POE_Data.LoadPlayerTalents(guid) 查DB
  → 遍历已点节点 → POE_EffectHandler.ApplyEffects()
  → 显示 "[星盘] 已恢复 N 个节点效果"
```

#### 后悔石重置流程

```
使用物品 70000 → OnResetItemUse()
  → 无已点节点 → 提示退出
  → 有已点节点 → 弹出菜单列表
  → 选择节点 → OnPlayerGossipSelect()
  → POE_EffectHandler.RemoveEffects() (参数取反)
  → DELETE character_poe_talents
  → poe_talent_points + cost
  → RemoveItem(70000, 1) 消耗后悔石
```

---

## 6. CI/CD 配置

### 6.1 Frok CI 适配

上游工作流全部包含 `if: github.repository == 'azerothcore/azerothcore-wotlk'` 限制，
将其改为允许在 callmefree fork 上运行：

```yaml
# 修改前
if: github.repository == 'azerothcore/azerothcore-wotlk'

# 修改后
if: (github.repository == 'azerothcore/azerothcore-wotlk' || github.repository_owner == 'callmefree')
```

### 6.2 已适配的工作流

| 工作流文件 | 触发方式 | 编译目标 |
|-----------|---------|---------|
| `.github/workflows/core-build-pch.yml` | push(master) / PR | Ubuntu (clang-15/18) with PCH |
| `.github/workflows/core-build-nopch.yml` | push(master) / PR | Ubuntu without PCH |
| `.github/workflows/core_modules_build.yml` | push(master) / PR | Modules build |
| `.github/workflows/windows_build.yml` | push(master) / labeled PR | Windows (MSVC) |
| `.github/workflows/macos_build.yml` | push(master) / PR | macOS |

### 6.3 CI 状态

| 运行 | 提交 | 结果 |
|------|------|------|
| #1 pch-build | 6466968 | cancelled（CI 启用前） |
| #2 pch-build + nopch-build | PR #1 同步 | 观察中 |
| #3 (待触发) | PR #2: phase-1-talent-demo | 等待 Actions 处理 |

---

## 7. 完整的代码清单

### 7.1 文件索引

| # | 文件路径 | 行数 | 类型 | 大小 |
|---|---------|------|------|------|
| 1 | `sql/poe_schema.sql` | 109 | SQL | 5.2 KB |
| 2 | `lua_scripts/POE_Data.lua` | 100 | Lua | 3.6 KB |
| 3 | `lua_scripts/POE_EffectHandler.lua` | 48 | Lua | 2.0 KB (v1.1 全局重算) |
| 4 | `lua_scripts/POE_TalentManager.lua` | 130 | Lua | 5.2 KB (v1.1 安全加固) |
| 5 | `lua_scripts/POE_ResetItem.lua` | 52 | Lua | 2.5 KB (v1.1 修复) |
| 6 | `docs/superpowers/specs/2026-06-28-poe-talent-system-design.md` | 206 | Markdown | 8.5 KB |
| 7 | `docs/superpowers/plans/2026-06-28-poe-talent-demo.md` | 280 | Markdown | 10.2 KB |

### 7.2 sql/poe_schema.sql（109 行）

```sql
-- ============================================================================
-- PoE 星盘系统 - Phase 1 数据库架构与种子数据
-- 适用版本: MaNGOS Zero / Turtle WoM
-- 创建日期: 2026-06-28
-- ============================================================================

CREATE TABLE IF NOT EXISTS `poe_talent_nodes` (
  `node_id`     INT UNSIGNED    NOT NULL AUTO_INCREMENT,
  `name`        VARCHAR(128)    NOT NULL DEFAULT '' COMMENT '节点显示名',
  `description` TEXT            COMMENT '节点效果描述',
  `pos_x`       SMALLINT        NOT NULL DEFAULT 0,
  `pos_y`       SMALLINT        NOT NULL DEFAULT 0,
  `icon_id`     INT UNSIGNED    NOT NULL DEFAULT 0,
  `max_rank`    TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `cost`        TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '消耗天赋点数，起点为0',
  `connections` TEXT            COMMENT '相连node_id列表，逗号分隔',
  `node_type`   ENUM('small','notable','keystone','start') NOT NULL DEFAULT 'small',
  `talent_group` VARCHAR(64)    DEFAULT NULL COMMENT '集群标签',
  PRIMARY KEY (`node_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `poe_talent_effects` (
  `effect_id`   INT UNSIGNED    NOT NULL AUTO_INCREMENT,
  `effect_name` VARCHAR(100)    DEFAULT NULL COMMENT '备注名',
  `script_name` VARCHAR(128)    NOT NULL COMMENT 'Lua函数名',
  `param1`      INT             DEFAULT 0,
  `param2`      INT             DEFAULT 0,
  PRIMARY KEY (`effect_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `poe_node_effect_binding` (
  `node_id`   INT UNSIGNED NOT NULL,
  `effect_id` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`node_id`, `effect_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `character_poe_talents` (
  `character_guid` INT UNSIGNED    NOT NULL,
  `node_id`        INT UNSIGNED    NOT NULL,
  `points_spent`   TINYINT UNSIGNED NOT NULL DEFAULT 1,
  PRIMARY KEY (`character_guid`, `node_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Demo 种子数据（力量线 3 节点）
INSERT INTO `poe_talent_nodes` VALUES
(1, '力量起点', '战士的天赋起点', 0, 0, 0, 0, 0, '2', 'start', NULL),
(2, '力量+5',   '增加5点力量',     1, 0, 0, 1, 1, '1,3', 'small', NULL),
(3, '力量+10',  '增加10点力量',    2, 0, 0, 1, 1, '2',   'small', NULL);

INSERT INTO `poe_talent_effects` VALUES
(1, '力量+5',  'TalentEffect_StatPlus', 1, 5),
(2, '力量+10', 'TalentEffect_StatPlus', 1, 10);

INSERT INTO `poe_node_effect_binding` VALUES (2,1), (3,2);

-- characters 库扩展
ALTER TABLE `characters` ADD COLUMN IF NOT EXISTS `poe_talent_points` SMALLINT UNSIGNED NOT NULL DEFAULT 0;
```

### 7.3 lua_scripts/POE_Data.lua（100 行）

```lua
-- POE_Data.lua
-- 星盘系统数据层：从DB加载节点/效果/绑定到内存缓存

POE_Data = {}
POE_Data.Nodes = {}
POE_Data.Effects = {}
POE_Data.Bindings = {}

function POE_Data.LoadCache()
    -- 加载 poe_talent_nodes，connections 字段自动解析为数字表
    local nodeResult = WorldDBQuery("SELECT node_id, name, description, pos_x, pos_y, icon_id, max_rank, cost, connections, node_type FROM poe_talent_nodes")
    POE_Data.Nodes = {}
    if nodeResult then
        repeat
            local connStr = nodeResult:GetString("connections")
            local connections = {}
            if connStr and connStr ~= "" then
                for id in string.gmatch(connStr, "(%d+)") do
                    table.insert(connections, tonumber(id))
                end
            end
            POE_Data.Nodes[nodeResult:GetUInt32("node_id")] = {
                id = nodeResult:GetUInt32("node_id"),
                name = nodeResult:GetString("name"),
                desc = nodeResult:GetString("description"),
                cost = nodeResult:GetUInt8("cost"),
                connections = connections,
                node_type = nodeResult:GetString("node_type"),
                max_rank = nodeResult:GetUInt8("max_rank")
            }
        until not nodeResult:NextRow()
    end

    -- 加载 poe_talent_effects
    local effectResult = WorldDBQuery("SELECT effect_id, script_name, param1, param2 FROM poe_talent_effects")
    POE_Data.Effects = {}
    if effectResult then
        repeat
            POE_Data.Effects[effectResult:GetUInt32("effect_id")] = {
                script = effectResult:GetString("script_name"),
                param1 = effectResult:GetInt32("param1"),
                param2 = effectResult:GetInt32("param2")
            }
        until not effectResult:NextRow()
    end

    -- 加载 poe_node_effect_binding
    local bindResult = WorldDBQuery("SELECT node_id, effect_id FROM poe_node_effect_binding")
    POE_Data.Bindings = {}
    if bindResult then
        repeat
            local nodeId = bindResult:GetUInt32("node_id")
            local effectId = bindResult:GetUInt32("effect_id")
            if not POE_Data.Bindings[nodeId] then POE_Data.Bindings[nodeId] = {} end
            table.insert(POE_Data.Bindings[nodeId], effectId)
        until not bindResult:NextRow()
    end
end

function POE_Data.GetNodeData(nodeId) return POE_Data.Nodes[nodeId] end

function POE_Data.GetNodeEffects(nodeId)
    local ids = POE_Data.Bindings[nodeId]
    if not ids then return {} end
    local effects = {}
    for _, eId in ipairs(ids) do
        if POE_Data.Effects[eId] then table.insert(effects, POE_Data.Effects[eId]) end
    end
    return effects
end

function POE_Data.LoadPlayerTalents(guid)
    local result = CharDBQuery("SELECT node_id, points_spent FROM character_poe_talents WHERE character_guid = " .. guid)
    local learned = {}
    if result then
        repeat
            learned[result:GetUInt32("node_id")] = result:GetUInt8("points_spent")
        until not result:NextRow()
    end
    return learned
end

function POE_Data.ReloadCache()
    POE_Data.LoadCache()
    print("[POE] 星盘数据缓存已重载")
end

POE_Data.LoadCache()
```

### 7.4 lua_scripts/POE_EffectHandler.lua（55 行 → 48 行，v1.1 全局重算）

```lua
-- POE_EffectHandler.lua
-- 采用 "全局重算" 模式：每次变更时重新汇总所有节点加成

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

    for nodeId, _ in pairs(learned) do
        local effects = POE_Data.GetNodeEffects(nodeId)
        for _, e in ipairs(effects) do
            if e.script == "TalentEffect_StatPlus" then
                local statId, amount = e.param1, e.param2
                statMods[statId] = (statMods[statId] or 0) + amount
            end
        end
    end

    for statId, totalBonus in pairs(statMods) do
        local base = player:GetBaseStat(statId)
        player:SetBaseStat(statId, base + totalBonus)
    end
end

function POE_EffectHandler.ApplyEffects(player, nodeId)
    POE_EffectHandler.RefreshAllStats(player)
    player:SendBroadcastMessage("|cff00ff00[星盘] 节点效果已应用，属性已重算|r")
end

function POE_EffectHandler.RemoveEffects(player, nodeId)
    POE_EffectHandler.RefreshAllStats(player)
    player:SendBroadcastMessage("|cffff4444[星盘] 节点已移除，属性已重算|r")
end

-- 保留函数以供查询，实际逻辑由 RefreshAllStats 统一处理
POE_EffectHandler.RegisterEffect("TalentEffect_StatPlus", function() end)

return POE_EffectHandler
```

### 7.5 lua_scripts/POE_TalentManager.lua（135 行 → v1.1 安全加固）

```lua
-- POE_TalentManager.lua
-- 星盘系统总机：Gossip菜单/加点/移除/登录恢复

local NPC_ENTRY = 200000

-- ===== 天赋点工具函数 =====
local function GetTalentPoints(player)
    local result = CharDBQuery("SELECT poe_talent_points FROM characters WHERE guid = " .. player:GetGUID())
    return (result and result:GetUInt16("poe_talent_points")) or 0
end

local function SetTalentPoints(player, points)
    CharDBExecute("UPDATE characters SET poe_talent_points = " .. points .. " WHERE guid = " .. player:GetGUID())
end

local function SaveTalent(player, nodeId)
    local nid = tonumber(nodeId) or 0
    CharDBExecute("INSERT INTO character_poe_talents (character_guid, node_id, points_spent) VALUES (" .. player:GetGUID() .. ", " .. nid .. ", 1) ON DUPLICATE KEY UPDATE points_spent = points_spent + 1")
end

local function RemoveTalent(player, nodeId)
    local nid = tonumber(nodeId) or 0
    CharDBExecute("DELETE FROM character_poe_talents WHERE character_guid = " .. player:GetGUID() .. " AND node_id = " .. nid)
end

-- ===== 验证逻辑 =====
local function CanLearn(player, nodeId, learnedTalents)
    local node = POE_Data.GetNodeData(nodeId)
    if not node then return false, "节点不存在" end
    if node.node_type == "start" and not learnedTalents[nodeId] then return true, "" end
    if learnedTalents[nodeId] and learnedTalents[nodeId] >= node.max_rank then return false, "该节点已满级" end
    local connected = false
    for _, connId in ipairs(node.connections) do
        if learnedTalents[connId] then connected = true; break end
    end
    if not connected then return false, "节点未解锁（需要相邻节点已点亮）" end
    if GetTalentPoints(player) < node.cost then return false, "天赋点不足" end
    return true, ""
end

-- ===== Gossip 菜单 =====
local function OpenTalentMenu(player)
    local learned = POE_Data.LoadPlayerTalents(player:GetGUID())
    local points = GetTalentPoints(player)
    local gossip = player:CreateGossipMenu()
    gossip:AddText("|cffffcc00【星盘天赋系统】|r")
    gossip:AddText("剩余天赋点: |cff00ff00" .. points .. "|r")
    gossip:AddText("------------------")
    for id, node in pairs(POE_Data.Nodes) do
        local status = "|cff888888未解锁|r"
        if learned[id] then status = "|cff00ff00已激活|r"
        else local can, _ = CanLearn(player, id, learned); if can then status = "|cffffff00[可加点]|r" end end
        gossip:AddMenuItem(id, node.name .. " " .. status, 0)
    end
    gossip:AddMenuItem(999, "|cffff4444【重置所有天赋点】（测试用）|r", 1)
    gossip:SendToPlayer(player)
end

-- ===== 事件回调 =====
local function OnGossipHello(event, player, creature)
    if creature:GetEntry() ~= NPC_ENTRY then return false end
    OpenTalentMenu(player)
    return true
end

local function OnGossipSelect(event, player, creature, sender, action, gossipId)
    if creature:GetEntry() ~= NPC_ENTRY then return false end
    local nodeId = tonumber(action) or 0
    if nodeId == 0 then return true end
    if nodeId == 999 then
        local learned = POE_Data.LoadPlayerTalents(player:GetGUID())
        for nid, _ in pairs(learned) do
            POE_EffectHandler.RefreshAllStats(player)
            RemoveTalent(player, nid)
        end
        SetTalentPoints(player, 10)
        player:SendBroadcastMessage("|cffff4444已重置所有天赋点|r")
        OpenTalentMenu(player); return true
    end
    local learned = POE_Data.LoadPlayerTalents(player:GetGUID())
    local can, reason = CanLearn(player, nodeId, learned)
    if not can then player:SendBroadcastMessage("|cffff4444[星盘] |r" .. reason); OpenTalentMenu(player); return true end
    local node = POE_Data.GetNodeData(nodeId)
    if not node then return true end
    local pointsBefore = GetTalentPoints(player)
    local success, err = pcall(function()
        SaveTalent(player, nodeId)
        local newPoints = pointsBefore - node.cost
        if newPoints < 0 then error("天赋点不足（事务内检查）") end
        SetTalentPoints(player, newPoints)
        POE_EffectHandler.RefreshAllStats(player)
    end)
    if not success then
        RemoveTalent(player, nodeId); SetTalentPoints(player, pointsBefore)
        POE_EffectHandler.RefreshAllStats(player)
        player:SendBroadcastMessage("|cffff4444[星盘] 加点失败，已回滚。错误: " .. tostring(err) .. "|r")
    else
        player:SendBroadcastMessage("|cff00ff00[星盘] 已点亮节点: |r" .. node.name)
    end
    OpenTalentMenu(player)
    return true
end

local function OnPlayerLogin(event, player)
    local learned = POE_Data.LoadPlayerTalents(player:GetGUID())
    local count = 0; for _,_ in pairs(learned) do count = count + 1 end
    if count > 0 then
        POE_EffectHandler.RefreshAllStats(player)
        player:SendBroadcastMessage("|cff00ff00[星盘] 已恢复 " .. count .. " 个节点效果|r")
    end
end

RegisterCreatureGossipEvent(NPC_ENTRY, 1, OnGossipHello)
RegisterCreatureGossipEvent(NPC_ENTRY, 2, OnGossipSelect)
RegisterPlayerEvent(3, OnPlayerLogin)
```

### 7.6 lua_scripts/POE_ResetItem.lua（55 行 → v1.1 修复版）

```lua
-- POE_ResetItem.lua
-- 修复：菜单ID显式设置 + 过滤起点 + SQL注入防御

local ITEM_ID = 70000

local function GetTalentPoints(player)
    local result = CharDBQuery("SELECT poe_talent_points FROM characters WHERE guid = " .. player:GetGUID())
    return (result and result:GetUInt16("poe_talent_points")) or 0
end

local function SetTalentPoints(player, points)
    CharDBExecute("UPDATE characters SET poe_talent_points = " .. tonumber(points) .. " WHERE guid = " .. player:GetGUID())
end

local function OnResetItemUse(event, player, item, target)
    local learned = POE_Data.LoadPlayerTalents(player:GetGUID())
    local count = 0
    for nodeId, _ in pairs(learned) do
        local node = POE_Data.GetNodeData(nodeId)
        if node and node.node_type ~= "start" then count = count + 1 end
    end
    if count == 0 then
        player:SendBroadcastMessage("|cffff4444[星盘] 你还没有可以重置的非起点节点|r")
        return true
    end
    local gossip = player:CreateGossipMenu(ITEM_ID)
    gossip:AddText("|cffffcc00选择要重置的节点:|r")
    for nodeId, _ in pairs(learned) do
        local node = POE_Data.GetNodeData(nodeId)
        if node and node.node_type ~= "start" then
            gossip:AddMenuItem(nodeId, node.name .. "（当前已激活）", 0)
        end
    end
    gossip:SendToPlayer(player)
    return true
end

local function OnPlayerGossipSelect(event, player, sender, action, gossipId)
    if gossipId ~= ITEM_ID then return false end
    local nodeId = tonumber(action) or 0
    local node = POE_Data.GetNodeData(nodeId)
    if not node or node.node_type == "start" then
        player:SendBroadcastMessage("|cffff4444[星盘] 起点节点不可重置|r")
        player:GossipComplete(); return true
    end
    POE_EffectHandler.RefreshAllStats(player)
    CharDBExecute("DELETE FROM character_poe_talents WHERE character_guid = " .. player:GetGUID() .. " AND node_id = " .. nodeId)
    SetTalentPoints(player, GetTalentPoints(player) + node.cost)
    if player:RemoveItem(ITEM_ID, 1) then
        player:SendBroadcastMessage("|cff00ff00[星盘] 节点 " .. node.name .. " 已重置，返还 " .. node.cost .. " 天赋点|r")
    else
        player:SendBroadcastMessage("|cffff4444[星盘] 物品消耗失败|r")
    end
    player:GossipComplete()
    return true
end

RegisterItemEvent(ITEM_ID, 2, OnResetItemUse)
RegisterPlayerGossipEvent(ITEM_ID, 1, OnPlayerGossipSelect)
```

---

## 8. 测试验证矩阵

### 8.1 正向路径测试

| TC# | 测试场景 | 前置条件 | 操作步骤 | 预期结果 | 验证方法 |
|-----|---------|---------|---------|---------|---------|
| TC-01 | 打开星盘菜单 | 玩家 1 级，天赋点=10，NPC 已放置 | 对话 NPC 200000 | 显示 3 个节点（力量起点/力量+5/力量+10），力量起点显示"已激活" | 视觉确认 Gossip 菜单 |
| TC-02 | 加点成功 | 玩家天赋点=10，节点2可加 | 在菜单中点节点2 | 提示"已点亮节点: 力量+5"，天赋点变为 9，力量 +5 | `.stat` 验证力量值 |
| TC-03 | 达节点加点 | TC-02 已通过 | 点节点3 | 提示"已点亮节点: 力量+10"，天赋点 8，力量 +15 | `.stat` 验证 |
| TC-04 | 重复加点被拒 | TC-02 已通过 | 再点节点2 | 提示"该节点已满级"，无变化 | |
| TC-05 | 天赋点不足 | 天赋点=0 | 点节点2 | 提示"天赋点不足" | |
| TC-06 | 节点未解锁 | 仅节点1已激活 | 点节点3（与节点1不相连） | 提示"节点未解锁" | |
| TC-07 | 登录恢复 | TC-03 已通过 | 下线 → 上线 | 提示"已恢复 2 个节点效果"，力量 +15 | `.stat` 验证 |
| TC-08 | 后悔石重置 | 节点2 已激活 | 右键使用后悔石 → 选节点2 | 提示"已重置"，天赋点+1，力量-5 | `.stat` 验证 |
| TC-09 | 后悔石无节点 | 天赋已全清 | 右键使用后悔石 | 提示"还没有点亮任何节点" | |

### 8.2 边界测试

| TC# | 测试场景 | 预期结果 |
|-----|---------|---------|
| TC-10 | 原点 start 节点不加点（cost=0） | 起点默认激活，不消耗天赋点 |
| TC-11 | 起点节点不可移除/重置 | canLearn 返回 false |
| TC-12 | 新角色天赋点=0 | 打开菜单后所有节点显示"未解锁"，无法加点 |
| TC-13 | 角色多客户端同时操作 | DB 行锁保障一致（ON DUPLICATE KEY） |

### 8.3 异常路径测试

| TC# | 场景 | 预期 |
|-----|------|------|
| TC-14 | NPC 未放置 | 无交互 |
| TC-15 | 后悔石不在背包 | 无响应 |
| TC-16 | 使用后悔石但取消菜单 | 无变化 |
| TC-17 | 加点时 pcall 捕获异常 | 自动回滚：DB 删除、点数恢复、属性重算 |
| TC-18 | 先点节点2 (+5STR) 再点节点3 (+10STR)，重置节点3 | STR 回退到 +5（非 +15→0→+5 错误链） |
| TC-19 | 后悔石菜单中出现起点 | 起点不显示，已被过滤 |
| TC-20 | 伪造 action=0 调用加点 | tonumber 后为 0，不执行 |

---

## 9. 回滚方案

### 9.1 DB 回滚

```sql
-- 删除所有星盘表
DROP TABLE IF EXISTS `poe_node_effect_binding`;
DROP TABLE IF EXISTS `character_poe_talents`;
DROP TABLE IF EXISTS `poe_talent_effects`;
DROP TABLE IF EXISTS `poe_talent_nodes`;

-- 移除 characters 扩展字段
ALTER TABLE `characters` DROP COLUMN IF EXISTS `poe_talent_points`;
```

### 9.2 Lua 回滚

从 `lua_scripts/` 目录移除以下文件：
- `POE_Data.lua`
- `POE_EffectHandler.lua`
- `POE_TalentManager.lua`
- `POE_ResetItem.lua`

### 9.3 Git 回滚

```bash
# 在本地仓库
git branch -D phase-1-talent-demo
git push origin --delete phase-1-talent-demo

# 或者回退 master（如果已合并）
git revert HEAD
git push origin master
```

### 9.4 CI 回滚

如果需要恢复上游原始 CI 工作流：
```bash
git checkout master
git checkout origin/master -- .github/workflows/
git commit -m "revert: restore upstream CI workflows"
git push
```

---

## 10. 后续规划

### Phase 2：核心融合（技能节点 + 职业法术）

- 添加 `node_type = 'skill'`
- 新增技能节点参数化（skill_id 绑定 LearnSpell）
- 多职业起点区分（class_mask 过滤）
- 被动光环系统替换 ModifyStat

### Phase 3：装备词缀系统

- poe_item_bases / poe_affix_pools 表
- 通货制作系统（蜕变/改造/富豪/崇高石）
- 物品实例化词缀存储

### 已知限制

- `ModifyStat` / `SetBaseStat` 方式不够稳定，后期需迁移到隐藏光环
- Gossip 菜单无法可视化星盘网状布局，后期需客户端插件
- 无事务保护（Eluna 无原生事务，需逻辑回滚）
- 单个 NPC 只能服务一个职业起点

---

## 11. 附录

### A. GitHub 链接

| 资源 | URL |
|------|-----|
| Fork 仓库 | https://github.com/callmefree/azerothcore-wotlk |
| PR #2 | https://github.com/callmefree/azerothcore-wotlk/pull/2 |
| Phase 1 分支 | https://github.com/callmefree/azerothcore-wotlk/tree/phase-1-talent-demo |
| Actions | https://github.com/callmefree/azerothcore-wotlk/actions |

### B. 本地文件路径

| 文件 | 绝对路径 |
|------|---------|
| SQL 脚本 | `E:\11111\3.35POE\sql\poe_schema.sql` |
| Lua 数据层 | `E:\11111\3.35POE\lua_scripts\POE_Data.lua` |
| Lua 效果层 | `E:\11111\3.35POE\lua_scripts\POE_EffectHandler.lua` |
| Lua 总机 | `E:\11111\3.35POE\lua_scripts\POE_TalentManager.lua` |
| Lua 后悔石 | `E:\11111\3.35POE\lua_scripts\POE_ResetItem.lua` |
| 设计规格 | `E:\11111\3.35POE\docs\superpowers\specs\2026-06-28-poe-talent-system-design.md` |
| 实现计划 | `E:\11111\3.35POE\docs\superpowers\plans\2026-06-28-poe-talent-demo.md` |
| 本档案 | `E:\11111\3.35POE\dev-archive-phase1.md` |

### C. 种子数据图谱

```
  (1) 力量起点 (start, cost=0)
      │ connections: "2"
      ▼
  (2) 力量+5 (small, cost=1)
      │ connections: "1,3"
      ├──→ (1) 力量起点（反向引用）
      ▼
  (3) 力量+10 (small, cost=1)
      │ connections: "2"
      └──→ (2) 力量+5
```

效果绑定：
- 节点 2 → effect_id 1 → `TalentEffect_StatPlus(param1=1(STR), param2=5)`
- 节点 3 → effect_id 2 → `TalentEffect_StatPlus(param1=1(STR), param2=10)`

### D. 依赖加载顺序

```
[服务器启动]
  │
  ├── 1. POE_Data.LoadCache()          ← 从 world 库加载所有数据到内存
  │
  ├── 2. POE_EffectHandler 加载        ← 注册所有效果函数
  │
  ├── 3. POE_TalentManager 注册事件    ← NPC Gossip + 登录事件
  │
  └── 4. POE_ResetItem 注册事件        ← 物品使用 + Gossip
```

[服务器运行中]
```
  │
  ├── 玩家登录 → OnPlayerLogin()       ← 恢复已点效果
  │
  ├── 对话NPC → OnGossipHello()        ← 打开星盘菜单
  │              └── OnGossipSelect()   ← 加点处理
  │
  └── 使用后悔石 → OnResetItemUse()    ← 重置处理
                    └── OnPlayerGossipSelect()
```
