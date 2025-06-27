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
        # 简化输出，将安装过程重定向
        if ! apt-get install -y -qq "$pkg" >/dev/null 2>&1; then
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
        # FIX: Corrected the Debian backports source URL
        cat >/etc/apt/sources.list <<EOF
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $CODENAME main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $CODENAME-updates main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $CODENAME-backports main contrib non-free non-free-firmware
deb https://security.debian.org/debian-security/ $CODENAME-security main contrib non-free non-free-firmware
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

# ================== 2. 安装中文字体 ===================
auto_set_fonts() {
    echo "2/7 安装中文字体并配置环境..."

    local FONT_PKG="fonts-wqy-zenhei"
    # OPTIMIZATION: Check if font package is already installed
    if dpkg -s "$FONT_PKG" &>/dev/null; then
        echo "  - ✅ 字体包 ($FONT_PKG) 已安装。"
    else
        echo "  - 准备安装字体包: $FONT_PKG"
        # Simplify output by redirecting apt's verbose messages
        if apt-get install -y -qq "$FONT_PKG" >/dev/null 2>&1; then
            echo "  - ✅ 字体包安装成功"
        else
            echo "  - ⚠️ 字体安装失败，可能影响中文显示"
        fi
    fi

    local OS=""
    if grep -qi 'ubuntu' /etc/os-release; then OS="ubuntu"; fi
    if grep -qi 'debian' /etc/os-release; then OS="debian"; fi
    
    # OPTIMIZATION: Check if locale is already configured
    if grep -q "LANG=zh_CN.UTF-8" /etc/default/locale 2>/dev/null; then
        echo "  - ✅ 中文环境 (zh_CN.UTF-8) 已配置。"
    else
        echo "  - 正在配置中文环境..."
        if [[ "$OS" == "ubuntu" ]]; then
            apt-get install -y -qq language-pack-zh-hans >/dev/null 2>&1 || echo "⚠️ Ubuntu 中文语言包安装失败"
        elif [[ "$OS" == "debian" ]]; then
            apt-get install -y -qq locales >/dev/null 2>&1 || echo "⚠️ 安装 locales 包失败"
            sed -i '/^# *zh_CN.UTF-8 UTF-8/s/^# *//' /etc/locale.gen
            locale-gen >/dev/null 2>&1 || echo "⚠️ 执行 locale-gen 失败"
        fi
        echo 'LANG=zh_CN.UTF-8' >> /etc/default/locale
        export LANG=zh_CN.UTF-8
        echo "  - ✅ 中文环境设置成功（需重新登录以完全生效）"
    fi

    echo "  - 刷新字体缓存..."
    if fc-cache -fv > /dev/null 2>&1; then
        echo "  - ✅ 字体缓存刷新完成"
    else
        echo "  - ⚠️ 字体缓存刷新失败，请手动执行 fc-cache -fv"
    fi
    echo "-------------------------------------"
}

