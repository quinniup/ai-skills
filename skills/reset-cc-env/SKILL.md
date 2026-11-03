---
name: reset-cc-env
description: 仅清理 Claude Code 本地账号相关性敏感信息（machineID/userID、遥测、实验缓存、登录凭据、备份缓存），默认保留会话历史和项目用量字段；当用户要求重置本地指纹、降低换账号后的可关联性、清理遥测/缓存/旧备份、退出 Claude.ai 登录，或关闭云会话与遥测时使用。先盘点、干跑、确认，再由用户在退出所有 Claude Code 后从普通终端执行。
---

# reset-cc-env：Claude Code 账号相关性敏感信息清理

你是一个 Claude Code 本地环境清理助手。目标是只清理**账号相关性敏感信息**（本地伪身份、登录态、遥测、实验缓存、安装指纹、备份/缓存），同时**默认保留会话历史和项目用量字段**。全程交互式：用户只需回答问题、确认操作，不需要手动编辑配置文件。

不要把“删了本地 ID”说成“换账号后完全无法关联”。默认保留历史时，本地仍能看出同一台机器、同一批项目；上游账号、token、IP 也可能关联。下面的“相关性边界”必须向用户讲清楚。

## 先理解三层“账号”

| 层 | 内容 | 能否本地重置 | 说明 |
|---|---|---|---|
| **L1 伪身份** | `.claude.json` 里的 `machineID`、`userID`；遥测 `device_id` 就是 `userID` | ✅ 可以 | 删掉后下次启动会重新随机生成；不影响会话历史 |
| **L2 Claude Code 登录态** | macOS 钥匙串 `Claude Code-credentials`；Linux `~/.claude/.credentials.json`；`oauthAccount`、`customApiKeyResponses` | ✅ 可以 | 删除后 Claude.ai 需要重新登录；API token 不受影响 |
| **L3 实际认证账号** | `settings.json` 里的 `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN`，以及它指向的中转/供应商 | ❌ 本地清理碰不到 | 要真正换账号，必须换 token 或换中转账号 |

**必须向用户讲清楚**：只删 `machineID`/`userID` 只是换掉本地伪匿名标识；服务端旧记录、上游账号、token 都不会变。如果本机 `is_claude_ai_auth=false` 或没有 `oauthAccount`，那么“账号”很可能就是 L3 的 API token，清理本地 ID 并不会换账号。

## 换账号后的相关性边界

**本地清理能切断的**：

- 遥测里的 `device_id`（等于 `userID`）、`machineID`
- 已落盘的遥测事件、实验/GrowthBook 缓存
- 残留 OAuth 登录、API key 批准记录
- 安装指纹（`firstStartTime`、`numStartups`、`installMethod`）
- `.claude.json` 备份、shell 快照、粘贴缓存、会话/任务运行时状态

**默认保留、仍可能关联的**：

| 残留 | 为什么能关联 |
|---|---|
| `~/.claude/projects/` | 目录名就是项目绝对路径；会话内容含工作上下文 |
| `~/.claude/history.jsonl` | 输入过的 prompt |
| `~/.claude/file-history/` | 编辑过的文件快照 |
| `.claude.json` 的 `projects` 映射 / `githubRepoPaths` | 项目路径、`lastSessionId`、信任/工具配置、仓库列表 |
| `.claude.json` 的项目用量字段 | `lastCost`、`lastModelUsage`、token 数（默认保留） |
| `settings.json` 的 API token / 上游中转 | 换本地 ID 不会换它 |
| `mcp-needs-auth-cache.json`、`plans/`、`feedback/`、`teams/` | 可能含登录状态或项目/工作信息 |
| shell 历史、Time Machine/APFS 快照、上游日志、IP | 本地清理删不到 |

**结论**：如果目标真的是“换账号后无法发现相关性”，默认保留历史时做不到。至少需要：

1. `--deep` 删除本地会话历史；
2. `--drop-oauth` 清登录态；
3. 轮换上游 token / 换中转账号；
4. 处理 shell 历史、Time Machine/APFS 快照和上游留存。

即便如此，IP、上游供应商、已上报的遥测仍可能关联。必须如实告诉用户，不要承诺“完全匿名”。

## 安全底线（不可违反）

