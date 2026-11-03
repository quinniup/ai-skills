#!/usr/bin/env bash
# Batch-convert QQ Music encrypted downloads for Shokz OpenSwim Pro.
# - .mgg/.qmcogg -> decrypted Ogg -> 320k MP3 (OpenSwim Pro has no Ogg support)
# - .mflac/.qmcflac -> FLAC (kept as-is)
# - .qmc0/.qmc3 -> MP3
# Existing outputs are skipped, so the script is safe to re-run after new downloads.
set -uo pipefail

SOURCE_DEFAULT="${HOME}/Library/Containers/com.tencent.QQMusicMac/Data/Library/Application Support/QQMusicMac/iQmc"
OUT_DEFAULT="${HOME}/myself/music/swimming"

usage() {
    cat <<'EOF'
usage: convert.sh [--source DIR] [--out DIR] [--clean] [--dry-run]

  --source DIR   QQ 音乐加密文件目录（默认：QQ 音乐 Mac 的 iQmc）
  --out DIR      输出目录（默认：~/myself/music/swimming）
  --clean        把转换成功或输出已存在且校验通过的源文件移入废纸篓（需用户明确确认后才加）
  --dry-run      只列出将要转换的文件，不写任何文件
EOF
}

SOURCE="$SOURCE_DEFAULT"
OUT="$OUT_DEFAULT"
CLEAN=0
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --source)
            [ $# -ge 2 ] || { echo "ERROR: --source 缺少参数" >&2; exit 2; }
            SOURCE="$2"; shift 2 ;;
        --out)
            [ $# -ge 2 ] || { echo "ERROR: --out 缺少参数" >&2; exit 2; }
            OUT="$2"; shift 2 ;;
        --clean)   CLEAN=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: 未知参数 $1" >&2; usage; exit 2 ;;
    esac
done

QMC2MP3="$(command -v qmc2mp3 2>/dev/null || true)"
if [ -z "$QMC2MP3" ] && [ -x "${HOME}/.local/bin/qmc2mp3" ]; then
    QMC2MP3="${HOME}/.local/bin/qmc2mp3"
fi
if [ -z "$QMC2MP3" ]; then
    echo "ERROR: 未找到 qmc2mp3，请先运行 install-qmc2mp3.sh" >&2
    exit 2
fi

[ -d "$SOURCE" ] || { echo "ERROR: 源目录不存在：$SOURCE" >&2; exit 2; }
mkdir -p "$OUT" || { echo "ERROR: 无法创建输出目录：$OUT" >&2; exit 2; }

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "WARN: 未找到 ffmpeg，.mgg 将无法转成 MP3（brew install ffmpeg）" >&2
fi

REAL_PLIST="${HOME}/Library/Preferences/com.tencent.QQMusicMac.plist"
CONTAINER_PLIST="${HOME}/Library/Containers/com.tencent.QQMusicMac/Data/Library/Preferences/com.tencent.QQMusicMac.plist"
if [ ! -f "$REAL_PLIST" ] && [ ! -f "$CONTAINER_PLIST" ]; then
    echo "WARN: 未找到 QQ 音乐登录配置，请先打开 QQ 音乐并确认已登录" >&2
fi

is_supported() {
    case "$1" in
        mgg|mgg0|mgg1|mggl|mflac|mflac0|mflach|qmc0|qmc2|qmc3|qmcflac|qmcogg) return 0 ;;
        *) return 1 ;;
    esac
}

verify_target() {
    [ -s "$1" ] || return 1
    if command -v ffprobe >/dev/null 2>&1; then
        dur="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$1" 2>/dev/null)"
        case "$dur" in
            ''|*[!0-9.]*) return 1 ;;
        esac
        [ "${dur%%.*}" -gt 0 ] 2>/dev/null || return 1
    fi
    return 0
}

clean_source() {
    if command -v trash >/dev/null 2>&1; then
        trash "$1" && printf '        已移入废纸篓：%s\n' "$2"
    else
        rm -f "$1" && printf '        已删除源文件：%s\n' "$2"
    fi
}

total=0
for f in "$SOURCE"/*; do
    [ -f "$f" ] || continue
    ext="$(printf '%s' "${f##*.}" | tr '[:upper:]' '[:lower:]')"
    is_supported "$ext" && total=$((total + 1))
done

if [ "$total" -eq 0 ]; then
    echo "源目录里没有可转换的加密文件：$SOURCE"
    exit 0
fi

echo "源目录：$SOURCE"
echo "输出目录：$OUT"
[ "$DRY_RUN" -eq 1 ] && echo "模式：dry-run（只预览，不写入）"
echo "待检查：$total 个文件"
echo ""

index=0
converted=0
skipped=0
failed=0
cleaned=0

for f in "$SOURCE"/*; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    ext="$(printf '%s' "${f##*.}" | tr '[:upper:]' '[:lower:]')"
    is_supported "$ext" || continue

    index=$((index + 1))
    base="${name%.*}"
    case "$ext" in
        mflac|mflac0|mflach|qmcflac) oext="flac" ;;
        *) oext="mp3" ;;
    esac
    target="$OUT/${base}.${oext}"

    if [ -s "$target" ]; then
        skipped=$((skipped + 1))
        printf '[%d/%d] SKIP  %s\n' "$index" "$total" "$name"
        if [ "$CLEAN" -eq 1 ] && [ "$DRY_RUN" -eq 0 ]; then
            if verify_target "$target"; then
                clean_source "$f" "$name"
                cleaned=$((cleaned + 1))
            else
                printf '        输出校验失败，保留源文件\n'
            fi
        fi
        continue
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        printf '[%d/%d] PLAN  %s -> %s\n' "$index" "$total" "$name" "${base}.${oext}"
        converted=$((converted + 1))
        continue
    fi

    log="$(mktemp "${TMPDIR:-/tmp}/swimming-times.XXXXXX")"
    if ! "$QMC2MP3" "$f" "$OUT" </dev/null >"$log" 2>&1; then
        failed=$((failed + 1))
        printf '[%d/%d] FAIL  %s\n' "$index" "$total" "$name"
        tail -n 15 "$log" | sed 's/^/        /'
        rm -f "$log"
        continue
    fi
    rm -f "$log"

    if [ ! -s "$target" ]; then
        failed=$((failed + 1))
        printf '[%d/%d] FAIL  %s（没有生成输出文件）\n' "$index" "$total" "$name"
        continue
    fi

    if ! verify_target "$target"; then
        failed=$((failed + 1))
        printf '[%d/%d] FAIL  %s（输出校验失败）\n' "$index" "$total" "$name"
        continue
    fi

    converted=$((converted + 1))
    printf '[%d/%d] OK    %s\n' "$index" "$total" "${base}.${oext}"

    if [ "$CLEAN" -eq 1 ]; then
        clean_source "$f" "$name"
        cleaned=$((cleaned + 1))
    fi
done

echo ""
if [ "$DRY_RUN" -eq 1 ]; then
    printf '预览完成：将转换 %d 个，已存在 %d 个\n' "$converted" "$skipped"
else
    printf '完成：成功 %d，跳过 %d，失败 %d' "$converted" "$skipped" "$failed"
    [ "$CLEAN" -eq 1 ] && printf '，已清理源文件 %d' "$cleaned"
    printf '\n'
fi

[ "$failed" -eq 0 ] || exit 1
