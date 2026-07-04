#!/usr/bin/env python3
# ============================================================
# cc-switch 自愈工具 —— codex provider 协议(wire_api)诊断与修复
#
# 背景：
#   codex 每个 provider 的 wire_api 决定它用哪种 API 协议握手：
#     - "responses" : OpenAI Responses API (/v1/responses)
#     - "chat"      : OpenAI Chat Completions (/v1/chat/completions)
#   会话在"新建那一刻"就绑定了协议，之后切 provider 不会重建会话。
#   如果一个 provider 的真实端点只支持 chat，却被配成 responses，
#   用它开的新会话第一次握手就失败，且无法被后续切换救活。
#
#   典型错误：阿里云百炼 compatible-mode 端点（只有 chat）被配成 responses。
#
# 本脚本全部动作：
#   diagnose        只读扫描，输出报告，不改任何东西
#   backup          把整个 cc-switch.db 复制到带时间戳的备份
#   fix <id...>     修复指定 provider 的 wire_api（自动先备份，事务写入，校验，失败回滚）
#   list-backups    列出已有备份
#   rollback <file> 从备份恢复整个数据库
#
# 安全原则：任何写操作前强制备份；写操作在事务中进行；写后校验；
#          绝不删除用户数据；不回显 API Key。
# ============================================================

import sys
import os
import re
import json
import time
import shutil
import sqlite3
from datetime import datetime

HOME = os.path.expanduser("~")
# 允许通过 CC_SWITCH_DB 环境变量覆盖数据库路径（测试/多环境用）。
DB_PATH = os.environ.get("CC_SWITCH_DB") or os.path.join(HOME, ".cc-switch", "cc-switch.db")
# 备份始终写到数据库同级的 backups/ 目录，跟随实际使用的 DB_PATH。
BACKUP_DIR = os.path.join(os.path.dirname(DB_PATH), "backups")
# DRY_RUN=1 时，fix/rollback 只打印将要做的操作，不写任何文件。
DRY_RUN = os.environ.get("DRY_RUN") in ("1", "true", "yes")

# 已知只支持 Chat Completions（不支持 Responses API）的端点特征。
# 命中这些特征而 wire_api=responses 的 provider 会被判定为“协议不匹配”。
CHAT_ONLY_HINTS = [
    "dashscope.aliyuncs.com",      # 阿里云百炼 DashScope
    "compatible-mode",             # 各家“OpenAI 兼容模式”通常只有 chat
    "aliyuncs.com/compatible",
    "dashscope-intl.aliyuncs.com",
]

RESET = "\033[0m"
RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
CYAN = "\033[0;36m"
BOLD = "\033[1m"


def c(color, text):
    return f"{color}{text}{RESET}"


def die(msg):
    print(c(RED, f"✗ {msg}"), file=sys.stderr)
    sys.exit(1)


def ensure_db():
    if not os.path.exists(DB_PATH):
        die(f"未找到 cc-switch 数据库: {DB_PATH}")


def open_ro():
    """只读打开（不会锁库、不会影响正在运行的 cc-switch）。"""
    uri = f"file:{DB_PATH}?mode=ro&immutable=1"
    return sqlite3.connect(uri, uri=True, timeout=5)


def open_rw():
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.execute("PRAGMA busy_timeout=10000")
    return conn


def extract_config_toml(settings_config):
    """settings_config 是 JSON 字符串，codex 的 TOML 存在其 config 字段里。"""
    try:
        obj = json.loads(settings_config)
    except (json.JSONDecodeError, TypeError):
        return None, None
    if isinstance(obj, dict) and "config" in obj:
        return obj, obj.get("config", "")
    return obj, None


def extract_auth_keys(settings_config):
    """返回 settings_config.auth 里非空的 key 名列表（只看是否存在与非空，绝不回显值）。"""
    try:
        obj = json.loads(settings_config)
    except (json.JSONDecodeError, TypeError):
        return []
    if not isinstance(obj, dict):
        return []
    auth = obj.get("auth")
    if not isinstance(auth, dict):
        return []
    return [k for k, v in auth.items() if isinstance(v, str) and v.strip()]


def toml_provider_table_names(toml_text):
    """提取所有 [model_providers.xxx] 的表名 xxx。"""
    if not toml_text:
        return []
    return re.findall(r"^\s*\[model_providers\.([A-Za-z0-9_-]+)\]", toml_text, re.MULTILINE)


def parse_toml_field(toml_text, field):
    """粗粒度提取 base_url / wire_api 等 key = "value" 字段。够用即可，不做完整 TOML 解析。"""
    if not toml_text:
        return None
    m = re.search(rf'^\s*{field}\s*=\s*"([^"]*)"', toml_text, re.MULTILINE)
    if m:
        return m.group(1)
    m = re.search(rf"^\s*{field}\s*=\s*'([^']*)'", toml_text, re.MULTILINE)
    if m:
        return m.group(1)
    return None


