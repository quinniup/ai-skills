#!/usr/bin/env bash
# reset-cc-env — reset Claude Code local identity / telemetry traces.
#
# Default behaviour preserves conversation history and per-project usage fields:
#   ~/.claude/projects/        full session transcripts (/resume)
#   ~/.claude/file-history/    file snapshots (/rewind)
#   ~/.claude/history.jsonl    prompt history
#   .claude.json -> projects   per-project trust / tools / lastSessionId / usage
#
# Use --strip-usage to remove per-project cost/usage subfields only.
# Use --deep to remove conversation history (requires typed confirmation).
#
# Modes:
#   inventory   read-only local data report (default)
#   plan        read-only list of what apply would do
#   apply       perform the reset; requires --yes and no running Claude Code
#
# IMPORTANT: apply edits .claude.json. A running Claude Code process holds that
# file in memory and rewrites it on exit, which would silently undo the reset.
# Therefore apply refuses to run while any Claude Code process is alive. Run it
# from a normal terminal after quitting every Claude Code session.
set -euo pipefail
umask 077

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

MODE="inventory"
ASSUME_YES=0
DEEP=0
STRIP_USAGE=0
DROP_OAUTH=0
CLOUD_OFF=0
TELEMETRY_OFF=0
SHOW_IDS=0
KEEP_BACKUP=0
CFG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CONFIG_OVERRIDE=""

usage() {
  cat <<'EOF'
用法: reset.sh [模式] [选项]

模式:
  inventory              只读盘点本地数据（默认）
  plan                   只读预览 apply 会做什么
  apply                  执行重置（需要 --yes，且没有 Claude Code 在运行）

选项:
  --yes, -y              确认执行 apply（仍会检查运行中的 Claude Code）
  --strip-usage          可选：剥离 .claude.json 中每个项目条目的成本/用量
                         字段（lastCost、lastModelUsage、lastTotal* 等），
                         保留项目条目、lastSessionId、信任与工具配置。
                         默认不剥离。
  --deep                 额外删除会话历史：projects/、file-history/、
                         history.jsonl、todos/、plans/、feedback/，
                         并清空 .claude.json 的 projects 映射
  --drop-oauth           删除残留的 Claude Code OAuth 凭据
                         （macOS 钥匙串 "Claude Code-credentials"；
                          Linux $CLAUDE_CONFIG_DIR/.credentials.json）
  --cloud-off            在 settings.json 的 env 中加入
                         CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
                         （会同时关闭云会话、遥测、错误上报、自动更新等）
  --telemetry-off        在 settings.json 的 env 中加入
                         DISABLE_TELEMETRY=1、DISABLE_ERROR_REPORTING=1、
                         DO_NOT_TRACK=1（保留自动更新）
  --show-ids             在 inventory/apply 输出中显示完整 ID（默认掩码）
  --keep-backup          保留临时配置备份（默认成功后删除）
  --config-dir <路径>    覆盖 CLAUDE_CONFIG_DIR
  --config <路径>        覆盖主配置路径（默认自动探测）
  -h, --help             显示帮助

示例:
  bash reset.sh inventory
  bash reset.sh plan --drop-oauth --cloud-off
  bash reset.sh apply --yes --drop-oauth --cloud-off
  bash reset.sh apply --yes --strip-usage   # 额外剥离项目成本/用量字段
  bash reset.sh apply --yes --deep          # 会要求输入 DELETE HISTORY
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    inventory|plan|apply) MODE="$1"; shift ;;
    --dry-run) MODE="plan"; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    --deep) DEEP=1; shift ;;
    --strip-usage) STRIP_USAGE=1; shift ;;
    --drop-oauth) DROP_OAUTH=1; shift ;;
    --cloud-off) CLOUD_OFF=1; shift ;;
    --telemetry-off) TELEMETRY_OFF=1; shift ;;
    --show-ids) SHOW_IDS=1; shift ;;
    --keep-backup) KEEP_BACKUP=1; shift ;;
    --config-dir) CFG_DIR="$2"; shift 2 ;;
    --config) CONFIG_OVERRIDE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1"; echo; usage; exit 2 ;;
  esac
done

