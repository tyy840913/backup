#!/bin/bash

# ==============================================================================
# 系统初始化脚本 (Debian/Ubuntu)
#
# 功能：
# 1. 设置系统 APT 镜像源 (清华大学/阿里云备用)
# 2. 设置系统时区为东八区 (Asia/Shanghai)
# 3. 修改 SSH 配置，允许 root 密码登录并确保普通用户密码登录
# 4. 设置系统字体为文泉驿正黑
# 5. 配置 UFW 防火墙，开放常用端口及内网访问 (支持 IPv4/IPv6)
#
# 特性：
# - 自动检测并安装所需依赖
# - 所有设置项先检查后设置，避免重复操作
# - 日志输出区分信息、警告和错误
# - 移除所有文件备份操作
# - 增加关键操作前的确认提示
# - 添加配置验证步骤
# ==============================================================================

# ==============================================================================
# --- 通用函数模块 ---
# ==============================================================================
# 定义颜色
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 记录信息
log_info() {
    echo -e "${GREEN}[INFO] $1${NC}"
}

# 记录警告
log_warn() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

# 记录错误并退出
log_error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# 确认操作
confirm_action() {
    local prompt="$1 (y/n) "
    local default=${2:-"n"} # 默认为否
    
    while true; do
        read -p "$prompt" -r
        case $REPLY in
            [Yy]*) return 0 ;;
            [Nn]*) return 1 ;;
            "") 
                if [[ "$default" == "y" ]]; then return 0
                else return 1
                fi ;;
            *) echo "请输入 y 或 n" ;;
        esac
    done
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本必须以 root 用户运行。"
    fi
}

# 安装软件包
install_package() {
    local pkg_name=$1
    if ! dpkg -s "$pkg_name" &> /dev/null; then
        log_info "正在安装 ${pkg_name}..."
        if ! apt update -y > /dev/null; then
            log_error "更新APT缓存失败，请检查网络连接或APT源。"
        fi
        
        if ! apt install -y "$pkg_name"; then
            log_error "安装 ${pkg_name} 失败。尝试手动运行 'apt update && apt install -y ${pkg_name}'"
        else
            log_info "${pkg_name} 安装成功。"
        fi
    else
        log_info "${pkg_name} 已安装。"
    fi
}

# 获取系统发行版名称（例如：jammy, bookworm）
get_os_release() {
    lsb_release -cs
}

# 判断系统类型 (debian/ubuntu)
get_system_type() {
    if grep -q "Ubuntu" /etc/issue || grep -q "Ubuntu" /etc/lsb-release; then
        echo "ubuntu"
    else
        echo "debian"
    fi
}

# ==============================================================================
# --- 功能模块 1: APT 镜像源设置 ---
# ==============================================================================
# APT 镜像源配置内容
get_tsinghua_debian_sources_content() {
    local release=$1
    cat <<EOF
# 默认注释了源码镜像以提高 apt update 速度，如有需要可自行取消注释
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ ${release} main contrib non-free
# deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ ${release} main contrib non-free

deb https://mirrors.tuna.tsinghua.edu.cn/debian/ ${release}-updates main contrib non-free
# deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ ${release}-updates main contrib non-free

deb https://mirrors.tuna.tsinghua.edu.cn/debian/ ${release}-backports main contrib non-free
# deb-src https://mirrors.tuna.tsinghua.edu.cn/debian/ ${release}-backports main contrib non-free

deb https://mirrors.tuna.tsinghua.edu.cn/debian-security ${release}/updates main contrib non-free
# deb-src https://mirrors.tuna.tsinghua.edu.cn/debian-security ${release}/updates main contrib non-free
EOF
}

get_tsinghua_ubuntu_sources_content() {
    local release=$1
    cat <<EOF
# 默认注释了源码镜像以提高 apt update 速度，如有需要可自行取消注释
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${release} main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${release} main restricted universe multiverse

deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${release}-updates main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${release}-updates main restricted universe multiverse

deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${release}-backports main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${release}-backports main restricted universe multiverse

deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${release}-security main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ ${release}-security main restricted universe multiverse
EOF
}

