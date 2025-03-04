#!/bin/bash
set -e

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RESET='\033[0m'

# 延时函数
delay() {
    sleep 0.5
}

# 系统检测函数
detect_os() {
    if [ -f /etc/alpine-release ]; then
        OS="Alpine"
        VERSION=$(cat /etc/alpine-release)
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
    else
        echo -e "${RED}无法检测操作系统版本${RESET}"
        exit 1
    fi
    echo -e "${BLUE}检测到系统：${OS} ${VERSION}${RESET}"
    delay
}

# 包管理器配置
init_pkg_manager() {
    case $OS in
        alpine)
            UPDATE_CMD="apk update"
            INSTALL_CMD="apk add"
            UNINSTALL_CMD="apk del"
            PKG_MANAGER="apk"
            ;;
        ubuntu|debian)
            UPDATE_CMD="apt-get update -qq"
            INSTALL_CMD="apt-get install -y -qq"
            UNINSTALL_CMD="apt-get purge -y -qq"
            PKG_MANAGER="apt"
            ;;
        centos|rhel|fedora)
            UPDATE_CMD="yum makecache -q"
            INSTALL_CMD="yum install -y -q"
            UNINSTALL_CMD="yum remove -y -q"
            PKG_MANAGER="yum"
            ;;
        *)
            echo -e "${RED}不支持的发行版${RESET}"
            exit 1
            ;;
    esac
    echo -e "${BLUE}初始化包管理器：${PKG_MANAGER}${RESET}"
    delay
}

# Docker安装状态检查
check_docker() {
    if command -v docker &>/dev/null; then
        DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
        echo -e "${YELLOW}检测到已安装Docker版本：${DOCKER_VERSION}${RESET}"
        read -p "是否重新安装？(y/N) " REINSTALL
        if [[ $REINSTALL =~ [Yy] ]]; then
            uninstall_docker
        else
            DOCKER_INSTALLED=true
        fi
    else
        read -p "检测到未安装Docker，是否现在安装？(Y/n) " INSTALL
        [[ ! $INSTALL =~ [Nn] ]] || exit 0
    fi
    delay
}

# Docker卸载函数
uninstall_docker() {
    echo -e "${BLUE}开始卸载旧版Docker...${RESET}"
    case $OS in
        alpine)
            $UNINSTALL_CMD docker-cli docker-engine docker-openrc docker-compose
            ;;
        ubuntu|debian)
            $UNINSTALL_CMD docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        centos|rhel|fedora)
            $UNINSTALL_CMD docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
    esac
    rm -rf /var/lib/docker /etc/docker
    delay
}

# Docker安装函数
install_docker() {
    echo -e "${BLUE}开始安装Docker...${RESET}"
    case $OS in
        alpine)
            $INSTALL_CMD docker-cli docker-engine docker-openrc
            ;;
        ubuntu|debian)
            # 使用阿里云镜像源
            curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/$OS/gpg | tee /etc/apt/trusted.gpg.d/docker.asc >/dev/null
            echo "deb [arch=$(dpkg --print-architecture)] https://mirrors.aliyun.com/docker-ce/linux/$OS $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list
            $UPDATE_CMD
            $INSTALL_CMD docker-ce docker-ce-cli containerd.io docker-buildx-plugin
            ;;
        centos|rhel|fedora)
            yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
            $INSTALL_CMD docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
    esac
    delay
}

# Docker Compose检查
check_compose() {
    if command -v docker-compose &>/dev/null; then
        COMPOSE_VERSION=$(docker-compose --version | awk '{print $3}' | tr -d ',')
        echo -e "${YELLOW}检测到Docker Compose版本：${COMPOSE_VERSION}${RESET}"
    else
        read -p "未检测到Docker Compose，是否安装？(Y/n) " INSTALL_COMPOSE
        [[ ! $INSTALL_COMPOSE =~ [Nn] ]] && install_compose
    fi
    delay
}

# Docker Compose安装
install_compose() {
    echo -e "${BLUE}开始安装Docker Compose...${RESET}"
    COMPOSE_URL="https://ghproxy.com/https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
    curl -L $COMPOSE_URL -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    delay
}

# 服务管理
service_control() {
    case $OS in
        alpine)
            rc-update add docker boot
            rc-service docker start
            ;;
        *)
            systemctl enable --now docker
            ;;
    esac
    echo -e "${GREEN}已设置Docker开机自启${RESET}"
    delay
}

# 镜像加速配置
configure_mirror() {
    MIRRORS=(
        "https://docker.m.daocloud.io"
        "https://docker.woskee.dns.army"
        "https://docker.woskee.dynv6.net"
        "https://registry.docker-cn.com"
        "https://mirror.ccs.tencentyun.com"
    )

    DAEMON_JSON="/etc/docker/daemon.json"
    mkdir -p $(dirname $DAEMON_JSON)
    
    if [ -f $DAEMON_JSON ]; then
        echo -e "${YELLOW}检测到现有镜像加速配置："
        cat $DAEMON_JSON
        read -p "是否覆盖现有配置？(y/N) " OVERWRITE
    else
        OVERWRITE="y"
    fi

    if [[ $OVERWRITE =~ [Yy] ]]; then
        echo "{ \"registry-mirrors\": [$(printf '"%s",' "${MIRRORS[@]}" | sed 's/,$//')] }" > $DAEMON_JSON
        echo -e "${GREEN}镜像加速配置已更新${RESET}"
        case $OS in
            alpine) rc-service docker restart ;;
            *) systemctl restart docker ;;
        esac
    else
        echo -e "${YELLOW}保持现有镜像配置${RESET}"
    fi
    delay
}

# 主执行流程
main() {
    detect_os
    init_pkg_manager
    check_docker
    if [ -z "$DOCKER_INSTALLED" ]; then
        install_docker
        service_control
    fi
    check_compose
    configure_mirror
    
    echo -e "\n${GREEN}安装完成！验证版本信息：${RESET}"
    docker --version
    docker-compose --version
    echo -e "\n${GREEN}镜像加速配置：${RESET}"
    docker info | grep -A 1 "Registry Mirrors"
}

main
