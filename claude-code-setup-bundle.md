# Claude Code 环境一键配置包

> 复制本文档，按步骤执行即可复刻完整的 Claude Code 工作环境。

---

## 一、全局指令文件 (~/.claude/CLAUDE.md)

```bash
mkdir -p ~/.claude
cat > ~/.claude/CLAUDE.md << 'EOF'
@RTK.md
EOF
```

## 二、RTK 指令文件 (~/.claude/RTK.md)

RTK (Rust Token Killer) 是一个 token 优化 CLI 代理，可节省 60-90% 的开发操作 token 消耗。

```bash
cat > ~/.claude/RTK.md << 'EOF'
# RTK - Rust Token Killer

**Usage**: Token-optimized CLI proxy (60-90% savings on dev operations)

## Meta Commands (always use rtk directly)

```bash
rtk gain              # Show token savings analytics
rtk gain --history    # Show command usage history with savings
rtk discover          # Analyze Claude Code history for missed opportunities
rtk proxy <cmd>       # Execute raw command without filtering (for debugging)
```

## Installation Verification

```bash
rtk --version         # Should show: rtk X.Y.Z
rtk gain              # Should work (not "command not found")
which rtk             # Verify correct binary
```

⚠️ **Name collision**: If `rtk gain` fails, you may have reachingforthejack/rtk (Rust Type Kit) installed instead.

## Hook-Based Usage

All other commands are automatically rewritten by the Claude Code hook.
Example: `git status` → `rtk git status` (transparent, 0 tokens overhead)

Refer to CLAUDE.md for full command reference.
EOF
```

## 三、全局配置 (~/.claude/config.json)

```bash
cat > ~/.claude/config.json << 'EOF'
{
  "primaryApiKey": "any"
}
EOF
```

## 四、Settings (~/.claude/settings.json)

> ⚠️ 根据你的实际代理地址和 API Key 修改 `env` 部分。以下是基于本地代理的配置模板。

```bash
cat > ~/.claude/settings.json << 'EOF'
{
  "env": {
    "ANTHROPIC_AUTH_TOKEN": "PROXY_MANAGED",
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:15721",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "claude-haiku-4-5",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME": "claude-haiku-4-5-20251001",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "claude-opus-4-8[1M]",
    "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME": "claude-opus-4-8",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "claude-sonnet-4-6[1M]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME": "claude-sonnet-4-6",
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "DISABLE_AUTOUPDATER": "1",
    "ENABLE_TOOL_SEARCH": "true"
  },
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "'/Applications/Muxy.app/Contents/Resources/Muxy_Muxy.bundle/muxy-claude-hook.sh' notification # muxy-notification-hook",
            "timeout": 10
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "'/Applications/Muxy.app/Contents/Resources/Muxy_Muxy.bundle/muxy-claude-hook.sh' stop # muxy-notification-hook",
            "timeout": 10
          }
        ]
      }
    ]
  },
  "skipDangerousModePermissionPrompt": true
}
EOF
```

## 五、Status Line 脚本 (~/.claude/statusline-command.sh)

Starship 风格的状态栏，显示 user@dir、git branch、model、context 使用率。

```bash
cat > ~/.claude/statusline-command.sh << 'STATUSLINE_EOF'
#!/usr/bin/env bash
# Claude Code status line — Starship-style (user@dir git branch | model ctx%)
input=$(cat)

GREEN='\033[32m'; CYAN='\033[36m'; YELLOW='\033[33m'; MAGENTA='\033[35m'
WHITE='\033[37m'; RED='\033[31m'; RESET='\033[0m'

user=$(whoami)
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -z "$cwd" ] && cwd=$(pwd)
dir=$(basename "$cwd")

model=$(echo "$input" | jq -r '.model.display_name // empty')

# Git branch
branch=$(git -C "$cwd" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null || true)

# Context usage
used_raw=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# Line 1: user@dir  git branch  model
line1="${GREEN}${user}${RESET}${WHITE}@${RESET}${CYAN}${dir}${RESET}"
if [ -n "$branch" ] && [ "$branch" != "HEAD" ]; then
  line1="${line1}  ${YELLOW}git ${branch}${RESET}"
fi
if [ -n "$model" ]; then
  line1="${line1}  ${MAGENTA}${model}${RESET}"
fi

# Line 2: context bar
if [ -n "$used_raw" ]; then
  pct=$(printf '%.0f' "$used_raw")
  if [ "$pct" -ge 90 ]; then BAR_COLOR="$RED"
  elif [ "$pct" -ge 70 ]; then BAR_COLOR="$YELLOW"
  else BAR_COLOR="$GREEN"; fi
  filled=$((pct / 10)); empty=$((10 - filled))
  bar=$(printf '%0.s█' $(seq 1 $filled) 2>/dev/null; printf '%0.s░' $(seq 1 $empty) 2>/dev/null)
  line2="${BAR_COLOR}${bar}${RESET} ${WHITE}ctx:${pct}%${RESET}"
  printf "${line1}\n${line2}"
else
  printf "${line1}"
fi
STATUSLINE_EOF
chmod +x ~/.claude/statusline-command.sh
```

