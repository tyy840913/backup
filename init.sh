#!/bin/bash
# 系统配置自动化检查与修复脚本
# 支持：Debian/Ubuntu, CentOS/RHEL, Alpine Linux

RED='\033[31m'    # 错误
GREEN='\033[32m'  # 成功
YELLOW='\033[33m' # 警告
BLUE='\033[34m'   # 信息
NC='\033[0m'      # 颜色重置

# 精准检测系统发行版
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case $ID in
            debian|ubuntu) echo "debian" ;;
            centos|rhel)   echo "centos" ;;
            alpine)        echo "alpine" ;;
            *)             echo "unknown" ;;
        esac
    else
        echo "unknown"
    fi
}

# 服务管理抽象层
manage_service() {
    case $OS in
        debian|centos)
            systemctl $2 $1
            ;;
        alpine)
            rc-service $1 $2
            ;;
    esac
}

# SSH服务检查与配置（增强版）
check_ssh() {
    echo -e "\n${BLUE}=== SSH服务检查 ===${NC}"
    
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
            debian) apt update && apt install -y $PKG ;;
            centos) yum install -y $PKG ;;
            alpine) apk add $PKG ;;
        esac || {
            echo -e "${RED}SSH安装失败，请检查网络连接${NC}"
            exit 1
        }
    fi

    # 自启动配置
    case $OS in
        debian|centos)
            if ! systemctl is-enabled $SERVICE &>/dev/null; then
                systemctl enable $SERVICE
            fi
            ;;
        alpine)
            if ! rc-update show | grep -q $SERVICE; then
                rc-update add $SERVICE
            fi
            ;;
    esac

    # 配置文件优化
    SSH_CONFIG="/etc/ssh/sshd_config"
    sed -i 's/#*PermitRootLogin.*/PermitRootLogin yes/' $SSH_CONFIG
    sed -i 's/#*PasswordAuthentication.*/PasswordAuthentication yes/' $SSH_CONFIG
    
    # 服务重启
    if ! manage_service $SERVICE restart; then
        echo -e "${RED}SSH服务重启失败${NC}"
        exit 1
    fi
    echo -e "${GREEN}[SSH] 服务已配置完成${NC}"
}

# 时区配置检查（增强版）
check_timezone() {
    echo -e "\n${BLUE}=== 时区检查与配置 ===${NC}"
    local TARGET_ZONE="Asia/Shanghai"
    local ZONE_FILE="/usr/share/zoneinfo/${TARGET_ZONE}"

    # 显示当前时间信息
    show_time_info() {
        echo -e "${BLUE}当前系统时间:${NC}"
        date "+%Y-%m-%d %H:%M:%S %Z (UTC%z)"
    }

    # 判断是否已经是东八区
    if date +%z | grep -qE '(\+0800|CST)'; then
        echo -e "${GREEN}时区已正确设置为东八区${NC}"
        show_time_info
        return 0
    fi

    # 安装时区数据包（如缺失）
    if [ ! -f "$ZONE_FILE" ]; then
        echo -e "${YELLOW}正在安装时区数据包..."
        case $OS in
            debian) apt update && apt install -y tzdata ;;
            centos) yum install -y tzdata ;;
            alpine) apk add --no-cache tzdata ;;
        esac || {
            echo -e "${RED}时区数据安装失败！请检查网络或软件源配置${NC}"
            return 1
        }
    fi

    # 尝试符号链接配置
    echo -e "${YELLOW}尝试符号链接配置..."
    if [ -w /etc/localtime ]; then
        # 清除可能存在的旧配置
        [ -f /etc/localtime ] && rm -f /etc/localtime
        # 创建符号链接
        if ln -sf "$ZONE_FILE" /etc/localtime; then
            echo -e "${GREEN}符号链接创建成功！"
            # Alpine兼容性处理
            [ "$OS" = "alpine" ] && echo "$TARGET_ZONE" > /etc/timezone
            show_time_info
            return 0
        else
            echo -e "${RED}符号链接创建失败，错误代码：$?${NC}"
        fi
    else
        echo -e "${YELLOW}/etc/localtime 无写入权限${NC}"
    fi

    # 符号链接失败后改用系统工具
    echo -e "${YELLOW}正在通过系统工具配置..."
    case $OS in
        debian|centos)
            timedatectl set-timezone "$TARGET_ZONE" || {
                echo -e "${RED}timedatectl 配置失败，请检查："
                echo -e "1. 需要root权限执行"
                echo -e "2. systemd服务是否运行${NC}"
                return 1
            }
            ;;
        alpine)
            cp -f "$ZONE_FILE" /etc/localtime
            echo "$TARGET_ZONE" > /etc/timezone
            ;;
    esac

    # 最终验证
    sleep 1 # 等待配置生效
    if date +%z | grep -qE '(\+0800|CST)'; then
        echo -e "${GREEN}时区配置验证通过！${NC}"
        show_time_info
    else
        echo -e "${RED}时区配置异常！当前时间："
        show_time_info
        return 1
    fi
}

# 主程序
OS=$(detect_os)
if [ "$OS" == "unknown" ]; then
    echo -e "${RED}不支持的发行版${NC}"
    exit 1
fi

check_ssh
check_timezone

echo -e "\n${GREEN}所有配置已完成，即将退出脚本！${NC}"
exit 0
