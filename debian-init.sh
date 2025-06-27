#!/bin/bash

# =========================================================
# 🚀 Linux 全自动初始化脚本 (增强版)
#
# 说明：
# - 自动检测并安装缺失的关键命令。
# - 智能适配 Netplan 和 interfaces 进行静态IP设置。
# - 每个功能模块均包含备用方案和错误检测。
# - 输出仅限关键提示，保证简洁。
# - 兼容 Debian/Ubuntu 常见环境。
# =========================================================

# --- 全局设置 ---
set -e
set -o pipefail

# --- 权限检查 ---
if [[ $EUID -ne 0 ]]; then
   echo "❌ 请使用root权限执行脚本"
   exit 1
fi

export LANG=C.UTF-8

# --- 核心辅助函数：确保命令存在，不存在则尝试安装 ---
ensure_command() {
    local cmd="$1"
    local pkg="$2"
    if ! command -v "$cmd" &>/dev/null; then
        echo "⚠️ 命令 '$cmd' 不存在, 尝试安装软件包 '$pkg'..."
        # 改进点：在安装前确保 apt-get update 成功
        if ! apt-get update -qq; then
            echo "❌ apt-get update 失败，无法安装 '$pkg'。请检查网络或APT源。"
            return 1
        fi
        if ! apt-get install -y -qq "$pkg"; then
            echo "❌ 安装 '$pkg' 失败, 无法执行相关功能。"
            return 1
        fi
        if ! command -v "$cmd" &>/dev/null; then
            echo "❌ 即使安装了 '$pkg'，命令 '$cmd' 仍然不可用，请手动检查。"
            return 1
        fi
        echo "✅ 命令 '$cmd' 安装成功。"
    fi
    return 0
}


# =========================================================
#                   功能模块定义
# =========================================================

# ================== 1. 更换APT源为清华镜像 ===================
auto_set_apt_sources() {
    echo "1/7 更换APT源为清华镜像..."

    if ! ensure_command "lsb_release" "lsb-release"; then
        echo "⚠️ 跳过APT源替换。"
        return
    fi

    local BACKUP="/etc/apt/sources.list.bak_$(date +%Y%m%d%H%M%S)"
    echo "  - 备份当前源到 $BACKUP"
    if [ -f /etc/apt/sources.list ]; then
        cp /etc/apt/sources.list "$BACKUP"
    fi

    local CODENAME
    CODENAME=$(lsb_release -cs 2>/dev/null)
    if [[ -z "$CODENAME" ]]; then
        echo "⚠️ 无法获取系统代号, 跳过APT源替换"
        cp "$BACKUP" /etc/apt/sources.list
        return
    fi

    echo "  - 系统代号: $CODENAME"

    if grep -qi 'ubuntu' /etc/os-release; then
        cat >/etc/apt/sources.list <<EOF
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $CODENAME main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $CODENAME-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $CODENAME-backports main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $CODENAME-security main restricted universe multiverse
EOF
    elif grep -qi 'debian' /etc/os-release; then
        cat >/etc/apt/sources.list <<EOF
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $CODENAME main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $CODENAME-updates main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian-backports/ $CODENAME-backports main contrib non-free
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security/ $CODENAME-security main contrib non-free
EOF
    else
        echo "⚠️ 不支持的系统, 跳过APT源替换"
        [ -f "$BACKUP" ] && cp "$BACKUP" /etc/apt/sources.list
        return
    fi

    echo "  - 正在更新APT缓存..."
    if apt-get update -qq; then
        echo "✅ APT源替换成功"
    else
        echo "⚠️ APT更新失败, 正在恢复源文件..."
        [ -f "$BACKUP" ] && cp "$BACKUP" /etc/apt/sources.list
        echo "  - 已恢复备份源, 请手动检查问题。"
    fi
    echo "-------------------------------------"
}