OS="$(uname -s)"
case "$OS" in
  Darwin|Linux) ;;
  *) echo "仅支持 macOS / Linux（Windows 请在 WSL 中运行）。" >&2; exit 1 ;;
esac

command -v jq >/dev/null 2>&1 || {
  echo "需要 jq。macOS: brew install jq；Debian/Ubuntu: sudo apt-get install jq" >&2
  exit 1
}

find_config() {
  if [ -n "$CONFIG_OVERRIDE" ]; then
    [ -f "$CONFIG_OVERRIDE" ] && { printf '%s\n' "$CONFIG_OVERRIDE"; return 0; }
    return 1
  fi
  local candidates=()
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ] || [ "$CFG_DIR" != "$HOME/.claude" ]; then
    candidates=("$CFG_DIR/.claude.json" "$HOME/.claude.json")
  else
    candidates=("$HOME/.claude.json" "$CFG_DIR/.claude.json")
  fi
  local c
  for c in "${candidates[@]}"; do
    [ -f "$c" ] || continue
    if jq -e 'has("machineID") or has("userID") or has("projects")' "$c" >/dev/null 2>&1; then
      printf '%s\n' "$c"
      return 0
    fi
  done
  return 1
}

CONFIG="$(find_config || true)"
if [ -z "$CONFIG" ]; then
  echo "找不到 Claude Code 主配置（期望 ~/.claude.json 或 \$CLAUDE_CONFIG_DIR/.claude.json）。" >&2
  echo "可用 --config <路径> 指定。当前配置目录: $CFG_DIR" >&2
  exit 1
fi

mask() {
  local v="${1:-absent}"
  if [ "$SHOW_IDS" = "1" ]; then
    printf '%s' "$v"
  elif [ "${#v}" -gt 16 ]; then
    printf '%s…(%s chars)' "${v:0:8}" "${#v}"
  else
    printf '%s' "$v"
  fi
}

size_of() {
  if [ -e "$1" ]; then
    du -sh "$1" 2>/dev/null | awk '{print $1}'
  else
    printf '不存在'
  fi
}

jsonl_count() {
  [ -d "$1" ] || { printf '0'; return; }
  find "$1" -type f -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' '
}

running_pids() {
  {
    pgrep -f "$HOME/.local/share/claude/versions/" 2>/dev/null || true
    pgrep -f "$HOME/.local/bin/claude" 2>/dev/null || true
    pgrep -f "@anthropic-ai/claude-code" 2>/dev/null || true
    pgrep -f "claude-code/cli.js" 2>/dev/null || true
  } | sort -u | tr '\n' ' '
}

oauth_present() {
  if [ "$OS" = "Darwin" ]; then
    security find-generic-password -s "Claude Code-credentials" >/dev/null 2>&1 \
      || [ -f "$CFG_DIR/.credentials.json" ]
  else
    [ -f "$CFG_DIR/.credentials.json" ]
  fi
}

correlation_note() {
  echo
  echo "== 换账号后的相关性残留 =="
  if [ "$DEEP" = "1" ]; then
    echo "  本地会话历史：本次 --deep 会删除。"
  else
    echo "  projects/ 目录名、.claude.json 的 projects 键 / githubRepoPaths：项目路径"
    echo "  history.jsonl：prompt 历史"
    echo "  file-history/：编辑过的文件快照"
    echo "  plans/、feedback/、teams/：可能含项目/工作信息"
    if [ "$STRIP_USAGE" = "1" ]; then
      echo "  .claude.json 项目用量字段：本次会剥离（--strip-usage）"
    else
      echo "  .claude.json 项目用量字段：默认保留（--strip-usage 可剥离）"
    fi
  fi
  echo "  settings.json 的 API token / 上游中转账号：本地清理不会更换"
  echo "  mcp-needs-auth-cache.json：MCP 登录状态"
  echo "  shell 历史、Time Machine/APFS 快照、上游日志：本地清理删不到"
  echo "  结论：默认保留历史时，换账号后本地仍能看出关联；"
  echo "        要尽量切断，需要 --deep + 轮换上游 token，并处理快照/日志。"
}

