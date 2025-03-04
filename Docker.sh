#!/bin/bash
# Docker安装脚本 - 支持Alpine/Debian/Ubuntu/CentOS系统
# 2025-03-04 更新

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RESET='\033[0m'

# 权限检测
SUDO_CMD=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO_CMD="sudo"
    echo -e "${YELLOW}检测到非root权限，后续操作将使用sudo执行${RESET}"
    sleep 0.5
fi

# 系统检测
detect_os() {
    if [ -f /etc/alpine-release ]; then
        OS="alpine"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    elif [ -f /etc/centos-release ]; then
        OS="centos"
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$(echo $ID | tr '[:upper:]' '[:lower:]')
    else
        echo -e "${RED}无法识别的操作系统${RESET}"
        exit 1
    fi
    echo -e "${BLUE}检测到系统类型：${OS}${RESET}"
    sleep 0.5
}

# Docker安装函数
install_docker() {
    case $OS in
        alpine)
            $SUDO_CMD apk add docker docker-cli docker-compose
            ;;
        debian|ubuntu)
            # 使用国内镜像源
            $SUDO_CMD apt-get update
            $SUDO_CMD apt-get install -y apt-transport-https ca-certificates curl
            curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/$OS/gpg | $SUDO_CMD apt-key add -
            $SUDO_CMD add-apt-repository "deb [arch=amd64] https://mirrors.aliyun.com/docker-ce/linux/$OS $(lsb_release -cs) stable"
            $SUDO_CMD apt-get update
            $SUDO_CMD apt-get install -y docker-ce docker-ce-cli containerd.io
            ;;
        centos)
            # 使用阿里源
            $SUDO_CMD yum install -y yum-utils
            $SUDO_CMD yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
            $SUDO_CMD yum makecache fast
            $SUDO_CMD yum install -y docker-ce docker-ce-cli containerd.io
            ;;
        *)
            echo -e "${RED}不支持的操作系统${RESET}"
            exit 1
            ;;
    esac
}

# Docker Compose安装
install_compose() {
    echo -e "${YELLOW}安装Docker Compose...${RESET}"
    COMPOSE_URL="https://ghproxy.com/https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
    $SUDO_CMD curl -L $COMPOSE_URL -o /usr/local/bin/docker-compose
    $SUDO_CMD chmod +x /usr/local/bin/docker-compose
    sleep 0.5
}

# 镜像源配置
configure_mirror() {
    DAEMON_JSON="/etc/docker/daemon.json"
    echo -e "${YELLOW}配置镜像加速源...${RESET}"
    if [ ! -d /etc/docker ]; then
        $SUDO_CMD mkdir -p /etc/docker
    fi
    
    if [ -f $DAEMON_JSON ]; then
        echo -e "${YELLOW}检测到现有配置文件："
        cat $DAEMON_JSON
        read -p "是否替换镜像源配置？(y/N) " choice
        if [[ $choice =~ [Yy] ]]; then
            $SUDO_CMD cp $DAEMON_JSON "${DAEMON_JSON}.bak"
        else
            return
        fi
    fi

    $SUDO_CMD tee $DAEMON_JSON > /dev/null <<EOF
{
    "registry-mirrors": [
        "https://docker.m.daocloud.io",
        "https://hub-mirror.c.163.com",
        "https://mirror.baidubce.com"
    ]
}
EOF
    sleep 0.5
}

# 主逻辑
detect_os

# Docker安装检查
if command -v docker &> /dev/null; then
    echo -e "${GREEN}检测到已安装Docker版本：$(docker --version)${RESET}"
    read -p "是否覆盖安装？(y/N) " choice
    if [[ $choice =~ [Yy] ]]; then
        echo -e "${YELLOW}卸载旧版本...${RESET}"
        case $OS in
            alpine) $SUDO_CMD apk del docker* ;;
            debian|ubuntu) $SUDO_CMD apt-get purge -y docker* ;;
            centos) $SUDO_CMD yum remove -y docker* ;;
        esac
        install_docker
    fi
else
    read -p "是否安装Docker？(Y/n) " choice
    if [[ ! $choice =~ [Nn] ]]; then
        install_docker
    else
        exit 0
    fi
fi

# Docker Compose检查
if ! command -v docker-compose &> /dev/null; then
    read -p "是否安装Docker Compose？(Y/n) " choice
    if [[ ! $choice =~ [Nn] ]]; then
        install_compose
    fi
else
    echo -e "${GREEN}检测到已安装Docker Compose版本：$(docker-compose --version)${RESET}"
    read -p "是否覆盖安装？(y/N) " choice
    if [[ $choice =~ [Yy] ]]; then
        install_compose
    fi
fi

# 开机自启配置
echo -e "${YELLOW}配置服务自启动...${RESET}"
case $OS in
    alpine)
        $SUDO_CMD rc-update add docker default
        $SUDO_CMD service docker start
        ;;
    *)
        $SUDO_CMD systemctl enable --now docker
        ;;
esac
sleep 0.5

# 镜像源配置
configure_mirror

# 验证安装
echo -e "${GREEN}验证安装结果："
docker --version
docker-compose --version
echo -e "镜像源配置："
cat /etc/docker/daemon.json 2>/dev/null
echo -e "${RESET}"
