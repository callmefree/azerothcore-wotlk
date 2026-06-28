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
-- Phase 2 扩展：多职业星盘扩容
-- ============================================================================

-- === 战士扩展（class_mask=1）===
INSERT INTO `poe_talent_nodes` (`node_id`, `name`, `description`, `pos_x`, `pos_y`, `cost`, `connections`, `node_type`, `class_mask`) VALUES
(17, '致死打击', '学会致死打击技能', 3, -2, 2, '2', 'skill', 1),
(18, '强化致死', '致死打击伤害提高10%', 4, -2, 1, '17', 'small', 1),
(19, '旋风斩', '学会旋风斩技能', 3, 2, 2, '2', 'skill', 1),
(20, '强化旋风斩', '旋风斩伤害提高5%', 4, 2, 1, '19', 'small', 1)
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`), `description` = VALUES(`description`), `cost` = VALUES(`cost`), `connections` = VALUES(`connections`), `node_type` = VALUES(`node_type`), `class_mask` = VALUES(`class_mask`);

-- === 盗贼线（class_mask=8）===
INSERT INTO `poe_talent_nodes` (`node_id`, `name`, `description`, `pos_x`, `pos_y`, `cost`, `connections`, `node_type`, `class_mask`) VALUES
(21, '敏捷起点', '盗贼的天赋起点', 0, 10, 0, '22', 'start', 8),
(22, '敏捷+5', '增加5点敏捷', 1, 10, 1, '21,23', 'small', 8),
(23, '敏捷+10', '增加10点敏捷', 2, 10, 1, '22', 'small', 8),
(24, '邪恶攻击', '学会邪恶攻击技能', 3, 9, 2, '22', 'skill', 8),
(25, '强化邪恶攻击', '邪恶攻击伤害提高5%', 4, 9, 1, '24', 'small', 8),
(26, '背刺', '学会背刺技能', 3, 11, 2, '22', 'skill', 8),
(27, '强化背刺', '背刺伤害提高5%', 4, 11, 1, '26', 'small', 8),
(28, '潜行', '学会潜行技能', 5, 10, 2, '23', 'skill', 8),
(29, '强化潜行', '潜行效果提高', 6, 10, 1, '28', 'small', 8),
(30, '剔骨', '学会剔骨技能', 3, 13, 2, '22', 'skill', 8)
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`), `description` = VALUES(`description`), `cost` = VALUES(`cost`), `connections` = VALUES(`connections`), `node_type` = VALUES(`node_type`), `class_mask` = VALUES(`class_mask`);

-- === 牧师线（class_mask=16）===
INSERT INTO `poe_talent_nodes` (`node_id`, `name`, `description`, `pos_x`, `pos_y`, `cost`, `connections`, `node_type`, `class_mask`) VALUES
(31, '精神起点', '牧师的天赋起点', 0, 15, 0, '32', 'start', 16),
(32, '精神+5', '增加5点精神', 1, 15, 1, '31,33', 'small', 16),
(33, '精神+10', '增加10点精神', 2, 15, 1, '32', 'small', 16),
(34, '治疗术', '学会治疗术技能', 3, 14, 2, '32', 'skill', 16),
(35, '强化治疗术', '治疗术效果提高10%', 4, 14, 1, '34', 'small', 16),
(36, '暗言术：痛', '学会暗言术：痛技能', 3, 16, 2, '32', 'skill', 16),
(37, '暗影伤害+5%', '暗影法术伤害提高5%', 4, 16, 1, '36', 'small', 16),
(38, '真言术：盾', '学会真言术：盾技能', 5, 15, 2, '33', 'skill', 16),
(39, '强化护盾', '护盾吸收量提高10%', 6, 15, 1, '38', 'small', 16),
(40, '快速治疗', '学会快速治疗技能', 3, 13, 2, '32', 'skill', 16)
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`), `description` = VALUES(`description`), `cost` = VALUES(`cost`), `connections` = VALUES(`connections`), `node_type` = VALUES(`node_type`), `class_mask` = VALUES(`class_mask`);

-- === 猎手线（class_mask=4）===
INSERT INTO `poe_talent_nodes` (`node_id`, `name`, `description`, `pos_x`, `pos_y`, `cost`, `connections`, `node_type`, `class_mask`) VALUES
(41, '远程起点', '猎人的天赋起点', 0, 20, 0, '42', 'start', 4),
(42, '敏捷+5', '增加5点敏捷', 1, 20, 1, '41,43', 'small', 4),
(43, '敏捷+10', '增加10点敏捷', 2, 20, 1, '42', 'small', 4),
(44, '猎人印记', '学会猎人印记技能', 3, 19, 1, '42', 'skill', 4),
(45, '强化印记', '印记使攻击强度提高', 4, 19, 1, '44', 'small', 4),
(46, '毒蛇钉刺', '学会计能毒蛇钉刺', 3, 21, 2, '42', 'skill', 4),
(47, '强化毒蛇', '毒蛇钉刺伤害提高10%', 4, 21, 1, '46', 'small', 4),
(48, '稳固射击', '学会稳固射击技能', 5, 20, 2, '43', 'skill', 4),
(49, '强化稳固', '稳固射击伤害提高5%', 6, 20, 1, '48', 'small', 4),
(50, '多重射击', '学会多重射击技能', 3, 23, 2, '42', 'skill', 4)
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`), `description` = VALUES(`description`), `cost` = VALUES(`cost`), `connections` = VALUES(`connections`), `node_type` = VALUES(`node_type`), `class_mask` = VALUES(`class_mask`);