def classify(base_url, wire_api):
    """返回 (status, reason)。status: ok / mismatch / unknown / chat_ok"""
    bl = (base_url or "").lower()
    is_chat_only = any(h in bl for h in CHAT_ONLY_HINTS)
    if is_chat_only:
        if wire_api == "responses":
            return "mismatch", "端点只支持 Chat Completions，却配成了 responses"
        elif wire_api == "chat":
            return "chat_ok", "chat 端点配置正确"
        else:
            return "unknown", f"chat 端点但 wire_api={wire_api!r}"
    # 非明显 chat-only 端点：大多是 Responses 中转，保持现状即可
    if wire_api == "responses":
        return "ok", "Responses 协议（中转/官方）"
    if wire_api == "chat":
        return "ok", "chat 协议"
    return "unknown", f"wire_api={wire_api!r}，无法判定"


def detect_extra_warnings(toml_text, settings_config):
    """检测除 wire_api 外的其它「会话开不起来」隐患，返回 warning 字符串列表。

    这些问题脚本不自动改（涉及鉴权/表名，需人工判断），只做提示。
    """
    warnings = []

    # 1. auth key 缺失或为空 —— 请求会 401，会话同样起不来
    env_key = parse_toml_field(toml_text, "env_key") or "OPENAI_API_KEY"
    requires_auth = parse_toml_field(toml_text, "requires_openai_auth")
    auth_keys = extract_auth_keys(settings_config)
    if not auth_keys:
        warnings.append("auth 里没有任何非空 API Key，请求大概率 401（会话同样开不起来）")
    elif env_key not in auth_keys:
        warnings.append(
            f"config 期望的 key 名 `{env_key}` 不在 auth 里（auth 现有：{', '.join(auth_keys)}）"
        )

    # 2. model_provider 指向的表名，跟实际 [model_providers.xxx] 对不上
    mp = parse_toml_field(toml_text, "model_provider")
    tables = toml_provider_table_names(toml_text)
    if mp and tables and mp not in tables:
        warnings.append(
            f"model_provider = \"{mp}\" 但实际定义的是 [model_providers.{'/'.join(tables)}]，表名对不上"
        )

    return warnings


def gather_codex_providers(conn):
    rows = conn.execute(
        "SELECT id, name, settings_config, is_current FROM providers "
        "WHERE app_type = 'codex' ORDER BY is_current DESC, name"
    ).fetchall()
    result = []
    for pid, name, settings_config, is_current in rows:
        _, toml_text = extract_config_toml(settings_config)
        base_url = parse_toml_field(toml_text, "base_url")
        wire_api = parse_toml_field(toml_text, "wire_api")
        model = parse_toml_field(toml_text, "model")
        status, reason = classify(base_url, wire_api)
        warnings = detect_extra_warnings(toml_text, settings_config)
        result.append({
            "id": pid,
            "name": name,
            "model": model,
            "base_url": base_url,
            "wire_api": wire_api,
            "is_current": bool(is_current),
            "status": status,
            "reason": reason,
            "warnings": warnings,
        })
    return result


def cmd_diagnose():
    ensure_db()
    conn = open_ro()
    try:
        providers = gather_codex_providers(conn)
    finally:
        conn.close()

    if not providers:
        print(c(YELLOW, "未找到任何 codex provider。"))
        return

    print(c(BOLD, "\ncodex provider 协议诊断\n"))
    icon = {"ok": c(GREEN, "✅ 正常"),
            "chat_ok": c(GREEN, "✅ 正常"),
            "mismatch": c(RED, "🔴 协议不匹配"),
            "unknown": c(YELLOW, "⚠ 待确认")}

    mismatches = []
    for p in providers:
        cur = c(CYAN, " (当前)") if p["is_current"] else ""
        print(f"{icon.get(p['status'], '?')}  {c(BOLD, p['name'])}{cur}")
        print(f"      id       : {p['id']}")
        print(f"      model    : {p['model']}")
        print(f"      base_url : {p['base_url']}")
        print(f"      wire_api : {p['wire_api']}   — {p['reason']}")
        for w in p.get("warnings", []):
            print(c(YELLOW, f"      ⚠ {w}"))
        print()
        if p["status"] == "mismatch":
            mismatches.append(p)

    if mismatches:
        print(c(RED, f"发现 {len(mismatches)} 个 wire_api 配置错误的 provider：\n"))
        for p in mismatches:
            print(c(RED, f"  • {p['name']} ({p['id']})"))
            print(f"      应把 wire_api 从 \"responses\" 改为 \"chat\"")
        print()
        print(c(YELLOW, "修复命令（会先自动备份，可回滚）："))
        ids = " ".join(p["id"] for p in mismatches)
        print(c(CYAN, f"  python3 heal.py fix {ids}"))
    else:
        print(c(GREEN, "所有 codex provider 的 wire_api 协议配置看起来都正常。"))

    # 汇总 wire_api 之外的隐患（脚本不自动改，需人工判断）
    warned = [p for p in providers if p.get("warnings")]
    if warned:
        print(c(YELLOW, f"\n另有 {len(warned)} 个 provider 存在其它隐患（不自动修，仅提示）："))
        for p in warned:
            print(c(YELLOW, f"  • {p['name']} ({p['id']})"))
            for w in p["warnings"]:
                print(f"      - {w}")
        print(c(CYAN, "  这类问题多与 API Key / 表名有关，需在 cc-switch 界面核对后手动改。"))

    # 机器可读结果给上层 skill 使用
    print("\n---JSON---")
    print(json.dumps({
        "providers": providers,
        "mismatch_ids": [p["id"] for p in mismatches],
        "warned_ids": [p["id"] for p in providers if p.get("warnings")],
    }, ensure_ascii=False))


