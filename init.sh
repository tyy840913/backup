#!/bin/bash
# 系统配置自动化检查与修复脚本
# 支持：Debian/Ubuntu, CentOS/RHEL, Alpine Linux

# 字体颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # 颜色重置

# 检测系统发行版
detect_os() {
    if [ -f /etc/alpine-release ]; then
        echo "alpine"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "centos"
    else
        echo "unknown"
    fi
}

# 功能1：SSH服务检查与配置
check_ssh() {
    case $OS in
        debian|centos)
            if ! systemctl status sshd &> /dev/null && ! systemctl status ssh &> /dev/null; then
                echo -e "${YELLOW}[SSH] 服务未安装，正在安装...${NC}"
                if [ "$OS" = "debian" ]; then
                    apt update && apt install -y openssh-server
                else
                    yum install -y openssh-server
                fi
                systemctl enable sshd && systemctl start sshd
            fi
            ;;
        alpine)
            if ! rc-service sshd status &> /dev/null; then
                echo -e "${YELLOW}[SSH] 服务未安装，正在安装...${NC}"
                apk add openssh && rc-update add sshd && rc-service sshd start
            fi
            ;;
    esac

    # 检查SSH配置
    SSH_CONFIG="/etc/ssh/sshd_config"
    grep -q "^PermitRootLogin yes" $SSH_CONFIG || sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' $SSH_CONFIG
    grep -q "^PasswordAuthentication yes" $SSH_CONFIG || sed -i 's/#PasswordAuthentication.*/PasswordAuthentication yes/' $SSH_CONFIG
    systemctl restart sshd || rc-service sshd restart
    echo -e "${GREEN}[SSH] 服务已配置：Root登录和密码认证已启用${NC}"
}

# 功能2：时区检查与配置
check_timezone() {
    CURRENT_TZ=$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}')
    [ -z "$CURRENT_TZ" ] && CURRENT_TZ=$(date +%Z)
    
    if [[ "$CURRENT_TZ" != *"CST"* ]] && [[ "$CURRENT_TZ" != *"Asia/Shanghai"* ]]; then
        echo -e "${YELLOW}[时区] 当前时区: $CURRENT_TZ，建议设置为东八区${NC}"
        case $OS in
            debian|centos)
                timedatectl set-timezone Asia/Shanghai
                ;;
            alpine)
                apk add --no-cache tzdata
                cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
                echo "Asia/Shanghai" > /etc/timezone
                apk del tzdata
                ;;
        esac
        echo -e "${GREEN}[时区] 已设置为 Asia/Shanghai${NC}"
    else
        echo -e "${GREEN}[时区] 当前已正确设置为东八区${NC}"
    fi
}

# 功能3：镜像源检查与配置
check_mirror() {
    declare -A MIRRORS=(
        ["aliyun"]="https://mirrors.aliyun.com"
        ["ustc"]="https://mirrors.ustc.edu.cn"
        ["huawei"]="https://repo.huaweicloud.com"
        ["tencent"]="https://mirrors.cloud.tencent.com"
    )

    case $OS in
        debian)
            SOURCE_FILE="/etc/apt/sources.list"
            ;;
        centos)
            SOURCE_FILE="/etc/yum.repos.d/CentOS-Base.repo"
            ;;
        alpine)
            SOURCE_FILE="/etc/apk/repositories"
            ;;
    esac

    # 显示当前源并确认
    echo -e "\n${YELLOW}当前镜像源配置："
    cat $SOURCE_FILE
    echo -e "${NC}"

    select MIRROR in "阿里云" "中科大" "华为云" "腾讯云" "跳过"; do
        case $REPLY in
            1) NEW_SOURCE=$MIRRORS[aliyun]; break ;;
            2) NEW_SOURCE=$MIRRORS[ustc]; break ;;
            3) NEW_SOURCE=$MIRRORS[huawei]; break ;;
            4) NEW_SOURCE=$MIRRORS[tencent]; break ;;
            5) return;;
            *) echo "无效选择";;
        esac
    done

    # 备份并替换源
    cp $SOURCE_FILE ${SOURCE_FILE}.bak
    case $OS in
        debian)
            sed -i "s|http://.*\.debian\.org|$NEW_SOURCE|g" $SOURCE_FILE
            ;;
        centos)
            curl -o $SOURCE_FILE $NEW_SOURCE/CentOS-$(rpm -E %centos)-repo.tar.gz
            ;;
        alpine)
            sed -i "s|http://dl-cdn.alpinelinux.org|$NEW_SOURCE|g" $SOURCE_FILE
            ;;
    esac
    echo -e "${GREEN}[镜像源] 已更新为 $NEW_SOURCE${NC}"
}

# 主程序
OS=$(detect_os)
echo -e "${GREEN}检测到系统类型：$OS${NC}"

check_ssh       # 
check_timezone  # 
check_mirror    # 

echo -e "\n${GREEN}所有检查项已完成，建议重启系统使配置生效！${NC}"
