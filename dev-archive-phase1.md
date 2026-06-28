# 流放艾泽拉斯 — Phase 1 开发档案

> **项目代号**: 流放艾泽拉斯 (Flow Exile Azeros)  
> **基础项目**: AzerothCore (wotlk) + Eluna 引擎  
> **Fork**: [callmefree/azerothcore-wotlk](https://github.com/callmefree/azerothcore-wotlk)  
> **开发日期**: 2026-06-28  
> **版本**: v2 (隐藏光环系统)  
> **作者**: WorkBuddy AI (Buddy) — MaNGOS/TurtleWoW 运维伙伴  

---

## 目录

1. [项目背景与动机](#1-项目背景与动机)
2. [开发流程记录](#2-开发流程记录)
3. [设计决策记录 (ADR)](#3-设计决策记录-adr)
4. [数据库架构](#4-数据库架构)
5. [Lua 脚本架构](#5-lua-脚本架构)
6. [DBC 法术创建指南](#6-dbc-法术创建指南)
7. [CI/CD 配置](#7-cicd-配置)
8. [完整的代码清单](#8-完整的代码清单)
9. [测试验证矩阵](#9-测试验证矩阵)
10. [回滚方案](#10-回滚方案)
11. [后续规划](#11-后续规划)
12. [附录](#12-附录)

---

## 1. 项目背景与动机

### 1.1 目标

在 AzerothCore 服务端上实现《流放之路》(Path of Exile) 风格的天赋星盘系统，完全取代魔兽原版的天赋面板。

### 1.2 核心创新点

- **星盘系统**: 网状天赋节点取代线性天赋树，节点间通过连接关系定义可达性
- **脚本驱动**: 所有效果通过 `script_name + param1/param2` 配置化，Lua 函数名动态绑定
- **隐藏光环**: 使用 DBC 被动光环，属性叠加/移除/登录恢复由魔兽引擎原生管理
- **消耗品重置**: 对标 PoE "后悔石" 的单个节点重置道具
- **事务保护**: pcall 包裹加点流程，失败时自动回滚

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

代码审查 → 5项硬伤修复 (v1.1)
  ├── SQL注入防御 → tonumber()
  ├── 属性全局重算 → RefreshAllStats
  ├── 事务保护 → pcall 回滚
  ├── 起点过滤 → 重置菜单过滤 start
  └── Gossip菜单ID → CreateGossipMenu(ITEM_ID)

架构升级 → 隐藏光环 (v2)
  └── SetBaseStat → AddAura/RemoveAura (spell_id)
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
| 代码审查 + 5 项硬伤修复 (v1.1) | 2 min | 5 |
| 隐藏光环迁移 (v2) | 3 min | 8 |
| **总计** | **~48 min** | **93+** |

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

### ADR-009: 属性系统 — 全局重算模式（v1.1 Hotfix → 已被 v2 取代）

- **状态**: 🔄 已被 ADR-014 取代
- **决策**: 弃用增量，改为 `RefreshAllStats()` 全局重算
- **原因**: 增量模式在节点移除顺序颠倒时产生属性叠加错误
- **被取代原因**: v2 隐藏光环更优（引擎原生管理叠加/移除，零重算，登录自动恢复）

### ADR-010: 事务保护与回滚（v1.1 Hotfix）

- **状态**: ✅ 保留
- **决策**: 加点流程用 `pcall` 包装，失败时手动回滚
- **原因**: 多点写入无原子性

### ADR-011: SQL 注入防御（v1.1 Hotfix）

- **状态**: ✅ 保留
- **决策**: 所有从 Gossip action/Sender 获取的整数值强制 `tonumber()`

### ADR-012: 起点节点不可重置（v1.1 Hotfix）

- **状态**: ✅ 保留

### ADR-013: Gossip 菜单 ID 显式绑定（v1.1 Hotfix）

- **状态**: ✅ 保留

### ADR-014: 迁移至隐藏光环系统（v2）

- **状态**: ✅ 当前方案
- **决策**: 将属性效果从 Lua `SetBaseStat` 改为 DBC 被动光环 `player:AddAura(spell_id)`
- **原因**: 原生光环管理叠加/移除/登录恢复，零重算逻辑，性能最优
- **方案**:
  - `poe_talent_effects` 增加 `spell_id` 列
  - `POE_EffectHandler.TalentEffect_StatPlus` 改为 `AddAura/RemoveAura`
  - 效果表 script_name 维持 `"TalentEffect_StatPlus"` 不变
- **DBC 需求**: 需手动创建 50000 (+5STR) 和 50001 (+10STR)
- **影响**: 彻底消除属性叠加问题，登录恢复零代码负担

---

## 4. 数据库架构

### 4.1 ER 关系

```
poe_talent_nodes (1) ──── (N) poe_node_effect_binding (N) ──── (1) poe_talent_effects
        │                                                               │
        │  node_id (PK)              node_id + effect_id (复合PK)        effect_id (PK)
        │  name                                                            script_name
        │  description                                                    param1
        │  pos_x / pos_y                                                  param2
        │  icon_id                                                        spell_id (v2: DBC法术ID)
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
| `poe_talent_effects` | world | 效果定义 | effect_id, script_name, param1, param2, **spell_id** (v2) |
| `poe_node_effect_binding` | world | 节点↔效果 M:N | node_id, effect_id (复合主键) |
| `character_poe_talents` | world | 角色已点节点 | character_guid, node_id |
| `characters.poe_talent_points` | characters | 角色可用天赋点 | SMALLINT UNSIGNED (新增列) |

---

## 5. Lua 脚本架构

### 5.1 文件依赖关系

```
POE_Data.lua (全局表)
  └── 无依赖，启动时自动 LoadCache()
  
POE_EffectHandler.lua (v2 光环版本)
  ├── 依赖: POE_Data (取节点效果列表)
  └─→ AddAura(spell_id) / RemoveAura(spell_id)
  
POE_TalentManager.lua
  ├── 依赖: POE_Data
  ├── 依赖: POE_EffectHandler
  └── 注册: RegisterCreatureGossipEvent + RegisterPlayerEvent

POE_ResetItem.lua
  ├── 依赖: POE_Data
  ├── 依赖: POE_EffectHandler
  └── 注册: RegisterItemEvent + RegisterPlayerGossipEvent
```

**加载顺序必须为**：① POE_Data.lua → ② POE_EffectHandler.lua → ③ POE_TalentManager.lua → ④ POE_ResetItem.lua

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
  → OpenTalentMenu() 渲染节点列表
  → 玩家选择节点 → OnGossipSelect()
  → CanLearn() 验证链
  → pcall() 事务保护:
    ① SaveTalent() 写库
    ② SetTalentPoints() 扣点
    ③ ApplyEffects() → AddAura(spell_id) 应用光环
  → pcall 失败 → 回滚: RemoveTalent() + 还点数
```

#### 后悔石重置流程

```
使用物品 70000 → OnResetItemUse()
  → 过滤 start 节点
  → 弹出菜单 → 选择节点 → OnPlayerGossipSelect()
  → RemoveEffects() → RemoveAura(spell_id)
  → DELETE character_poe_talents
  → 还点数 + 消耗后悔石
```

#### 登录恢复流程

```
角色登录 → OnPlayerLogin()
  → POE_EffectHandler.RestoreOnLogin()
  → 遍历已点节点 → AddAura(spell_id)
  → 提示已恢复 N 个光环
```

---

## 6. DBC 法术创建指南（v2 必要步骤）

**本步骤需要手动完成，一次性。** 创建后后续节点只需填不同 spell_id 即可。

### 所需工具

MyDBCEditor — 编辑 `spell.dbc`（GitHub 或 AzerothCore 社区可下载）。

### 操作步骤

1. 备份原始 `spell.dbc`
2. 用 MyDBCEditor 打开
3. 追加以下两行：

| 字段 | 列号 | 50000 | 50001 |
|------|------|-------|-------|
| ID | 0 | 50000 | 50001 |
| 名称 (Name) | 13-20 | 星盘之力+5 | 星盘之力+10 |
| 效果1 (Effect 1) | 30 | 21 | 21 |
| 效果基础值1 (BasePoints) | 33 | 5 | 10 |
| 效果Misc值1 (MiscValueA) | 35 | 1 (STR) | 1 (STR) |
| 施法时间 | 46 | 0 | 0 |
| 持续时间 | 50 | -1 (永久) | -1 (永久) |
| 法术等级 | 47 | 0 | 0 |
| 法力消耗 | 49 | 0 | 0 |
| 法术类别 | 60 | 0 | 0 |

4. 保存，重启服务端生效

### 验证

```sql
SELECT effect_id, script_name, spell_id FROM poe_talent_effects;
-- 返回: 1 | TalentEffect_StatPlus | 50000
--       2 | TalentEffect_StatPlus | 50001
```

---

## 7. CI/CD 配置

### 7.1 Fork CI 适配

上游工作流全部包含 `if: github.repository == 'azerothcore/azerothcore-wotlk'`，改为允许 fork 编译：

```yaml
if: (github.repository == 'azerothcore/azerothcore-wotlk' || github.repository_owner == 'callmefree')
```

### 7.2 已适配的工作流

| 工作流文件 | 触发方式 | 编译目标 |
|-----------|---------|---------|
| `.github/workflows/core-build-pch.yml` | push(master) / PR | Ubuntu with PCH |
| `.github/workflows/core-build-nopch.yml` | push(master) / PR | Ubuntu without PCH |
| `.github/workflows/core_modules_build.yml` | push(master) / PR | Modules |
| `.github/workflows/windows_build.yml` | push(master) / labeled PR | Windows (MSVC) |
| `.github/workflows/macos_build.yml` | push(master) / PR | macOS |

---

## 8. 完整的代码清单

### 8.1 文件索引

| # | 文件路径 | 行数 | 类型 | 大小 | 版本 |
|---|---------|------|------|------|------|
| 1 | `sql/poe_schema.sql` | 120+ | SQL | 5.5 KB | v2 |
| 2 | `lua_scripts/POE_Data.lua` | 100 | Lua | 3.6 KB | v2 |
| 3 | `lua_scripts/POE_EffectHandler.lua` | 48 | Lua | 2.0 KB | v2 光环 |
| 4 | `lua_scripts/POE_TalentManager.lua` | 130 | Lua | 5.2 KB | v2 |
| 5 | `lua_scripts/POE_ResetItem.lua` | 52 | Lua | 2.5 KB | v2 |
| 6 | 设计规格文档 | 206 | Markdown | 8.5 KB | v1 |
| 7 | 实现计划 | 280 | Markdown | 10.2 KB | v1 |

### 8.2 sql/poe_schema.sql（v2）

```sql
-- 4张 world 表（同 v1，略——详见 poe_schema.sql 文件）
-- ...

-- v2 新增：spell_id 列
ALTER TABLE `poe_talent_effects` ADD COLUMN IF NOT EXISTS `spell_id` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '光环法术ID（被动）' AFTER `param2`;

UPDATE `poe_talent_effects` SET `spell_id` = 50000 WHERE `effect_id` = 1;
UPDATE `poe_talent_effects` SET `spell_id` = 50001 WHERE `effect_id` = 2;
```

### 8.3 lua_scripts/POE_Data.lua（v2）

```lua
-- POE_Data.lua (v2)
-- 核心变动：LoadCache() 读取 spell_id 列
local effectResult = WorldDBQuery("SELECT effect_id, script_name, param1, param2, spell_id FROM poe_talent_effects")
-- 详见 POE_Data.lua 文件
```

### 8.4 lua_scripts/POE_EffectHandler.lua（v2 光环）

```lua
-- POE_EffectHandler.lua — v2 隐藏光环版
local POE_EffectHandler = {}
local EffectRegistry = {}

function POE_EffectHandler.RegisterEffect(name, func)
    EffectRegistry[name] = func
end

function POE_EffectHandler.ApplyEffects(player, nodeId)
    local effects = POE_Data.GetNodeEffects(nodeId)
    for _, e in ipairs(effects) do
        local func = EffectRegistry[e.script]
        if func then func(player, e, true)
        else print("[POE] 警告: 未注册的效果脚本 " .. e.script) end
    end
end

function POE_EffectHandler.RemoveEffects(player, nodeId)
    local effects = POE_Data.GetNodeEffects(nodeId)
    for _, e in ipairs(effects) do
        local func = EffectRegistry[e.script]
        if func then func(player, e, false)
        else print("[POE] 警告: 未注册的效果脚本 " .. e.script) end
    end
end

-- 通用光环：engine manages stacking/removal
POE_EffectHandler.RegisterEffect("TalentEffect_StatPlus", function(player, e, isApply)
    if e.spell_id == 0 then print("[POE] 警告: 缺少 spell_id"); return end
    if isApply then player:AddAura(e.spell_id, player)
    else player:RemoveAura(e.spell_id) end
end)

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

return POE_EffectHandler
```

### 8.5 lua_scripts/POE_TalentManager.lua（v2 安全加固 + 光环）

```lua
-- 核心变化：OnGossipSelect 中用 ApplyEffects（光环）替代 RefreshAllStats
-- OnPlayerLogin 调用 RestoreOnLogin
-- pcall 事务保护 + tonumber 注入防御 均保留
-- 详见 POE_TalentManager.lua 文件
```

### 8.6 lua_scripts/POE_ResetItem.lua（v2）

```lua
-- 逻辑不变（RemoveEffects 已适配光环版）
-- 起点过滤 + CreateGossipMenu(ITEM_ID) + tonumber 均保留
-- 详见 POE_ResetItem.lua 文件
```

---

## 9. 测试验证矩阵

### 9.1 正向路径测试

| TC# | 测试场景 | 前置条件 | 操作步骤 | 预期结果 | 验证方法 |
|-----|---------|---------|---------|---------|---------|
| TC-01 | 打开星盘菜单 | DBC 已安装，NPC 已放置 | 对话 NPC 200000 | 显示 3 个节点 | 视觉确认 |
| TC-02 | 加点成功 | 天赋点=10 | 点节点2 | 光环 50000 激活，力量 +5 | `.stat` 或光环面板 |
| TC-03 | 达节点加点 | TC-02 已通过 | 点节点3 | 光环 50001 激活，力量 +15 | `.stat` |
| TC-04 | 重复加点被拒 | 已点节点2 | 再点节点2 | "该节点已满级" | |
| TC-05 | 天赋点不足 | 点数为0 | 点节点 | "天赋点不足" | |
| TC-06 | 节点未解锁 | 仅起点 | 点节点3 | "节点未解锁" | |
| TC-07 | 登录恢复 | 2 个节点已激活 | 下线→上线 | 力量 +15，提示恢复 2 个光环 | `.stat` |
| TC-08 | 后悔石重置 | 节点2 激活 | 右键→选择节点2 | 光环 50000 移除，力量 -5 | `.stat` |
| TC-09 | 后悔石无节点 | 天赋全清 | 右键物品 | "没有可以重置的节点" | |

### 9.2 边界测试

| TC# | 测试场景 | 预期结果 |
|-----|---------|---------|
| TC-10 | 起点 cost=0，默认激活 | 不消耗点数 |
| TC-11 | 起点不可重置 | 过滤，不在重置菜单中 |
| TC-12 | 新角色天赋点=0 | 所有节点显示未解锁 |
| TC-13 | 并发加点 | ON DUPLICATE KEY 保障 |

### 9.3 异常路径

| TC# | 场景 | 预期 |
|-----|------|------|
| TC-14 | NPC 未放置 | 无交互 |
| TC-15 | DBC 法术 50000 未创建 | AddAura 无效果，print 日志 |
| TC-16 | 取消重置菜单 | 无变化 |

### 9.4 v2 新增验证

| TC# | 场景 | 预期 |
|-----|------|------|
| TC-17 | 加点 pcall 捕获异常 | 回滚：DB 删除 + 点数恢复 |
| TC-18 | 光环叠加正确性 | 加 A(50000)+B(50001)，移 A 后 B 仍在，力量 +10 |
| TC-19 | 光环自动持久化 | 下线后光环由引擎保存，上线自动恢复 |
| TC-20 | 伪造 action=0 | tonumber→0，跳过 |

---

## 10. 回滚方案

### 10.1 DB 回滚

```sql
DROP TABLE IF EXISTS `poe_node_effect_binding`;
DROP TABLE IF EXISTS `character_poe_talents`;
DROP TABLE IF EXISTS `poe_talent_effects`;
DROP TABLE IF EXISTS `poe_talent_nodes`;
ALTER TABLE `characters` DROP COLUMN IF EXISTS `poe_talent_points`;
ALTER TABLE `poe_talent_effects` DROP COLUMN IF EXISTS `spell_id`;
```

### 10.2 DBC 回滚

用备份恢复原始 `spell.dbc`。

### 10.3 Lua 回滚

从 `lua_scripts/` 移除 4 个 POE 文件。

### 10.4 Git 回滚

```bash
git branch -D phase-1-talent-demo
git push origin --delete phase-1-talent-demo
```

### 10.5 CI 回滚

```bash
git checkout master
git checkout origin/master -- .github/workflows/
git commit -m "revert: restore upstream CI workflows"
git push
```

---

## 11. 后续规划

### Phase 2：核心融合（技能节点 + 职业法术）

- 新增 `node_type = 'skill'`，`spell_id` 指向学习技能
- 多职业起点（`class_mask` 字段）
- 显示优化

### Phase 3：装备词缀系统

- poe_item_bases / poe_affix_pools
- 通货制作（蜕变/改造/富豪/崇高石）

### 已知限制

- DBC 编辑需要手动操作
- Gossip 菜单无法可视化网状布局（后期需客户端插件）
- 无 Eluna 原生事务，pcall 回滚是逻辑层保护

---

## 12. 附录

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
  (1) 力量起点 (start, cost=0) → (2) 力量+5 (small, cost=1, spell=50000)
                                    ↓
                               (3) 力量+10 (small, cost=1, spell=50001)
```

### D. 架构演进路线

| 版本 | 方案 | 属性管理 | 登录恢复 | 当前状态 |
|------|------|---------|---------|---------|
| v0 | 增量 SetBaseStat | Lua 手动 | Lua 遍历 | ❌ 已废弃 |
| v1.1 | 全局重算 RefreshAllStats | Lua 遍历汇总 | Lua 遍历 | ❌ 已废弃 |
| **v2** | **隐藏光环 AddAura** | **引擎原生** | **引擎原生** | ✅ **当前方案** |