-- === 术士线（class_mask=256）===
INSERT INTO `poe_talent_nodes` (`node_id`, `name`, `description`, `pos_x`, `pos_y`, `cost`, `connections`, `node_type`, `class_mask`) VALUES
(51, '暗影起点', '术士的天赋起点', 0, 25, 0, '52', 'start', 256),
(52, '智力+5', '增加5点智力', 1, 25, 1, '51,53', 'small', 256),
(53, '智力+10', '增加10点智力', 2, 25, 1, '52', 'small', 256),
(54, '暗影箭', '学会暗影箭技能', 3, 24, 2, '52', 'skill', 256),
(55, '暗影伤害+5%', '暗影法术伤害提高5%', 4, 24, 1, '54', 'small', 256),
(56, '腐蚀术', '学会腐蚀术技能', 3, 26, 2, '52', 'skill', 256),
(57, '腐蚀增效', '腐蚀术伤害提高10%', 4, 26, 1, '56', 'small', 256),
(58, '召唤小鬼', '学会召唤小鬼技能', 5, 25, 2, '53', 'skill', 256)
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`), `description` = VALUES(`description`), `cost` = VALUES(`cost`), `connections` = VALUES(`connections`), `node_type` = VALUES(`node_type`), `class_mask` = VALUES(`class_mask`);

-- === 扩展效果定义 ===
INSERT INTO `poe_talent_effects` (`effect_id`, `effect_name`, `script_name`, `param1`, `param2`, `spell_id`) VALUES
-- 战士技能
(8,  'LearnSpell: 致死打击',  'TalentEffect_LearnSpell', 0, 0, 12294),
(9,  'LearnSpell: 旋风斩',    'TalentEffect_LearnSpell', 0, 0, 1680),
(10, 'ModDamagePercent: 致死+10%', 'TalentEffect_ModDamagePercent', 1, 10, 0),
(11, 'ModDamagePercent: 旋风斩+5%', 'TalentEffect_ModDamagePercent', 1, 5, 0),
-- 盗贼技能
(12, 'LearnSpell: 邪恶攻击',  'TalentEffect_LearnSpell', 0, 0, 1752),
(13, 'LearnSpell: 背刺',      'TalentEffect_LearnSpell', 0, 0, 53),
(14, 'LearnSpell: 潜行',      'TalentEffect_LearnSpell', 0, 0, 1784),
(15, 'LearnSpell: 剔骨',      'TalentEffect_LearnSpell', 0, 0, 2098),
(16, 'ModDamagePercent: 邪恶+5%', 'TalentEffect_ModDamagePercent', 1, 5, 0),
(17, 'ModDamagePercent: 背刺+5%', 'TalentEffect_ModDamagePercent', 1, 5, 0),
-- 牧师技能
(18, 'LearnSpell: 治疗术',    'TalentEffect_LearnSpell', 0, 0, 2060),
(19, 'LearnSpell: 暗言术痛',  'TalentEffect_LearnSpell', 0, 0, 589),
(20, 'LearnSpell: 真言术盾',  'TalentEffect_LearnSpell', 0, 0, 17),
(21, 'LearnSpell: 快速治疗',  'TalentEffect_LearnSpell', 0, 0, 2061),
-- 猎人技能
(22, 'LearnSpell: 猎人印记',  'TalentEffect_LearnSpell', 0, 0, 1130),
(23, 'LearnSpell: 毒蛇钉刺',  'TalentEffect_LearnSpell', 0, 0, 1978),
(24, 'LearnSpell: 稳固射击',  'TalentEffect_LearnSpell', 0, 0, 56641),
(25, 'LearnSpell: 多重射击',  'TalentEffect_LearnSpell', 0, 0, 2643),
-- 术士技能
(26, 'LearnSpell: 暗影箭',    'TalentEffect_LearnSpell', 0, 0, 686),
(27, 'LearnSpell: 腐蚀术',    'TalentEffect_LearnSpell', 0, 0, 172),
(28, 'LearnSpell: 召唤小鬼',  'TalentEffect_LearnSpell', 0, 0, 688),
-- 属性点（无 DBC 法术时直接修改属性）
(29, '敏捷+5',   'TalentEffect_StatPlus', 3, 5,  0),
(30, '敏捷+10',  'TalentEffect_StatPlus', 3, 10, 0),
(31, '精神+5',   'TalentEffect_StatPlus', 6, 5,  0),
(32, '精神+10',  'TalentEffect_StatPlus', 6, 10, 0)
ON DUPLICATE KEY UPDATE `effect_name` = VALUES(`effect_name`), `script_name` = VALUES(`script_name`), `param1` = VALUES(`param1`), `param2` = VALUES(`param2`), `spell_id` = VALUES(`spell_id`);

-- === 扩展绑定关系 ===
INSERT INTO `poe_node_effect_binding` (`node_id`, `effect_id`) VALUES
(17, 8),   (18, 10),  (19, 9),   (20, 11),
(22, 29),  (23, 30),  (24, 12),  (25, 16),
(26, 13),  (27, 17),  (28, 14),  (30, 15),
(32, 31),  (33, 32),  (34, 18),  (36, 19),
(38, 20),  (40, 21),
(42, 29),  (43, 30),  (44, 22),  (46, 23),
(48, 24),  (50, 25),
(52, 5),   (53, 5),   (54, 26),  (55, 6),
(56, 27),  (58, 28)
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