# ================== 2. 安装依赖工具 ===================
auto_install_dependencies() {
    echo "2/7 安装必要工具..."

    local PKGS="curl wget vim htop net-tools nano ufw unzip bc tar"
    local FAILED_PKGS=()

    if ! command -v apt-get &>/dev/null; then
        echo "⚠️ 未检测到apt-get, 跳过依赖安装"
        return
    fi

    echo "  - 准备安装: $PKGS"
    for pkg in $PKGS; do
        if ! apt-get install -y "$pkg" -qq; then
            echo "⚠️ 软件包 $pkg 安装失败"
            FAILED_PKGS+=("$pkg")
        fi
    done

    if [ ${#FAILED_PKGS[@]} -eq 0 ]; then
        echo "✅ 所有工具安装成功"
    else
        echo "❌ 以下软件包安装失败: ${FAILED_PKGS[*]}"
        echo "   请手动检查网络连接或APT源问题。"
    fi
    echo "-------------------------------------"
}

# ================== 3. 设置时区 ===================
auto_set_timezone() {
    echo "3/7 设置时区为 Asia/Shanghai..."

    if command -v timedatectl &>/dev/null; then
        timedatectl set-timezone Asia/Shanghai
        echo "✅ 时区设置成功 (使用 timedatectl)"
        echo "-------------------------------------"
        return
    fi

    if [ -f /usr/share/zoneinfo/Asia/Shanghai ]; then
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
        echo "✅ 时区设置成功 (使用 /etc/localtime)"
        echo "-------------------------------------"
        return
    fi

    echo "⚠️ 时区设置失败, timedatectl 和 zoneinfo 文件均不可用。"
    echo "-------------------------------------"
}

# ================== 4. 配置SSH允许root密码登录 ===================
auto_config_ssh() {
    echo "4/7 配置SSH允许root密码登录..."
    local SSH_CONF="/etc/ssh/sshd_config"

    if [ ! -f "$SSH_CONF" ]; then
        echo "⚠️ 未找到SSH配置文件, 跳过"
        return
    fi

    cp "$SSH_CONF" "$SSH_CONF.bak_$(date +%Y%m%d%H%M%S)"

    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' "$SSH_CONF"
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$SSH_CONF"

    echo "  - 正在重启SSH服务..."
    if systemctl restart sshd 2>/dev/null; then
        echo "✅ SSH配置生效 (sshd 服务)"
    elif systemctl restart ssh 2>/dev/null; then
        echo "✅ SSH配置生效 (ssh 服务)"
    else
        echo "⚠️ SSH服务重启失败, 请手动执行 'systemctl restart ssh'"
    fi
    echo "-------------------------------------"
}

# ================== 5. 禁用防火墙 ===================
auto_disable_firewall() {
    echo "5/7 禁用系统防火墙..."

    if command -v ufw &>/dev/null; then
        ufw --force disable >/dev/null 2>&1
        echo "✅ UFW已禁用"
    fi

    if systemctl list-unit-files | grep -q firewalld.service; then
        systemctl stop firewalld.service
        systemctl disable firewalld.service
        echo "✅ firewalld已禁用"
    fi

    if command -v iptables &>/dev/null; then
        iptables -F
        iptables -X
        iptables -P INPUT ACCEPT
        iptables -P FORWARD ACCEPT
        iptables -P OUTPUT ACCEPT
        echo "✅ iptables规则已清空"
    fi

    echo "-------------------------------------"
}

# ================== 6. 安装中文字体 ===================
auto_set_fonts() {
    echo "6/7 安装中文字体并配置环境..."

    local FONT_PKGS="fonts-wqy-zenhei fonts-wqy-microhei"
    echo "  - 准备安装字体包: $FONT_PKGS"
    if apt-get install -y $FONT_PKGS -qq; then
        echo "✅ 字体包安装成功"
    else
        echo "⚠️ 字体安装失败, 可能影响中文显示。"
    fi

    if grep -qi 'ubuntu' /etc/os-release; then
        echo "  - 安装中文语言包..."
        apt-get install -y -qq language-pack-zh-hans language-pack-gnome-zh-hans || echo "⚠️ 中文语言包安装失败"
    fi

    if ! grep -q "LANG=zh_CN.UTF-8" /etc/default/locale 2>/dev/null; then
        echo "  - 设置系统默认locale为 zh_CN.UTF-8"
        echo "LANG=zh_CN.UTF-8" > /etc/default/locale
        export LANG=zh_CN.UTF-8
        echo "✅ 中文环境设置成功 (需要重新登录以完全生效)"
    else
        echo "  - 中文环境已是 zh_CN.UTF-8, 无需更改。"
    fi
    echo "-------------------------------------"
}

# ================== 7. 静态IP交互配置 ===================
interactive_set_static_ip() {
    echo "7/7 交互式静态IP设置"
    is_valid_ip() {
        local ip=$1
        [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && return 0
        return 1
    }

    local IFACE
    IFACE=$(ip -o -4 route show to default | awk '{print $5}')
    if [[ -z "$IFACE" ]]; then
        echo "⚠️ 无法自动检测默认网络接口, 跳过静态IP设置。"
        return
    fi
    echo "  - 检测到默认网络接口: $IFACE"

    local IP_CIDR
    IP_CIDR=$(ip -4 addr show "$IFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | head -1)
    if [[ -z "$IP_CIDR" ]]; then
        echo "⚠️ 无法检测到当前IP, 跳过静态IP设置。"
        return
    fi

    local CURRENT_IP=${IP_CIDR%/*}
    local CIDR=${IP_CIDR#*/}
    local GATEWAY=$(ip route | awk '/default/ {print $3}')
    local DNS_SERVERS=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')

    echo ""
    echo "--- 请输入新的网络配置 (直接回车使用括号内的当前值) ---"

    read -p "IP地址 [${CURRENT_IP}]: " NEW_IP
    NEW_IP=${NEW_IP:-$CURRENT_IP}
    if ! is_valid_ip "$NEW_IP"; then echo "❌ IP地址格式错误, 跳过设置。"; return; fi

    read -p "子网掩码 (CIDR格式) [${CIDR}]: " NEW_CIDR
    NEW_CIDR=${NEW_CIDR:-$CIDR}
    [[ "$NEW_CIDR" -ge 1 && "$NEW_CIDR" -le 32 ]] || { echo "❌ CIDR格式错误, 跳过设置。"; return; }

    read -p "网关 [${GATEWAY}]: " NEW_GATEWAY
    NEW_GATEWAY=${NEW_GATEWAY:-$GATEWAY}
    if ! is_valid_ip "$NEW_GATEWAY"; then echo "❌ 网关地址格式错误, 跳过设置。"; return; fi

    read -p "DNS服务器 [${DNS_SERVERS:-223.5.5.5 114.114.114.114}]: " NEW_DNS
    NEW_DNS=${NEW_DNS:-${DNS_SERVERS:-"223.5.5.5 114.114.114.114"}}

    echo "-------------------------------------"
    echo "  - IP:         $NEW_IP/$NEW_CIDR"
    echo "  - Gateway:    $NEW_GATEWAY"
    echo "  - DNS:        $NEW_DNS"
    echo "-------------------------------------"
    read -p "确认以上信息并应用? (y/N): " confirm
    [[ ! "$confirm" =~ ^[yY]([eE][sS])?$ ]] && { echo "  - 操作已取消。"; return; }

    if command -v netplan &>/dev/null; then
        echo "  - 使用 Netplan 配置..."
        # 改进点：更稳妥的 Netplan 文件处理，如果不存在则创建新文件
        local NETPLAN_FILE=$(find /etc/netplan -name "*.yaml" | head -n 1)
        if [[ -z "$NETPLAN_FILE" ]]; then
            NETPLAN_FILE="/etc/netplan/99-static-config.yaml"
            echo "  - 未找到现有 Netplan 配置，将创建新文件: $NETPLAN_FILE"
        else
            echo "  - 找到现有 Netplan 配置: $NETPLAN_FILE"
            cp "$NETPLAN_FILE" "$NETPLAN_FILE.bak_$(date +%Y%m%d%H%M%S)"
        fi

        # 改进点：只有当 NEW_DNS 不为空时才生成 nameservers 配置
        local DNS_CONFIG=""
        if [[ -n "$NEW_DNS" ]]; then
            local DNS_YAML=$(echo "$NEW_DNS" | awk '{ for(i=1;i<=NF;i++) printf "'\''%s'\''%s", $i, (i<NF?", ":"") }')
            DNS_CONFIG="      nameservers:\n        addresses: [$DNS_YAML]"
        fi

        cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: no
      addresses: [$NEW_IP/$NEW_CIDR]
      routes:
        - to: default
          via: $NEW_GATEWAY
$DNS_CONFIG
EOF
        netplan apply && echo "✅ 静态IP配置已应用" || echo "❌ 应用失败，请检查配置"
    elif [ -f /etc/network/interfaces ]; then
        local INTERFACES_FILE="/etc/network/interfaces"
        cp "$INTERFACES_FILE" "$INTERFACES_FILE.bak_$(date +%Y%m%d%H%M%S)"

        ensure_command "bc" "bc" >/dev/null
        local i mask=0
        for ((i=0; i<$NEW_CIDR; i++)); do mask=$(( (mask << 1) | 1 )); done
        mask=$(( mask << (32 - NEW_CIDR) ))
        local NETMASK="$(( (mask >> 24) & 255 )).$(( (mask >> 16) & 255 )).$(( (mask >> 8) & 255 )).$(( mask & 255 ))"

        cat > "$INTERFACES_FILE" <<EOF
source /etc/network/interfaces.d/*
auto lo
iface lo inet loopback

auto $IFACE
iface $IFACE inet static
    address $NEW_IP
    netmask $NETMASK
    gateway $NEW_GATEWAY
    dns-nameservers $NEW_DNS
EOF
        echo "✅ /etc/network/interfaces 文件已更新，请手动 ifdown/ifup 或重启生效"
        # 考虑在此处添加尝试重启网络服务的代码，但请注意可能导致SSH连接中断
        systemctl restart networking || echo "⚠️ 自动重启网络服务失败，请手动重启。"
    else
        echo "❌ 未找到支持的网络配置方式"
    fi
    echo "-------------------------------------"
}

# =========================================================
#                   主执行逻辑
# =========================================================
main() {
    echo "✅ 权限检查通过，开始执行初始化..."
    echo "========================================================="

    auto_set_apt_sources
    auto_install_dependencies
    auto_set_timezone
    auto_config_ssh
    auto_disable_firewall
    auto_set_fonts

    read -p "是否需要进行交互式静态IP设置? (y/N): " setup_ip
    if [[ "$setup_ip" =~ ^[yY]([eE][sS])?$ ]]; then
        interactive_set_static_ip
    else
        echo "  - 已跳过静态IP设置。"
        echo "-------------------------------------"
    fi

    echo "🚀🚀🚀 所有任务执行完毕！🚀🚀🚀"
    echo "建议重启系统以确保所有配置完全生效: reboot"
}

main
