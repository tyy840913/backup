#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# GitHub 加速器代理 (脚本级别配置)
GH_PROXY="https://ghproxy.net/"

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}请使用 root 权限运行此脚本${NC}"
        exit 1
    fi
}

# 检测系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        echo -e "${GREEN}检测到系统: $OS${NC}"
    elif [ -f /etc/alpine-release ]; then
        OS="alpine"
        echo -e "${GREEN}检测到系统: Alpine Linux${NC}"
    else
        echo -e "${RED}无法检测操作系统${NC}"
        exit 1
    fi
}

# 检查并安装依赖，避免重复安装
install_dependencies() {
    echo -e "${CYAN}--- 检查并安装依赖包 ---${NC}"
    
    # 移除了 wget，只保留 curl 和 jq
    REQUIRED_COMMANDS="curl jq"
    PACKAGES_TO_INSTALL=""
    
    for cmd in $REQUIRED_COMMANDS; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${YELLOW}命令 '$cmd' 未找到，准备安装...${NC}"
            PACKAGES_TO_INSTALL+="$cmd "
        else
            echo -e "${GREEN}✔ 命令 '$cmd' 已存在${NC}"
        fi
    done
    
    PACKAGES_TO_INSTALL=$(echo "$PACKAGES_TO_INSTALL" | sed 's/ *$//')

    if [ -n "$PACKAGES_TO_INSTALL" ]; then
        echo -e "${BLUE}开始安装缺失的依赖: $PACKAGES_TO_INSTALL${NC}"
        case $OS in
            ubuntu|debian)
                apt-get update
                apt-get install -y $PACKAGES_TO_INSTALL
                ;;
            centos|rhel|fedora)
                if command -v dnf &> /dev/null; then
                    dnf install -y $PACKAGES_TO_INSTALL
                else
                    yum install -y $PACKAGES_TO_INSTALL
                fi
                ;;
            alpine)
                apk update
                apk add $PACKAGES_TO_INSTALL
                ;;
            *)
                echo -e "${RED}无法为未知系统自动安装依赖，请手动安装: $PACKAGES_TO_INSTALL${NC}"
                return 1
                ;;
        esac
        if [ $? -ne 0 ]; then
            echo -e "${RED}依赖安装失败，请检查错误信息。${NC}"
            exit 1
        fi
        echo -e "${GREEN}依赖安装完成。${NC}"
    else
        echo -e "${GREEN}所有依赖均已安装，无需操作。${NC}"
    fi
}

# 使用系统包管理工具安装 Docker
install_docker() {
    echo -e "${CYAN}--- 安装 Docker ---${NC}"
    
    if command -v docker &> /dev/null; then
        echo -e "${YELLOW}Docker 已安装，跳过。${NC}"
        # 确保 Docker 服务是启动的
        if ! pgrep dockerd > /dev/null; then
           echo -e "${YELLOW}检测到 Docker 已安装但未运行，尝试启动...${NC}"
           if [ "$OS" = "alpine" ]; then service docker start; else systemctl start docker; fi
        fi
        return 0
    fi

    case $OS in
        ubuntu|debian)
            apt-get install -y docker.io
            ;;
        centos)
            yum install -y docker
            ;;
        rhel)
            subscription-manager repos --enable=rhel-7-server-extras-rpms
            yum install -y docker
            ;;
        fedora)
            dnf install -y docker
            ;;
        alpine)
            apk add docker
            ;;
        *)
            echo -e "${RED}不支持的 Linux 发行版: $OS${NC}"
            exit 1
            ;;
    esac
    
    echo -e "${GREEN}Docker 安装完成，正在启动服务...${NC}"
    if [ "$OS" = "alpine" ]; then
        rc-update add docker boot && service docker start
    else
        systemctl start docker && systemctl enable docker
    fi
}

# 安装 Docker Compose
install_docker_compose() {
    echo -e "${CYAN}--- 安装 Docker Compose ---${NC}"
    
    if command -v docker-compose &> /dev/null; then
        echo -e "${YELLOW}Docker Compose 已安装，跳过。${NC}"
        return 0
    fi

    echo -e "${BLUE}尝试从系统源安装 Docker Compose...${NC}"
    case $OS in
        ubuntu|debian) apt-get install -y docker-compose > /dev/null 2>&1 ;;
        centos|rhel|fedora)
            if command -v dnf &> /dev/null; then dnf install -y docker-compose > /dev/null 2>&1; else yum install -y docker-compose > /dev/null 2>&1; fi ;;
        alpine) apk add docker-compose > /dev/null 2>&1 ;;
    esac
    
    if command -v docker-compose &> /dev/null; then
        echo -e "${GREEN}从系统源安装 Docker Compose 成功${NC}"
        return 0
    fi

    echo -e "${YELLOW}系统源安装失败或不可用，尝试从 GitHub 下载...${NC}"
    COMPOSE_VERSION=$(curl -s "${GH_PROXY}https://api.github.com/repos/docker/compose/releases/latest" | jq -r ".tag_name")
    if [ -z "$COMPOSE_VERSION" ] || [ "$COMPOSE_VERSION" = "null" ]; then
        echo -e "${RED}无法获取 Docker Compose 最新版本号${NC}"; return 1;
    fi

    echo -e "${BLUE}下载 Docker Compose ${COMPOSE_VERSION}...${NC}"
    DOWNLOAD_URL="${GH_PROXY}https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)"
    
    if curl -L "$DOWNLOAD_URL" -o /usr/local/bin/docker-compose; then
        chmod +x /usr/local/bin/docker-compose
        ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
        echo -e "${GREEN}Docker Compose ${COMPOSE_VERSION} 安装完成${NC}"
    else
        echo -e "${RED}Docker Compose 下载失败${NC}"; return 1;
    fi
}