# ================== 3. 安装依赖工具 ==================
auto_install_dependencies() {
    echo "3/7 安装必要工具..."

    local PKGS="curl wget vim htop net-tools nano ufw unzip bc tar"
    local FAILED_PKGS=()
    local PKGS_TO_INSTALL=()

    # OPTIMIZATION: Check which packages are missing first
    for pkg in $PKGS; do
        if ! dpkg -s "$pkg" &>/dev/null; then
            PKGS_TO_INSTALL+=("$pkg")
        fi
    done

    if [ ${#PKGS_TO_INSTALL[@]} -eq 0 ]; then
        echo "✅ 所有必要工具均已安装。"
        echo "-------------------------------------"
        return
    fi
    
    echo "  - 正在更新APT缓存..."
    apt-get update -qq

    echo "  - 准备安装: ${PKGS_TO_INSTALL[*]}"
    # OPTIMIZATION: Install all missing packages at once
    if apt-get install -y -qq "${PKGS_TO_INSTALL[@]}" >/dev/null 2>&1; then
        echo "✅ 成功安装 ${#PKGS_TO_INSTALL[@]} 个新工具。"
    else
        # Check again to see which ones failed
        for pkg in "${PKGS_TO_INSTALL[@]}"; do
            if ! dpkg -s "$pkg" &>/dev/null; then
                FAILED_PKGS+=("$pkg")
            fi
        done
        echo "❌ 以下软件包安装失败: ${FAILED_PKGS[*]}"
        echo "   请手动检查网络连接或APT源问题。"
    fi
    echo "-------------------------------------"
}


# ================== 4. 设置时区 ===================
auto_set_timezone() {
    echo "4/7 设置时区为 Asia/Shanghai..."

    # FIX: Restore compatibility logic
    if command -v timedatectl &>/dev/null; then
        timedatectl set-timezone Asia/Shanghai
        echo "✅ 时区设置成功 (使用 timedatectl)"
    elif [ -f /usr/share/zoneinfo/Asia/Shanghai ]; then
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
        echo "✅ 时区设置成功 (使用 /etc/localtime)"
    else
        echo "⚠️ 时区设置失败, timedatectl 和 zoneinfo 文件均不可用。"
    fi
    echo "-------------------------------------"
}

# ================== 5. 配置SSH允许root密码登录 ===================
auto_config_ssh() {
    echo "5/7 配置SSH允许root密码登录..."
    local SSH_CONF="/etc/ssh/sshd_config"

    if [ ! -f "$SSH_CONF" ]; then
        echo "⚠️ 未找到SSH配置文件, 跳过"
        return
    fi

    # OPTIMIZATION: Check if already configured
    if grep -q "^\s*PermitRootLogin\s*yes" "$SSH_CONF" && grep -q "^\s*PasswordAuthentication\s*yes" "$SSH_CONF"; then
        echo "✅ SSH已配置为允许root密码登录。"
        echo "-------------------------------------"
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
        echo "⚠️ SSH服务重启失败, 请手动执行 'systemctl restart ssh' 或 'systemctl restart sshd'"
    fi
    echo "-------------------------------------"
}

# ================== 6. 配置防火墙 (开放内网及常用端口) ===================
auto_configure_firewall() {
    # FIX: Corrected the step number
    echo "6/7 配置防火墙 (开放内网及常用端口)..."
    local COMMON_PORTS="22 80 88 443 5244 5678 9000"
    local PRIVATE_NETWORKS="10.0.0.0/8 172.16.0.0/12 192.168.0.0/16"

    if command -v ufw &>/dev/null; then
        echo "  - 检测到 UFW, 开始进行配置..."
        # FIX: Use non-interactive reset to prevent script from stopping
        ufw --force reset >/dev/null 2>&1
        ufw default allow outgoing
        ufw default deny incoming
        echo "    - 正在开放内网访问..."
        for net in $PRIVATE_NETWORKS; do
            ufw allow from "$net" to any comment 'Allow-Internal-LAN'
        done
        echo "    - 正在开放外网常用端口: $COMMON_PORTS"
        for port in $COMMON_PORTS; do
            ufw allow "$port/tcp" comment 'Allow-Common-Services'
        done
        ufw --force enable
        echo "✅ UFW 配置完成并已启用。"
        echo "-------------------------------------"
        return
    fi
    
    # The rest of the firewall logic (firewalld, iptables) is kept as is from your original script
    if systemctl is-active --quiet firewalld; then
        echo "  - 检测到 firewalld, 开始进行配置..."
        echo "    - 正在开放内网访问..."
        for net in $PRIVATE_NETWORKS; do firewall-cmd --permanent --zone=trusted --add-source="$net" >/dev/null; done
        echo "    - 正在开放外网常用端口: $COMMON_PORTS"
        for port in $COMMON_PORTS; do firewall-cmd --permanent --zone=public --add-port="$port/tcp" >/dev/null; done
        firewall-cmd --reload
        echo "✅ firewalld 配置完成。"
        echo "-------------------------------------"
        return
    fi
    if command -v iptables &>/dev/null; then
        echo "  - 未检测到 UFW/firewalld, 使用 iptables 作为备用方案..."
        ensure_command "netfilter-persistent" "iptables-persistent" >/dev/null
        iptables -F; iptables -X; iptables -Z
        iptables -P INPUT DROP; iptables -P FORWARD DROP; iptables -P OUTPUT ACCEPT
        iptables -A INPUT -i lo -j ACCEPT
        iptables -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
        echo "    - 正在开放内网访问..."
        for net in $PRIVATE_NETWORKS; do iptables -A INPUT -s "$net" -j ACCEPT; done
        echo "    - 正在开放外网常用端口: $COMMON_PORTS"
        for port in $COMMON_PORTS; do iptables -A INPUT -p tcp --dport "$port" -j ACCEPT; done
        echo "  - 正在持久化 iptables 规则..."
        netfilter-persistent save
        echo "✅ iptables 规则已配置并持久化。"
        echo "-------------------------------------"
        return
    fi

    echo "⚠️ 未找到可用的防火墙管理工具 (UFW, firewalld, iptables), 跳过防火墙配置。"
    echo "-------------------------------------"
}

# ================== 7. 静态IP交互配置 ===================

# 检查命令是否存在并提供安装提示 (如果需要的话)
ensure_command() {
    local cmd=$1
    local install_pkg=${2:-$cmd}
    if ! command -v "$cmd" &>/dev/null; then
        echo "错误: 命令 '$cmd' 未找到。请尝试安装 '$install_pkg'。" >&2
        return 1
    fi
    return 0
}

# 简单合法性校验（仅最后一段，0-255）
is_valid_octet() {
    local num=$1
    [[ "$num" =~ ^[0-9]{1,3}$ && "$num" -ge 0 && "$num" -le 255 ]]
}

# 检查是否为有效的完整IP地址
is_valid_ip() {
    local ip=$1
    local stat=1
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
        [ "$i1" -le 255 -a "$i2" -le 255 -a "$i3" -le 255 -a "$i4" -le 255 ]
        stat=$?
    fi
    return $stat
}

# 检查IP地址是否被占用 (通过ping检测)
is_ip_available() {
    local ip=$1
    echo -n "  - 正在检测 IP 地址 $ip 是否可用..."
    # ping -c 1 -W 1 尝试ping一次，等待1秒
    if ping -c 1 -W 1 "$ip" &>/dev/null; then
        echo "❌ 已被占用或存在设备。"
        return 1
    else
        echo "✅ 可用。"
        return 0
    fi
}

interactive_set_static_ip() {
    echo "--- 7/7 交互式静态IP设置 ---"

    local IFACE
    IFACE=$(ip -o -4 route show to default | awk '{print $5}')
    if [[ -z "$IFACE" ]]; then
        echo "⚠️ 无法自动检测默认网络接口。请确保网络连接正常。"
        return
    fi
    echo "  - 检测到默认网络接口: $IFACE"

    local IP_CIDR
    IP_CIDR=$(ip -4 addr show "$IFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}/\d+' | head -1)
    if [[ -z "$IP_CIDR" ]]; then
        echo "⚠️ 无法检测到当前IP地址。请检查网络接口 '$IFACE' 的配置。"
        return
    fi

    local CURRENT_IP=${IP_CIDR%/*}
    local CIDR=${IP_CIDR#*/}
    local GATEWAY=$(ip route | awk '/default/ {print $3}' | head -1) # 确保只取一个
    local DNS_SERVERS=$(grep "nameserver" /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
    local BASE_IP=$(echo "$CURRENT_IP" | cut -d'.' -f1-3) # 获取当前IP的前三段

    echo ""
    echo "--- 当前网络信息 ---"
    echo "  - 接口:      $IFACE"
    echo "  - IP/CIDR:   $CURRENT_IP/$CIDR"
    echo "  - 网关:      ${GATEWAY:-未检测到}"
    echo "  - DNS:       ${DNS_SERVERS:-未检测到}"
    echo "-------------------"

    echo ""
    read -p "是否需要修改IP地址？(Y/n): " MODIFY_IP_CONFIRM
    MODIFY_IP_CONFIRM=${MODIFY_IP_CONFIRM:-y}

    local NEW_IP="$CURRENT_IP" # 默认新IP为当前IP

    if [[ "$MODIFY_IP_CONFIRM" =~ ^[yY]$ ]]; then
        local DEFAULT_LAST_OCTET="254"
        local DEFAULT_PROPOSED_IP="${BASE_IP}.${DEFAULT_LAST_OCTET}" # 使用实际的BASE_IP

        echo ""
        echo "--- 设定静态IP地址 ---"
        if is_ip_available "$DEFAULT_PROPOSED_IP"; then
            read -p "预设IP地址 ${DEFAULT_PROPOSED_IP} 可用。是否使用此IP？(Y/n): " USE_DEFAULT_IP_CONFIRM
            USE_DEFAULT_IP_CONFIRM=${USE_DEFAULT_IP_CONFIRM:-y}
            if [[ "$USE_DEFAULT_IP_CONFIRM" =~ ^[yY]$ ]]; then
                NEW_IP="$DEFAULT_PROPOSED_IP"
            else
                echo "  - 请输入您希望设置的新IP地址的最后一段 (例如: 100)，"
                echo "    或输入完整的IP地址 (例如: ${BASE_IP}.100)。" # 使用实际的BASE_IP作为示例
                read -p "新IP地址 [${BASE_IP}.x]: " USER_INPUT_IP # 提示也使用实际的BASE_IP
                if is_valid_ip "$USER_INPUT_IP"; then
                    NEW_IP="$USER_INPUT_IP"
                elif is_valid_octet "$USER_INPUT_IP"; then
                    NEW_IP="${BASE_IP}.${USER_INPUT_IP}"
                else
                    echo "❌ 输入的IP地址格式无效，请检查。"
                    return
                fi
                if ! is_ip_available "$NEW_IP"; then
                    echo "❌ 您输入的IP地址 $NEW_IP 可能已被占用或无效，请重新尝试。"
                    return
                fi
            fi
        else
            echo "预设IP地址 ${DEFAULT_PROPOSED_IP} 无法使用。" # 使用实际的BASE_IP
            echo "  - 请输入您希望设置的新IP地址的最后一段 (例如: 100)，"
            echo "    或输入完整的IP地址 (例如: ${BASE_IP}.100)。" # 使用实际的BASE_IP作为示例
            read -p "新IP地址 [${BASE_IP}.x]: " USER_INPUT_IP # 提示也使用实际的BASE_IP
            if is_valid_ip "$USER_INPUT_IP"; then
                NEW_IP="$USER_INPUT_IP"
            elif is_valid_octet "$USER_INPUT_IP"; then
                NEW_IP="${BASE_IP}.${USER_INPUT_IP}"
            else
                echo "❌ 输入的IP地址格式无效，请检查。"
                return
            fi
            if ! is_ip_available "$NEW_IP"; then
                echo "❌ 您输入的IP地址 $NEW_IP 可能已被占用或无效，请重新尝试。"
                return
            fi
        fi
    else
        echo "  - 保持当前IP地址不变: $NEW_IP"
    fi

    # 网关设置 (默认不修改)
    local NEW_GATEWAY="$GATEWAY"
    echo ""
    echo "--- 网关设置 ---"
    echo "当前网关: ${GATEWAY:-未检测到}"
    read -p "是否需要修改网关？(y/N): " MODIFY_GATEWAY_CONFIRM
    if [[ "$MODIFY_GATEWAY_CONFIRM" =~ ^[yY]$ ]]; then
        read -p "请输入新的完整网关地址 (例如: ${BASE_IP}.1): " USER_INPUT_GATEWAY # 示例使用实际BASE_IP
        if is_valid_ip "$USER_INPUT_GATEWAY"; then
            NEW_GATEWAY="$USER_INPUT_GATEWAY"
        else
            echo "❌ 输入的网关地址格式无效，将保持原有网关不变。"
        fi
    fi

    # DNS服务器设置
    local NEW_DNS_SERVERS="$DNS_SERVERS"
    echo ""
    echo "--- DNS 服务器设置 ---"
    echo "当前DNS服务器: ${DNS_SERVERS:-未检测到}"
    read -p "是否需要修改DNS服务器？(Y/n): " MODIFY_DNS_CONFIRM
    MODIFY_DNS_CONFIRM=${MODIFY_DNS_CONFIRM:-y}

    if [[ "$MODIFY_DNS_CONFIRM" =~ ^[yY]$ ]]; then
        echo "您可以选择预设的DNS，或者输入自定义的DNS服务器。"
        echo "  1. 使用网关作为DNS服务器 ($NEW_GATEWAY)"
        echo "  2. 使用阿里公共DNS (223.5.5.5, 223.6.6.6)"
        echo "  3. 使用114公共DNS (114.114.114.114, 114.115.115.115)"
        echo "  4. 自定义DNS服务器"
        read -p "请选择 (1/2/3/4) [1]: " DNS_CHOICE
        DNS_CHOICE=${DNS_CHOICE:-1}

        case "$DNS_CHOICE" in
            1)
                if [[ -n "$NEW_GATEWAY" ]]; then
                    NEW_DNS_SERVERS="$NEW_GATEWAY"
                    echo "  - 已设置为使用网关 ($NEW_GATEWAY) 作为DNS服务器。"
                else
                    echo "⚠️ 无法获取到有效网关，将尝试使用当前检测到的DNS。"
                fi
                ;;
            2)
                NEW_DNS_SERVERS="223.5.5.5 223.6.6.6"
                echo "  - 已设置为使用阿里公共DNS。"
                ;;
            3)
                NEW_DNS_SERVERS="114.114.114.114 114.115.115.115"
                echo "  - 已设置为使用114公共DNS。"
                ;;
            4)
                read -p "请输入自定义DNS服务器 (多个请用空格分隔，例如: 8.8.8.8 1.1.1.1) [$DNS_SERVERS]: " CUSTOM_DNS
                NEW_DNS_SERVERS=${CUSTOM_DNS:-$DNS_SERVERS}
                if [[ -z "$NEW_DNS_SERVERS" ]]; then
                    echo "⚠️ 未输入任何DNS服务器，系统可能无法解析域名。"
                else
                    echo "  - 已设置为自定义DNS服务器: $NEW_DNS_SERVERS"
                fi
                ;;
            *)
                echo "无效的选择，将尝试使用当前检测到的DNS。"
                ;;
        esac
    else
        echo "  - 保持当前DNS服务器不变: $NEW_DNS_SERVERS"
    fi

    echo ""
    echo "-------------------------------------"
    echo "  --- 即将应用的静态IP配置 ---"
    echo "  - 接口:         $IFACE"
    echo "  - IP:           $NEW_IP/$CIDR"
    echo "  - 网关:         ${NEW_GATEWAY:-未设置}"
    echo "  - DNS:          ${NEW_DNS_SERVERS:-未设置}"
    echo "  - IPv6:         使用DHCP获取 (保持不变)"
    echo "-------------------------------------"
    read -p "确认以上信息并应用? (y/N): " confirm
    [[ ! "$confirm" =~ ^[yY]([eE][sS])?$ ]] && { echo "  - 操作已取消。"; return; }

    # Netplan 配置
    if command -v netplan &>/dev/null; then
        echo "  - 正在使用 Netplan 配置..."
        local NETPLAN_DIR="/etc/netplan"
        local NETPLAN_FILE=$(find "$NETPLAN_DIR" -name "*.yaml" -print -quit)
        if [[ -z "$NETPLAN_FILE" ]]; then
            NETPLAN_FILE="$NETPLAN_DIR/01-netcfg.yaml"
            echo "  - 未找到现有 Netplan 配置，将创建新文件: $NETPLAN_FILE"
        else
            echo "  - 找到现有 Netplan 配置: $NETPLAN_FILE"
            cp "$NETPLAN_FILE" "$NETPLAN_FILE.bak_$(date +%Y%m%d%H%M%S)"
        fi

        # 组装 DNS YAML 字符串，确保每个IP都被单引号包围
        local DNS_YAML_ENTRIES=()
        if [[ -n "$NEW_DNS_SERVERS" ]]; then
            for dns_ip in $NEW_DNS_SERVERS; do
                DNS_YAML_ENTRIES+=("'$dns_ip'")
            done
        fi
        local DNS_YAML=$(IFS=,; echo "${DNS_YAML_ENTRIES[*]}")


        cat > "$NETPLAN_FILE" <<EOF
