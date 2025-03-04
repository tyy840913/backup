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
        OS=$(grep -oP '^ID=\K\w+' /etc/os-release)
        CODENAME=$(grep -oP 'VERSION_CODENAME=\K\w+' /etc/os-release)
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
            # 处理Ubuntu的codename特殊情况
            [ "$OS" = "ubuntu" ] && [ "$CODENAME" = "lunar" ] && CODENAME="jammy"
            
            # 安装依赖
            apt-get update
            apt-get install -y ca-certificates curl gnupg

            # 添加Docker官方GPG密钥
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg

            # 设置仓库
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/$OS $CODENAME stable" | \
tee /etc/apt/sources.list.d/docker.list > /dev/null

            # 安装Docker
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

    # 启动服务
    if [ "$OS" != "alpine" ]; then
        systemctl enable --now docker 2>/dev/null
    fi
}

# 安装Docker Compose
install_compose() {
    echo -e "${CYAN}开始安装Docker Compose...${NC}"
    case $OS in
        "alpine")
            apk add --no-cache docker-compose ;;
        *)
            # 获取最新稳定版
            COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | cut -d'"' -f4)
            
            # 下载并安装
            curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
            ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose ;;
    esac
}

# 镜像加速配置
configure_mirror() {
    local DAEMON_JSON="/etc/docker/daemon.json"
    declare -A MIRRORS=(
        "https://proxy.1panel.live"

        "https://docker.1panel.top"

        "https://docker.m.daocloud.io"

        "https://docker.woskee.dns.army"

        "https://docker.woskee.dynv6.net"
)

    echo -e "\n${CYAN}请选择镜像加速源：${NC}"
    select key in "${!MIRRORS[@]}" "手动输入" "跳过"; do
        case $key in
            "手动输入")
                read -p "请输入镜像加速URL: " custom_url
                MIRROR_URL=$custom_url
                break ;;
            "跳过")
                return ;;
            *)
                [ -n "$key" ] && MIRROR_URL=${MIRRORS[$key]} && break ;;
        esac
    done

    echo -e "${YELLOW}配置镜像加速源: $MIRROR_URL${NC}"
    
    # 备份原有配置
    if [ -f $DAEMON_JSON ]; then
        cp $DAEMON_JSON ${DAEMON_JSON}.bak
        echo -e "${GREEN}已备份原配置文件至 ${DAEMON_JSON}.bak${NC}"
    fi

    # 创建或修改配置
    mkdir -p $(dirname $DAEMON_JSON)
    if [ -s $DAEMON_JSON ]; then
        # 使用jq修改现有配置
        if command -v jq &>/dev/null; then
            jq --arg url "$MIRROR_URL" '.registry-mirrors |= [(.registry-mirrors // [] | .[]), $url] | unique' $DAEMON_JSON > ${DAEMON_JSON}.tmp
            mv ${DAEMON_JSON}.tmp $DAEMON_JSON
        else
            echo -e "${YELLOW}检测到jq未安装，采用追加模式配置${NC}"
            sed -i "s/\"registry-mirrors\":.*/&, \"$MIRROR_URL\"/" $DAEMON_JSON
        fi
    else
        cat <<-EOF > $DAEMON_JSON
        {
            "registry-mirrors": ["$MIRROR_URL"]
        }
EOF
    fi

    # 重启服务
    if [ "$OS" = "alpine" ]; then
        service docker restart
    else
        systemctl restart docker
    fi
    echo -e "${GREEN}镜像加速配置完成${NC}"
}

# 主逻辑
main() {
    # 检查root权限
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
    if ! check_compose; then
        install_compose
    else
        echo -e "${BLUE}检测到Docker Compose已安装${NC}"
    fi

    # 配置镜像加速
    configure_mirror

    # 验证安装
    echo -e "\n${CYAN}=== 安装验证 ===${NC}"
    echo -e "${GREEN}Docker版本: $(docker --version 2>/dev/null || echo '未安装')${NC}"
    echo -e "${GREEN}Docker Compose版本: $(docker-compose --version 2>/dev/null || echo '未安装')${NC}"

    # 服务状态检查
    echo -e "\n${CYAN}=== 服务状态 ===${NC}"
    if [ "$OS" = "alpine" ]; then
        rc-status docker | grep -q started && echo -e "Docker状态: ${GREEN}运行中${NC}" || echo -e "Docker状态: ${RED}未运行${NC}"
    else
        systemctl is-active docker | grep -q active && echo -e "Docker状态: ${GREEN}运行中${NC}" || echo -e "Docker状态: ${RED}未运行${NC}"
    fi
}

main "$@"