get_aliyun_debian_sources_content() {
    local release=$1
    cat <<EOF
# 默认注释了源码镜像以提高 apt update 速度，如有需要可自行取消注释
deb https://mirrors.aliyun.com/debian/ ${release} main contrib non-free
# deb-src https://mirrors.aliyun.com/debian/ ${release} main contrib non-free

deb https://mirrors.aliyun.com/debian/ ${release}-updates main contrib non-free
# deb-src https://mirrors.aliyun.com/debian/ ${release}-updates main contrib non-free

deb https://mirrors.aliyun.com/debian/ ${release}-backports main contrib non-free
# deb-src https://mirrors.aliyun.com/debian/ ${release}-backports main contrib non-free

deb https://mirrors.aliyun.com/debian-security ${release}/updates main contrib non-free
# deb-src https://mirrors.aliyun.com/debian-security ${release}/updates main contrib non-free
EOF
}

get_aliyun_ubuntu_sources_content() {
    local release=$1
    cat <<EOF
# 默认注释了源码镜像以提高 apt update 速度，如有需要可自行取消注释
deb https://mirrors.aliyun.com/ubuntu/ ${release} main restricted universe multiverse
# deb-src https://mirrors.aliyun.com/ubuntu/ ${release} main restricted universe multiverse

deb https://mirrors.aliyun.com/ubuntu/ ${release}-updates main restricted universe multiverse
# deb-src https://mirrors.aliyun.com/ubuntu/ ${release}-updates main restricted universe multiverse

deb https://mirrors.aliyun.com/ubuntu/ ${release}-backports main restricted universe multiverse
# deb-src https://mirrors.aliyun.com/ubuntu/ ${release}-backports main restricted universe multiverse

deb https://mirrors.aliyun.com/ubuntu/ ${release}-security main restricted universe multiverse
# deb-src https://mirrors.aliyun.com/ubuntu/ ${release}-security main restricted universe multiverse
EOF
}

# 设置APT镜像源为清华园 (支持备用源)
set_apt_source() {
    log_info "正在设置APT镜像源。"

    local release=$(get_os_release)
    local sources_list="/etc/apt/sources.list"
    local system_type=$(get_system_type)

    # 检查是否已经是清华源
    if grep -q "mirrors.tuna.tsinghua.edu.cn" "$sources_list"; then
        log_info "APT源已是清华大学镜像，无需重复设置。"
        return 0
    fi

    if ! confirm_action "确定要更改APT源为清华大学镜像吗？"; then
        log_info "已取消APT源设置。"
        return 0
    fi

    log_info "尝试使用清华大学镜像源..."
    if [ "$system_type" == "ubuntu" ]; then
        get_tsinghua_ubuntu_sources_content "$release" > "$sources_list"
    else
        get_tsinghua_debian_sources_content "$release" > "$sources_list"
    fi

    log_info "正在更新APT缓存 (清华大学源)..."
    if ! apt update -y > /dev/null; then
        log_warn "更新APT缓存失败，清华大学镜像源可能不可用。尝试使用阿里云镜像源作为备用..."
        
        if [ "$system_type" == "ubuntu" ]; then
            get_aliyun_ubuntu_sources_content "$release" > "$sources_list"
        else
            get_aliyun_debian_sources_content "$release" > "$sources_list"
        fi

        log_info "正在更新APT缓存 (阿里云源)..."
        if ! apt update -y > /dev/null; then
            log_error "更新APT缓存再次失败，阿里云镜像源可能也不可用。请检查网络连接或手动配置APT源。"
        else
            log_info "APT镜像源设置为阿里云成功。"
        fi
    else
        log_info "APT镜像源设置为清华大学成功。"
    fi
}

