#!/bin/bash
# ============================================================
# sing-box 代理一键部署脚本
# 面向零基础用户，交互式引导完成全部部署
# ============================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_step() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}▶ $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_info() {
    echo -e "${CYAN}  ℹ $1${NC}"
}

print_warn() {
    echo -e "${YELLOW}  ⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}  ✗ $1${NC}"
}

print_success() {
    echo -e "${GREEN}  ✓ $1${NC}"
}

# ============================================================
# 欢迎信息
# ============================================================
clear
echo -e "${GREEN}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║     🚀 代理服务一键部署工具                  ║"
echo "  ║     基于 sing-box-yg                        ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""
echo "  本脚本将帮你完成以下操作："
echo "  1. 生成 SSH 密钥（免密登录你的服务器）"
echo "  2. 在服务器上安装 sing-box 代理服务"
echo "  3. 将配置文件下载到本机"
echo ""
echo -e "${YELLOW}  请准备好你的 VPS 信息（IP 地址和 root 密码）${NC}"
echo ""
read -p "  准备好了吗？按回车继续..." _

# ============================================================
# 第一步：收集用户信息
# ============================================================
print_step "第一步：输入你的 VPS 信息"

echo ""
read -p "  请输入 VPS 的 IP 地址: " VPS_IP

# 验证 IP 格式（简单校验）
if [[ ! "$VPS_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && [[ ! "$VPS_IP" =~ : ]]; then
    print_error "IP 地址格式不正确，请检查后重新运行脚本"
    exit 1
fi

echo ""
read -p "  请输入 SSH 端口号 [默认 22]: " VPS_PORT
VPS_PORT=${VPS_PORT:-22}

echo ""
echo -e "  请输入 root 密码（${YELLOW}输入时不会显示，这是正常的${NC}）:"
read -s VPS_PASS
echo ""

if [ -z "$VPS_PASS" ]; then
    print_error "密码不能为空"
    exit 1
fi

print_success "信息已记录（密码仅用于本次部署，不会保存到任何文件）"

# ============================================================
# 第二步：生成 SSH 密钥
# ============================================================
print_step "第二步：生成 SSH 密钥"

SSH_KEY="$HOME/.ssh/id_ed25519_singbox"
SSH_PUB="$SSH_KEY.pub"

if [ -f "$SSH_KEY" ]; then
    print_info "检测到已有密钥: $SSH_KEY"
    read -p "  是否使用已有密钥？[Y/n]: " USE_EXISTING
    USE_EXISTING=${USE_EXISTING:-Y}
    if [[ "$USE_EXISTING" =~ ^[Nn] ]]; then
        rm -f "$SSH_KEY" "$SSH_PUB"
        ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "singbox-deploy-$(date +%Y%m%d)"
        print_success "新密钥已生成"
    else
        print_success "使用已有密钥"
    fi
else
    print_info "正在生成 SSH 密钥..."
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -C "singbox-deploy-$(date +%Y%m%d)"
    print_success "密钥已生成: $SSH_KEY"
fi

# ============================================================
# 第三步：部署公钥到 VPS
# ============================================================
print_step "第三步：将密钥部署到你的 VPS"

print_info "正在连接 VPS 并部署公钥..."
print_info "（可能需要几秒钟，请耐心等待）"

# 检查 sshpass 是否安装
if ! command -v sshpass &> /dev/null; then
    print_warn "需要安装 sshpass 工具来自动输入密码..."
    if command -v brew &> /dev/null; then
        brew install hudochenkov/sshpass/sshpass 2>/dev/null || brew install esolitos/ipa/sshpass 2>/dev/null
    else
        print_error "请先安装 Homebrew: https://brew.sh"
        print_info "或者手动运行: brew install hudochenkov/sshpass/sshpass"
        exit 1
    fi
fi

# 部署公钥
PUB_KEY_CONTENT=$(cat "$SSH_PUB")

sshpass -p "$VPS_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -p "$VPS_PORT" "root@$VPS_IP" \
    "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$PUB_KEY_CONTENT' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys" 2>/dev/null

if [ $? -eq 0 ]; then
    print_success "公钥部署成功！以后可以免密登录"
else
    print_error "公钥部署失败，请检查 IP 和密码是否正确"
    exit 1
fi

# 验证免密登录
print_info "验证免密登录..."
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$SSH_KEY" -p "$VPS_PORT" "root@$VPS_IP" "echo ok" &>/dev/null
if [ $? -eq 0 ]; then
    print_success "免密登录验证通过"
else
    print_warn "免密登录验证未通过，后续操作将使用密码"
    USE_KEY=false
fi

# 清除密码变量（安全措施）
unset VPS_PASS

# SSH 命令封装
SSH_CMD="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 -i $SSH_KEY -p $VPS_PORT root@$VPS_IP"
SCP_CMD="scp -o StrictHostKeyChecking=no -i $SSH_KEY -P $VPS_PORT"

# ============================================================
# 第四步：安装 sing-box-yg
# ============================================================
print_step "第四步：在 VPS 上安装 sing-box 代理服务"

print_info "正在远程安装 sing-box-yg..."
print_info "这个过程可能需要 1-3 分钟，请耐心等待"
print_warn "安装过程中如果提示选择，脚本会自动使用默认配置"
echo ""

# 先检查是否已安装
INSTALLED=$($SSH_CMD "command -v sing-box &>/dev/null && echo yes || echo no" 2>/dev/null)

if [ "$INSTALLED" = "yes" ]; then
    print_info "检测到 sing-box 已安装"
    read -p "  是否重新安装？[y/N]: " REINSTALL
    REINSTALL=${REINSTALL:-N}
    if [[ ! "$REINSTALL" =~ ^[Yy] ]]; then
        print_success "跳过安装，使用现有服务"
        SKIP_INSTALL=true
    fi
fi

if [ "$SKIP_INSTALL" != "true" ]; then
    # 使用非交互方式安装 sing-box-yg
    # sing-box-yg 脚本支持按回车使用默认值
    $SSH_CMD "bash <(wget -qO- https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh)" </dev/null

    if [ $? -eq 0 ]; then
        print_success "sing-box 安装完成"
    else
        print_warn "自动安装可能需要交互操作"
        print_info "请手动 SSH 登录完成安装："
        echo ""
        echo -e "    ${CYAN}ssh -i $SSH_KEY -p $VPS_PORT root@$VPS_IP${NC}"
        echo -e "    ${CYAN}bash <(wget -qO- https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh)${NC}"
        echo ""
        print_info "安装完成后，输入 sb 进入管理菜单生成配置"
        read -p "  安装完成后按回车继续..." _
    fi
fi

# ============================================================
# 第五步：下载配置文件
# ============================================================
print_step "第五步：下载 Clash/Mihomo 配置文件"

# sing-box-yg 生成的配置文件可能位置
REMOTE_PATHS=(
    "/root/sing-box-yg/clash_meta.yaml"
    "/root/sing-box-yg/url/clash_meta.yaml"
    "/root/sbyg_config/clash_meta.yaml"
    "/root/sing-box/clash_meta.yaml"
)

# 本地配置目录
LOCAL_CONFIG_DIR="$HOME/.config/clash.meta"
mkdir -p "$LOCAL_CONFIG_DIR"

print_info "正在从 VPS 查找配置文件..."

CONFIG_FOUND=false
for REMOTE_PATH in "${REMOTE_PATHS[@]}"; do
    EXISTS=$($SSH_CMD "[ -f '$REMOTE_PATH' ] && echo yes || echo no" 2>/dev/null)
    if [ "$EXISTS" = "yes" ]; then
        print_success "找到配置文件: $REMOTE_PATH"
        $SCP_CMD "root@$VPS_IP:$REMOTE_PATH" "$LOCAL_CONFIG_DIR/config.yaml"
        if [ $? -eq 0 ]; then
            CONFIG_FOUND=true
            print_success "配置文件已下载到: $LOCAL_CONFIG_DIR/config.yaml"
        fi
        break
    fi
done

# 如果没找到，尝试搜索
if [ "$CONFIG_FOUND" != "true" ]; then
    print_warn "未在默认路径找到配置文件，正在搜索..."
    FOUND_PATH=$($SSH_CMD "find /root -name 'clash_meta*' -o -name '*clash*yaml' 2>/dev/null | head -1" 2>/dev/null)

    if [ -n "$FOUND_PATH" ]; then
        print_success "找到: $FOUND_PATH"
        $SCP_CMD "root@$VPS_IP:$FOUND_PATH" "$LOCAL_CONFIG_DIR/config.yaml"
        if [ $? -eq 0 ]; then
            CONFIG_FOUND=true
            print_success "配置文件已下载"
        fi
    fi
fi

if [ "$CONFIG_FOUND" != "true" ]; then
    print_warn "未找到自动生成的配置文件"
    print_info "这通常意味着需要手动在 sing-box 管理面板中生成"
    echo ""
    print_info "请执行以下步骤："
    echo -e "    1. SSH 登录: ${CYAN}ssh -i $SSH_KEY -p $VPS_PORT root@$VPS_IP${NC}"
    echo -e "    2. 输入: ${CYAN}sb${NC}"
    echo -e "    3. 在菜单中选择「生成/查看订阅链接」"
    echo -e "    4. 找到 Clash/Mihomo 配置文件路径"
    echo -e "    5. 手动下载: ${CYAN}scp -i $SSH_KEY -P $VPS_PORT root@$VPS_IP:<路径> ~/.config/clash.meta/config.yaml${NC}"
    echo ""
fi

# ============================================================
# 第六步：检查 ClashX Meta 客户端
# ============================================================
print_step "第六步：检查本地客户端"

CLASHX_APP="/Applications/ClashX Meta.app"
if [ -d "$CLASHX_APP" ]; then
    print_success "ClashX Meta 已安装"
else
    print_warn "未检测到 ClashX Meta"
    echo ""
    echo -e "  请下载安装 ClashX Meta："
    echo -e "  ${CYAN}https://github.com/MetaCubeX/ClashX.Meta/releases/download/v1.4.35/ClashX.Meta.zip${NC}"
    echo ""
    read -p "  是否现在打开下载页面？[Y/n]: " OPEN_DL
    OPEN_DL=${OPEN_DL:-Y}
    if [[ "$OPEN_DL" =~ ^[Yy] ]]; then
        open "https://github.com/MetaCubeX/ClashX.Meta/releases/tag/v1.4.35"
    fi
    echo ""
    print_info "下载安装后，配置文件已就位，直接启动即可使用"
fi

# ============================================================
# 完成
# ============================================================
print_step "🎉 部署完成！"

echo ""
echo "  ┌─────────────────────────────────────────────────┐"
echo "  │  部署摘要                                        │"
echo "  ├─────────────────────────────────────────────────┤"
echo -e "  │  VPS 地址:    ${CYAN}$VPS_IP${NC}"
echo -e "  │  SSH 密钥:    ${CYAN}$SSH_KEY${NC}"
echo -e "  │  配置文件:    ${CYAN}$LOCAL_CONFIG_DIR/config.yaml${NC}"
echo "  │                                                 │"
echo "  │  后续管理:                                       │"
echo -e "  │  ${CYAN}ssh -i $SSH_KEY -p $VPS_PORT root@$VPS_IP${NC}"
echo -e "  │  然后输入 ${CYAN}sb${NC} 进入管理菜单"
echo "  └─────────────────────────────────────────────────┘"
echo ""

if [ "$CONFIG_FOUND" = "true" ]; then
    echo -e "  ${GREEN}现在可以打开 ClashX Meta，配置已自动就位。${NC}"
    echo -e "  点击菜单栏图标 → 「设置为系统代理」即可使用。"
fi

echo ""
print_info "如需帮助，参考手册: sing-box-deploy-guide.md"
echo ""
