#!/usr/bin/env bash
#
# 系统配置自动化检查与修复脚本
# 版本: 2.0 (稳定版)
#
# 变更日志:
# - 增加全局Root权限检查，确保脚本在正确的权限下运行。
# - 优化SSH配置检查的正则表达式，使其能兼容不同的空格格式。
# - 调整manage_service函数参数顺序，提高代码可读性。
# - 移除函数内冗余的权限检查。
#
# 支持系统：Debian/Ubuntu, CentOS/RHEL, Alpine Linux

# --- 颜色定义 ---
RED='\033[0;31m'    # 错误
GREEN='\033[0;32m'  # 成功
YELLOW='\033[0;33m' # 警告
BLUE='\033[0;34m'   # 信息
NC='\033[0m'      # 颜色重置

# --- 核心函数 ---

# 1. 检查Root权限 (全局)
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误: 此脚本必须以root权限运行。${NC}"
        echo -e "${YELLOW}请尝试使用 'sudo $0' 命令来运行此脚本。${NC}"
        exit 1
    fi
}

# 2. 精准检测系统发行版
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case $ID in
            debian|ubuntu) echo "debian" ;;
            centos|rhel|fedora) echo "centos" ;; # 将Fedora归入此类
            alpine)        echo "alpine" ;;
            *)             echo "unknown" ;;
        esac
    else
        echo "unknown"
    fi
}

# 3. 服务管理抽象层 (优化后)
# 用法: manage_service <action> <service_name>
# 例如: manage_service "restart" "sshd"
manage_service() {
    local action=$1
    local service=$2
    case $OS in
        debian|centos)
            systemctl "$action" "$service"
            ;;
        alpine)
            # Alpine的rc-service命令参数顺序是 service action
            rc-service "$service" "$action"
            ;;
    esac
}

# --- 功能模块 ---

# 模块一: SSH服务检查与配置（增强版）
check_ssh() {
    echo -e "\n${BLUE}=== SSH 服务检查与配置 ===${NC}"
    
    local PKG=""
    local SERVICE=""
    case $OS in
        debian)
            PKG="openssh-server"
            SERVICE="ssh"
            ;;
        centos)
            PKG="openssh-server"
            SERVICE="sshd"
            ;;
        alpine)
            PKG="openssh"
            SERVICE="sshd"
            ;;
    esac

    # 安装状态检查
    if ! command -v sshd &>/dev/null; then
        echo -e "${YELLOW}[SSH] 服务未安装，正在安装...${NC}"
        case $OS in
            debian) apt-get update && apt-get install -y $PKG ;;
            centos) yum install -y $PKG ;;
            alpine) apk add --no-cache $PKG ;;
        esac || {
            echo -e "${RED}[SSH] 安装失败，请检查网络或软件源。${NC}"
            return 1 # 使用return代替exit，增加灵活性
        }
    fi

    # 自启动配置
    case $OS in
        debian|centos)
            if ! systemctl is-enabled "$SERVICE" &>/dev/null; then
                manage_service "enable" "$SERVICE"
                echo -e "${GREEN}[SSH] 已成功启用 $SERVICE 开机自启动。${NC}"
            else
                echo -e "[SSH] 服务 $SERVICE 已启用自启动，无需操作。"
            fi
            ;;
        alpine)
            if ! rc-update show | grep -q "$SERVICE"; then
                rc-update add "$SERVICE" default # 添加到默认运行级别
                echo -e "${GREEN}[SSH] 已成功将 $SERVICE 添加至默认运行级别。${NC}"
            else
                echo -e "[SSH] 服务 $SERVICE 已在运行级别中，无需操作。"
            fi
            ;;
    esac

    # 配置文件优化（使用更精确的grep和状态检测）
    local SSH_CONFIG="/etc/ssh/sshd_config"
    local CONFIG_CHANGED=0

    # 检查Root登录配置 (^\s*... 匹配带前导空格的行)
    if ! grep -qE "^\s*PermitRootLogin\s+yes\s*$" "$SSH_CONFIG"; then
        sed -i 's/^\s*#*\s*PermitRootLogin.*/PermitRootLogin yes/' "$SSH_CONFIG"
        echo -e "[SSH] 配置更新：已启用 Root 登录。"
        CONFIG_CHANGED=1
    else
        echo -e "[SSH] 配置检查：Root 登录已启用，无需修改。"
    fi

    # 检查密码认证配置
    if ! grep -qE "^\s*PasswordAuthentication\s+yes\s*$" "$SSH_CONFIG"; then
        sed -i 's/^\s*#*\s*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSH_CONFIG"
        echo -e "[SSH] 配置更新：已启用密码认证。"
        CONFIG_CHANGED=1
    else
        echo -e "[SSH] 配置检查：密码认证已启用，无需修改。"
    fi

    # 仅在配置变更时重启服务
    if [ $CONFIG_CHANGED -eq 1 ]; then
        echo -e "${YELLOW}[SSH] 配置已变更，正在重启服务以生效...${NC}"
        if ! manage_service "restart" "$SERVICE"; then
            echo -e "${RED}[SSH] 服务重启失败，请手动执行 'systemctl restart $SERVICE' 或 'rc-service $SERVICE restart'。${NC}"
            return 1
        fi
        echo -e "${GREEN}[SSH] 服务配置已更新并成功重启。${NC}"
    else
        echo -e "${GREEN}[SSH] 配置无变动，无需重启服务。${NC}"
    fi
}