# 由脚本自动生成，用于配置静态IP
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: no
      dhcp6: true # 保持IPv6通过DHCP获取
      addresses: [$NEW_IP/$CIDR]
$(if [[ -n "$NEW_GATEWAY" ]]; then echo "      routes:"; echo "        - to: default"; echo "          via: $NEW_GATEWAY"; fi)
$(if [[ -n "$DNS_YAML" ]]; then echo "      nameservers:"; echo "        addresses: [$DNS_YAML]"; fi)
EOF
        netplan generate && netplan apply
        if [[ $? -eq 0 ]]; then
            echo "✅ 静态IP配置已通过 Netplan 应用成功！"
            echo "  - 您可能需要重启设备或网络服务以确保完全生效。"
        else
            echo "❌ Netplan 应用失败，请检查配置文件 ($NETPLAN_FILE) 或日志。"
        fi

    # /etc/network/interfaces 配置
    elif [ -f /etc/network/interfaces ]; then
        echo "  - 正在使用 /etc/network/interfaces 配置..."
        local INTERFACES_FILE="/etc/network/interfaces"
        cp "$INTERFACES_FILE" "$INTERFACES_FILE.bak_$(date +%Y%m%d%H%M%S)"

        # 计算子网掩码 (Bash 内部位运算实现，无需bc)
        local i mask=0
        for ((i=0; i<$CIDR; i++)); do mask=$(( (mask << 1) | 1 )); done
        mask=$(( mask << (32 - CIDR) ))
        local NETMASK="$(( (mask >> 24) & 255 )).$(( (mask >> 16) & 255 )).$(( (mask >> 8) & 255 )).$(( mask & 255 ))"

        cat > "$INTERFACES_FILE" <<EOF