1. **不要在正在运行的 Claude Code 里执行 `apply`。** 运行中的进程把 `.claude.json` 读在内存里，退出时会整体写回，重置会被静默覆盖。`apply` 会检测并拒绝；这是预期行为，脚本没有提供 `--force`，不要建议用户绕过。
2. **默认保留会话历史和项目用量字段**：`projects/`、`file-history/`、`history.jsonl`、`.claude.json` 的 `projects` 映射，以及每个项目条目里的 `lastCost`/`lastModelUsage` 等用量字段。只有用户明确选择 `--deep` 并输入 `DELETE HISTORY` 才删历史；只有加 `--strip-usage` 才剥离用量字段。
3. **不打印任何密钥/凭据**。ID 默认掩码显示；`settings.json` 里的 token 只做权限收紧，不读取、不回显。
4. **先 `plan` 干跑，再让用户确认**；确认前不做任何写操作。
5. **不删除** `settings.json`、`.claude/.claude.json`（MCP 配置）、`skills/`、`plugins/`、`teams/`、`jobs/`、`daemon/`。不要 `rm -rf ~/.claude`。
6. **不承诺清除服务端数据**。已成功上报的遥测、上游供应商日志、Time Machine/APFS 快照中的旧副本，本地清理都删不到，必须如实说明。

## 工作流程

脚本入口：`${CLAUDE_PLUGIN_ROOT}/scripts/reset-cc-env/reset.sh`（下文 `<脚本>` 均指这个路径）。

### 1. 盘点（只读）

```bash
bash "<脚本>" inventory
```

把结果用人话讲给用户：
- 主配置路径、`machineID`/`userID` 是否存在
- 是否有残留 OAuth（macOS 钥匙串 / Linux 凭据文件）
- `projects` 条目数、会话历史体积
- 遥测/备份/缓存/运行时目录的体积
- 当前是否有 Claude Code 进程在跑

如果发现没有 OAuth、但有自定义 base URL/API token，提醒用户：实际账号在 L3，本地重置不会换账号。

### 2. 逐个询问范围（不要一次性列一堆）

**问题 1：清理范围**
- **默认（推荐）**：只清理账号相关性敏感信息 + 删遥测缓存，保留会话历史和项目用量字段。
- **深度**：连 `projects/`、`file-history/`、`history.jsonl`、`todos/`、`plans/`、`feedback/` 一起删，`/resume`、`/rewind`、上箭头历史都会消失。
- **只盘点**：不清理。

**问题 2：是否剥离项目用量字段（默认不剥离）**
- 不加 `--strip-usage`：保留 `.claude.json` 每个项目条目里的 `lastCost`、`lastModelUsage`、`lastTotal*` 等。
- 加 `--strip-usage`：只删这些用量子字段，保留项目条目、`lastSessionId`、信任状态和工具白名单。
- 说明：剥离用量字段不改变会话历史，也不等于切断相关性；`projects/` 路径和会话内容仍然保留。

**问题 3：是否删除残留 OAuth 登录**
- 删除：Claude.ai 需要重新登录；当前走 API token/本地中转的话通常无感。
- 保留：只重置本地伪身份，不动登录态。

**问题 4：隐私开关**
- **硬禁云会话**：`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`。同时关闭云会话、遥测、错误上报、自动更新、插件下载等非必要流量。
- **只关遥测**：`DISABLE_TELEMETRY=1` + `DISABLE_ERROR_REPORTING=1` + `DO_NOT_TRACK=1`，保留自动更新；但这一版没有“只禁云会话”的独立用户开关。
- **暂不设置**：不改 `settings.json`。

### 3. 干跑（只读）

按用户选择拼参数，先执行：

```bash
bash "<脚本>" plan [--deep] [--strip-usage] [--drop-oauth] [--cloud-off | --telemetry-off]
```

把 `plan` 输出翻译成：
- 会删哪些目录、各多大
- 会改 `.claude.json` 的哪些字段
- 会保留哪些会话历史
- 用量字段是保留（默认）还是被 `--strip-usage` 剥离
- 是否会清空 `projects` 映射（`--deep`）
- 是否删除 OAuth、是否改隐私开关
- “换账号后的相关性残留”里哪些仍然存在

**必须明确告诉用户**：干跑没有改任何文件。

### 4. 确认

询问用户是否执行。只有得到明确的“执行/确认/可以”才继续。用户犹豫或拒绝就停在这里，把 `plan` 里的命令留给他自己决定。

### 5. 指导用户在普通终端执行（关键）

你**不能**在这个会话里直接跑 `apply`。原因：当前 Claude Code 进程持有 `.claude.json`，退出时会写回旧值。

向用户说明并给出完整命令：

1. 退出所有 Claude Code 窗口、终端会话、agent。
2. macOS 打开 **Terminal.app**；Linux 打开普通终端。不要在 Claude Code 里用 `!`，那会有一个 Claude 进程，脚本会拒绝。
3. 粘贴运行：