def do_backup():
    ensure_db()
    os.makedirs(BACKUP_DIR, exist_ok=True)
    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    dest = os.path.join(BACKUP_DIR, f"cc-switch.db.heal-backup.{ts}")
    # 用 SQLite backup API 做一致性快照（即使 cc-switch 正在运行也安全）
    src = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True, timeout=10)
    try:
        dst = sqlite3.connect(dest)
        try:
            src.backup(dst)
        finally:
            dst.close()
    finally:
        src.close()
    size = os.path.getsize(dest)
    print(c(GREEN, f"✓ 已备份数据库 → {dest}  ({size} bytes)"))
    return dest


def cmd_backup():
    do_backup()


def cmd_list_backups():
    if not os.path.isdir(BACKUP_DIR):
        print("尚无备份。")
        return
    files = sorted(
        (f for f in os.listdir(BACKUP_DIR) if "heal-backup" in f),
        reverse=True,
    )
    if not files:
        print("尚无 heal 备份。")
        return
    print(c(BOLD, "已有备份（新→旧）："))
    for f in files:
        full = os.path.join(BACKUP_DIR, f)
        size = os.path.getsize(full)
        print(f"  {full}  ({size} bytes)")


def cmd_fix(ids):
    ensure_db()
    if not ids:
        die("请提供要修复的 provider id，例如: python3 heal.py fix <id>")

    # 1. 先看这些 id 当前状态，确认确实需要修
    conn = open_ro()
    try:
        providers = {p["id"]: p for p in gather_codex_providers(conn)}
    finally:
        conn.close()

    targets = []
    for pid in ids:
        p = providers.get(pid)
        if not p:
            print(c(YELLOW, f"⚠ 跳过：未找到 provider id={pid}"))
            continue
        if p["status"] != "mismatch":
            print(c(YELLOW, f"⚠ 跳过：{p['name']} ({pid}) 当前状态为 {p['status']}，无需修复"))
            continue
        targets.append(p)

    if not targets:
        print(c(YELLOW, "没有需要修复的 provider，退出。"))
        return

    # DRY_RUN：只预告将要做的改动，不备份、不写库
    if DRY_RUN:
        print(c(BOLD, "\n[DRY_RUN] 以下改动将被执行（当前不会真正写入）："))
        for p in targets:
            print(f"  • {p['name']} ({p['id']}): wire_api responses → chat")
        print(c(CYAN, "  去掉 DRY_RUN=1 再次运行即可真正修复。"))
        return

    # 2. 强制备份
    print(c(BOLD, "\n[1/4] 修复前强制备份..."))
    backup_path = do_backup()

    # 3. 事务内修改
    print(c(BOLD, "\n[2/4] 写入修复（事务保护）..."))
    conn = open_rw()
    changed = []
    try:
        conn.execute("BEGIN")
        for p in targets:
            row = conn.execute(
                "SELECT settings_config FROM providers WHERE id=? AND app_type='codex'",
                (p["id"],),
            ).fetchone()
            if not row:
                continue
            obj, toml_text = extract_config_toml(row[0])
            if toml_text is None:
                print(c(YELLOW, f"  ⚠ {p['name']}: 无法解析 config，跳过"))
                continue
            new_toml, n = re.subn(
                r'(wire_api\s*=\s*)"responses"',
                r'\1"chat"',
                toml_text,
            )
            if n == 0:
                print(c(YELLOW, f"  ⚠ {p['name']}: 未找到 wire_api=\"responses\"，跳过"))
                continue
            obj["config"] = new_toml
            new_settings = json.dumps(obj, ensure_ascii=False)
            conn.execute(
                "UPDATE providers SET settings_config=? WHERE id=? AND app_type='codex'",
                (new_settings, p["id"]),
            )
            changed.append(p)
            print(f"  ✓ {p['name']} ({p['id']}): wire_api responses → chat")
        conn.commit()
    except Exception as e:
        conn.rollback()
        conn.close()
        print(c(RED, f"✗ 写入失败，已回滚事务: {e}"))
        print(c(CYAN, f"  数据库未改动。若仍担心，可从备份恢复：\n"
                      f"  python3 heal.py rollback {backup_path}"))
        sys.exit(1)
    finally:
        try:
            conn.close()
        except Exception:
            pass

    # 4. 写后校验
    print(c(BOLD, "\n[3/4] 校验修复结果..."))
    conn = open_ro()
    try:
        after = {p["id"]: p for p in gather_codex_providers(conn)}
    finally:
        conn.close()

    ok = True
    for p in changed:
        now = after.get(p["id"])
        if now and now["wire_api"] == "chat" and now["status"] in ("chat_ok", "ok"):
            print(c(GREEN, f"  ✓ {p['name']}: 现在 wire_api={now['wire_api']} ({now['status']})"))
        else:
            ok = False
            print(c(RED, f"  ✗ {p['name']}: 校验异常，当前 wire_api={now['wire_api'] if now else '?'}"))

    print(c(BOLD, "\n[4/4] 完成"))
    if ok and changed:
        print(c(GREEN, f"✓ 已修复 {len(changed)} 个 provider。"))
    print(c(YELLOW, "\n重要后续步骤："))
    print("  1) cc-switch 桌面应用可能仍持有旧配置缓存。请在 cc-switch 里")
    print("     重新点选一次该 provider（或重启 cc-switch），让本地代理重载配置。")
    print("  2) 你开着本地代理（enableLocalProxy）。如果经代理仍失败，说明是代理层")
    print("     覆盖了协议，需要在 cc-switch 界面把该 provider 的协议改为 chat。")
    print(c(CYAN, f"\n如需回滚：python3 heal.py rollback {backup_path}"))


