#!/bin/bash


# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 系统检测
detect_os() {
    if [ -f /etc/os-release ]; then
        OS=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
        CODENAME=$(grep 'VERSION_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '"')
    elif [ -f /etc/alpine-release ]; then
        OS="alpine"
        CODENAME=$(cat /etc/alpine-release | cut -d'.' -f1-2)
    else
        echo -e "${RED}无法检测操作系统${NC}"
        exit 1
    fi
}

# 依赖检查
check_dependencies() {
    local missing=()
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v gpg >/dev/null 2>&1 || {
        case $OS in
            "ubuntu"|"debian") missing+=("gnupg") ;;
            "centos"|"rhel"|"fedora") missing+=("gnupg2") ;;
            "alpine") missing+=("gnupg") ;;
        esac
    }
    command -v jq >/dev/null 2>&1 || missing+=("jq")

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
            apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
            rm -rf /var/lib/docker /etc/docker ;;
        "centos"|"rhel"|"fedora")
            yum remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
            rm -rf /var/lib/docker /etc/docker ;;
        "alpine")
            apk del docker-cli docker-engine docker-openrc docker-compose
            rm -rf /var/lib/docker /etc/docker ;;
    esac
    echo -e "${GREEN}Docker卸载完成${NC}"
}

# 安装Docker
install_docker() {
    echo -e "${CYAN}开始安装Docker...${NC}"
    case $OS in
        "ubuntu"|"debian")
            [ "$OS" = "ubuntu" ] && [ "$CODENAME" = "lunar" ] && CODENAME="jammy"
            
            apt-get update
            apt-get install -y ca-certificates curl gnupg

            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg

            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/$OS $CODENAME stable" | \
tee /etc/apt/sources.list.d/docker.list > /dev/null

            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin ;;

        "centos"|"rhel"|"fedora")
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin ;;

        "alpine")
            apk add --no-cache docker-cli docker-engine docker-openrc
            rc-update add docker default
            service docker start ;;
    esac

    if [ "$OS" = "alpine" ]; then
        rc-update add docker default
        service docker start
    else
        systemctl enable --now docker 2>/dev/null
    fi
}

# 安装Docker Compose（修复版）
install_compose() {
    echo -e "${CYAN}开始安装Docker Compose...${NC}"
    case $OS in
        "alpine")
            apk add --no-cache docker-compose ;;
        *)
            COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | cut -d'"' -f4)
            BINARY_URL="https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)"
            
            # 使用临时目录和install命令
            TEMP_DIR=$(mktemp -d)
            echo -e "${YELLOW}下载Docker Compose到临时目录: $TEMP_DIR${NC}"
            
            if ! curl -L "$BINARY_URL" -o "$TEMP_DIR/docker-compose"; then
                echo -e "${RED}错误：Docker Compose 下载失败${NC}"
                rm -rf "$TEMP_DIR"
                exit 1
            fi

            if [ ! -s "$TEMP_DIR/docker-compose" ]; then
                echo -e "${RED}错误：下载文件为空，请检查网络连接${NC}"
                rm -rf "$TEMP_DIR"
                exit 1
            fi

            echo -e "${GREEN}文件下载验证通过，正在安装...${NC}"
            install -v -D -m 755 "$TEMP_DIR/docker-compose" /usr/local/bin/docker-compose
            ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
            rm -rf "$TEMP_DIR"
            ;;
    esac
}