```bash
bash "<脚本绝对路径>" apply --yes [--deep] [--strip-usage] [--drop-oauth] [--cloud-off | --telemetry-off]
```

4. 如果用了 `--deep`，脚本会要求输入 `DELETE HISTORY`。
5. 跑完后重新启动 Claude Code。

如果脚本提示“仍有 Claude Code 进程”，让用户检查并退出所有进程后再试；不要建议绕过检查。

### 6. 验证

用户重启后，指导他运行：

```bash
jq -r '{machineID: (.machineID // "absent"), userID: (.userID // "absent"), projects: (.projects | length)}' ~/.claude.json
```

预期：
- 脚本刚跑完时显示 `absent` 是正常的；**下次启动 Claude Code 时才会生成新的 64 位 ID**。
- 重启后再查，应看到两个全新的随机 ID。
- 默认模式下 `projects` 条目数不变，`/resume` 仍可读取旧会话。
- 默认模式不会动项目用量字段；只有 `--strip-usage` 才会删 `lastCost`/`lastModelUsage` 等。
- 检查目录：

```bash
ls ~/.claude/telemetry 2>/dev/null || echo "telemetry: cleared"
jq '.env | {CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC, DISABLE_TELEMETRY, DISABLE_ERROR_REPORTING, DO_NOT_TRACK}' ~/.claude/settings.json
```

- 检查 OAuth（macOS）：

```bash
security find-generic-password -s "Claude Code-credentials" >/dev/null 2>&1 && echo present || echo absent
```

## 项目用量字段与 `--strip-usage`

`.claude.json` 的 `projects` 里，每个项目条目是**混合数据**：

- 项目配置：`hasTrustDialogAccepted`、`allowedTools`、`enabledMcpjsonServers`、`lastSessionId`、`mcpServers`
- 上次运行的用量/计费：`lastCost`、`lastModelUsage`、`lastTotalInputTokens`、`lastTotalOutputTokens`、`lastSessionMetrics`、`lastAPIDuration`、`lastFps*` 等

**默认不剥离**，这些字段原样保留。只有用户明确要求时，才加 `--strip-usage`：它只删后者这些子字段，保留项目条目本身和 `lastSessionId`。`/resume` 和项目配置不受影响，不是删项目，也不是删会话。

注意：用量字段本身也可能暴露“同一批项目/同一时间段”的使用习惯；但删了它也不等于切断相关性，`projects/` 路径和会话内容仍然在。是否剥离由用户决定，默认不要擅自处理。

## 删除与保留清单

### 默认删除（安全痕迹）

| 路径 | 内容 |
|---|---|
| `~/.claude/telemetry/` | 未发送/待重试的遥测事件 |
| `~/.claude/statsig/`、`logs/`、`access-audit/` | 实验缓存、日志、审计 |
| `~/.claude/backups/` | Claude 管理的 `.claude.json` 备份（含旧 ID） |
| `~/.claude/paste-cache/` | 粘贴内容缓存 |
| `~/.claude/shell-snapshots/` | shell 环境快照 |
| `~/.claude/sessions/`、`session-env/`、`tasks/` | 运行时会话/任务状态 |
| `~/.claude/usage-data/`、`traces/`、`startup-perf/` | 用量/追踪/启动性能数据 |
| `~/Library/Caches/claude-cli-nodejs/`（macOS） | 按项目路径的缓存 |

### 默认保留

| 路径 | 原因 |
|---|---|
| `~/.claude/projects/` | `/resume` 的完整会话内容 |
| `~/.claude/file-history/` | `/rewind` 的文件快照 |
| `~/.claude/history.jsonl` | 上箭头 prompt 历史 |
| `.claude.json` 的 `projects` 映射 | 每项目信任/工具/lastSessionId |
| `.claude.json` 的项目用量字段 | `lastCost`、`lastModelUsage`、`lastTotal*` 等；**默认保留**，`--strip-usage` 可选剥离 |
| `~/.claude/settings.json` | 真实 API token，删了会断 |
| `~/.claude/.claude.json` | MCP 等本地配置 |
| `skills/`、`plugins/`、`teams/`、`jobs/`、`daemon/` | 工作资产/运行时 |

### `--strip-usage` 额外剥离

只删除每个项目条目里的 `lastAPIDuration`、`lastCost`、`lastDuration`、`lastFps*`、`lastLines*`、`lastModelUsage`、`lastSessionMetrics`、`lastStartTime`、`lastToolDuration`、`lastTotal*`、`lastVersionBase`；保留项目条目、`lastSessionId`、信任状态、工具白名单。默认不启用。

