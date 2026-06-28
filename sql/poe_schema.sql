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
-- Phase 2 种子数据：多职业技能节点 + 强化节点
-- ============================================================================

-- 更新现有节点的 class_mask（战士=1）
UPDATE `poe_talent_nodes` SET `class_mask` = 1 WHERE `node_id` IN (1,2,3);

-- 战士技能线
INSERT INTO `poe_talent_nodes` (`node_id`, `name`, `description`, `pos_x`, `pos_y`, `cost`, `connections`, `node_type`, `class_mask`) VALUES
(8,  '英勇打击', '学会英勇打击技能', 3, 0, 2, '2',   'skill',   1),
(9,  '强化英勇', '英勇打击伤害提高5%', 4, -1, 1, '8',  'small',   1),
(10, '破甲加成', '英勇打击额外降低护甲10%', 4, 1, 1, '8', 'small', 1)
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`), `description` = VALUES(`description`), `cost` = VALUES(`cost`), `connections` = VALUES(`connections`), `node_type` = VALUES(`node_type`), `class_mask` = VALUES(`class_mask`);

-- 法师火焰线
INSERT INTO `poe_talent_nodes` (`node_id`, `name`, `description`, `pos_x`, `pos_y`, `cost`, `connections`, `node_type`, `class_mask`) VALUES
(11, '火焰起点', '法师的火焰天赋起点', 0, 5, 0, '12',  'start',   256),
(12, '智力+5',   '增加5点智力',         1, 5, 1, '11,13', 'small',  256),
(13, '智力+10',  '增加10点智力',        2, 5, 1, '12',    'small',  256),
(14, '火球术',   '学会火球术技能',      3, 5, 2, '12',    'skill',  256),
(15, '火焰伤害+5%', '火焰法术伤害提高5%', 4, 4, 1, '14',  'small',  256),
(16, '点燃几率', '火焰法术有10%几率点燃目标', 4, 6, 1, '14', 'small', 256)
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`), `description` = VALUES(`description`), `cost` = VALUES(`cost`), `connections` = VALUES(`connections`), `node_type` = VALUES(`node_type`), `class_mask` = VALUES(`class_mask`);

-- Phase 2 效果定义（LearnSpell + ModDamagePercent）
INSERT INTO `poe_talent_effects` (`effect_id`, `effect_name`, `script_name`, `param1`, `param2`, `spell_id`) VALUES
(3, 'LearnSpell: 英勇打击', 'TalentEffect_LearnSpell', 0, 0, 78),
(4, 'LearnSpell: 火球术',   'TalentEffect_LearnSpell', 0, 0, 133),
(5, 'ModDamagePercent: 英勇+5%', 'TalentEffect_ModDamagePercent', 1, 5, 0),
(6, 'ModDamagePercent: 火焰+5%', 'TalentEffect_ModDamagePercent', 2, 5, 0),
(7, '法术触发: 点燃', 'TalentEffect_IgniteChance', 10, 0, 0)
ON DUPLICATE KEY UPDATE `effect_name` = VALUES(`effect_name`), `script_name` = VALUES(`script_name`), `param1` = VALUES(`param1`), `param2` = VALUES(`param2`), `spell_id` = VALUES(`spell_id`);

-- Phase 2 节点-效果绑定
INSERT INTO `poe_node_effect_binding` (`node_id`, `effect_id`) VALUES
(8, 3),
(9, 5),
(14, 4),
(15, 6),
(16, 7)
ON DUPLICATE KEY UPDATE `node_id` = VALUES(`node_id`), `effect_id` = VALUES(`effect_id`);

-- ============================================================================
-- Phase 2 迁移：ENUM 扩展 + class_mask
-- ============================================================================

-- 添加 'skill' 到 node_type ENUM
ALTER TABLE `poe_talent_nodes` MODIFY COLUMN `node_type` ENUM('small','notable','keystone','start','skill') NOT NULL DEFAULT 'small';

-- 添加 class_mask 列（职业掩码）
ALTER TABLE `poe_talent_nodes` ADD COLUMN IF NOT EXISTS `class_mask` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '职业掩码(1=战士,2=圣骑,4=猎人,8=盗贼,16=牧师,32=死骑,64=萨满,128=法师,256=术士,512=小德,1024=武僧,2048=恶魔猎手)' AFTER `talent_group`;

-- ============================================================================
-- 完成
-- ============================================================================
