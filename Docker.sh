#!/bin/bash

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 延时函数
sleep_with_output() {
    echo -e "${BLUE}等待0.5秒...${NC}"
    sleep 0.5
}

# 检测系统发行版
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/alpine-release ]; then
        DISTRO="alpine"
        VERSION=$(cat /etc/alpine-release)
    else
        echo -e "${RED}无法检测系统发行版${NC}"
        exit 1
    fi
    echo -e "${GREEN}检测到系统发行版: ${DISTRO} ${VERSION}${NC}"
}

# 安装Docker
install_docker() {
    case $DISTRO in
        ubuntu|debian)
            echo -e "${BLUE}开始安装Docker...${NC}"
            sudo apt-get update
            sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
            curl -fsSL https://download.docker.com/linux/$DISTRO/gpg | sudo tee /etc/apt/trusted.gpg.d/docker.asc > /dev/null
            sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/$DISTRO $(lsb_release -cs) stable"
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io
            ;;
        centos|rhel)
            echo -e "${BLUE}开始安装Docker...${NC}"
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io
            ;;
        alpine)
            echo -e "${BLUE}开始安装Docker...${NC}"
            sudo apk add docker
            ;;
        *)
            echo -e "${RED}不支持的系统发行版${NC}"
            exit 1
            ;;
    esac
    echo -e "${GREEN}Docker安装完成${NC}"
}

# 卸载Docker
uninstall_docker() {
    case $DISTRO in
        ubuntu|debian)
            echo -e "${BLUE}开始卸载Docker...${NC}"
            sudo apt-get purge -y docker-ce docker-ce-cli containerd.io
            sudo rm -rf /var/lib/docker
            ;;
        centos|rhel)
            echo -e "${BLUE}开始卸载Docker...${NC}"
            sudo yum remove -y docker-ce docker-ce-cli containerd.io
            sudo rm -rf /var/lib/docker
            ;;
        alpine)
            echo -e "${BLUE}开始卸载Docker...${NC}"
            sudo apk del docker
            ;;
        *)
            echo -e "${RED}不支持的系统发行版${NC}"
            exit 1
            ;;
    esac
    echo -e "${GREEN}Docker卸载完成${NC}"
}

# 安装Docker Compose
install_docker_compose() {
    echo -e "${BLUE}开始安装Docker Compose...${NC}"
    sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    echo -e "${GREEN}Docker Compose安装完成${NC}"
}

# 卸载Docker Compose
uninstall_docker_compose() {
    echo -e "${BLUE}开始卸载Docker Compose...${NC}"
    sudo rm -f /usr/local/bin/docker-compose
    echo -e "${GREEN}Docker Compose卸载完成${NC}"
}

# 检查Docker是否已安装
check_docker_installed() {
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version)
        echo -e "${GREEN}Docker已安装: ${DOCKER_VERSION}${NC}"
        return 0
    else
        echo -e "${YELLOW}Docker未安装${NC}"
        return 1
    fi
}

# 检查Docker Compose是否已安装
check_docker_compose_installed() {
    if command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE_VERSION=$(docker-compose --version)
        echo -e "${GREEN}Docker Compose已安装: ${DOCKER_COMPOSE_VERSION}${NC}"
        return 0
    else
        echo -e "${YELLOW}Docker Compose未安装${NC}"
        return 1
    fi
}

# 设置开机自启
enable_docker_startup() {
    case $DISTRO in
        ubuntu|debian|centos|rhel)
            echo -e "${BLUE}设置Docker开机自启...${NC}"
            sudo systemctl enable docker
            ;;
        alpine)
            echo -e "${BLUE}设置Docker开机自启...${NC}"
            sudo rc-update add docker
            ;;
        *)
            echo -e "${RED}不支持的系统发行版${NC}"
            exit 1
            ;;
    esac
    echo -e "${GREEN}Docker开机自启已设置${NC}"
}

# 配置镜像加速源
configure_mirror() {
    MIRROR_FILE="/etc/docker/daemon.json"
    MIRRORS=(
        "https://docker.1panel.top"
        "https://proxy.1panel.live"
        "https://docker.m.daocloud.io"
        "https://docker.woskee.dns.army"
        "https://docker.woskee.dynv6.net"
    )

    if [ ! -f $MIRROR_FILE ]; then
        echo -e "${BLUE}创建镜像加速源文件...${NC}"
        sudo mkdir -p /etc/docker
        echo '{"registry-mirrors": []}' | sudo tee $MIRROR_FILE > /dev/null
    fi

    echo -e "${BLUE}当前镜像加速源:${NC}"
    sudo cat $MIRROR_FILE

    read -p "是否覆盖写入镜像加速源? (y/n): " choice
    if [ "$choice" = "y" ]; then
        echo -e "${BLUE}写入镜像加速源...${NC}"
        sudo jq '.registry-mirrors = $mirrors' --argjson mirrors "$(printf '%s\n' "${MIRRORS[@]}" | jq -R . | jq -s .)" $MIRROR_FILE > /tmp/daemon.json
        sudo mv /tmp/daemon.json $MIRROR_FILE
        echo -e "${GREEN}镜像加速源已更新${NC}"
        return 0
    else
        echo -e "${YELLOW}镜像加速源未修改${NC}"
        return 1
    fi
}

# 重启Docker
restart_docker() {
    case $DISTRO in
        ubuntu|debian|centos|rhel)
            echo -e "${BLUE}重启Docker...${NC}"
            sudo systemctl restart docker
            ;;
        alpine)
            echo -e "${BLUE}重启Docker...${NC}"
            sudo service docker restart
            ;;
        *)
            echo -e "${RED}不支持的系统发行版${NC}"
            exit 1
            ;;
    esac
    echo -e "${GREEN}Docker已重启${NC}"
}

# 主函数
main() {
    detect_distro
    sleep_with_output

    if check_docker_installed; then
        read -p "Docker已安装，是否重新安装? (y/n): " choice
        if [ "$choice" = "y" ]; then
            uninstall_docker
            sleep_with_output
            install_docker
        fi
    else
        read -p "Docker未安装，是否安装? (y/n): " choice
        if [ "$choice" = "y" ]; then
            install_docker
        fi
    fi
    sleep_with_output

    if check_docker_compose_installed; then
        echo -e "${GREEN}Docker Compose已安装${NC}"
    else
        read -p "Docker Compose未安装，是否安装? (y/n): " choice
        if [ "$choice" = "y" ]; then
            install_docker_compose
        fi
    fi
    sleep_with_output

    enable_docker_startup
    sleep_with_output

    if configure_mirror; then
        restart_docker
    fi
    sleep_with_output

    echo -e "${GREEN}脚本执行完成${NC}"
}

main
