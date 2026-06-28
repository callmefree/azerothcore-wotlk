# Phase 1 Demo — 星盘天赋系统 实现计划

> **面向 AI 代理的工作者：** 使用 subagent-driven-development（推荐）或 executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 在 AzerothCore + Eluna 上实现 3 节点星盘天赋 Demo，可加点/登录恢复/后悔石重置。

**架构：** 4 张 world 库表 + 1 个 characters 库扩展字段 + 4 个 Lua 脚本。
NPC 触发 Gossip 菜单交互，Eluna 事件驱动效果执行。

**技术栈：** AzerothCore (wotlk) + Eluna Lua 引擎 / MySQL 5.7+/ Lua 5.1

**参考设计规格：** `docs/superpowers/specs/2026-06-28-poe-talent-system-design.md`

---

### 任务 1：建表与种子数据

**文件：**
- 创建：`sql/poe_schema.sql`
- 执行目标：world 库（4 张表） + characters 库（1 个 ALTER）

- [ ] **步骤 1：编写 SQL 建表脚本**

```sql
-- ======== world 库：四张核心表 ========

CREATE TABLE IF NOT EXISTS `poe_talent_nodes` (
  `node_id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `name` VARCHAR(128) NOT NULL DEFAULT '' COMMENT '节点显示名',
  `description` TEXT COMMENT '节点效果描述',
  `pos_x` SMALLINT NOT NULL DEFAULT 0,
  `pos_y` SMALLINT NOT NULL DEFAULT 0,
  `icon_id` INT UNSIGNED NOT NULL DEFAULT 0,
  `max_rank` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  `cost` TINYINT UNSIGNED NOT NULL DEFAULT 1 COMMENT '消耗天赋点数，起点为0',
  `connections` TEXT COMMENT '相连node_id列表，逗号分隔',
  `node_type` ENUM('small','notable','keystone','start') NOT NULL DEFAULT 'small',
  `talent_group` VARCHAR(64) DEFAULT NULL COMMENT '集群标签',
  PRIMARY KEY (`node_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `poe_talent_effects` (
  `effect_id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `effect_name` VARCHAR(100) DEFAULT NULL COMMENT '备注名',
  `script_name` VARCHAR(128) NOT NULL COMMENT 'Lua函数名',
  `param1` INT DEFAULT 0,
  `param2` INT DEFAULT 0,
  PRIMARY KEY (`effect_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `poe_node_effect_binding` (
  `node_id` INT UNSIGNED NOT NULL,
  `effect_id` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`node_id`, `effect_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `character_poe_talents` (
  `character_guid` INT UNSIGNED NOT NULL,
  `node_id` INT UNSIGNED NOT NULL,
  `points_spent` TINYINT UNSIGNED NOT NULL DEFAULT 1,
  PRIMARY KEY (`character_guid`, `node_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ======== world 库：种子数据 ========

INSERT INTO `poe_talent_nodes` (`node_id`, `name`, `description`, `pos_x`, `pos_y`, `cost`, `connections`, `node_type`) VALUES
(1, '力量起点', '战士的天赋起点', 0, 0, 0, '2', 'start'),
(2, '力量+5', '增加5点力量', 1, 0, 1, '1,3', 'small'),
(3, '力量+10', '增加10点力量', 2, 0, 1, '2', 'small');

INSERT INTO `poe_talent_effects` (`effect_id`, `effect_name`, `script_name`, `param1`, `param2`) VALUES
(1, '力量+5',   'TalentEffect_StatPlus', 1, 5),
(2, '力量+10',  'TalentEffect_StatPlus', 1, 10);

INSERT INTO `poe_node_effect_binding` (`node_id`, `effect_id`) VALUES
(2, 1),
(3, 2);

-- ======== characters 库：扩展字段 ========
ALTER TABLE `characters` ADD COLUMN IF NOT EXISTS `poe_talent_points` SMALLINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '可用天赋点数';
```

- [ ] **步骤 2：执行建表脚本**

```sql
-- 连接 MySQL 执行
SOURCE /path/to/sql/poe_schema.sql;
```

验证：`SELECT * FROM poe_talent_nodes;` 返回 3 行。

- [ ] **步骤 3：Commit SQL 脚本**

---

### 任务 2：编写 POE_Data.lua（数据层）

**文件：**
- 创建：`lua_scripts/POE_Data.lua`

- [ ] **步骤 1：编写 POE_Data.lua**

```lua
-- POE_Data.lua
local POE_Data = {}
POE_Data.Nodes = {}
POE_Data.Effects = {}
POE_Data.Bindings = {}

function POE_Data.LoadCache()
    -- 加载节点定义
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

    -- 加载效果定义
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

    -- 加载绑定关系
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

function POE_Data.GetNodeData(nodeId)
    return POE_Data.Nodes[nodeId]
end

function POE_Data.GetNodeEffects(nodeId)
    local ids = POE_Data.Bindings[nodeId]
    if not ids then return {} end
    local effects = {}
    for _, eId in ipairs(ids) do
        if POE_Data.Effects[eId] then
            table.insert(effects, POE_Data.Effects[eId])
        end
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

-- 热重载入口
function POE_Data.ReloadCache()
    POE_Data.LoadCache()
    print("[POE] 星盘数据缓存已重载")
end

-- 初始化
POE_Data.LoadCache()
return POE_Data
```

- [ ] **步骤 2：Commit**

---

### 任务 3：编写 POE_EffectHandler.lua（效果执行器）

**文件：**
- 创建：`lua_scripts/POE_EffectHandler.lua`

- [ ] **步骤 1：编写 POE_EffectHandler.lua**

```lua
-- POE_EffectHandler.lua
local POE_EffectHandler = {}
local EffectRegistry = {}

function POE_EffectHandler.RegisterEffect(name, func)
    EffectRegistry[name] = func
end

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

function POE_EffectHandler.RemoveEffects(player, nodeId)
    local effects = POE_Data.GetNodeEffects(nodeId)
    for _, e in ipairs(effects) do
        local func = EffectRegistry[e.script]
        if func then
            func(player, e.param1, -e.param2)
        else
            print("[POE] 警告: 未注册的效果脚本 " .. e.script)
        end
    end
end

-- ===== 效果实现 =====

-- 通用属性加成（STAT_STRENGTH=1, STAT_AGILITY=2 等）
POE_EffectHandler.RegisterEffect("TalentEffect_StatPlus", function(player, statId, amount)
    local current = player:GetBaseStat(statId)
    player:SetBaseStat(statId, current + amount)
    player:SendBroadcastMessage("属性已变更: " .. (amount > 0 and "+" or "") .. amount)
end)

return POE_EffectHandler
```

- [ ] **步骤 2：Commit**

---

### 任务 4：编写 POE_TalentManager.lua（总机与 Gossip 交互）

**文件：**
- 创建：`lua_scripts/POE_TalentManager.lua`

- [ ] **步骤 1：编写 POE_TalentManager.lua**

```lua
-- POE_TalentManager.lua
local NPC_ENTRY = 200000

local function GetTalentPoints(player)
    local result = CharDBQuery("SELECT poe_talent_points FROM characters WHERE guid = " .. player:GetGUID())
    if result then return result:GetUInt16("poe_talent_points") else return 0 end
end

local function SetTalentPoints(player, points)
    CharDBExecute("UPDATE characters SET poe_talent_points = " .. points .. " WHERE guid = " .. player:GetGUID())
end

local function SaveTalent(player, nodeId)
    CharDBExecute("INSERT INTO character_poe_talents (character_guid, node_id, points_spent) VALUES (" .. player:GetGUID() .. ", " .. nodeId .. ", 1) ON DUPLICATE KEY UPDATE points_spent = points_spent + 1")
end

local function RemoveTalent(player, nodeId)
    CharDBExecute("DELETE FROM character_poe_talents WHERE character_guid = " .. player:GetGUID() .. " AND node_id = " .. nodeId)
end

local function CanLearn(player, nodeId, learnedTalents)
    local node = POE_Data.GetNodeData(nodeId)
    if not node then return false, "节点不存在" end

    -- 起点：未学习时可免费激活
    if node.node_type == "start" and not learnedTalents[nodeId] then
        return true, ""
    end

    -- 已满级不可再点
    if learnedTalents[nodeId] and learnedTalents[nodeId] >= node.max_rank then
        return false, "该节点已满级"
    end

    -- 连接有效性：与任一已激活节点相连即可
    local connected = false
    for _, connId in ipairs(node.connections) do
        if learnedTalents[connId] then
            connected = true
            break
        end
    end
    if not connected then
        return false, "节点未解锁（需要相邻节点已点亮）"
    end

    -- 天赋点足够
    local points = GetTalentPoints(player)
    if points < node.cost then
        return false, "天赋点不足"
    end

    return true, ""
end

local function OpenTalentMenu(player)
    local learned = POE_Data.LoadPlayerTalents(player:GetGUID())
    local points = GetTalentPoints(player)

    local gossip = player:CreateGossipMenu()
    gossip:AddText("【星盘天赋系统】 剩余天赋点: " .. points)
    gossip:AddText("------------------")

    for id, node in pairs(POE_Data.Nodes) do
        local status = "未解锁"
        if learned[id] then
            status = "已激活"
        else
            local can, _ = CanLearn(player, id, learned)
            if can then status = "[可加点]" end
        end
        gossip:AddMenuItem(id, node.name .. " (" .. status .. ")", 0)
    end

    gossip:AddMenuItem(999, "【重置所有天赋点】", 1)
    gossip:SendToPlayer(player)
end

local function OnGossipHello(event, player, creature)
    if creature:GetEntry() ~= NPC_ENTRY then return false end
    OpenTalentMenu(player)
    return true
end

local function OnGossipSelect(event, player, creature, sender, action, gossipId)
    if creature:GetEntry() ~= NPC_ENTRY then return false end

    if action == 999 then
        -- 全量重置（测试用）
        local learned = POE_Data.LoadPlayerTalents(player:GetGUID())
        for nodeId, _ in pairs(learned) do
            POE_EffectHandler.RemoveEffects(player, nodeId)
            RemoveTalent(player, nodeId)
        end
        SetTalentPoints(player, 10)
        player:SendBroadcastMessage("已重置所有天赋点")
        OpenTalentMenu(player)
        return true
    end

    local nodeId = action
    local learned = POE_Data.LoadPlayerTalents(player:GetGUID())
    local can, reason = CanLearn(player, nodeId, learned)

    if can then
        local node = POE_Data.GetNodeData(nodeId)
        -- 先写库（防失败）
        SaveTalent(player, nodeId)
        -- 应用效果
        POE_EffectHandler.ApplyEffects(player, nodeId)
        -- 扣点数
        SetTalentPoints(player, GetTalentPoints(player) - node.cost)
        player:SendBroadcastMessage("✅ 已点亮节点: " .. node.name)
    else
        player:SendBroadcastMessage("❌ " .. reason)
    end

    OpenTalentMenu(player)
    return true
end

local function OnPlayerLogin(event, player)
    local learned = POE_Data.LoadPlayerTalents(player:GetGUID())
    for nodeId, _ in pairs(learned) do
        POE_EffectHandler.ApplyEffects(player, nodeId)
    end
    player:SendBroadcastMessage("⚡ 星盘效果已恢复")
end

RegisterCreatureGossipEvent(NPC_ENTRY, 1, OnGossipHello)
RegisterCreatureGossipEvent(NPC_ENTRY, 2, OnGossipSelect)
RegisterPlayerEvent(3, OnPlayerLogin)
```

- [ ] **步骤 2：Commit**

---

### 任务 5：编写 POE_ResetItem.lua（后悔石）

**文件：**
- 创建：`lua_scripts/POE_ResetItem.lua`

- [ ] **步骤 1：编写 POE_ResetItem.lua**

```lua
-- POE_ResetItem.lua
local ITEM_ID = 70000

local function OnResetItemUse(event, player, item, target)
    local learned = POE_Data.LoadPlayerTalents(player:GetGUID())
    local count = 0
    for _ in pairs(learned) do count = count + 1 end

    if count == 0 then
        player:SendBroadcastMessage("你还没有点亮任何节点")
        return true
    end

    local gossip = player:CreateGossipMenu()
    gossip:AddText("选择要重置的节点:")
    for nodeId, _ in pairs(learned) do
        local node = POE_Data.GetNodeData(nodeId)
        if node then
            gossip:AddMenuItem(nodeId, node.name, 0)
        end
    end
    gossip:SendToPlayer(player)
    return true
end

local function OnPlayerGossipSelect(event, player, sender, action, gossipId)
    if gossipId ~= ITEM_ID then return false end

    local nodeId = action
    local node = POE_Data.GetNodeData(nodeId)
    if not node then return true end

    -- 移除效果
    POE_EffectHandler.RemoveEffects(player, nodeId)
    -- 删除DB记录
    CharDBExecute("DELETE FROM character_poe_talents WHERE character_guid = " .. player:GetGUID() .. " AND node_id = " .. nodeId)
    -- 归还天赋点
    SetTalentPoints(player, GetTalentPoints(player) + node.cost)
    -- 消耗物品
    if player:RemoveItem(ITEM_ID, 1) then
        player:SendBroadcastMessage("✅ 节点 " .. node.name .. " 已重置，返还 " .. node.cost .. " 天赋点")
    else
        player:SendBroadcastMessage("❌ 物品消耗失败")
    end
    return true
end

RegisterItemEvent(ITEM_ID, 2, OnResetItemUse)
RegisterPlayerGossipEvent(ITEM_ID, 1, OnPlayerGossipSelect)
```

- [ ] **步骤 2：Commit**

---

### 任务 6：服务器配置与验证

- [ ] **步骤 1：确认 Lua 脚本目录**

验证 `worldserver.conf` 中 `Eluna.ScriptPath` 指向 `lua_scripts/` 目录。

- [ ] **步骤 2：放置脚本文件**

将 `POE_Data.lua`、`POE_EffectHandler.lua`、`POE_TalentManager.lua`、`POE_ResetItem.lua` 放入 `lua_scripts/` 目录。

- [ ] **步骤 3：创建 NPC**

```sql
-- 在world库中插入自定义NPC
-- 使用现有模型（比如训练师模型 display_id 3503）
-- 或者使用 .npc add 200000 命令
```

游戏内命令：`.npc add 200000`（到主城放置）

- [ ] **步骤 4：添加初始天赋点**

```sql
UPDATE characters SET poe_talent_points = 10 WHERE guid = <你的角色GUID>;
```

或游戏内命令：直接修改数据库。

- [ ] **步骤 5：添加后悔石**

游戏内命令：`.additem 70000`

- [ ] **步骤 6：测试正向路径——加点**

```
1. 对话 NPC 200000
2. 确认显示 3 个节点菜单
3. 点击节点 2 "力量+5"
4. 确认消息 "✅ 已点亮节点"
5. 查看角色面板，力量 +5
6. 天赋点 -1
```

- [ ] **步骤 7：测试路径——登录恢复**

```
1. 下线角色
2. 重新登录
3. 确认消息 "⚡ 星盘效果已恢复"
4. 查看角色面板，力量仍为 +5（总属性）
```

- [ ] **步骤 8：测试路径——后悔石重置**

```
1. 使用后悔石（右键点击）
2. 显示已点节点列表（节点2）
3. 选择节点2
4. 确认消息 "✅ 节点 力量+5 已重置"
5. 天赋点 +1
6. 力量回到原始值
```
