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

    # 强制root权限检查
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：此操作需要root权限！${NC}"
        return 1
    fi

    # 显示当前时间信息
    show_time_info() {
        date "+%Y-%m-%d %H:%M:%S %Z (UTC%z)"
    }

    # 判断是否已经是东八区
    if date +%z | grep -qE '(\+0800|CST)'; then
        echo -e "${GREEN}时区已正确设置为东八区${NC}"
        show_time_info
        return 0
    fi

    # 安装时区数据包（仅在缺失时）
    if [ ! -f "$ZONE_FILE" ]; then
        echo -e "${YELLOW}时区文件缺失，正在安装tzdata..."
        case $OS in
            debian) apt update && apt install -y tzdata ;;
            centos) yum install -y tzdata ;;
            alpine) apk add --no-cache tzdata ;;
        esac || {
            echo -e "${RED}时区数据安装失败！请检查网络或软件源配置${NC}"
            return 1
        }
    fi

    # 配置时区：符号链接 → 文件复制 → 系统工具（优先级递增）
    echo -e "${YELLOW}尝试配置时区..."

    # 方法1: 符号链接（Alpine允许但需同时更新/etc/timezone）
    if ln -sf "$ZONE_FILE" /etc/localtime 2>/dev/null; then
        echo -e "${GREEN}符号链接创建成功！"
        [ "$OS" = "alpine" ] && echo "$TARGET_ZONE" > /etc/timezone
    else
        # 方法2: 直接复制文件（适用于符号链接受限环境）
        if cp -f "$ZONE_FILE" /etc/localtime 2>/dev/null; then
            echo -e "${YELLOW}使用文件复制成功！"
            [ "$OS" = "alpine" ] && echo "$TARGET_ZONE" > /etc/timezone
        else
            # 方法3: 调用系统工具（Alpine专用）
            echo -e "${YELLOW}尝试通过系统工具配置..."
            case $OS in
                alpine)
                    if command -v setup-timezone >/dev/null; then
                        setup-timezone -z "$TARGET_ZONE" && echo -e "${GREEN}setup-timezone 配置成功！"
                    else
                        echo -e "${RED}Alpine系统缺少setup-timezone工具，请手动安装tzdata！${NC}"
                        return 1
                    fi
                    ;;
                debian|centos)
                    timedatectl set-timezone "$TARGET_ZONE" || {
                        echo -e "${RED}timedatectl 配置失败！请检查:"
                        echo -e "1. 是否以root运行"
                        echo -e "2. systemd服务是否正常${NC}"
                        return 1
                    }
                    ;;
            esac
        fi
    fi

    # 最终验证（增加重试逻辑）
    local RETRY=3
    while [ $RETRY -gt 0 ]; do
        sleep 1
        if date +%z | grep -qE '(\+0800|CST)'; then
            echo -e "${GREEN}时区配置验证通过！${NC}"
            show_time_info
            return 0
        fi
        RETRY=$((RETRY-1))
    done

    # 所有方法均失败
    echo -e "${RED}时区配置失败！请手动执行以下操作:"
    echo -e "1. 确保文件存在: ls -l $ZONE_FILE"
    echo -e "2. 手动设置: ln -sf $ZONE_FILE /etc/localtime"
    echo -e "3. Alpine系统需额外写入: echo $TARGET_ZONE > /etc/timezone${NC}"
    return 1
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
