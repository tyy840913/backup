#!/bin/bash

# =========================================================================
# Docker & Docker Compose 智能安装/更新脚本 (v3.1 最终定制版)
#
# 特性:
# - 使用用户指定的代理源进行下载，确保网络访问性。
# - 跨平台兼容 (Debian/Ubuntu, CentOS/RHEL/Fedora, Alpine)。
# - 自动检查并安装 curl, gpg, jq 等核心依赖。
# - 智能检测更新，并提示用户进行相应操作。
# - 自动配置用户指定的镜像加速，并提供交互式选项。
# =========================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 全局变量
LATEST_DOCKER_VERSION=""
LATEST_COMPOSE_VERSION=""
OS=""
CODENAME=""

# 代理路由URL
PROXY_ROUTE_URL="https://route.woskee.nyc.mn/"

# 根据终端代理设置获取最终下载URL
get_download_url() {
    local original_url="$1"
    # 检查 http_proxy 或 https_proxy 环境变量是否设置
    if [[ -z "$http_proxy" && -z "$https_proxy" ]]; then
        echo "${PROXY_ROUTE_URL}${original_url}"
    else
        echo "${original_url}"
    fi
}

# --- 功能函数 ---

detect_os() {
    if [ -f /etc/os-release ]; then
        OS=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
        CODENAME=$(grep 'VERSION_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
    elif [ -f /etc/alpine-release ]; then
        OS="alpine"; CODENAME=$(cat /etc/alpine-release | cut -d'.' -f1-2);
    else
        echo -e "${RED}错误：无法检测操作系统${NC}"; exit 1;
    fi
}

check_dependencies() {
    local missing=()
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    if [ "$OS" != "alpine" ]; then
        command -v gpg >/dev/null 2>&1 || { case $OS in "ubuntu"|"debian") missing+=("gnupg");; "centos"|"rhel"|"fedora") missing+=("gnupg2");; esac; };
    fi
    command -v jq >/dev/null 2>&1 || missing+=("jq")
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${YELLOW}正在安装缺失的依赖: ${missing[*]}${NC}"
        case $OS in
            "ubuntu"|"debian") apt-get update && apt-get install -y "${missing[@]}";;
            "centos"|"rhel"|"fedora") yum install -y "${missing[@]}";;
            "alpine") apk add --no-cache "${missing[@]}";;
        esac
    fi
}

get_latest_versions() {
    echo -e "${BLUE}正在从软件源检查最新可用版本...${NC}"
    case $OS in
        "ubuntu"|"debian") LATEST_DOCKER_VERSION=$(apt-cache madison docker-ce | awk '{print $3}' | head -n 1 | cut -d':' -f2);;
        "centos"|"rhel"|"fedora") LATEST_DOCKER_VERSION=$(yum --showduplicates list docker-ce | grep 'docker-ce' | awk '{print $2}' | tail -n 1 | cut -d':' -f2);;
    esac
    ### 修正：恢复您指定的代理API地址 ###
    local github_api_url="https://api.github.com/repos/docker/compose/releases/latest"
    local final_github_api_url=$(get_download_url "$github_api_url")
    LATEST_COMPOSE_VERSION=$(curl -s "$final_github_api_url" | jq -r .tag_name)
}

# 返回值: 0=最新, 1=未安装, 2=可更新
check_docker() {
    if ! command -v docker &>/dev/null; then return 1; fi
    local installed_version=$(docker --version | awk '{print $3}' | tr -d ',')
    echo -e "${GREEN}检测到已安装 Docker 版本: $installed_version${NC}"
    if [[ -n "$LATEST_DOCKER_VERSION" && "$installed_version" != "$LATEST_DOCKER_VERSION" ]]; then
        echo -e "${YELLOW}发现新版本! 最新可用版本为: $LATEST_DOCKER_VERSION${NC}"; return 2;
    fi
    return 0
}