# ---------------------------------------------------------------------------
# inventory
# ---------------------------------------------------------------------------
inventory() {
  echo "== Claude Code 本地状态 =="
  echo "系统:       $OS"
  echo "配置目录:   $CFG_DIR"
  echo "主配置:     $CONFIG ($(size_of "$CONFIG"))"
  echo
  echo "== 身份 / 账号字段 =="
  echo "machineID:  $(mask "$(jq -r '.machineID // empty' "$CONFIG")")"
  echo "userID:     $(mask "$(jq -r '.userID // empty' "$CONFIG")")"
  echo "oauthAccount: $(jq -r 'if has("oauthAccount") then "present" else "absent" end' "$CONFIG")"
  echo "subscription: $(jq -r '.hasAvailableSubscription // false' "$CONFIG")"
  echo "customApiKeyResponses: $(jq -c '(.customApiKeyResponses // {}) | {approved: ((.approved // [])|length), rejected: ((.rejected // [])|length)}' "$CONFIG")"
  echo "projects 条目: $(jq -r '.projects // {} | length' "$CONFIG")"
  echo
  echo "== 登录凭据 =="
  if oauth_present; then
    if [ "$OS" = "Darwin" ]; then
      echo "macOS 钥匙串: Claude Code-credentials 存在"
    else
      echo "Linux 凭据文件: $CFG_DIR/.credentials.json 存在"
    fi
  else
    echo "未发现残留 OAuth 凭据"
  fi
  echo
  echo "== 会话历史（默认保留） =="
  echo "projects/:        $(size_of "$CFG_DIR/projects") / $(jsonl_count "$CFG_DIR/projects") 个 jsonl"
  echo "file-history/:    $(size_of "$CFG_DIR/file-history")"
  echo "history.jsonl:    $(size_of "$CFG_DIR/history.jsonl")"
  echo "todos/:           $(size_of "$CFG_DIR/todos")"
  echo "plans/:           $(size_of "$CFG_DIR/plans")"
  echo "项目用量字段:     $(jq '[.projects[]? | select(type=="object" and has("lastCost"))] | length' "$CONFIG") 个项目含 lastCost（默认保留，--strip-usage 可剥离）"
  echo
  echo "== 遥测 / 缓存 / 运行时状态 =="
  for d in telemetry statsig logs access-audit backups paste-cache shell-snapshots sessions session-env tasks usage-data traces startup-perf; do
    printf '%-18s %s\n' "$d/" "$(size_of "$CFG_DIR/$d")"
  done
  if [ "$OS" = "Darwin" ]; then
    printf '%-18s %s\n' "Library cache" "$(size_of "$HOME/Library/Caches/claude-cli-nodejs")"
  fi
  echo
  echo "== 运行中的 Claude Code =="
  PIDS="$(running_pids)"
  if [ -n "$PIDS" ]; then
    echo "PID: $PIDS"
    echo "注意：apply 会拒绝执行；先把它们全部退出。"
  else
    echo "未发现"
  fi
  correlation_note
}

# ---------------------------------------------------------------------------
# plan
# ---------------------------------------------------------------------------
DELETE_DIRS=(
  "$CFG_DIR/telemetry"
  "$CFG_DIR/statsig"
  "$CFG_DIR/logs"
  "$CFG_DIR/access-audit"
  "$CFG_DIR/backups"
  "$CFG_DIR/paste-cache"
  "$CFG_DIR/shell-snapshots"
  "$CFG_DIR/sessions"
  "$CFG_DIR/session-env"
  "$CFG_DIR/tasks"
  "$CFG_DIR/usage-data"
  "$CFG_DIR/traces"
  "$CFG_DIR/startup-perf"
)

if [ "$OS" = "Darwin" ]; then
  DELETE_DIRS+=("$HOME/Library/Caches/claude-cli-nodejs")
fi

DEEP_DIRS=(
  "$CFG_DIR/projects"
  "$CFG_DIR/file-history"
  "$CFG_DIR/todos"
  "$CFG_DIR/plans"
  "$CFG_DIR/feedback"
)