# ==============================================================================
# --- 功能模块 2: 时区设置 ---
# ==============================================================================
# 设置系统时区为东八区，中国时区 (支持备用方案)
set_timezone_shanghai() {
    log_info "正在设置系统时区为东八区 (Asia/Shanghai)。"

    local current_timezone=""
    if command -v timedatectl &> /dev/null; then
        current_timezone=$(timedatectl show --property=Timezone --value)
    elif [ -f "/etc/timezone" ]; then
        current_timezone=$(cat /etc/timezone)
    fi

    if [ "$current_timezone" == "Asia/Shanghai" ]; then
        log_info "系统时区已设置为 Asia/Shanghai，无需重复设置。"
        return 0
    fi

    if ! confirm_action "确定要将时区设置为 Asia/Shanghai 吗？"; then
        log_info "已取消时区设置。"
        return 0
    fi

    install_package "tzdata" # 确保tzdata已安装

    log_info "正在设置时区..."
    if command -v timedatectl &> /dev/null; then
        if ! timedatectl set-timezone Asia/Shanghai &> /dev/null; then
            log_warn "timedatectl 设置时区失败，尝试使用传统方法..."
            echo "Asia/Shanghai" > /etc/timezone
            if ! dpkg-reconfigure --frontend noninteractive tzdata &> /dev/null; then
                log_error "传统方法设置时区失败，请手动检查。"
            else
                log_info "系统时区设置为 Asia/Shanghai 成功 (传统方法)。"
            fi
        else
            log_info "系统时区设置为 Asia/Shanghai 成功 (timedatectl)。"
        fi
    else
        log_warn "未找到 timedatectl 命令，尝试使用传统方法设置时区..."
        echo "Asia/Shanghai" > /etc/timezone
        if ! dpkg-reconfigure --frontend noninteractive tzdata &> /dev/null; then
            log_error "传统方法设置时区失败，请手动检查。"
        else
            log_info "系统时区设置为 Asia/Shanghai 成功 (传统方法)。"
        fi
    fi
    
    # 验证时区设置
    local verified_timezone=""
    if command -v timedatectl &> /dev/null; then
        verified_timezone=$(timedatectl show --property=Timezone --value)
    else
        verified_timezone=$(cat /etc/timezone)
    fi
    
    if [ "$verified_timezone" != "Asia/Shanghai" ]; then
        log_warn "时区设置验证失败，当前时区为 ${verified_timezone}。请手动设置。"
    else
        log_info "时区设置验证成功。"
    fi
}

# ==============================================================================
# --- 功能模块 3: SSH 配置 ---
# ==============================================================================
# 修改SSH配置 (允许root密码登录并确保普通用户密码登录)
modify_ssh_config() {
    log_info "正在修改SSH配置。"

    local sshd_config="/etc/ssh/sshd_config"
    local sshd_config_backup="/etc/ssh/sshd_config.bak"
    local config_changed=0

    if ! confirm_action "警告：允许root密码登录会降低系统安全性。确定要继续吗？" "n"; then
        log_info "已取消SSH配置修改。"
        return 0
    fi

    # 备份原始配置文件
    log_info "备份SSH配置文件到 ${sshd_config_backup}"
    cp "$sshd_config" "$sshd_config_backup"

    # --- 允许 root 密码登录 ---
    if grep -qE "^\s*PermitRootLogin\s+yes" "$sshd_config"; then
        log_info "SSH配置已允许root密码登录，跳过设置。"
    else
        log_info "设置SSH允许root密码登录..."
        sed -i '/^PermitRootLogin/s/^.*$/PermitRootLogin yes/' "$sshd_config"
        # 如果不存在该行，则添加
        if ! grep -qE "^PermitRootLogin\s+yes" "$sshd_config"; then
            echo "PermitRootLogin yes" >> "$sshd_config"
        fi
        config_changed=1
        log_info "root密码登录设置完成。"
    fi

    # --- 确保普通用户密码登录 (PasswordAuthentication) ---
    if grep -qE "^\s*PasswordAuthentication\s+yes" "$sshd_config"; then
        log_info "SSH配置已允许密码认证 (包括普通用户)，跳过设置。"
    else
        log_info "设置SSH允许所有用户密码认证..."
        sed -i '/^PasswordAuthentication/s/^.*$/PasswordAuthentication yes/' "$sshd_config"
        # 如果不存在该行，则添加
        if ! grep -qE "^PasswordAuthentication\s+yes" "$sshd_config"; then
            echo "PasswordAuthentication yes" >> "$sshd_config"
        fi
        config_changed=1
        log_info "密码认证设置完成。"
    fi

    # 验证SSH配置
    if [ $config_changed -eq 1 ]; then
        log_info "正在验证SSH配置..."
        if ! /usr/sbin/sshd -t; then
            log_error "SSH配置验证失败，已恢复原始配置。请手动检查错误。"
            mv "$sshd_config_backup" "$sshd_config"
            return 1
        fi

        log_info "正在重启SSH服务..."
        if ! systemctl restart ssh &> /dev/null; then
            log_error "重启SSH服务失败，已恢复原始配置。请手动检查SSH服务。"
            mv "$sshd_config_backup" "$sshd_config"
            systemctl restart ssh
            return 1
        else
            log_info "SSH配置修改并服务重启成功。"
            log_warn "请确保您已为root用户和您需要的其他普通用户设置了强密码，以保证系统安全！"
        fi
    else
        log_info "无需修改SSH配置，跳过服务重启。"
    fi
}

