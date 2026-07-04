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
| `openclaw-init` | OpenClaw 一键初始化，通过 CC Switch 配置 API 和通讯渠道 | `/openclaw-init` |
| `cc-switch-heal` | cc-switch / Codex 配置自愈，诊断并修复 provider 协议不匹配（百炼被错配成 responses 导致会话开不起来），自动备份可回滚 | `/cc-switch-heal` |

## 目录结构

```
ai-tools/
├── skills/
│   ├── singbox/
│   │   └── singbox-deploy.md
│   ├── cc-switch-heal/
│   │   └── cc-switch-heal.md
│   └── <new-skill>
│       └── <new-skill>.md
├── scripts/
│   ├── singbox/
│   │   └── deploy.sh
│   ├── cc-switch-heal/
│   │   └── heal.py
│   └── <new-skill>/
│       └── ...
├── templates/
│   └── skill-template.md           # 新技能模板
├── CLAUDE.md
├── README.md
└── .gitignore
```

## 分发给他人

两种方式：

1. **整仓引用**：对方克隆本仓库，在其 `~/.claude/settings.json` 中配置 `skillsPath` 指向本仓库的 `.claude/skills/`
2. **单技能复制**：将对应的 `.claude/skills/<name>.md` 和 `scripts/<name>/` 复制到对方项目中

## 新建技能

参考 `templates/skill-template.md`，按以下步骤添加：

1. 复制模板到 `skills/<skill-name>/<skill-name>.md`
2. 如果有配套脚本，放到 `scripts/<skill-name>/`
3. 更新本 README 的技能表格
