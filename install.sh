#!/bin/bash
# ================================================================
#  Azen Laptop Resource Management (ALRM) - 一键安装脚本
#  用于在老笔记本上快速部署所有组件
# ================================================================

set -e  # 遇到错误立即退出

# ---------- 颜色输出 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ---------- 检查权限 ----------
if [[ $EUID -ne 0 ]]; then
    print_error "此脚本需要 root 权限运行"
    echo "请使用: sudo ./install.sh"
    exit 1
fi

# ---------- 获取当前用户名 ----------
REAL_USER=${SUDO_USER:-$(whoami)}
REAL_HOME=$(eval echo ~$REAL_USER)

print_info "当前用户: $REAL_USER"
print_info "用户目录: $REAL_HOME"

# ---------- 1. 安装依赖 ----------
print_info "正在安装依赖包..."
apt update
apt install -y python3-pydbus python3-gi gir1.2-glib-2.0 acpid

# ---------- 2. 创建目录结构 ----------
print_info "创建目录结构..."
mkdir -p /etc/azen
mkdir -p /var/log/azen
mkdir -p /usr/local/bin

# ---------- 3. 从 GitHub 下载文件 ----------
print_info "从 GitHub 下载组件..."

# 替换为你的 GitHub 仓库地址
GITHUB_REPO="https://raw.githubusercontent.com/你的用户名/你的仓库名/main"

# 下载配置文件
wget -q -O /etc/azen/system-mode.conf "$GITHUB_REPO/system-mode.conf"
print_success "配置文件下载完成"

# 下载 Python 守护进程
wget -q -O /usr/local/bin/azen-alrm.py "$GITHUB_REPO/azen-alrm.py"
chmod +x /usr/local/bin/azen-alrm.py
print_success "Python 守护进程下载完成"

# 下载 Shell 配置脚本
wget -q -O /usr/local/bin/azen-sleep-config.sh "$GITHUB_REPO/azen-sleep-config.sh"
chmod +x /usr/local/bin/azen-sleep-config.sh
print_success "Shell 配置脚本下载完成"

# ---------- 4. 更新配置文件中的用户名 ----------
print_info "更新配置文件中的用户名..."
sed -i "s/你的用户名/$REAL_USER/g" /etc/systemd/system/azen-alrm.service 2>/dev/null || true

# ---------- 5. 下载 Systemd 服务文件 ----------
print_info "安装 Systemd 服务..."

# ALRM 守护进程服务
wget -q -O /etc/systemd/system/azen-alrm.service "$GITHUB_REPO/azen-alrm.service"
# 替换用户名
sed -i "s/你的用户名/$REAL_USER/g" /etc/systemd/system/azen-alrm.service

# 睡眠配置服务
wget -q -O /etc/systemd/system/azen-sleep.service "$GITHUB_REPO/azen-sleep.service"

# 合盖事件处理服务
wget -q -O /etc/systemd/system/azen-lid-handler.service "$GITHUB_REPO/azen-lid-handler.service"

print_success "Systemd 服务安装完成"

# ---------- 6. 重载并启用服务 ----------
print_info "重载 Systemd..."
systemctl daemon-reload

print_info "启用服务..."
systemctl enable azen-sleep.service
systemctl enable azen-lid-handler.service
systemctl enable azen-alrm.service

print_info "启动服务..."
systemctl start azen-sleep.service
systemctl start azen-alrm.service

# ---------- 7. 配置 ACPI（如果存在） ----------
if [ -d "/etc/acpi/events" ]; then
    print_info "配置 ACPI 事件监听..."
    
    cat > /etc/acpi/events/azen-lid << 'EOF'
event=button/lid.*
action=/usr/bin/systemctl start azen-lid-handler.service
EOF
    
    # 重启 ACPI 服务
    systemctl restart acpid
    print_success "ACPI 配置完成"
fi

# ---------- 8. 验证安装 ----------
print_info "验证安装状态..."

sleep 2  # 等待服务启动

if systemctl is-active --quiet azen-alrm.service; then
    print_success "✅ ALRM 守护进程运行正常"
else
    print_warning "⚠️  ALRM 守护进程未运行，检查日志: journalctl -u azen-alrm.service"
fi

if systemctl is-active --quiet azen-sleep.service; then
    print_success "✅ 睡眠配置服务运行正常"
else
    print_warning "⚠️  睡眠配置服务未运行"
fi

# ---------- 9. 显示状态 ----------
echo ""
echo "================================================================"
print_success " 🎉 Azen 系统安装完成！"
echo "================================================================"
echo ""
echo "当前状态："
echo "  - ALRM 守护进程: $(systemctl is-active azen-alrm.service)"
echo "  - 睡眠配置服务: $(systemctl is-active azen-sleep.service)"
echo ""
echo "常用命令："
echo "  查看状态: sudo systemctl status azen-alrm.service"
echo "  查看日志: sudo journalctl -u azen-alrm.service -f"
echo "  切换模式: sudo nano /etc/azen/system-mode.conf && sudo systemctl restart azen-alrm.service"
echo "  测试合盖: sudo systemctl start azen-lid-handler.service"
echo ""
echo "配置文件位置："
echo "  /etc/azen/system-mode.conf"
echo ""
echo "日志位置："
echo "  /var/log/azen/azen-sleep.log"
echo ""
echo "================================================================"
