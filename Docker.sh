#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # 恢复默认颜色

# 系统检测
OS=$(grep -oP '^ID=\K\w+' /etc/os-release 2>/dev/null)
[[ -z "$OS" ]] && OS=$(cat /etc/alpine-release 2>/dev/null | cut -d'.' -f1)
CODENAME=$(grep -oP 'VERSION_CODENAME=\K\w+' /etc/os-release 2>/dev/null)

# 依赖检查
check_dependencies() {
    local missing=()
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v gpg >/dev/null 2>&1 || missing+=("gpg")
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${YELLOW}安装依赖: ${missing[*]}${NC}"
        case $OS in
            "ubuntu"|"debian")
                apt-get update && apt-get install -y ${missing[@]} ;;
            "centos"|"rhel"|"fedora")
                yum install -y ${missing[@]} ;;
            "alpine")
                apk add --no-cache ${missing[@]} ;;
        esac
    fi
}

# Docker安装状态检查
check_docker() {
    if command -v docker &>/dev/null; then
        DOCKER_VERSION=$(docker --version | awk '{print $3}' | tr -d ',')
        echo -e "${GREEN}检测到已安装Docker版本: $DOCKER_VERSION${NC}"
        return 0
    fi
    return 1
}

# Docker Compose检查
check_compose() {
    if command -v docker-compose &>/dev/null; then
        COMPOSE_VERSION=$(docker-compose --version | awk '{print $3}' | tr -d ',')
        echo -e "${GREEN}检测到已安装Docker Compose版本: $COMPOSE_VERSION${NC}"
        return 0
    fi
    return 1
}

# 卸载Docker
uninstall_docker() {
    echo -e "${RED}正在卸载旧版本Docker...${NC}"
    case $OS in
        "ubuntu"|"debian")
            apt-get remove -y docker docker-engine docker.io containerd runc
            rm -rf /var/lib/docker ;;
        "centos"|"rhel"|"fedora")
            yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine
            rm -rf /var/lib/docker ;;
        "alpine")
            apk del docker-cli docker-engine docker-openrc docker-compose
            rm -rf /var/lib/docker ;;
    esac
    echo -e "${GREEN}Docker卸载完成${NC}"
}

# 安装Docker
install_docker() {
    echo -e "${CYAN}开始安装Docker...${NC}"
    case $OS in
        "ubuntu"|"debian")
            # Ubuntu特殊处理
            apt-get update
            apt-get install -y ca-certificates curl gnupg
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://add.woskee.nyc.mn/download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://add.woskee.nyc.mn/download.docker.com/linux/$OS ${CODENAME} stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin ;;

        "centos"|"rhel"|"fedora")
            yum install -y yum-utils
            yum-config-manager --add-repo https://add.woskee.nyc.mn/download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin ;;

        "alpine")
            apk add --no-cache docker-cli docker-engine docker-openrc
            rc-update add docker default
            service docker start ;;
    esac
    systemctl enable --now docker 2>/dev/null
}

# 安装Docker Compose
install_compose() {
    echo -e "${CYAN}开始安装Docker Compose...${NC}"
    case $OS in
        "alpine")
            apk add --no-cache docker-compose ;;
        *)
            COMPOSE_VERSION=$(curl -s https://add.woskee.nyc.mn/api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d'"' -f4)
            curl -L "https://add.woskee.nyc.mn/github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
            ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose 2>/dev/null ;;
    esac
}

# 镜像加速配置
configure_mirror() {
    DAEMON_JSON="/etc/docker/daemon.json"
    MIRROR_URL="https:https://proxy.1panel.live"

                "https://docker.1panel.top"

                "https://docker.m.daocloud.io"

                "https://docker.woskee.dns.army"

                "https://docker.woskee.dynv6.net"

    echo -e "${YELLOW}配置镜像加速源...${NC}"
    if [ -f $DAEMON_JSON ]; then
        echo -e "${BLUE}当前配置文件内容:${NC}"
        cat $DAEMON_JSON
        read -p "是否要覆盖现有配置？(y/N): " choice
        case "$choice" in
            y|Y)
                cp $DAEMON_JSON ${DAEMON_JSON}.bak
                echo -e "${GREEN}已备份原配置文件${NC}" ;;
            *)
                return ;;
        esac
    fi

    mkdir -p $(dirname $DAEMON_JSON)
    cat > $DAEMON_JSON <EOF
{
    "registry-mirrors": ["$MIRROR_URL"]
}
EOF
    echo -e "${GREEN}镜像加速配置完成${NC}"
}

# 主逻辑
main() {
    # 检查root权限
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}请使用sudo或root用户运行此脚本${NC}"
        exit 1
    fi

    check_dependencies

    # Docker安装流程
    if check_docker; then
        read -p "检测到已安装Docker，是否要重新安装？(y/N): " choice
        case "$choice" in
            y|Y)
                uninstall_docker
                install_docker ;;
            *)
                echo -e "${BLUE}跳过Docker安装${NC}" ;;
        esac
    else
        read -p "是否要安装Docker？(Y/n): " choice
        case "$choice" in
            n|N)
                echo -e "${RED}安装已取消${NC}"
                exit 0 ;;
            *)
                install_docker ;;
        esac
    fi

    # Docker Compose安装流程
    if ! check_compose; then
        install_compose
    else
        echo -e "${BLUE}检测到Docker Compose已安装${NC}"
    fi

    # 配置镜像加速
    configure_mirror

    # 服务管理
    echo -e "${YELLOW}配置服务自启动...${NC}"
    case $OS in
        "alpine")
            rc-update add docker default 2>/dev/null
            service docker restart ;;
        *)
            systemctl enable docker 2>/dev/null
            systemctl restart docker ;;
    esac

    # 验证安装
    echo -e "\n${CYAN}验证安装结果:${NC}"
    docker --version && docker-compose --version
    echo -e "${GREEN}Docker服务状态:${NC}"
    case $OS in
        "alpine") service docker status ;;
        *) systemctl status docker --no-pager ;;
    esac
}

main "$@"