# ==============================================================================
# --- 功能模块 4: 字体设置 ---
# ==============================================================================
# 修改系统字体为中文字体，使用兼容性最好的字体
set_chinese_fonts() {
    log_info "正在安装中文字体，使用兼容性最好的文泉驿正黑（wqy-zenhei）。"

    # 检查是否已安装中文字体
    if fc-list :lang=zh | grep -q "WenQuanYi Zen Hei"; then
        log_info "文泉驿正黑字体已安装，无需重复设置。"
        return 0
    fi

    if ! confirm_action "确定要安装文泉驿正黑字体吗？"; then
        log_info "已取消字体安装。"
        return 0
    fi

    install_package "fontconfig" # 确保fontconfig已安装
    install_package "fonts-wqy-zenhei" # 文泉驿正黑

    # 刷新字体缓存
    log_info "正在刷新字体缓存..."
    if ! fc-cache -fv &> /dev/null; then
        log_warn "字体缓存刷新失败，但字体可能已安装成功。"
    fi

    if fc-list :lang=zh | grep -q "WenQuanYi Zen Hei"; then
        log_info "中文字体文泉驿正黑安装成功。"
    else
        log_warn "中文字体安装可能不完整或未能正确识别，请手动检查。"
    fi
}

# ==============================================================================
# --- 功能模块 5: UFW 防火墙设置 ---
# ==============================================================================
# 设置ufw防火墙，开放内网无限制访问外网开放常用端口加88端口 (考虑IPv6)
configure_ufw() {
    log_info "正在配置UFW防火墙。"

    if ! confirm_action "确定要配置UFW防火墙吗？"; then
        log_info "已取消防火墙配置。"
        return 0
    fi

    install_package "ufw" # 确保ufw已安装

    # 确保UFW的IPv6支持是开启的
    if ! grep -qE "^\s*IPV6=yes" /etc/default/ufw; then
        log_info "启用UFW的IPv6支持..."
        sed -i '/^IPV6=/s/^.*$/IPV6=yes/' /etc/default/ufw
        if ! grep -qE "^IPV6=yes" /etc/default/ufw; then
             echo "IPV6=yes" >> /etc/default/ufw
        fi
    else
        log_info "UFW的IPv6支持已开启。"
    fi

    # 检查ufw状态
    ufw_status=$(ufw status | grep -o "Status: active")
    if [ "$ufw_status" == "Status: active" ]; then
        log_info "UFW防火墙已启用，正在检查规则。"
    else
        log_info "UFW防火墙未启用，正在启用并设置默认策略。"
        # 设置默认策略：拒绝所有入站，允许所有出站
        ufw default deny incoming &> /dev/null
        ufw default allow outgoing &> /dev/null
        if ! ufw enable &> /dev/null; then
            log_error "启用UFW防火墙失败。请手动检查UFW服务。"
        fi
        log_info "UFW防火墙已启用，默认拒绝所有入站连接，允许所有出站连接。"
    fi

    log_info "添加UFW规则..."

    # 开放常用端口 (这些规则通常同时适用于IPv4和IPv6)
    common_ports=("22/tcp" "80/tcp" "443/tcp" "88/tcp") # SSH, HTTP, HTTPS, 88端口

    for port in "${common_ports[@]}"; do
        # 检查是否已存在该端口的规则
        if ! ufw status | grep -qE "^${port}\s+ALLOW\s+Anywhere"; then
            log_info "开放端口: ${port} (同时作用于IPv4和IPv6)"
            if ! ufw allow "$port" &> /dev/null; then
                log_warn "开放端口 ${port} 失败，跳过此端口。"
            fi
        else
            log_info "端口 ${port} 已开放，跳过。"
        fi
    done

    # 允许内网无限制访问 (IPv4和IPv6)
    # 请根据实际内网IP段调整。这里示例了常见的IPv4私有地址和IPv6 ULA/Local
    internal_networks_ipv4=("192.168.0.0/16" "10.0.0.0/8" "172.16.0.0/12")
    internal_networks_ipv6=("fc00::/7" "fe80::/10") # IPv6 Unique Local Address (ULA) 和 Link-Local Address

    for net in "${internal_networks_ipv4[@]}"; do
        if ! ufw status | grep -qE "^Anywhere\s+ALLOW\s+${net}"; then
            log_info "允许IPv4内网 ${net} 无限制访问。"
            if ! ufw allow from "$net" to any &> /dev/null; then
                log_warn "允许IPv4内网 ${net} 访问失败，跳过此网络。"
            fi
        else
            log_info "已允许IPv4内网 ${net} 访问，跳过。"
        fi
    done

    for net in "${internal_networks_ipv6[@]}"; do
        if ! ufw status | grep -qE "^Anywhere \(v6\)\s+ALLOW\s+${net}"; then
            log_info "允许IPv6内网 ${net} 无限制访问。"
            if ! ufw allow from "$net" to any &> /dev/null; then
                log_warn "允许IPv6内网 ${net} 访问失败，跳过此网络。"
            fi
        else
            log_info "已允许IPv6内网 ${net} 访问，跳过。"
        fi
    done

    log_info "UFW防火墙配置完成。以下是详细状态："
    ufw status verbose
}