apply_flags() {
  local f=""
  [ "$DEEP" = "1" ] && f="$f --deep"
  [ "$STRIP_USAGE" = "1" ] && f="$f --strip-usage"
  [ "$DROP_OAUTH" = "1" ] && f="$f --drop-oauth"
  [ "$CLOUD_OFF" = "1" ] && f="$f --cloud-off"
  [ "$TELEMETRY_OFF" = "1" ] && f="$f --telemetry-off"
  printf '%s' "$f"
}

plan() {
  echo "== 计划（只读，未做任何修改） =="
  echo
  echo "将删除:"
  for d in "${DELETE_DIRS[@]}"; do
    if [ -e "$d" ]; then
      printf '  [删除] %-58s %s\n' "$d" "$(size_of "$d")"
    else
      printf '  [跳过] %-58s 不存在\n' "$d"
    fi
  done
  if [ "$DEEP" = "1" ]; then
    for d in "${DEEP_DIRS[@]}"; do
      if [ -e "$d" ]; then
        printf '  [删除] %-58s %s\n' "$d" "$(size_of "$d")"
      else
        printf '  [跳过] %-58s 不存在\n' "$d"
      fi
    done
    printf '  [删除] %-58s %s\n' "$CFG_DIR/history.jsonl" "$(size_of "$CFG_DIR/history.jsonl")"
  fi
  echo
  echo "将修改 $CONFIG:"
  echo "  [删除字段] machineID, userID, firstStartTime, firstStartVersion, numStartups,"
  echo "             installMethod, cachedExperimentData, cachedExperimentFeatures,"
  echo "             cachedGrowthBookFeatures, cachedGrowthBookFeaturesAt,"
  echo "             customApiKeyResponses, hasAvailableSubscription,"
  echo "             subscriptionNoticeCount, autoModeClassifierBillingNoticeAcknowledgedAt,"
  echo "             oauthAccount"
  if [ "$DEEP" = "1" ]; then
    echo "  [清空]     projects 映射、githubRepoPaths（会话历史将被删除）"
  elif [ "$STRIP_USAGE" = "1" ]; then
    echo "  [剥离]     每个项目条目里的 lastCost / lastModelUsage / lastTotal* /"
    echo "             lastSessionMetrics / lastAPIDuration / lastFps* 等用量字段"
    echo "             （保留 lastSessionId、信任状态、工具白名单）"
  else
    echo "  [保留]     每个项目条目里的用量/计费字段（默认不剥离；"
    echo "             需要时加 --strip-usage）"
  fi
  echo
  echo "将保留:"
  for d in settings.json settings.local.json skills plugins teams jobs daemon mcp-needs-auth-cache.json; do
    [ -e "$CFG_DIR/$d" ] && printf '  [保留] %s\n' "$CFG_DIR/$d"
  done
  [ -e "$CFG_DIR/.claude.json" ] && printf '  [保留] %s（MCP 等本地配置）\n' "$CFG_DIR/.claude.json"
  if [ "$DEEP" != "1" ]; then
    echo "  [保留] $CFG_DIR/projects/（会话内容）"
    echo "  [保留] $CFG_DIR/file-history/（/rewind 快照）"
    echo "  [保留] $CFG_DIR/history.jsonl（prompt 历史）"
    echo "  [保留] .claude.json 的 projects 映射"
  fi
  echo
  if [ "$DROP_OAUTH" = "1" ]; then
    if [ "$OS" = "Darwin" ]; then
      echo "将删除: macOS 钥匙串项 Claude Code-credentials（若存在）"
      echo "        $CFG_DIR/.credentials.json（若存在）"
    else
      echo "将删除: $CFG_DIR/.credentials.json（若存在）"
    fi
  else
    echo "将保留: 现有 OAuth 登录凭据"
  fi
  echo
  if [ "$CLOUD_OFF" = "1" ]; then
    echo "将修改: $CFG_DIR/settings.json -> env 增加 CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
    echo "         （同时关闭云会话、遥测、错误上报、自动更新等非必要流量）"
  elif [ "$TELEMETRY_OFF" = "1" ]; then
    echo "将修改: $CFG_DIR/settings.json -> env 增加 DISABLE_TELEMETRY=1,"
    echo "         DISABLE_ERROR_REPORTING=1, DO_NOT_TRACK=1（保留自动更新）"
  else
    echo "不修改 settings.json 的隐私开关"
  fi
  correlation_note
  echo
  echo "== 未做任何修改 =="
  echo
  echo "确认后，先退出所有 Claude Code，再在普通终端运行："
  echo "  bash \"$SCRIPT_PATH\" apply --yes$(apply_flags)"
  if [ "$DEEP" = "1" ]; then
    echo "  注意：--deep 会再加问一次，必须输入 DELETE HISTORY。"
  fi
}