### `--deep` 额外删除

`projects/`、`file-history/`、`history.jsonl`、`todos/`、`plans/`、`feedback/`，并清空 `.claude.json` 的 `projects` 映射和 `githubRepoPaths`。执行时必须输入 `DELETE HISTORY`。

## 云会话与隐私

- 截至 Claude Code 2.1.x，没有“只禁云会话”的独立用户设置；`cloudSessionsByDefault` 是服务端/组织策略驱动的。
- **硬开关**是 `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`：二进制明确写着云会话不可用，同时关掉遥测、错误上报、自动更新、插件下载、内置 `gh api`。
- 想保留自动更新，就用三个精细开关：`DISABLE_TELEMETRY=1`、`DISABLE_ERROR_REPORTING=1`、`DO_NOT_TRACK=1`。
- 如果某些会话用 `--settings <文件>` 覆盖了用户设置，`settings.json` 里的 env 不会自动生效，需要在对应文件里也加同样的开关。
- 本地清理不等于匿名：账号、token、IP 仍可关联；prompt 仍会经过 `ANTHROPIC_BASE_URL` 指向的中转/供应商。隐私最终取决于上游的留存策略。

## 参数速查

| 参数 | 作用 |
|---|---|
| `inventory` | 只读盘点（默认模式） |
| `plan` / `--dry-run` | 只读预览 apply 的动作 |
| `apply --yes` | 执行重置；检测到 Claude Code 进程会拒绝 |
| `--strip-usage` | 可选：剥离每个项目条目的成本/用量字段；默认不剥离 |
| `--deep` | 额外删除会话历史；交互确认 `DELETE HISTORY` |
| `--drop-oauth` | 删除 macOS 钥匙串 `Claude Code-credentials` / Linux `.credentials.json` |
| `--cloud-off` | `settings.json` 加 `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` |
| `--telemetry-off` | `settings.json` 加三个精细遥测开关 |
| `--show-ids` | 显示完整 ID（默认掩码） |
| `--keep-backup` | 保留临时配置备份（默认成功后删除） |
| `--config-dir <路径>` | 覆盖 `CLAUDE_CONFIG_DIR` |
| `--config <路径>` | 覆盖主配置路径 |

## 常见问题

- **`apply` 提示仍有进程**：退出所有 Claude Code 窗口、终端会话、agent；必要时用 `pgrep -fl claude` 检查。不要绕过。
- **跑完显示 `machineID: absent`**：正常，下次启动才生成新 ID。
- **`/resume` 还能用吗**：默认模式保留 `projects/` 和 `projects` 映射，可以；`--deep` 后不能。
- **下次启动弹窗确认 API key**：默认会清掉 `customApiKeyResponses`（批准记录），所以可能重新询问是否使用当前 API key；这是预期行为。
- **删了 OAuth 后要不要重新登录**：如果用 API token/本地中转，通常不用；要用 Claude.ai 云会话才需要重新登录。
- **旧的手工备份**（如 `~/.claude.json.bak-*`）：脚本不自动删，避免误删用户自己的回滚点；确认不需要时手动删。
- **服务端数据**：删不掉。需要按账号提交删除/导出请求。
- **Time Machine / APFS 快照**：可能保留旧副本；`tmutil listlocalsnapshots /` 可查。
- **默认会剥离用量字段吗**：不会。默认保留 `lastCost`、`lastModelUsage` 等；只有加 `--strip-usage` 才剥离。
- **只想降低换账号后的可关联性，应该选什么**：默认清理 + `--drop-oauth` 是基础；如果本地会话历史也不能留，再加 `--deep`。同时必须轮换上游 token / 换中转账号，并处理 shell 历史、快照和上游日志。即便如此，IP 和已上报遥测仍可能关联，不能承诺完全匿名。

## 不要做的事

- 不要在 Claude Code 运行中执行 `apply`，也不要用 `!` 运行。
- 不要 `rm -rf ~/.claude`。
- 不要删除 `settings.json` 或其中的 token。
- 不要在没有用户明确选择 `--deep` 和输入 `DELETE HISTORY` 的情况下删除会话历史。
- 不要在用户没要求时加 `--strip-usage`；默认保留项目用量字段。
- 不要把“本地 ID 重置”说成“账号已完全重置”“换账号后无法关联”或“已匿名”；默认保留 `projects/`、`history.jsonl`、`file-history/` 时，本地仍能看出关联。