# ==============================================================================
# --- 主脚本逻辑 ---
# ==============================================================================
main() {
    check_root

    log_info "=== 系统初始化脚本开始运行 ==="
    log_info "系统信息: $(lsb_release -d | cut -f2-) ($(uname -m))"
    log_info "当前用户: $(whoami)"
    log_info "工作目录: $(pwd)"
    log_info "运行时间: $(date)"

    if ! confirm_action "确定要继续执行系统初始化吗？"; then
        log_info "已取消系统初始化。"
        exit 0
    fi

    log_info "--- 执行 APT 镜像源设置 ---"
    set_apt_source

    log_info "--- 执行 时区设置 ---"
    set_timezone_shanghai

    log_info "--- 执行 SSH 配置修改 ---"
    modify_ssh_config

    log_info "--- 执行 字体设置 ---"
    set_chinese_fonts

    log_info "--- 执行 UFW 防火墙设置 ---"
    configure_ufw

    log_info "=== 系统初始化脚本运行完毕 ==="
    log_info "请注意：SSH配置修改后，请确保root用户和其他普通用户都有密码，否则将无法通过密码登录。"
    log_info "如果需要，请使用 'passwd <username>' 命令设置或修改用户密码。"
    log_info "系统将在10秒后重启以应用所有更改。按Ctrl+C取消重启。"

    # 倒计时重启
    for i in {10..1}; do
        echo -ne "系统将在 ${i} 秒后重启...\r"
        sleep 1
    done

    log_info "正在重启系统..."
    shutdown -r now
}

# 脚本入口
main "$@"