# 返回值: 0=最新, 1=未安装, 2=可更新
check_compose() {
    if ! command -v docker-compose &>/dev/null; then return 1; fi
    local installed_version=$(docker-compose --version | awk '{print $3}' | tr -d ',')
    echo -e "${GREEN}检测到已安装 Docker Compose 版本: $installed_version${NC}"
    if [[ -n "$LATEST_COMPOSE_VERSION" && "$installed_version" != "$LATEST_COMPOSE_VERSION" ]]; then
        echo -e "${YELLOW}发现新版本! 最新可用版本为: $LATEST_COMPOSE_VERSION${NC}"; return 2;
    fi
    return 0
}

### 修正1：恢复您指定的代理下载地址 ###
install_or_update_docker() {
    echo -e "${CYAN}--- 开始安装/更新 Docker ---${NC}"
    case $OS in
        "ubuntu"|"debian")
            [ "$OS" = "ubuntu" ] && [ "$CODENAME" = "lunar" ] && CODENAME="jammy"
            apt-get install -y ca-certificates
            install -m 0755 -d /etc/apt/keyrings
            local docker_gpg_url="https://download.docker.com/linux/$OS/gpg"
            local final_docker_gpg_url=$(get_download_url "$docker_gpg_url")
            curl -fsSL "$final_docker_gpg_url" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
            local docker_repo_url="https://download.docker.com/linux/$OS"
            local final_docker_repo_url=$(get_download_url "$docker_repo_url")
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] $final_docker_repo_url $CODENAME stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
            ;;
        "centos"|"rhel"|"fedora")
            yum install -y yum-utils
            local docker_ce_repo_url="https://download.docker.com/linux/centos/docker-ce.repo"
            local final_docker_ce_repo_url=$(get_download_url "$docker_ce_repo_url")
            yum-config-manager --add-repo "$final_docker_ce_repo_url"
            yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
            ;;
        "alpine")
            apk update && apk add --no-cache docker docker-openrc
            ;;
    esac
    if [ "$OS" = "alpine" ]; then rc-update add docker default && service docker start; else systemctl enable --now docker; fi
}

### 修正1：恢复您指定的代理下载地址 ###
install_or_update_compose() {
    echo -e "${CYAN}--- 开始安装/更新 Docker Compose (版本: ${LATEST_COMPOSE_VERSION}) ---${NC}"
    case $OS in
        "alpine") apk add --no-cache docker-compose ;;
        *)
            local original_binary_url="https://github.com/docker/compose/releases/download/${LATEST_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)"
            local binary_url=$(get_download_url "$original_binary_url")
            local temp_file; temp_file=$(mktemp)
            echo "正在从 $binary_url 下载..."
            if ! curl -L "$binary_url" -o "$temp_file"; then echo -e "${RED}错误：下载失败${NC}"; rm -f "$temp_file"; return 1; fi
            if [ ! -s "$temp_file" ]; then echo -e "${RED}错误：下载的文件为空${NC}"; rm -f "$temp_file"; return 1; fi
            install -m 755 "$temp_file" /usr/local/bin/docker-compose
            ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
            rm -f "$temp_file"
            ;;
    esac
}