# 模块二: 时区配置检查（增强版）
check_timezone() {
    echo -e "\n${BLUE}=== 时区检查与配置 ===${NC}"
    local TARGET_ZONE="Asia/Shanghai"
    local ZONE_FILE="/usr/share/zoneinfo/${TARGET_ZONE}"

    # 内部函数：显示当前时间信息
    show_time_info() {
        echo -n "当前系统时间: "
        date "+%Y-%m-%d %H:%M:%S %Z (UTC%z)"
    }

    # 判断是否已经是目标时区
    if date +%z | grep -qE '(\+0800|CST)'; then
        echo -e "${GREEN}时区已正确设置为 ${TARGET_ZONE}。${NC}"
        show_time_info
        return 0
    fi

    echo -e "${YELLOW}当前时区不正确，开始自动配置为 ${TARGET_ZONE}...${NC}"

    # 确保时区数据包已安装（仅在缺失时）
    if [ ! -f "$ZONE_FILE" ]; then
        echo -e "${YELLOW}时区数据文件缺失，正在安装...${NC}"
        case $OS in
            debian) apt-get update && apt-get install -y tzdata ;;
            centos) yum install -y tzdata ;;
            alpine) apk add --no-cache tzdata ;;
        esac || {
            echo -e "${RED}时区数据包安装失败！请检查网络或软件源配置。${NC}"
            return 1
        }
    fi

    # 核心配置逻辑
    case $OS in
        debian|centos)
            if command -v timedatectl >/dev/null; then
                timedatectl set-timezone "$TARGET_ZONE"
            else
                ln -sf "$ZONE_FILE" /etc/localtime
            fi
            ;;
        alpine)
            # Alpine需要同时更新/etc/timezone文件
            ln -sf "$ZONE_FILE" /etc/localtime && echo "$TARGET_ZONE" > /etc/timezone
            ;;
    esac

    # 最终验证
    if date +%z | grep -qE '(\+0800|CST)'; then
        echo -e "${GREEN}时区配置成功！${NC}"
        show_time_info
    else
        echo -e "${RED}时区配置失败！请手动检查系统。${NC}"
        echo -e "建议命令: 'timedatectl set-timezone ${TARGET_ZONE}' 或 'ln -sf ${ZONE_FILE} /etc/localtime'"
        return 1
    fi
}

# --- 主程序入口 ---
main() {
    check_root
    OS=$(detect_os)

    if [ "$OS" == "unknown" ]; then
        echo -e "${RED}错误：无法识别或不支持当前操作系统。${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}检测到操作系统: $OS, 开始执行自动化检查...${NC}"

    check_ssh
    check_timezone

    echo -e "\n${GREEN}所有检查与配置任务已完成。${NC}"
}

# 执行主函数
main
