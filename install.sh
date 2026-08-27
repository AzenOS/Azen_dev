#!/bin/bash
# ================================================================
#  Azen Laptop Resource Management (ALRM) - 一键安装脚本
#  适配 AzenOS/Azen_dev 仓库结构
#  优先从 Release 下载 AzenPKG，失败则回退到直接下载单个文件
# ================================================================

set -e

# ---------- 颜色输出 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ---------- 检查权限 ----------
if [[ $EUID -ne 0 ]]; then
    print_error "此脚本需要 root 权限运行"
    echo "请使用: sudo ./install.sh"
    exit 1
fi

# ---------- 获取当前用户 ----------
REAL_USER=${SUDO_USER:-$(whoami)}
REAL_HOME=$(eval echo ~$REAL_USER)
print_info "当前用户: $REAL_USER"

# ---------- 1. 安装依赖 ----------
print_info "正在安装依赖包..."
apt update
apt install -y python3-pydbus python3-gi gir1.2-glib-2.0 acpid wget unzip

# ---------- 2. 创建工作目录 ----------
WORK_DIR="/tmp/azen_install"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# ---------- 3. 下载 AzenPKG ----------
print_info "尝试从 GitHub Release 下载 AzenPKG_ver.2.zip ..."
RELEASE_URL="https://github.com/AzenOS/Azen_dev/releases/download/adjust_files/AzenPKG_ver.2.zip"
if wget -q --show-progress "$RELEASE_URL" -O AzenPKG.zip; then
    print_success "AzenPKG.zip 下载成功"
    print_info "正在解压..."
    unzip -q -o AzenPKG.zip -d extracted
    SOURCE_DIR="$WORK_DIR/extracted"
else
    print_warning "从 Release 下载失败，回退到从仓库主页下载单个文件..."
    SOURCE_DIR="$WORK_DIR/single_files"
    mkdir -p "$SOURCE_DIR"
    BASE_URL="https://raw.githubusercontent.com/AzenOS/Azen_dev/main"
    
    # 下载文件列表（根据你的仓库实际文件调整）
    wget -q -O "$SOURCE_DIR/system-mode.conf" "$BASE_URL/system-mode.conf"
    wget -q -O "$SOURCE_DIR/azen-alrm.py" "$BASE_URL/azen-alrm.py"
    wget -q -O "$SOURCE_DIR/azen-sleep-config.sh" "$BASE_URL/azen-sleep-config.sh"
    wget -q -O "$SOURCE_DIR/azen-alrm.service" "$BASE_URL/azen-alrm.service"
    wget -q -O "$SOURCE_DIR/azen-sleep.service" "$BASE_URL/azen-sleep.service"
    wget -q -O "$SOURCE_DIR/azen-lid-handler.service" "$BASE_URL/azen-lid-handler.service"
    
    print_success "所有文件下载完成"
fi

# ---------- 4. 安装文件 ----------
print_info "开始安装 Azen 组件..."

# 创建目录
mkdir -p /etc/azen /var/log/azen /usr/local/bin

# 复制配置文件
cp "$SOURCE_DIR/system-mode.conf" /etc/azen/system-mode.conf

# 复制并设置可执行脚本
cp "$SOURCE_DIR/azen-alrm.py" /usr/local/bin/
cp "$SOURCE_DIR/azen-sleep-config.sh" /usr/local/bin/
chmod +x /usr/local/bin/azen-alrm.py
chmod +x /usr/local/bin/azen-sleep-config.sh

# 复制服务文件
cp "$SOURCE_DIR"/*.service /etc/systemd/system/

# 替换服务文件中的用户名
sed -i "s/你的用户名/$REAL_USER/g" /etc/systemd/system/azen-alrm.service

print_success "文件安装完成"

# ---------- 5. 配置 ACPI ----------
if [ -d "/etc/acpi/events" ]; then
    print_info "配置 ACPI 事件监听..."
    cat > /etc/acpi/events/azen-lid << 'EOF'
event=button/lid.*
action=/usr/bin/systemctl start azen-lid-handler.service
EOF
    systemctl restart acpid
fi

# ---------- 6. 启用并启动服务 ----------
print_info "启用 Systemd 服务..."
systemctl daemon-reload
systemctl enable azen-sleep.service
systemctl enable azen-lid-handler.service
systemctl enable azen-alrm.service

print_info "启动服务..."
systemctl start azen-sleep.service
systemctl start azen-alrm.service

# ---------- 7. 清理 ----------
cd /
rm -rf "$WORK_DIR"

# ---------- 8. 状态检查 ----------
sleep 2
echo ""
echo "================================================================"
if systemctl is-active --quiet azen-alrm.service; then
    print_success " 🎉 Azen 系统安装成功并运行正常！"
else
    print_warning " ⚠️  安装完成，但服务未正常运行，请检查日志。"
fi
echo "================================================================"
echo ""
echo "  📁 配置文件: /etc/azen/system-mode.conf"
echo "  📋 查看日志: sudo journalctl -u azen-alrm.service -f"
echo "  🔄 切换模式: 修改配置文件后执行 sudo systemctl restart azen-alrm.service"
echo ""