### 修正2：恢复您指定的镜像加速源 ###
configure_mirror() {
    local DAEMON_JSON="/etc/docker/daemon.json"

    echo -e "\n${CYAN}--- Docker 代理配置 ---${NC}"
    mkdir -p "$(dirname "$DAEMON_JSON")"
    
    if [ -f "$DAEMON_JSON" ]; then
        echo -e "${GREEN}发现现有配置文件: $DAEMON_JSON${NC}"
        read -p "是否要使用推荐的代理配置覆盖现有配置？(y/N): " replace_choice
        if [[ ! "$replace_choice" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}已跳过 Docker 代理配置。${NC}"; return;
        fi
    fi

    echo -e "${YELLOW}正在写入新的 Docker 代理配置...${NC}"
    # 注意：这里移除了 MIRRORS 数组和相关的 jq 逻辑，直接写入代理配置
    if ! jq -n '{ "http-proxy": "http://127.0.0.1:7890", "https-proxy": "http://127.0.0.1:7890", "no-proxy": "localhost,127.0.0.1" }' > "$DAEMON_JSON"; then
        echo -e "${RED}错误：生成配置文件失败！${NC}"; return 1;
    fi

    echo -e "${GREEN}配置写入成功，内容如下:${NC}"
    jq . "$DAEMON_JSON"
    
    echo -e "\n${YELLOW}正在重启 Docker 服务以应用配置...${NC}"
    if systemctl restart docker; then
        echo -e "${GREEN}Docker 服务重启成功。${NC}";
    else
        echo -e "${RED}Docker 服务重启失败，请手动检查: systemctl status docker${NC}"; return 1;
    fi
}

# --- 主逻辑 ---
main() {
    if [ "$(id -u)" -ne 0 ]; then echo -e "${RED}请使用 sudo 或 root 用户运行此脚本${NC}"; exit 1; fi

    detect_os
    check_dependencies
    
    case $OS in
        "ubuntu"|"debian") apt-get update > /dev/null;;
        "centos"|"rhel"|"fedora") yum makecache > /dev/null;;
    esac
    get_latest_versions

    echo -e "\n${CYAN}================ Docker =================${NC}"
    check_docker; docker_status=$?
    case $docker_status in
        0) echo -e "${GREEN}Docker 已是最新版本，无需操作。${NC}";;
        1) read -p "未检测到 Docker，是否立即安装？(Y/n): " c; if [[ "$c" =~ ^[Yy]?$ ]]; then install_or_update_docker; else echo -e "${BLUE}已跳过 Docker 安装。${NC}"; fi;;
        2) read -p "检测到 Docker 新版本，是否立即更新？(Y/n): " c; if [[ "$c" =~ ^[Yy]?$ ]]; then install_or_update_docker; else echo -e "${BLUE}已跳过 Docker 更新。${NC}"; fi;;
    esac

    echo -e "\n${CYAN}============ Docker Compose ============${NC}"
    check_compose; compose_status=$?
    case $compose_status in
        0) echo -e "${GREEN}Docker Compose 已是最新版本，无需操作。${NC}";;
        1) read -p "未检测到 Docker Compose，是否立即安装？(Y/n): " c; if [[ "$c" =~ ^[Yy]?$ ]]; then install_or_update_compose; else echo -e "${BLUE}已跳过 Compose 安装。${NC}"; fi;;
        2) read -p "检测到 Docker Compose 新版本，是否立即更新？(Y/n): " c; if [[ "$c" =~ ^[Yy]?$ ]]; then install_or_update_compose; else echo -e "${BLUE}已跳过 Compose 更新。${NC}"; fi;;
    esac

    if command -v docker &>/dev/null; then
        configure_mirror
        echo -e "\n${CYAN}============== 最终验证 ==============${NC}"
        echo -e "${GREEN}Docker 版本: $(docker --version 2>/dev/null || echo '未安装')${NC}"
        if systemctl is-active --quiet docker; then
            echo -e "Docker 服务: ${GREEN}运行中${NC}"
            if docker info 2>/dev/null | grep -q "Registry Mirrors"; then echo -e "镜像加速: ${GREEN}已配置${NC}"; else echo -e "镜像加速: ${YELLOW}未在 docker info 中检测到${NC}"; fi
            if docker info 2>/dev/null | grep -q -E "HTTP Proxy:|HTTPS Proxy:"; then echo -e "Docker 代理: ${GREEN}已配置${NC}"; else echo -e "Docker 代理: ${YELLOW}未在 docker info 中检测到${NC}"; fi
        else
            echo -e "Docker 服务: ${RED}未运行${NC}"
        fi
    fi

    echo -e "${GREEN}Docker Compose 版本: $(docker-compose --version 2>/dev/null || echo '未安装')${NC}"
    echo -e "\n${GREEN}脚本执行完毕。${NC}"
}

# 脚本入口
main "$@"