# 配置 Docker 加速和代理
configure_docker_proxy_and_mirror() {
    local DAEMON_JSON="/etc/docker/daemon.json"
    local PROXY_CONF_DIR="/etc/systemd/system/docker.service.d"
    local CONFIG_CHANGED=0

    echo -e "\n${CYAN}--- 配置 Docker 镜像加速与 systemd 代理 ---${NC}"

    mkdir -p "$(dirname "$DAEMON_JSON")"
    
    if [ ! -f "$DAEMON_JSON" ] || ! grep -q "registry-mirrors" "$DAEMON_JSON"; then
        CONFIG_CHANGED=1
        MIRRORS_JSON='"registry-mirrors": ["https://docker.woskee.nyc.mn", "https://docker.luxxk.dpdns.org", "https://docker.woskee.dpdns.org", "https://docker.wosken.dpdns.org"]'
        if [ -f "$DAEMON_JSON" ]; then
            sed -i 's/}$/,\n  '"$MIRRORS_JSON"'\n}/' "$DAEMON_JSON"
        else
            echo -e "{\n  $MIRRORS_JSON\n}" > "$DAEMON_JSON"
        fi
        echo -e "${GREEN}镜像加速器已配置到 $DAEMON_JSON${NC}"
    else
        echo -e "${YELLOW}检测到已存在的镜像加速配置，跳过。${NC}"
    fi

    if [ "$OS" != "alpine" ]; then
        if [ ! -f "$PROXY_CONF_DIR/http-proxy.conf" ]; then
            CONFIG_CHANGED=1
            mkdir -p "$PROXY_CONF_DIR"
            cat > "$PROXY_CONF_DIR/http-proxy.conf" <<EOF
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:7890"
Environment="HTTPS_PROXY=http://127.0.0.1:7890"
Environment="NO_PROXY=localhost,127.0.0.1,docker.1ms.run,.nyc,.dpdns.org"
EOF
            echo -e "${GREEN}systemd 代理配置已写入。${NC}"
        else
            echo -e "${YELLOW}检测到已存在的 systemd 代理配置，跳过。${NC}"
        fi
    fi

    if [ "$CONFIG_CHANGED" -eq 1 ]; then
        echo -e "${YELLOW}正在应用配置并重启 Docker 服务...${NC}"
        if [ "$OS" = "alpine" ]; then
            service docker restart
        else
            systemctl daemon-reload && systemctl restart docker
        fi
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Docker 重启成功。${NC}"
        else
            echo -e "${RED}Docker 重启失败，请手动排查问题。${NC}"; return 1;
        fi
    else
        echo -e "${GREEN}Docker 配置无变化，无需重启。${NC}"
    fi
}

# 验证安装
verify_installation() {
    echo -e "\n${CYAN}--- 验证安装状态 ---${NC}"
    if pgrep dockerd > /dev/null; then
        echo -e "${GREEN}✔ Docker 进程正在运行${NC}"
    else
        echo -e "${RED}✖ Docker 进程未运行${NC}"
    fi

    if command -v docker-compose > /dev/null; then
        echo -e "${GREEN}✔ docker-compose 命令可用${NC}"
    else
        echo -e "${RED}✖ docker-compose 命令未找到${NC}"
    fi
}

# 从 docker info 获取并显示实时配置
show_config_info() {
    echo -e "${GREEN}\n=== Docker 实际运行配置 (来自 'docker info') ===${NC}"

    if ! command -v docker >/dev/null || ! docker info >/dev/null 2>&1; then
        echo -e "${RED}无法连接到 Docker 守护进程，无法获取配置信息。${NC}"
        echo -e "${YELLOW}请确保 Docker 服务正在运行。${NC}"
        return
    fi
    
    local DOCKER_INFO
    DOCKER_INFO=$(docker info)
    
    echo -e "${CYAN}镜像加速器 (Registry Mirrors):${NC}"
    local MIRRORS
    MIRRORS=$(echo "$DOCKER_INFO" | sed -n '/Registry Mirrors:/, /^[[:space:]]*$/{ /Registry Mirrors:/d; p }' | sed 's/^[ \t]*//')
    if [ -n "$MIRRORS" ]; then
        echo -e "${MIRRORS}"
    else
        echo -e "  未配置"
    fi

    echo -e "\n${CYAN}HTTP/HTTPS 代理:${NC}"
    local HTTP_PROXY HTTPS_PROXY NO_PROXY
    HTTP_PROXY=$(echo "$DOCKER_INFO" | grep -i 'HTTP Proxy:' | awk -F': ' '{print $2}')
    HTTPS_PROXY=$(echo "$DOCKER_INFO" | grep -i 'HTTPS Proxy:' | awk -F': ' '{print $2}')
    NO_PROXY=$(echo "$DOCKER_INFO" | grep -i 'No Proxy:' | awk -F': ' '{print $2}')

    echo -e "  HTTP Proxy:  ${HTTP_PROXY:-未配置}"
    echo -e "  HTTPS Proxy: ${HTTPS_PROXY:-未配置}"
    echo -e "  No Proxy:    ${NO_PROXY:-未配置}"
    
    echo -e "\n${CYAN}脚本级 GitHub 加速器:${NC}"
    echo -e "  ${GH_PROXY}"
}

# 主函数
main() {
    check_root
    detect_os
    install_dependencies
    install_docker
    install_docker_compose
    configure_docker_proxy_and_mirror
    verify_installation
    show_config_info
    
    echo -e "\n${BLUE}安装与配置流程结束。${NC}"
}

# 执行主函数
main "$@"