# 由脚本自动生成，用于配置静态IP
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

auto $IFACE
iface $IFACE inet static
    address $NEW_IP
    netmask $NETMASK
    gateway $NEW_GATEWAY
$(if [[ -n "$NEW_DNS_SERVERS" ]]; then echo "    dns-nameservers $NEW_DNS_SERVERS"; fi)

# 保持 IPv6 通过 DHCP 获取
iface $IFACE inet6 dhcp
EOF
        echo "✅ /etc/network/interfaces 文件已更新。"
        echo "  - 请注意: 对于此配置方式，您通常需要手动重启网络服务或设备才能使更改生效。"
        echo "  - 尝试重启网络服务 (可能需要root权限):"
        echo "    sudo systemctl restart networking"
        echo "    或者执行: sudo ifdown $IFACE && sudo ifup $IFACE"
        systemctl restart networking &>/dev/null && echo "  - 尝试自动重启网络服务成功。" || echo "  - 自动重启网络服务失败，请手动重启。"
    else
        echo "❌ 未找到支持的网络配置方式 (Netplan 或 /etc/network/interfaces)。"
        echo "  - 您的系统可能使用了其他网络管理工具，请手动配置。"
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
    auto_set_fonts
    auto_install_dependencies
    auto_set_timezone
    auto_config_ssh
    auto_configure_firewall

    read -p "是否需要进行交互式静态IP设置? (y/N): " setup_ip
    if [[ "$setup_ip" =~ ^[yY]([eE][sS])?$ ]]; then
        # This will call the function you paste in the section above
        interactive_set_static_ip
    else
        echo "  - 已跳过静态IP设置。"
        echo "-------------------------------------"
    fi

    echo "🚀🚀🚀 所有任务执行完毕！🚀🚀🚀"
    echo "建议重启系统以确保所有配置完全生效: reboot"
}

main
