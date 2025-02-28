#!/bin/bash

# 检查Root权限
if [[ $EUID -ne 0 ]]; then
   echo "请使用 root 权限运行本脚本" 
   exit 1
fi

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 获取系统信息
if [ -f /etc/alpine-release ]; then
    DISTRO="alpine"
    VERSION=$(cat /etc/alpine-release | cut -d'.' -f1-2)
elif [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
    VERSION=$VERSION_ID
else
    echo -e "${RED}无法识别系统版本${NC}"
    exit 1
fi

# 检查Docker是否已安装
check_docker_installed() {
    if command -v docker &>/dev/null; then
        echo -e "${YELLOW}Docker 已经安装，跳过安装步骤${NC}"
        return 0
    fi
    return 1
}

# 检查Docker Compose是否已安装
check_compose_installed() {
    if command -v docker-compose &>/dev/null; then
        echo -e "${YELLOW}Docker Compose 已经安装，跳过安装步骤${NC}"
        return 0
    fi
    return 1
}

# 设置开机启动
enable_service() {
    case $DISTRO in
        alpine)
            if rc-update show default | grep -q docker; then
                echo -e "${YELLOW}Docker 已设置开机启动${NC}"
            else
                rc-update add docker default
                echo -e "${GREEN}已设置Docker开机启动${NC}"
            fi
            ;;
        *)
            if systemctl is-enabled docker &>/dev/null; then
                echo -e "${YELLOW}Docker 已设置开机启动${NC}"
            else
                systemctl enable docker --now
                echo -e "${GREEN}已设置Docker开机启动${NC}"
            fi
            ;;
    esac
}

# 安装Docker
install_docker() {
    echo -e "${GREEN}正在安装 Docker...${NC}"
    case $DISTRO in
        debian|ubuntu)
            apt-get update
            apt-get install -y \
                ca-certificates \
                curl \
                gnupg
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$DISTRO/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$DISTRO \
                $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io
            ;;
        centos|rhel)
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io
            ;;
        fedora)
            dnf -y install dnf-plugins-core
            dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            dnf -y install docker-ce docker-ce-cli containerd.io
            ;;
        alpine)
            apk add docker docker-cli docker-compose
            ;;
        *)
            echo -e "${RED}不支持的发行版: $DISTRO${NC}"
            exit 1
            ;;
    esac
}

# 安装Docker Compose
install_compose() {
    echo -e "${GREEN}正在安装 Docker Compose...${NC}"
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
}

# 配置镜像加速
configure_registry() {
    DAEMON_JSON="/etc/docker/daemon.json"
    REGISTRIES=(
        "https://docker.woskee.nyc.mn"
        "https://docker.woskee.dns.army"
    )

    # 备份原有配置
    if [ -f $DAEMON_JSON ]; then
        cp $DAEMON_JSON "${DAEMON_JSON}.bak"
        echo -e "${YELLOW}已备份原配置文件: ${DAEMON_JSON}.bak${NC}"
    fi

    # 创建配置
    cat > $DAEMON_JSON << EOF
{
    "registry-mirrors": ${REGISTRIES[@]@Q},
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    }
}
EOF

    echo -e "${GREEN}镜像加速配置完成${NC}"
    systemctl restart docker || rc-service docker restart
}

# 镜像搜索功能
search_images() {
    while true; do
        read -p "输入镜像名称（留空退出）: " image
        if [ -z "$image" ]; then
            break
        fi
        docker search $image
    done
}

# 主安装流程
main() {
    # 安装Docker
    if ! check_docker_installed; then
        install_docker
    fi

    # 安装Docker Compose
    if ! check_compose_installed; then
        if [ "$DISTRO" != "alpine" ]; then
            install_compose
        else
            echo -e "${YELLOW}Alpine 系统已通过apk安装docker-compose${NC}"
        fi
    fi

    enable_service
    configure_registry
    
    echo -e "\n${GREEN}安装完成！${NC}"
    echo -e "Docker 版本: $(docker --version)"
    echo -e "Docker Compose 版本: $(docker-compose --version)"
    
    # 启动镜像搜索
    echo -e "\n# Docker Hub 镜像搜索"
    echo -e "快速查找、下载和部署 Docker 容器镜像"
    read -p "提示：按回车键开始搜索，直接回车退出..."
    search_images
}

main