def cmd_rollback(backup_file):
    if not backup_file or not os.path.exists(backup_file):
        die(f"备份文件不存在: {backup_file}")
    ensure_db()
    if DRY_RUN:
        print(c(BOLD, "[DRY_RUN] 将执行回滚（当前不会真正写入）："))
        print(f"  {backup_file} → {DB_PATH}")
        print(c(CYAN, "  去掉 DRY_RUN=1 再次运行即可真正回滚。"))
        return
    # 回滚前，再给当前库做一次安全快照，防止用户回滚错了还能回来
    print(c(BOLD, "回滚前先给当前数据库做一次安全快照..."))
    safety = do_backup()
    print(c(BOLD, "\n恢复中..."))
    shutil.copy2(backup_file, DB_PATH)
    # 清理可能存在的 WAL/SHM，避免旧 WAL 覆盖恢复内容
    for suffix in ("-wal", "-shm"):
        p = DB_PATH + suffix
        if os.path.exists(p):
            os.remove(p)
    print(c(GREEN, f"✓ 已从备份恢复: {backup_file}"))
    print(c(CYAN, f"  （回滚前的状态也已快照到: {safety}）"))
    print(c(YELLOW, "  请重启 cc-switch 使其重新加载数据库。"))


USAGE = """cc-switch 自愈工具

用法:
  python3 heal.py diagnose            扫描并诊断所有 codex provider（只读，安全）
  python3 heal.py backup              手动备份 cc-switch.db
  python3 heal.py fix <id> [<id>...]  修复指定 provider 的 wire_api（先备份）
  python3 heal.py list-backups        列出已有备份
  python3 heal.py rollback <file>     从备份恢复整个数据库
"""


def main():
    if len(sys.argv) < 2:
        print(USAGE)
        sys.exit(0)
    cmd = sys.argv[1]
    args = sys.argv[2:]
    if cmd == "diagnose":
        cmd_diagnose()
    elif cmd == "backup":
        cmd_backup()
    elif cmd == "fix":
        cmd_fix(args)
    elif cmd == "list-backups":
        cmd_list_backups()
    elif cmd == "rollback":
        cmd_rollback(args[0] if args else None)
    else:
        print(USAGE)
        die(f"未知命令: {cmd}")


if __name__ == "__main__":
    main()
