# ai-tools

Claude Code 技能包 — 可分发给团队成员使用的自动化工具集合。

## 使用方式

将本仓库克隆到本地后，在 Claude Code 中通过 `/skill` 调用：

```bash
git clone https://github.com/quinniup/ai-tools.git
```

然后在你的项目 `.claude/settings.json` 中添加技能路径，或直接将 `.claude/skills/` 下的文件复制到你自己项目的对应目录。

## 技能总览

| skill name | description | label | version | remark |
|------|------|------|------|------|
| [`init-proj`](skills/init-proj/SKILL.md) | 初始化、审计或迁移项目的共享 Agent 工作区（AGENTS/CLAUDE 入口、规则、角色、记忆） | 研发 | 1.0.0 | 默认 audit 只读，init / migrate 需明确授权 |
| [`docs-template`](skills/docs-template/SKILL.md) | 按团队统一模板写文档，问答收集信息后结合代码逐节填写，行文言简意赅 | 研发 | 1.0.0 | 当前仅含研发技术设计方案模板 |
| [`singbox-deploy`](skills/singbox-deploy/SKILL.md) | 一键部署 sing-box 代理到 VPS，配置 SSH 免密并下载 Clash/Mihomo 配置 | 工具 | 1.0.0 | 需要 VPS 的 IP 和 root 密码 |
| [`reset-cc-env`](skills/reset-cc-env/SKILL.md) | 清理 Claude Code 本地账号相关信息与遥测痕迹，默认保留会话历史 | 工具 | 1.0.0 | 需退出所有 Claude Code 后在普通终端执行 |
| [`swimming-times`](skills/swimming-times/SKILL.md) | QQ 音乐加密歌曲批量转 MP3/FLAC，整理 Shokz OpenSwim Pro 游泳歌单 | 娱乐 | 1.0.0 | 仅 macOS，依赖 qmc2mp3、ffmpeg |

- 调用方式：`/<skill name>`，插件安装后可能带命名空间。
- label 可选值：娱乐、研发、效率、工具、创作，可按需扩充。
- 已废弃：`cc-switch-heal`（2026-11-05 移除）。

## init-proj

技能正文与参考模板集中在 [skills/init-proj](skills/init-proj/SKILL.md)，不绑定某个业务仓库。默认 audit 只读盘点；init / migrate 按明确授权创建或迁移，保留既有规则、skills、hooks 与本机权限。

通过本仓 marketplace 安装到用户范围，可在多个项目复用，无需每个项目存一份：

```text
/plugin marketplace add /本机/ai-tools/实际路径
/plugin install init-proj@ai-skills
```

安装时选择用户范围（而非仅当前项目）；实际作用域和调用名以当前 Claude Code 版本为准。仅移动源文件不等于当前工具已完成全局注册，本次不改全局配置。

## swimming-times

把 QQ 音乐 Mac 下载的加密歌曲（`.mgg` / `.mflac` / `.qmc*`）批量转成 Shokz OpenSwim Pro 能播放的 MP3/FLAC。默认输出到 `~/myself/music/swimming`，已有文件自动跳过；只有用户明确确认后才清理源文件（优先移入废纸篓）。

依赖 `qmc2mp3`。首次使用前执行：

```bash
bash scripts/swimming-times/install-qmc2mp3.sh
```

需要 macOS、`git`、`cargo`、`ffmpeg`，并保持 QQ 音乐登录。转换脚本支持 `--dry-run` 预览，详见 [skills/swimming-times](skills/swimming-times/SKILL.md)。

```text
/plugin install swimming-times --marketplace quinniup/ai-skills
```

## reset-cc-env

仅清理 Claude Code 本地账号相关性敏感信息与遥测痕迹，默认**保留会话历史**（`projects/`、`file-history/`、`history.jsonl`）和项目用量字段。需要时加 `--strip-usage` 才剥离每个项目条目的成本/用量字段；默认不剥离。先盘点、干跑、确认；因为运行中的 Claude Code 会把内存里的 `.claude.json` 写回，最终 `apply` 必须在退出所有 Claude Code 后从普通终端执行。可选删除残留 OAuth、关闭云会话/遥测。

默认保留历史时，换账号后本地仍可能看出同一批项目和会话；要尽量切断关联，需要 `--deep` 删除本地历史，并轮换上游 token / 更换中转账号。已上报遥测、上游日志、IP 和快照仍可能关联，不能承诺完全匿名。

```text
/plugin install reset-cc-env --marketplace quinniup/ai-skills
```

脚本支持 macOS / Linux（WSL 可用），只依赖 `bash`、`jq`、`du`、`find`，macOS 额外使用系统 `security` 命令。详见 [skills/reset-cc-env](skills/reset-cc-env/SKILL.md)。

## docs-template

按团队统一模板写文档。当前提供研发技术设计方案模板（[templates/tech-design.md](skills/docs-template/templates/tech-design.md)），章节覆盖概述、详细设计、接口、表结构、迁移、配置、发布与回滚、风险。技能会先问清主题、需求材料、改动类型和输出位置，再读代码按模板逐节填写；行文要求言简意赅：优先用图、表、列表，只写结论和事实，不写铺垫和空话；不涉及的章节标注原因，缺信息处标 `【待补充】`，不编造内容。

新增模板：在 `skills/docs-template/templates/` 放模板文件，并在 [SKILL.md](skills/docs-template/SKILL.md) 的“可用模板”表格补一行。

```text
/plugin install docs-template --marketplace quinniup/ai-skills
```

## 目录结构

```
ai-tools/
├── skills/
│   ├── singbox/
│   │   └── singbox-deploy.md
│   └── <new-skill>
│       └── <new-skill>.md
├── scripts/
│   ├── singbox/
│   │   └── deploy.sh
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
3. 在本 README 的「技能总览」表格补一行（填写 label 和 version）
