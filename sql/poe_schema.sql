-- ============================================================================
-- PoE 星盘系统 - Phase 1 数据库架构与种子数据
-- 
-- 适用版本: MaNGOS Zero / Turtle WoM
-- 创建日期: 2026-06-28
-- 
-- 执行方式:
--   1. world 库部分：USE mangos0; SOURCE poe_schema.sql;
--   2. characters 库部分：USE characters; SOURCE poe_schema.sql;
--      （文件末尾会自动切换库执行）
-- ============================================================================

-- ============================================================================
-- Part A: world 库（节点定义、效果定义、关联表）
-- ============================================================================

-- 1. 天赋节点表 (poe_talent_nodes)
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

-- 2. 天赋效果定义表 (poe_talent_effects)
CREATE TABLE IF NOT EXISTS `poe_talent_effects` (
  `effect_id`   INT UNSIGNED    NOT NULL AUTO_INCREMENT,
  `effect_name` VARCHAR(100)    DEFAULT NULL COMMENT '备注名',
  `script_name` VARCHAR(128)    NOT NULL COMMENT 'Lua函数名',
  `param1`      INT             DEFAULT 0,
  `param2`      INT             DEFAULT 0,
  `spell_id`    INT UNSIGNED    NOT NULL DEFAULT 0 COMMENT '光环法术ID（被动）',
  PRIMARY KEY (`effect_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. 节点-效果关联表 (poe_node_effect_binding)
CREATE TABLE IF NOT EXISTS `poe_node_effect_binding` (
  `node_id`   INT UNSIGNED NOT NULL,
  `effect_id` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`node_id`, `effect_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- Seed 数据 — 3 个 Demo 节点（力量线）+ 效果绑定
-- ============================================================================

INSERT INTO `poe_talent_nodes` (`node_id`, `name`, `description`, `pos_x`, `pos_y`, `cost`, `connections`, `node_type`) VALUES
(1, '力量起点', '战士的天赋起点', 0, 0, 0, '2', 'start'),
(2, '力量+5',   '增加5点力量',     1, 0, 1, '1,3', 'small'),
(3, '力量+10',  '增加10点力量',    2, 0, 1, '2',   'small')
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`), `description` = VALUES(`description`), `cost` = VALUES(`cost`), `connections` = VALUES(`connections`);

INSERT INTO `poe_talent_effects` (`effect_id`, `effect_name`, `script_name`, `param1`, `param2`, `spell_id`) VALUES
(1, '力量+5',  'TalentEffect_StatPlus', 1, 5,  50000),
(2, '力量+10', 'TalentEffect_StatPlus', 1, 10, 50001)
ON DUPLICATE KEY UPDATE `effect_name` = VALUES(`effect_name`), `script_name` = VALUES(`script_name`), `param1` = VALUES(`param1`), `param2` = VALUES(`param2`), `spell_id` = VALUES(`spell_id`);

INSERT INTO `poe_node_effect_binding` (`node_id`, `effect_id`) VALUES
(2, 1),
(3, 2)
ON DUPLICATE KEY UPDATE `node_id` = VALUES(`node_id`), `effect_id` = VALUES(`effect_id`);

-- ============================================================================
-- Part B: characters 库（玩家数据表 + 角色扩展字段 + NPC/物品模板）
-- ⚠ 根据实际环境修改下一行的库名（AzerothCore 可能用 `acore_characters`）
-- ============================================================================
USE `characters`;

-- 4. 角色已学天赋表 (character_poe_talents) — 必须在 characters 库
CREATE TABLE IF NOT EXISTS `character_poe_talents` (
  `character_guid` INT UNSIGNED    NOT NULL,
  `node_id`        INT UNSIGNED    NOT NULL,
  `points_spent`   TINYINT UNSIGNED NOT NULL DEFAULT 1,
  PRIMARY KEY (`character_guid`, `node_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 5. 角色天赋点余额字段
ALTER TABLE `characters` ADD COLUMN IF NOT EXISTS `poe_talent_points` SMALLINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '可用天赋点数';

-- ============================================================================
-- Part C: characters 库 — NPC 200000 和物品 70000 模板
-- ============================================================================

-- 星盘导师 NPC（entry=200000）
INSERT INTO `creature_template` (`entry`, `name`, `subname`, `minlevel`, `maxlevel`, `faction`, `npcflag`, `display_id1`, `display_id2`, `display_id3`, `display_id4`, `AIName`, `ScriptName`)
VALUES (200000, '星盘导师', '流放之路天赋系统', 80, 80, 35, 1, 3503, 0, 0, 0, '', '')
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`), `subname` = VALUES(`subname`), `display_id1` = VALUES(`display_id1`);

-- 后悔石物品（entry=70000）
INSERT INTO `item_template` (`entry`, `name`, `class`, `subclass`, `Quality`, `Flags`, `maxcount`, `stackable`, `spellid_1`, `spelltrigger_1`, `description`)
VALUES (70000, '后悔石', 15, 0, 3, 0, 1, 20, 70000, 2, '右键使用，重置一个天赋节点')
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`);

-- ============================================================================
-- 完成
-- ============================================================================