## 六、已安装插件列表

以下插件需要通过 Claude Code 的 `/plugins` 命令安装：

### 插件市场源

| 市场名 | GitHub 仓库 |
|--------|-------------|
| claude-plugins-official | `anthropics/claude-plugins-official` |
| anthropic-agent-skills | `anthropics/skills` |
| fullstack-dev-skills | `jeffallan/claude-skills` |
| openai-codex | `openai/codex-plugin-cc` |
| superpowers-marketplace | `obra/superpowers-marketplace` |

### 已安装插件清单

| 插件 | 来源市场 | 用途 |
|------|----------|------|
| agent-sdk-dev | claude-plugins-official | Agent SDK 开发辅助 |
| skill-creator | claude-plugins-official | 技能创建工具 |
| claude-md-management | claude-plugins-official | CLAUDE.md 管理 |
| claude-code-setup | claude-plugins-official | Claude Code 环境配置 |
| coderabbit | claude-plugins-official | 代码审查 |
| code-review | claude-plugins-official | 代码评审 |
| context7 | claude-plugins-official | 上下文增强 |
| frontend-design | claude-plugins-official | 前端设计辅助 |
| superpowers | claude-plugins-official | 超能力增强包 |
| gopls-lsp | claude-plugins-official | Go LSP |
| jdtls-lsp | claude-plugins-official | Java LSP |
| typescript-lsp | claude-plugins-official | TypeScript LSP |
| pyright-lsp | claude-plugins-official | Python LSP |
| rust-analyzer-lsp | claude-plugins-official | Rust LSP |
| lua-lsp | claude-plugins-official | Lua LSP |
| document-skills | anthropic-agent-skills | 文档生成技能集 |
| example-skills | anthropic-agent-skills | 示例技能集 |
| fullstack-dev-skills | fullstack-dev-skills | 全栈开发技能 |
| codex | openai-codex | OpenAI Codex 集成 |
| claude-session-driver | superpowers-marketplace | 会话驱动 |
| elements-of-style | superpowers-marketplace | 写作风格指南 |
| superpowers | superpowers-marketplace | 超能力增强 |
| superpowers-lab | superpowers-marketplace | 超能力实验室 |

### 一键安装命令

在 Claude Code 中依次执行：

```
/plugins marketplace add anthropics/claude-plugins-official
/plugins marketplace add anthropics/skills
/plugins marketplace add jeffallan/claude-skills
/plugins marketplace add openai/codex-plugin-cc
/plugins marketplace add obra/superpowers-marketplace

/plugins install agent-sdk-dev
/plugins install skill-creator
/plugins install claude-md-management
/plugins install claude-code-setup
/plugins install coderabbit
/plugins install code-review
/plugins install context7
/plugins install frontend-design
/plugins install superpowers@claude-plugins-official
/plugins install gopls-lsp
/plugins install jdtls-lsp
/plugins install typescript-lsp
/plugins install pyright-lsp
/plugins install rust-analyzer-lsp
/plugins install lua-lsp
/plugins install document-skills
/plugins install example-skills
/plugins install fullstack-dev-skills
/plugins install codex
/plugins install claude-session-driver
/plugins install elements-of-style
/plugins install superpowers@superpowers-marketplace
/plugins install superpowers-lab
```

## 七、备用 Settings 配置（火山引擎 doubao）

如果使用火山引擎 doubao-seed-2.0-code 模型：

```bash
cat > ~/.claude/settings.json.ark << 'EOF'
{
  "env": {
    "ANTHROPIC_API_KEY": "<你的火山引擎API Key>",
    "ANTHROPIC_BASE_URL": "https://ark.cn-beijing.volces.com/api/coding",
    "ANTHROPIC_MODEL": "doubao-seed-2.0-code",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
  },
  "includeCoAuthoredBy": false,
  "permissions": {
    "allow": [],
    "deny": []
  },
  "statusLine": {
    "type": "command",
    "command": "npx ccusage statusline"
  },
  "outputStyle": "Explanatory",
  "alwaysThinkingEnabled": true,
  "model": "opus",
  "effortLevel": "high"
}
EOF
```

切换配置：`cp ~/.claude/settings.json.ark ~/.claude/settings.json`

---

## 八、项目级技能仓库

克隆技能工具集到本地：

```bash
git clone https://github.com/quinniup/ai-tools.git
```

包含技能：
- `/singbox-deploy` — sing-box 代理一键部署（零基础交互式引导）

---

## 注意事项

1. `settings.json` 中的 `ANTHROPIC_BASE_URL` 和认证信息需要根据你自己的代理/API 配置修改
2. Muxy hook 需要安装 [Muxy.app](https://muxy.app)，如果不用可以删除 hooks 部分
3. RTK 需要单独安装（`cargo install rtk` 或从 release 下载）
4. Status line 依赖 `jq`，确保已安装：`brew install jq`
5. 插件安装需要网络访问 GitHub
