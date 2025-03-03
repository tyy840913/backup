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
    echo -e "\n${BLUE}=== 时区检查 ===${NC}"
    TARGET_ZONE="Asia/Shanghai"
    ZONE_FILE="/usr/share/zoneinfo/${TARGET_ZONE}"
    
    # 自动安装缺失的时区文件
    if [ ! -f "$ZONE_FILE" ]; then
        echo -e "${YELLOW}时区文件缺失，正在安装时区数据包...${NC}"
        case $OS in
            debian) apt update && apt install -y tzdata ;;
            centos) yum install -y tzdata ;;
            alpine) apk add --no-cache tzdata ;;
        esac || {
            echo -e "${RED}时区数据包安装失败，请检查网络或软件源配置${NC}"
            return 1
        }
        
        # 二次验证文件是否存在
        if [ ! -f "$ZONE_FILE" ]; then
            echo -e "${RED}时区文件安装后仍不存在：$ZONE_FILE${NC}"
            return 1
        fi
    fi

    # Alpine专用处理逻辑
    if [ "$OS" = "alpine" ]; then
        echo -e "${YELLOW}Alpine系统强制使用文件拷贝方式...${NC}"
        apk add --no-cache tzdata >/dev/null 2>&1
        if [ -f /etc/localtime ]; then
            rm -f /etc/localtime  # 删除可能存在的旧文件
        fi
        cp -f "$ZONE_FILE" /etc/localtime
        echo "$TARGET_ZONE" > /etc/timezone
    else
        # 优先尝试符号链接方式
        if [ -w /etc/localtime ]; then
            # 强制删除可能存在的普通文件
            [ -f /etc/localtime ] && rm -f /etc/localtime
            ln -sf "$ZONE_FILE" /etc/localtime
        else
            echo -e "${YELLOW}无写入权限，使用timedatectl配置...${NC}"
            timedatectl set-timezone "$TARGET_ZONE" || {
                echo -e "${RED}时区设置命令失败，请检查权限${NC}"
                return 1
            }
        fi
    fi

    # 最终验证（兼容Alpine的date输出）
    echo -e "\n${BLUE}当前系统时间信息:${NC}"
    date "+%Y-%m-%d %H:%M:%S %Z (UTC%z)"  # 修改格式字符串

    if date | grep -qE "CST|UTC+08|+08"; then
        echo -e "${GREEN}时区已正确设置为东八区${NC}"
    else
        echo -e "${RED}时区配置异常，当前时间：$(date)${NC}"
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
