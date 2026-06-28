-- ============================================================================
-- PoE 星盘系统 - Phase 1 数据库架构与种子数据
-- 
-- 适用版本: MaNGOS Zero / Turtle WoM
-- 创建日期: 2026-06-28
-- ============================================================================

-- 切换到 world 库（请根据实际数据库名调整）
-- USE `mangos0`;
-- USE `world`;

-- ============================================================================
-- 1. 天赋节点表 (poe_talent_nodes)
--    定义星盘上每一个可用的天赋节点。
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

-- ============================================================================
-- 2. 天赋效果定义表 (poe_talent_effects)
--    定义每个天赋节点能产生的实际游戏效果及其 Lua 回调。
-- ============================================================================
CREATE TABLE IF NOT EXISTS `poe_talent_effects` (
  `effect_id`   INT UNSIGNED    NOT NULL AUTO_INCREMENT,
  `effect_name` VARCHAR(100)    DEFAULT NULL COMMENT '备注名',
  `script_name` VARCHAR(128)    NOT NULL COMMENT 'Lua函数名',
  `param1`      INT             DEFAULT 0,
  `param2`      INT             DEFAULT 0,
  PRIMARY KEY (`effect_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- 3. 节点-效果关联表 (poe_node_effect_binding)
--    多对多关联节点与效果。
-- ============================================================================
CREATE TABLE IF NOT EXISTS `poe_node_effect_binding` (
  `node_id`   INT UNSIGNED NOT NULL,
  `effect_id` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`node_id`, `effect_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- 4. 角色已学天赋表 (character_poe_talents)
--    记录每个角色已激活的天赋节点及投入点数。
-- ============================================================================
CREATE TABLE IF NOT EXISTS `character_poe_talents` (
  `character_guid` INT UNSIGNED    NOT NULL,
  `node_id`        INT UNSIGNED    NOT NULL,
  `points_spent`   TINYINT UNSIGNED NOT NULL DEFAULT 1,
  PRIMARY KEY (`character_guid`, `node_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================================================
-- Seed 数据 — 3 个 Demo 节点（力量线）
-- ============================================================================

INSERT INTO `poe_talent_nodes` (`node_id`, `name`, `description`, `pos_x`, `pos_y`, `cost`, `connections`, `node_type`) VALUES
(1, '力量起点', '战士的天赋起点', 0, 0, 0, '2', 'start'),
(2, '力量+5',   '增加5点力量',     1, 0, 1, '1,3', 'small'),
(3, '力量+10',  '增加10点力量',    2, 0, 1, '2',   'small');

INSERT INTO `poe_talent_effects` (`effect_id`, `effect_name`, `script_name`, `param1`, `param2`) VALUES
(1, '力量+5',  'TalentEffect_StatPlus', 1, 5),
(2, '力量+10', 'TalentEffect_StatPlus', 1, 10);

INSERT INTO `poe_node_effect_binding` (`node_id`, `effect_id`) VALUES
(2, 1),
(3, 2);

-- ============================================================================
-- characters 库：扩展字段
-- 请先 USE `characters` 或 `auth` 再执行下面语句
-- ============================================================================
-- USE `characters`;

ALTER TABLE `characters` ADD COLUMN IF NOT EXISTS `poe_talent_points` SMALLINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '可用天赋点数';

-- ============================================================================
-- Phase 1 v2 — 隐藏光环迁移（可选，推荐）
-- ============================================================================

-- 效果表增加 spell_id 列，用于绑定 DBC 被动光环法术
ALTER TABLE `poe_talent_effects` ADD COLUMN IF NOT EXISTS `spell_id` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '光环法术ID（被动）' AFTER `param2`;

-- 更新种子数据，绑定自定义 DBC 法术
UPDATE `poe_talent_effects` SET `spell_id` = 50000 WHERE `effect_id` = 1;
UPDATE `poe_talent_effects` SET `spell_id` = 50001 WHERE `effect_id` = 2;

-- ============================================================================
-- 执行方式
-- ============================================================================
-- 1. 登录 MySQL/MariaDB:
--    mysql -u root -p
--
-- 2. 选择 world 库并执行建表与种子数据:
--    USE mangos0;
--    SOURCE /path/to/sql/poe_schema.sql;
--    或者直接导入:
--    mysql -u root -p mangos0 < E:\11111\3.35POE\sql\poe_schema.sql
--
-- 3. characters 库的 ALTER TABLE 需要单独执行:
--    mysql -u root -p characters < 包含 ALTER TABLE 的部分
--    或在 mysql 客户端中:
--    USE characters;
--    SOURCE /path/to/sql/poe_schema.sql;
--
-- ============================================================================
