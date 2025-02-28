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
    if grep -qi "alpine" /etc/os-release 2>/dev/null; then
        echo "alpine"
    elif grep -qi "debian" /etc/os-release 2>/dev/null; then
        echo "debian"
    elif grep -qi "centos\|rhel\|fedora" /etc/os-release 2>/dev/null; then
        echo "centos"
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

# SSH服务检查与配置
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

    if ! command -v sshd &>/dev/null; then
        echo -e "${YELLOW}[SSH] 服务未安装，正在安装...${NC}"
        case $OS in
            debian) apt update && apt install -y $PKG ;;
            centos) yum install -y $PKG ;;
            alpine) apk add $PKG ;;
        esac
    fi

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

    SSH_CONFIG="/etc/ssh/sshd_config"
    sed -i 's/#*PermitRootLogin.*/PermitRootLogin yes/' $SSH_CONFIG
    sed -i 's/#*PasswordAuthentication.*/PasswordAuthentication yes/' $SSH_CONFIG
    
    manage_service $SERVICE restart
    echo -e "${GREEN}[SSH] 服务已配置完成${NC}"
}

# 时区配置检查
check_timezone() {
    echo -e "\n${BLUE}=== 时区检查 ===${NC}"
    TARGET_ZONE="Asia/Shanghai"
    
    case $OS in
        debian|centos)
            CURRENT_ZONE=$(timedatectl show --value -p Timezone)
            ;;
        alpine)
            CURRENT_ZONE=$(cat /etc/timezone 2>/dev/null)
            ;;
    esac

    if [ "$CURRENT_ZONE" != "$TARGET_ZONE" ]; then
        echo -e "${YELLOW}当前时区: ${CURRENT_ZONE:-未设置}, 正在配置为东八区...${NC}"
        case $OS in
            debian|centos)
                timedatectl set-timezone $TARGET_ZONE
                ;;
            alpine)
                apk add --no-cache tzdata
                cp /usr/share/zoneinfo/$TARGET_ZONE /etc/localtime
                echo $TARGET_ZONE > /etc/timezone
                apk del tzdata
                ;;
        esac
        echo -e "${GREEN}时区已设置为 $TARGET_ZONE${NC}"
    else
        echo -e "${GREEN}当前时区已正确设置为东八区${NC}"
    fi
}

# 镜像源配置（已修正顺序）
configure_mirror() {
    echo -e "\n${BLUE}=== 镜像源配置 ===${NC}"
    
    declare -A MIRRORS=(
        [1]="阿里云镜像源"
        [2]="腾讯云镜像源" 
        [3]="华为云镜像源"
        [4]="清华大学镜像源"
    )
    
    declare -A URLS=(
        [1]="mirrors.aliyun.com"
        [2]="mirrors.cloud.tencent.com"
        [3]="repo.huaweicloud.com"
        [4]="mirrors.tuna.tsinghua.edu.cn"
    )

    echo "请选择镜像源 (输入编号):"
    # 修正遍历顺序为1-4
    for key in 1 2 3 4; do
        echo "$key) ${MIRRORS[$key]}"
    done

    while true; do
        read -p "请输入选择 (1-4): " choice
        [[ $choice =~ ^[1-4]$ ]] && break
        echo -e "${RED}无效输入，请重新选择${NC}"
    done

    NEW_MIRROR=${URLS[$choice]}
    echo -e "${GREEN}已选择: ${MIRRORS[$choice]}${NC}"

    case $OS in
        debian)
            SOURCE_FILE="/etc/apt/sources.list"
            sed -i "s|http://.*\.debian\.org|https://$NEW_MIRROR|g" $SOURCE_FILE
            apt update
            ;;
        centos)
            SOURCE_FILE="/etc/yum.repos.d/CentOS-Base.repo"
            sed -i "s|^baseurl=.*|baseurl=https://$NEW_MIRROR|g" $SOURCE_FILE
            yum makecache
            ;;
        alpine)
            SOURCE_FILE="/etc/apk/repositories"
            sed -i "s|http://dl-cdn.alpinelinux.org|https://$NEW_MIRROR|g" $SOURCE_FILE
            apk update
            ;;
    esac
    
    echo -e "${GREEN}镜像源更新完成${NC}"
}

# 主程序
OS=$(detect_os)
if [ "$OS" == "unknown" ]; then
    echo -e "${RED}不支持的发行版${NC}"
    exit 1
fi

check_ssh
check_timezone
configure_mirror

echo -e "\n${GREEN}所有配置已完成，即将退出脚本！${NC}"
exit 0