# 镜像加速配置（增强版）
configure_mirror() {
    local DAEMON_JSON="/etc/docker/daemon.json"
    declare -a MIRRORS=(
        "https://proxy.1panel.live"
        "https://docker.1panel.top"
        "https://docker.m.daocloud.io"
        "https://docker.woskee.dns.army"
        "https://docker.woskee.dynv6.net"
    )

    echo -e "\n${CYAN}=== 镜像加速配置 ===${NC}"
    
    # 确保目录存在
    if [ ! -d "$(dirname "$DAEMON_JSON")" ]; then
        echo -e "${YELLOW}创建docker配置目录: $(dirname "$DAEMON_JSON")${NC}"
        mkdir -pv "$(dirname "$DAEMON_JSON")"
    fi

    # 处理现有配置文件
    if [ -f "$DAEMON_JSON" ]; then
        echo -e "${GREEN}发现现有配置文件: $DAEMON_JSON${NC}"
        echo -e "${BLUE}当前配置内容：${NC}"
        jq . "$DAEMON_JSON" 2>/dev/null || cat "$DAEMON_JSON"
        
        read -p $'\n是否要替换现有配置？(y/N): ' replace_choice
        case "$replace_choice" in
            y|Y)
                # 备份原配置
                BACKUP_FILE="${DAEMON_JSON}.bak_$(date +%Y%m%d%H%M%S)"
                cp -v "$DAEMON_JSON" "$BACKUP_FILE"
                echo -e "${GREEN}已备份原配置到: $BACKUP_FILE${NC}" ;;
            *)
                echo -e "${BLUE}保留现有配置，跳过镜像加速设置${NC}"
                return ;;
        esac
    else
        echo -e "${YELLOW}创建新配置文件: $DAEMON_JSON${NC}"
        touch "$DAEMON_JSON"
    fi

    # 生成新配置
    NEW_CONFIG=$(jq -n --argjson mirrors "$(printf '%s\n' "${MIRRORS[@]}" | jq -R . | jq -s .)" \
        '{registry-mirrors: $mirrors}')

    # 写入配置
    echo "$NEW_CONFIG" | jq . > "$DAEMON_JSON"
    chmod 600 "$DAEMON_JSON"  # 设置安全权限
    
    echo -e "${GREEN}镜像加速配置已更新，应用以下镜像源：${NC}"
    jq '.registry-mirrors' "$DAEMON_JSON"

    # 重启服务
    echo -e "\n${YELLOW}正在重启Docker服务...${NC}"
    if [ "$OS" = "alpine" ]; then
        service docker restart
    else
        systemctl restart docker
    fi
}

# 主逻辑
main() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}请使用sudo或root用户运行此脚本${NC}"
        exit 1
    fi

    detect_os
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
    if check_compose; then
        read -p "检测到已安装Docker Compose，是否要重新安装？(y/N): " compose_choice
        case "$compose_choice" in
            y|Y)
                install_compose ;;
            *)
                echo -e "${BLUE}跳过Docker Compose安装${NC}" ;;
        esac
    else
        read -p "是否要安装Docker Compose？(Y/n): " compose_choice
        case "$compose_choice" in
            n|N)
                echo -e "${RED}跳过Docker Compose安装${NC}" ;;
            *)
                install_compose ;;
        esac
    fi

    # 强制配置镜像加速
    configure_mirror

    # 验证安装
    echo -e "\n${CYAN}=== 安装验证 ===${NC}"
    echo -e "${GREEN}Docker版本: $(docker --version 2>/dev/null || echo '未安装')${NC}"
    echo -e "${GREEN}Docker Compose版本: $(docker-compose --version 2>/dev/null || echo '未安装')${NC}"

    # 服务状态检查（双重验证）
    echo -e "\n${CYAN}=== 服务状态 ===${NC}"
    if [ "$OS" = "alpine" ]; then
        if rc-service docker status | grep -q started; then
            echo -e "服务检测: ${GREEN}运行中${NC}"
        else
            echo -e "服务检测: ${RED}未运行${NC}"
        fi
    else
        systemctl is-active docker | grep -q active && \
        echo -e "服务检测: ${GREEN}运行中${NC}" || \
        echo -e "服务检测: ${RED}未运行${NC}"
    fi

    # 进程级验证
    if docker ps >/dev/null 2>&1; then
        echo -e "进程验证: ${GREEN}Docker正在响应${NC}"
    else
        echo -e "进程验证: ${RED}Docker未响应${NC}"
    fi
}

main "$@"
