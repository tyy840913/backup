#!/bin/bash

# 定义镜像加速源（可自行替换）
REGISTRY_MIRRORS='[
"https://docker.1panel.top",
"https://proxy.1panel.live",
"https://docker.m.daocloud.io",
"https://docker.woskee.dns.army",
"https://docker.woskee.dynv6.net"
]'

# 检测系统类型
detect_os() {
    if [ -f /etc/alpine-release ]; then
        echo "alpine"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "redhat"
    else
        echo "unsupported"
        exit 1
    fi
}

# 检查安装状态
check_installed() {
    local os_type=$1
    echo "=== 当前安装状态检查 ==="
    
    # 检查Docker
    if command -v docker &> /dev/null; then
        echo "[Docker] 已安装版本: $(docker --version | awk '{print $3}' | tr -d ',')"
        DOCKER_INSTALLED=true
    else
        DOCKER_INSTALLED=false
    fi
    
    # 检查Docker Compose
    if command -v docker-compose &> /dev/null; then
        echo "[Docker Compose] 已安装版本: $(docker-compose --version | awk '{print $3}' | tr -d ',')"
        COMPOSE_INSTALLED=true
    else
        # 检查插件版compose
        if docker compose version &> /dev/null; then
            echo "[Docker Compose] 已集成版本: $(docker compose version | awk '/version/{print $3}')"
            COMPOSE_INSTALLED=true
        else
            COMPOSE_INSTALLED=false
        fi
    fi
}

# 卸载现有版本
uninstall() {
    local os_type=$1
    echo "=== 开始卸载现有版本 ==="
    
    case $os_type in
        debian)
            apt-get -y remove docker docker-engine docker.io containerd runc
            apt-get -y purge docker-ce docker-ce-cli containerd.io
            rm -rf /var/lib/docker /etc/docker
            ;;
        redhat)
            yum -y remove docker-ce docker-ce-cli containerd.io
            rm -rf /var/lib/docker /etc/docker
            ;;
        alpine)
            apk del docker docker-cli docker-compose
            rm -rf /var/lib/docker /etc/docker
            ;;
    esac
    
    # 删除docker-compose独立安装
    rm -f /usr/local/bin/docker-compose
    echo "卸载完成"
}

# 安装流程
install() {
    local os_type=$1
    echo "=== 开始安装流程 ==="
    
    case $os_type in
        debian)
            apt-get update
            apt-get -y install docker.io docker-compose-plugin
            ;;
        redhat)
            yum install -y yum-utils
            yum-config-manager --enable extras
            yum install -y docker docker-compose-plugin
            ;;
        alpine)
            apk update
            apk add docker docker-compose
            rc-update add docker boot
            service docker start
            ;;
    esac
    
    # 验证安装
    if ! command -v docker &> /dev/null; then
        echo "Docker安装失败!" >&2
        exit 1
    fi
    echo "Docker安装成功: $(docker --version)"
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        echo "Docker Compose安装失败!" >&2
        exit 1
    fi
    echo "Docker Compose安装成功"
}

# 配置镜像加速
configure_mirror() {
    echo "=== 配置镜像加速 ==="
    DOCKER_DIR=/etc/docker
    CONFIG_FILE=$DOCKER_DIR/daemon.json
    
    mkdir -p $DOCKER_DIR
    echo "{
  \"registry-mirrors\": $REGISTRY_MIRRORS,
  \"log-driver\": \"json-file\",
  \"log-opts\": {
    \"max-size\": \"100m\"
  }
}" | tee $CONFIG_FILE > /dev/null
    
    systemctl restart docker
    echo "镜像加速配置完成"
}

# 设置开机自启
enable_autostart() {
    local os_type=$1
    echo "=== 设置开机自启 ==="
    
    case $os_type in
        debian|redhat)
            if ! systemctl is-enabled docker &> /dev/null; then
                systemctl enable docker
                systemctl restart docker
            fi
            ;;
        alpine)
            if ! rc-update show | grep -q docker; then
                rc-update add docker boot
                service docker restart
            fi
            ;;
    esac
    echo "开机自启已设置"
}

# 主流程
main() {
    OS_TYPE=$(detect_os)
    echo "检测到系统类型: $OS_TYPE"
    
    check_installed $OS_TYPE
    
    if $DOCKER_INSTALLED || $COMPOSE_INSTALLED; then
        read -p "检测到已安装版本，是否重新安装？(y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            uninstall $OS_TYPE
        else
            exit 0
        fi
    fi
    
    install $OS_TYPE
    enable_autostart $OS_TYPE
    configure_mirror
    
    echo "=== 安装完成 ==="
    docker --version
    docker compose version
}

main "$@"
