#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 初始化变量
declare -A PKG_MANAGER
declare -A SERVICE_MANAGER
DOCKER_PROXY="https://mirror.ghproxy.com/"
MIRRORS=(
    "https://docker.1panel.top"
    "https://proxy.1panel.live"
    "https://docker.m.daocloud.io"
    "https://docker.woskee.dns.army"
    "https://docker.woskee.dynv6.net"
)
DAEMON_JSON="/etc/docker/daemon.json"

# 系统检测函数
detect_system() {
    echo -e "${BLUE}▶ 开始检测系统信息...${NC}"
    sleep 0.5
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/alpine-release ]; then
        DISTRO="alpine"
        VERSION=$(cat /etc/alpine-release)
    else
        echo -e "${RED}✖ 无法检测操作系统${NC}"
        exit 1
    fi

    case $DISTRO in
        ubuntu|debian)
            PKG_MANAGER["install"]="apt-get install -y"
            PKG_MANAGER["remove"]="apt-get purge -y"
            PKG_MANAGER["repo_update"]="apt-get update"
            SERVICE_MANAGER["restart"]="systemctl restart docker"
            SERVICE_MANAGER["enable"]="systemctl enable docker"
            GPG_DIR="/etc/apt/keyrings"
            ;;
        centos|fedora|rhel)
            PKG_MANAGER["install"]="yum install -y"
            PKG_MANAGER["remove"]="yum remove -y"
            PKG_MANAGER["repo_update"]="yum makecache"
            SERVICE_MANAGER["restart"]="systemctl restart docker"
            SERVICE_MANAGER["enable"]="systemctl enable docker"
            GPG_DIR="/etc/pki/rpm-gpg"
            ;;
        alpine)
            PKG_MANAGER["install"]="apk add --no-cache"
            PKG_MANAGER["remove"]="apk del"
            SERVICE_MANAGER["restart"]="rc-service docker restart"
            SERVICE_MANAGER["enable"]="rc-update add docker"
            ;;
        *)
            echo -e "${RED}✖ 不支持的发行版: $DISTRO${NC}"
            exit 1
            ;;
    esac

    echo -e "${GREEN}✔ 检测到系统: ${DISTRO} ${VERSION}${NC}"
    sleep 0.5
}

# Docker 检测函数
check_docker() {
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
        echo -e "${YELLOW}⚠ 检测到已安装 Docker 版本: ${DOCKER_VERSION}${NC}"
        read -p "是否重新安装? [y/N] " reinstall
        if [[ $reinstall =~ ^[Yy]$ ]]; then
            uninstall_docker
            install_docker
        fi
    else
        read -p "检测到未安装 Docker，是否安装? [Y/n] " install_docker
        if [[ ! $install_docker =~ ^[Nn]$ ]]; then
            install_docker
        fi
    fi
}

# Docker Compose 检测函数
check_compose() {
    if command -v docker-compose &> /dev/null; then
        COMPOSE_VERSION=$(docker-compose --version | awk '{print $3}' | tr -d ',')
        echo -e "${GREEN}✔ Docker Compose 已安装 (${COMPOSE_VERSION})${NC}"
    else
        read -p "是否安装 Docker Compose? [Y/n] " install_compose
        if [[ ! $install_compose =~ ^[Nn]$ ]]; then
            install_compose
        fi
    fi
    sleep 0.5
}

# 卸载 Docker 函数
uninstall_docker() {
    echo -e "${BLUE}▶ 开始卸载旧版本 Docker...${NC}"
    case $DISTRO in
        ubuntu|debian)
            ${PKG_MANAGER["remove"]} docker-ce docker-ce-cli containerd.io
            rm -rf /var/lib/docker /etc/docker
            ;;
        centos|fedora|rhel)
            ${PKG_MANAGER["remove"]} docker-ce docker-ce-cli containerd.io
            rm -rf /var/lib/docker
            ;;
        alpine)
            ${PKG_MANAGER["remove"]} docker docker-cli docker-compose
            ;;
    esac
    echo -e "${GREEN}✔ Docker 卸载完成${NC}"
    sleep 0.5
}

# 安装 Docker 函数
install_docker() {
    echo -e "${BLUE}▶ 开始安装 Docker...${NC}"
    case $DISTRO in
        ubuntu|debian)
            # 添加 Docker 仓库
            curl -fsSL ${DOCKER_PROXY}https://download.docker.com/linux/$DISTRO/gpg | gpg --dearmor -o $GPG_DIR/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=$GPG_DIR/docker.gpg] ${DOCKER_PROXY}https://download.docker.com/linux/$DISTRO $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
            ${PKG_MANAGER["repo_update"]}
            ${PKG_MANAGER["install"]} docker-ce docker-ce-cli containerd.io
            ;;
        centos|fedora)
            yum-config-manager --add-repo ${DOCKER_PROXY}https://download.docker.com/linux/$DISTRO/docker-ce.repo
            ${PKG_MANAGER["install"]} docker-ce docker-ce-cli containerd.io
            ;;
        alpine)
            ${PKG_MANAGER["install"]} docker docker-cli
            ;;
    esac
    
    # 启动 Docker 服务
    if [ "$DISTRO" != "alpine" ]; then
        systemctl start docker
    else
        rc-service docker start
    fi
    
    echo -e "${GREEN}✔ Docker 安装完成${NC}"
    sleep 0.5
}

# 安装 Docker Compose 函数
install_compose() {
    echo -e "${BLUE}▶ 安装 Docker Compose...${NC}"
    local COMPOSE_URL="${DOCKER_PROXY}https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
    curl -L $COMPOSE_URL -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    echo -e "${GREEN}✔ Docker Compose 安装完成${NC}"
    sleep 0.5
}

# 配置镜像加速
configure_mirror() {
    echo -e "${BLUE}▶ 配置镜像加速...${NC}"
    [ ! -d /etc/docker ] && mkdir -p /etc/docker
    
    if [ -f $DAEMON_JSON ]; then
        echo -e "${YELLOW}⚠ 检测到现有配置文件:"
        cat $DAEMON_JSON
        read -p "是否覆盖? [y/N] " overwrite
    else
        overwrite="y"
    fi

    if [[ $overwrite =~ ^[Yy]$ ]]; then
        cat > $DAEMON_JSON <<EOF
{
    "registry-mirrors": ${MIRRORS[@]@Q}
}
EOF
        echo -e "${GREEN}✔ 镜像加速配置已更新${NC}"
        RESTART_DOCKER=1
    else
        echo -e "${YELLOW}⚠ 保留原有配置${NC}"
    fi
    sleep 0.5
}

# 设置开机自启
enable_service() {
    echo -e "${BLUE}▶ 设置开机自启...${NC}"
    ${SERVICE_MANAGER["enable"]} 2>/dev/null || true
    echo -e "${GREEN}✔ 已设置开机自启${NC}"
    sleep 0.5
}

# 主函数
main() {
    detect_system
    check_docker
    check_compose
    configure_mirror
    enable_service

    if [ $RESTART_DOCKER ]; then
        echo -e "${BLUE}▶ 重启 Docker 服务...${NC}"
        ${SERVICE_MANAGER["restart"]}
        sleep 1
    fi

    echo -e "${GREEN}\n✔ 安装完成！"
    echo -e "Docker 版本: $(docker --version)"
    echo -e "Docker Compose 版本: $(docker-compose --version)"
    echo -e "镜像加速配置: ${MIRRORS[@]}${NC}"
}

main "$@"
