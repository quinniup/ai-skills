#!/usr/bin/env bash
# Install the qmc2mp3 helper used by the swimming-times skill.
# Requires macOS, Rust (cargo), git, ffmpeg; QQ Music for Mac must be logged in.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
TARGET="${BIN_DIR}/qmc2mp3"
QMC_REPO="https://github.com/ownlight6/qmc-decoder.git"

info()  { printf '%s\n' "$*"; }
warn()  { printf 'WARN: %s\n' "$*" >&2; }
die()   { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if command -v qmc2mp3 >/dev/null 2>&1; then
    info "qmc2mp3 已安装：$(command -v qmc2mp3)"
    exit 0
fi
if [ -x "$TARGET" ]; then
    info "qmc2mp3 已安装：$TARGET"
    case ":${PATH}:" in
        *":${BIN_DIR}:"*) ;;
        *) warn "该目录不在 PATH 中，请把下面一行加入 ~/.zshrc：export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
    esac
    exit 0
fi

[ "$(uname -s)" = "Darwin" ] || die "本技能仅支持 macOS（QQ 音乐 Mac 下载目录与钥匙串路径都是 macOS 专用）"

missing=""
for cmd in git cargo ffmpeg; do
    command -v "$cmd" >/dev/null 2>&1 || missing="${missing} ${cmd}"
done
if [ -n "$missing" ]; then
    warn "缺少依赖：${missing# }"
    info "  安装 Rust：curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    info "  安装 ffmpeg：brew install ffmpeg"
    info "  安装 git：xcode-select --install"
    exit 1
fi

# qmc-decoder reads QQ Music credentials from the sandbox container path.
# Some QQ Music builds write to ~/Library/Preferences instead; bridge the gap.
REAL_PLIST="${HOME}/Library/Preferences/com.tencent.QQMusicMac.plist"
CONTAINER_PLIST="${HOME}/Library/Containers/com.tencent.QQMusicMac/Data/Library/Preferences/com.tencent.QQMusicMac.plist"
if [ ! -e "$CONTAINER_PLIST" ] && [ -f "$REAL_PLIST" ]; then
    mkdir -p "$(dirname "$CONTAINER_PLIST")"
    ln -s "$REAL_PLIST" "$CONTAINER_PLIST"
    info "已建立 QQ 音乐配置软链接：$CONTAINER_PLIST"
    info "  -> $REAL_PLIST"
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/qmc2mp3.XXXXXX")"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

info "==> 下载 qmc-decoder 源码"
git clone --depth 1 "$QMC_REPO" "$TMP_DIR/src" >/dev/null 2>&1 || die "git clone 失败，请检查网络"

cd "$TMP_DIR/src"
# 去掉 workspace 成员，避免构建时拉取整套 Tauri 依赖
awk 'BEGIN{skip=0}
     /^\[workspace\]/{skip=1; next}
     skip==1 && /^[[:space:]]*$/{skip=0; next}
     skip==0{print}' Cargo.toml > Cargo.toml.new
mv Cargo.toml.new Cargo.toml
rm -rf src-tauri

mkdir -p examples
cp "$SCRIPT_DIR/qmc2mp3.rs" examples/decrypt.rs

info "==> 编译 qmc2mp3（首次需要下载依赖，约 1-3 分钟）"
cargo build --release --example decrypt

mkdir -p "$BIN_DIR"
install -m 755 "$TMP_DIR/src/target/release/examples/decrypt" "$TARGET"

"$TARGET" --help >/dev/null 2>&1 || die "编译产物无法运行"

info ""
info "安装完成：$TARGET"
case ":${PATH}:" in
    *":${BIN_DIR}:"*) ;;
    *)
        warn "$BIN_DIR 不在 PATH 中"
        info "请把下面一行加入 ~/.zshrc 并重开终端："
        info "  export PATH=\"\$HOME/.local/bin:\$PATH\""
        ;;
esac
info ""
info "下一步：确认 QQ 音乐已登录，然后运行 convert.sh"
info "注意：qmc2mp3 依赖 qmc-decoder（GPL-3.0），仅用于转换自己有权播放的音乐。"
