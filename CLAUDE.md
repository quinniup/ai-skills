# CLAUDE.md

本仓库是 Claude Code 技能工具集，用于分发给团队成员。

## 仓库结构

- `.claude/skills/` — 技能定义文件（markdown），Claude Code 加载入口
- `scripts/` — 技能依赖的可执行脚本，按技能名分目录

## 技能开发规范

1. 技能文件放 `.claude/skills/<name>.md`
2. 配套脚本放 `scripts/<name>/`
3. 脚本中使用 `$SKILL_DIR` 引用自身所在目录（由技能注入）
4. 面向小白用户的技能必须有交互式引导，不能让用户手动编辑配置文件
