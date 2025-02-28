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
    
    # 检查时区文件是否存在
    if [ ! -f "$ZONE_FILE" ]; then
        echo -e "${RED}错误：时区文件 $ZONE_FILE 不存在${NC}"
        return 1
    fi

    # 优先尝试符号链接方式
    if [ -w /etc/localtime ]; then
        CURRENT_ZONE=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')
        if [ "$CURRENT_ZONE" != "$TARGET_ZONE" ]; then
            echo -e "${YELLOW}当前时区: ${CURRENT_ZONE}, 正在配置为东八区...${NC}"
            ln -sf "$ZONE_FILE" /etc/localtime
        fi
    else
        echo -e "${YELLOW}无法创建符号链接，改用专用配置...${NC}"
        case $OS in
            debian|centos)
                timedatectl set-timezone $TARGET_ZONE
                ;;
            alpine)
                apk add --no-cache tzdata
                cp "$ZONE_FILE" /etc/localtime
                echo $TARGET_ZONE > /etc/timezone
                apk del tzdata
                ;;
        esac
    fi

    # 最终验证
    if [ "$(date +%Z)" == "CST" ]; then
        echo -e "${GREEN}时区已正确设置为东八区${NC}"
    else
        echo -e "${RED}时区配置异常，当前时区：$(date +%Z)${NC}"
        return 1
    fi
}

# 镜像源配置（支持6个国内源）
configure_mirror() {
    echo -e "\n${BLUE}=== 镜像源配置 ===${NC}"
    
    declare -A MIRRORS=(
        [1]="阿里云" [2]="腾讯云" [3]="华为云" 
        [4]="清华大学" [5]="网易" [6]="中科大"
    )
    
    declare -A URLS=(
        [1]="mirrors.aliyun.com"
        [2]="mirrors.cloud.tencent.com"
        [3]="repo.huaweicloud.com" 
        [4]="mirrors.tuna.tsinghua.edu.cn"
        [5]="mirrors.163.com"
        [6]="mirrors.ustc.edu.cn"
    )

    echo "请选择镜像源:"
    for key in 1 2 3 4 5 6; do
        echo "$key) ${MIRRORS[$key]}"
    done

    while true; do
        read -p "请输入选择 (1-6): " choice
        [[ $choice =~ ^[1-6]$ ]] && break
        echo -e "${RED}无效输入，请重新选择${NC}"
    done

    NEW_MIRROR=${URLS[$choice]}
    echo -e "${GREEN}已选择: ${MIRRORS[$choice]} 镜像源${NC}"

    case $OS in
        debian)
            SOURCE_FILE="/etc/apt/sources.list"
            sed -i "s|http://.*\.debian\.org|https://$NEW_MIRROR|g" $SOURCE_FILE
            sed -i "s|http://security\.debian\.org|https://$NEW_MIRROR|g" $SOURCE_FILE
            if ! apt update; then
                echo -e "${RED}APT更新失败，请检查镜像源配置${NC}"
                exit 1
            fi
            ;;
        centos)
            SOURCE_FILE="/etc/yum.repos.d/CentOS-Base.repo"
            # 关键修复：移除HTML内容污染，使用正确正则表达式
            sed -i "s|^mirrorlist=|#mirrorlist=|g" $SOURCE_FILE
            sed -i "s|^#baseurl=http://mirror.centos.org|baseurl=https://$NEW_MIRROR|g" $SOURCE_FILE
            if ! yum makecache; then
                echo -e "${RED}YUM缓存失败，请检查镜像源配置${NC}"
                exit 1
            fi
            ;;
        alpine)
            SOURCE_FILE="/etc/apk/repositories"
            sed -i "s|http://dl-cdn.alpinelinux.org|https://$NEW_MIRROR|g" $SOURCE_FILE
            if ! apk update; then
                echo -e "${RED}APK更新失败，请检查镜像源配置${NC}"
                exit 1
            fi
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
