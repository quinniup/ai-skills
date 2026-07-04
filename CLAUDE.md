# CLAUDE.md

本仓库是 Claude Code 技能工具集，用于分发给团队成员。

本仓库同时是一个 Claude Code plugin marketplace，团队成员通过 `/plugin marketplace add` 安装其中的技能。

## 仓库结构

- `.claude-plugin/marketplace.json` — marketplace 清单，每个技能作为一个独立 plugin 列出（`source: "./"` + `skills` 指向对应目录，`strict: false`）
- `skills/<name>/SKILL.md` — 技能定义文件（文件名必须是大写 `SKILL.md`，目录名即技能标识，需与 frontmatter `name` 一致）
- `scripts/<name>/` — 技能依赖的可执行脚本，按技能名分目录

## 技能开发规范

1. 技能放 `skills/<name>/SKILL.md`，目录名 = frontmatter `name`
2. 配套脚本放 `scripts/<name>/`
3. 脚本中用 `${CLAUDE_PLUGIN_ROOT}/scripts/<name>` 引用（plugin 安装后会拷贝到缓存目录，相对路径不可靠）
4. 新增技能后，在 `.claude-plugin/marketplace.json` 的 `plugins` 数组补一条对应条目
5. 改动后跑 `claude plugin validate .` 校验
6. 面向小白用户的技能必须有交互式引导，不能让用户手动编辑配置文件