# ---------------------------------------------------------------------------
# apply
# ---------------------------------------------------------------------------
apply() {
  if [ "$ASSUME_YES" != "1" ]; then
    echo "apply 需要 --yes。先跑 plan 并确认。" >&2
    exit 2
  fi

  PIDS="$(running_pids)"
  if [ -n "$PIDS" ]; then
    echo "拒绝执行：仍有 Claude Code 进程在运行。" >&2
    echo "PID: $PIDS" >&2
    echo "运行中的进程会在退出时把内存里的旧 .claude.json 写回，导致重置失效。" >&2
    echo "请退出所有 Claude Code 窗口/终端会话/agent，然后在普通终端重新运行本命令。" >&2
    exit 1
  fi

  if [ -f "$CFG_DIR/settings.json" ] && ! jq empty "$CFG_DIR/settings.json" >/dev/null 2>&1; then
    echo "拒绝执行：$CFG_DIR/settings.json 不是合法 JSON。" >&2
    exit 1
  fi

  if [ "$DEEP" = "1" ]; then
    if [ ! -t 0 ]; then
      echo "--deep 需要交互确认，请在普通终端运行。" >&2
      exit 2
    fi
    printf '这会删除会话历史（projects/、file-history/、history.jsonl、todos/、plans/、feedback/）。\n输入 DELETE HISTORY 继续: '
    read -r answer
    [ "$answer" = "DELETE HISTORY" ] || { echo "已取消。"; exit 1; }
  fi

  BK="$(mktemp "${TMPDIR:-/tmp}/claude-json-backup.XXXXXX")"
  chmod 600 "$BK"
  cp -p "$CONFIG" "$BK"
  trap 'echo "失败。旧配置临时备份在: $BK" >&2; exit 1' ERR

  JQ_PROGRAM='
    del(
      .machineID, .userID,
      .firstStartTime, .firstStartVersion, .numStartups, .installMethod,
      .cachedExperimentData, .cachedExperimentFeatures,
      .cachedGrowthBookFeatures, .cachedGrowthBookFeaturesAt,
      .customApiKeyResponses,
      .hasAvailableSubscription, .subscriptionNoticeCount,
      .autoModeClassifierBillingNoticeAcknowledgedAt,
      .oauthAccount
    )
  '
  if [ "$DEEP" = "1" ]; then
    JQ_PROGRAM="$JQ_PROGRAM | .projects = {} | .githubRepoPaths = []"
  elif [ "$STRIP_USAGE" = "1" ]; then
    JQ_PROGRAM="$JQ_PROGRAM | .projects = ((.projects // {}) | with_entries(
        .value |= (if type == \"object\" then del(
          .lastAPIDuration, .lastAPIDurationWithoutRetries, .lastCost,
          .lastDuration, .lastFpsAverage, .lastFpsLow1Pct,
          .lastLinesAdded, .lastLinesRemoved, .lastModelUsage,
          .lastSessionMetrics, .lastStartTime, .lastToolDuration,
          .lastTotalCacheCreationInputTokens, .lastTotalCacheReadInputTokens,
          .lastTotalInputTokens, .lastTotalOutputTokens,
          .lastTotalWebSearchRequests, .lastVersionBase
        ) else . end)
      ))"
  fi

  TMP="$CONFIG.tmp.$$"
  jq "$JQ_PROGRAM" "$CONFIG" > "$TMP"
  jq empty "$TMP"
  if [ "$DEEP" != "1" ]; then
    [ "$(jq '.projects | length' "$TMP")" = "$(jq '.projects | length' "$CONFIG")" ]
  fi
  mv "$TMP" "$CONFIG"
  chmod 600 "$CONFIG"

  for d in "${DELETE_DIRS[@]}"; do
    rm -rf "$d"
  done
  if [ "$DEEP" = "1" ]; then
    for d in "${DEEP_DIRS[@]}"; do
      rm -rf "$d"
    done
    rm -f "$CFG_DIR/history.jsonl"
  fi

  if [ "$DROP_OAUTH" = "1" ]; then
    if [ "$OS" = "Darwin" ]; then
      security delete-generic-password -s "Claude Code-credentials" >/dev/null 2>&1 || true
    fi
    rm -f "$CFG_DIR/.credentials.json"
    if oauth_present; then
      echo "提示: OAuth 凭据仍存在（钥匙串可能拒绝删除或文件权限不足），请在系统钥匙串中手动删除。"
    fi
  fi

  if [ "$CLOUD_OFF" = "1" ] || [ "$TELEMETRY_OFF" = "1" ]; then
    SETTINGS="$CFG_DIR/settings.json"
    if [ -f "$SETTINGS" ]; then
      SBK="$(mktemp "${TMPDIR:-/tmp}/claude-settings-backup.XXXXXX")"
      chmod 600 "$SBK"
      cp -p "$SETTINGS" "$SBK"
      STMP="$SETTINGS.tmp.$$"
      if [ "$CLOUD_OFF" = "1" ]; then
        jq '.env = ((.env // {}) + {"CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"})' "$SETTINGS" > "$STMP"
      else
        jq '.env = ((.env // {}) + {
          "DISABLE_TELEMETRY": "1",
          "DISABLE_ERROR_REPORTING": "1",
          "DO_NOT_TRACK": "1"
        })' "$SETTINGS" > "$STMP"
      fi
      if ! jq empty "$STMP" >/dev/null 2>&1; then
        echo "settings.json 改写失败，原文件未动。备份: $SBK" >&2
        rm -f "$STMP"
        exit 1
      fi
      mv "$STMP" "$SETTINGS"
      rm -f "$SBK"
    else
      echo "提示: $SETTINGS 不存在，跳过隐私开关设置。"
    fi
  fi

  chmod 600 "$CFG_DIR/settings.json" 2>/dev/null || true
  chmod 600 "$CFG_DIR/settings.local.json" 2>/dev/null || true
  chmod 600 "$CFG_DIR/settings.json.bak" 2>/dev/null || true
  chmod 600 "$CFG_DIR/settings.json.debug" 2>/dev/null || true

  echo "== 完成 =="
  echo "machineID: $(mask "$(jq -r '.machineID // empty' "$CONFIG")")"
  echo "userID:    $(mask "$(jq -r '.userID // empty' "$CONFIG")")"
  echo "projects 条目: $(jq -r '.projects // {} | length' "$CONFIG")"
  if [ "$DEEP" = "1" ]; then
    echo "用量字段: 随 projects 映射一起清空（--deep）"
  elif [ "$STRIP_USAGE" = "1" ]; then
    echo "用量字段: 已剥离（--strip-usage）"
  else
    echo "用量字段: 保留（默认；需要时加 --strip-usage）"
  fi
  echo
  for d in "${DELETE_DIRS[@]}"; do
    if [ -e "$d" ]; then echo "仍存在: $d"; else echo "已清:   $d"; fi
  done
  if [ "$DEEP" = "1" ]; then
    echo "会话历史: 已删除（--deep）"
  else
    echo "会话历史: 保留（projects/、file-history/、history.jsonl）"
  fi
  echo
  echo "machineID/userID 显示 absent 是正常的：下次启动 Claude Code 时才会生成新值。"
  echo "已成功上报的遥测和上游服务端日志无法通过本地清理删除。"
  correlation_note
  if [ "$KEEP_BACKUP" = "1" ]; then
    echo "旧配置临时备份保留在: $BK"
  else
    rm -f "$BK"
    echo "旧配置临时备份已删除。"
  fi
}

case "$MODE" in
  inventory) inventory ;;
  plan) plan ;;
  apply) apply ;;
  *) echo "未知模式: $MODE" >&2; usage; exit 2 ;;
esac
