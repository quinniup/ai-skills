# ai-tools

Claude Code 技能包 — 可分发给团队成员使用的自动化工具集合。

## 使用方式

将本仓库克隆到本地后，在 Claude Code 中通过 `/skill` 调用：

```bash
git clone https://github.com/quinniup/ai-tools.git
```

然后在你的项目 `.claude/settings.json` 中添加技能路径，或直接将 `.claude/skills/` 下的文件复制到你自己项目的对应目录。

## 包含的技能

| 技能 | 说明 | 调用方式 |
|------|------|----------|
| `singbox-deploy` | sing-box 代理一键部署（面向零基础用户） | `/singbox-deploy` |

## 目录结构

```
ai-tools/
├── .claude/
│   └── skills/
│       └── singbox-deploy.md      # 技能定义文件
├── scripts/
│   └── singbox/
│       └── deploy.sh              # 部署脚本
├── CLAUDE.md                      # Claude Code 项目指令
├── README.md
└── .gitignore
```

## 分发给他人

两种方式：

1. **整仓引用**：对方克隆本仓库，在其 `~/.claude/settings.json` 中配置 `skillsPath` 指向本仓库的 `.claude/skills/`
2. **单技能复制**：将 `.claude/skills/singbox-deploy.md` 和 `scripts/singbox/` 复制到对方项目中

## 贡献新技能

在 `.claude/skills/` 下新建 `<skill-name>.md`，遵循 frontmatter 格式：

```markdown
---
name: skill-name
description: 一句话描述
---

技能指令内容...
```
