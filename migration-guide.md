# 流放艾泽拉斯 — 项目迁移说明

> 将开发环境从旧设备完整迁移到新设备，保留全部 git 历史、开发进度和工具链。

---

## 目录

1. [迁移清单](#1-迁移清单)
2. [新设备环境搭建](#2-新设备环境搭建)
3. [代码迁移](#3-代码迁移)
4. [数据库部署](#4-数据库部署)
5. [客户端插件安装](#5-客户端插件安装)
6. [验证清单](#6-验证清单)
7. [常见问题](#7-常见问题)
8. [附录：项目全景](#8-附录项目全景)

---

## 1. 迁移清单

出发前从旧设备收集以下内容：

| # | 项目 | 路径（旧设备） | 必须？ |
|---|------|---------------|--------|
| 1 | SSH 私钥 | `~/.ssh/id_ed25519` + `id_ed25519.pub` | ✅ 必须（git push 需要） |
| 2 | 项目源码 | 直接从 GitHub clone | ❌ 无需手动打包 |
| 3 | 开发记忆 | `E:\11111\3.35POE\.workbuddy\` | ⚠️ 建议（保留开发上下文） |
| 4 | 数据库备份 | MySQL dump | ⚠️ 建议（保留角色数据） |
| 5 | tar.gz 包 | `E:\11111\3.35POE\POE_StarAtlas_Phase2.tar.gz` | ❌ 备用方案 |
| 6 | GitHub token | 如使用 gh CLI 需要重新认证 | ⚠️ 如果用 gh 操作 PR |

---

## 2. 新设备环境搭建

### 2.1 安装 Git

**Windows**: 下载 [Git for Windows](https://git-scm.com/download/win) 安装包，一路默认即可。

**Linux (Ubuntu/Debian)**:
```bash
sudo apt update && sudo apt install git -y
```

验证：`git --version` 应显示 2.x+。

### 2.2 安装 GitHub CLI（可选，用于 PR 管理）

```bash
# Windows (Git Bash 中执行):
curl -L "https://github.com/cli/cli/releases/latest/download/gh_$(curl -s https://api.github.com/repos/cli/cli/releases/latest | grep tag_name | cut -d'"' -f4 | tr -d 'v')_windows_amd64.zip" -o /tmp/gh.zip
unzip /tmp/gh.zip -d /tmp/gh_extract
cp /tmp/gh_extract/bin/gh.exe /usr/bin/gh.exe
gh --version

# Linux:
# sudo apt install gh  或 参考 https://github.com/cli/cli/blob/trunk/docs/install_linux.md
```

### 2.3 配置 SSH 认证

将旧设备的 SSH 私钥复制到新设备：

```bash
# 在旧设备上查看公钥（确认是哪个 key 绑定了 GitHub）:
cat ~/.ssh/id_ed25519.pub

# 复制整个 ~/.ssh/ 目录到新设备同位置，或：
# 在新设备上创建新 key:
ssh-keygen -t ed25519 -C "674968117@qq.com"
# 然后去 GitHub -> Settings -> SSH and GPG keys 添加新公钥
```

验证连接：
```bash
ssh -T git@github.com
# 预期输出: Hi callmefree! You've successfully authenticated...
```

### 2.4 配置 Git 用户

```bash
git config --global user.name "callmefree"
git config --global user.email "674968117@qq.com"
```

---

## 3. 代码迁移

### 方式 A：完整 Git 恢复（推荐，保留全部提交历史）

```bash
# 克隆 fork（用 SSH）:
git clone git@github.com:callmefree/azerothcore-wotlk.git
cd azerothcore-wotlk

# 切换到开发分支:
git checkout phase-1-talent-demo

# 确认历史完整:
git log --oneline -5
# 应看到 beb4c1e, e79e252, 3537841, ... 等提交

# 确认远程可写:
git push origin phase-1-talent-demo
# 输出: Everything up-to-date
```

### 方式 B：打包文件恢复（备用）

```bash
git clone git@github.com:callmefree/azerothcore-wotlk.git
cd azerothcore-wotlk
git checkout phase-1-talent-demo
tar xzf POE_StarAtlas_Phase2.tar.gz
git status  # 应显示若干未提交的变更（打包时可能包含未提交文件）
```

### 方式 C：全新开始（从零搭建）

```bash
# 方法同上，clone 后无需任何额外步骤
# 所有自定义文件已在 git 仓库中
```

---

## 4. 数据库部署

### 4.1 导入架构和种子数据

```bash
# 导入 world 库部分:
mysql -u root -p mangos0 < sql/poe_schema.sql

# 如果数据库名不同（如 AzerothCore 的 acore_world）:
mysql -u root -p acore_world < sql/poe_schema.sql
```

执行前手动编辑 `sql/poe_schema.sql`，找到 `USE \`characters\`;` 这一行，将库名改为实际使用的名称。

### 4.2 验证导入

```sql
USE mangos0;
SELECT COUNT(*) FROM poe_talent_nodes;    -- 应返回 68
SELECT COUNT(*) FROM poe_talent_effects;  -- 应返回 40
SELECT COUNT(*) FROM poe_node_effect_binding;  -- 应返回 60+

SELECT node_id, name, node_type, class_mask FROM poe_talent_nodes LIMIT 10;
```

### 4.3 创建 DBC 法术（手动，一次性）

用 MyDBCEditor 打开 `spell.dbc`，追加两条被动光环法术：

| 字段 | ID 50000 | ID 50001 |
|------|----------|----------|
| Name | 星盘之力+5 | 星盘之力+10 |
| Effect 1 | 21 (STAT) | 21 (STAT) |
| BasePoints | 5 | 10 |
| MiscValueA | 1 (STR) | 1 (STR) |
| 持续时间 | -1 (永久) | -1 (永久) |

保存后重启服务端。

---

## 5. 客户端插件安装

```bash
# 将 addons 目录复制到 WoW 客户端:
cp -r addons/POEStarMap "/path/to/WoW/Interface/AddOns/POEStarMap"
```

在 WoW 插件列表中确认 "POE 星盘" 已勾选。

游戏内：
- 输入 `/poemap` 或 `/poestar` 打开星盘
- 或按 `Alt+S` 快捷键
- 左键节点加点，右键节点重置

---

## 6. 验证清单

在新设备上依次验证：

- [ ] `git log --oneline | wc -l` ≥ 24（提交历史完整）
- [ ] `git remote -v` 指向 `callmefree/azerothcore-wotlk`
- [ ] 当前在 `phase-1-talent-demo` 分支
- [ ] `git push origin phase-1-talent-demo` 成功（无权限错误）
- [ ] 数据库 `poe_talent_nodes` 有 68 条记录
- [ ] `lua_scripts/` 下有 6 个 POE_ 开头的文件
- [ ] `addons/POEStarMap/` 有 3 个文件（toc/xml/lua）
- [ ] 服务端启动无 Lua 报错
- [ ] 游戏内 NPC 200000 可交互
- [ ] `/poemap` 可打开星盘面板

---

## 7. 常见问题

**Q: push 失败 "Permission denied (publickey)"**
A: SSH key 未配置或未绑定 GitHub。运行 `ssh -T git@github.com` 诊断。

**Q: 数据库导入报错 "Unknown database"**
A: `poe_schema.sql` 中 `USE characters` 需要改为实际的库名（如 `acore_characters`）。

**Q: NPC 200000 看不到**
A: `creature_template` 模型字段未正确导入。确认 SQL 中 `display_id1` = 3503。

**Q: 客户端插件不加载**
A: 确认 WoW 版本是 3.3.5a (12340)，插件目录结构为 `Interface/AddOns/POEStarMap/POEStarMap.toc`。

**Q: /poemap 没反应**
A: 确认插件已启用，聊天框输入 `/poemap` 后按回车，无报错则重启 WoW。

---

## 8. 附录：项目全景

### 文件结构

```
azerothcore-wotlk/
├── lua_scripts/
│   ├── POE_Data.lua              # 数据层（节点/效果缓存）
│   ├── POE_EffectHandler.lua     # 效果注册器，PlayerMods 管理
│   ├── POE_CombatEvents.lua      # 战斗事件钩子
│   ├── POE_TalentManager.lua     # 总机、Gossip、升级、GM 命令
│   ├── POE_ResetItem.lua         # 后悔石物品
│   └── POE_AddonComm.lua         # 客户端插件通信层
├── sql/
│   └── poe_schema.sql            # 完整建表 + 种子数据
├── addons/POEStarMap/
│   ├── POEStarMap.toc            # 插件清单
│   ├── POEStarMap.xml            # UI 框架
│   └── POEStarMap.lua            # 客户端逻辑
├── docs/superpowers/
│   ├── specs/                    # 设计规格文档
│   └── plans/                    # 开发计划
├── dev-archive-phase1.md         # Phase 1 开发档案
├── CLAUDE.md                     # 项目 AI 助手说明
└── migration-guide.md            # 本文档
```

### 开发进度

| Phase | 状态 | 核心内容 |
|-------|------|---------|
| **Phase 1** | ✅ 完成 | 5 张 DB 表、4 个 Lua 脚本、Gossip 星盘、后悔石、v2 隐藏光环、12 项 bug 修复 |
| **Phase 2** | ✅ 基础完成 | 技能节点(LearnSpell)、6 职业星盘(68 节点)、class_mask、升级自动给点、ModDamage/Ignite/OnKill 效果、战斗事件系统、客户端插件(POEStarMap) |
| **Phase 3** | 📋 规划 | 词缀装备 / 制作通货 / 物品实例化 |

### 速查

| 项目 | 值 |
|------|-----|
| GitHub | https://github.com/callmefree/azerothcore-wotlk |
| 分支 | `phase-1-talent-demo` |
| 最新提交 | `beb4c1e` |
| 总提交 | 24 |
| NPC entry | 200000（星盘导师） |
| 物品 entry | 70000（后悔石） |
| GM 命令 | `.poe reload` / `.poe addpoints N` |
| 客户端命令 | `/poemap` / `/poestar` / `Alt+S` |
