#!/bin/bash

# 镜像加速器列表（清理后的有效镜像地址）
MIRRORS=(
    "https://docker.woskee.nyc.mn",
    "https://docker.woskee.dns.army",
    "https://docker.woskee.dynv6.net",
    "https://proxy.1panel.live",
    "https://docker.1panel.top"
)

# 系统检测函数
detect_os() {
    if grep -iq "alpine" /etc/os-release 2>/dev/null || [ -f /etc/alpine-release ]; then
        echo "alpine"
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID" | tr '[:upper:]' '[:lower:]'
    else
        echo "unknown"
    fi
}

# Docker安装函数
install_docker() {
    case "$1" in
        alpine)
            if ! apk -q info docker &>/dev/null; then
                apk add --no-cache docker docker-compose openrc
                echo "Docker 安装完成"
            fi
            ;;
        debian|ubuntu|raspbian)
            if ! dpkg -l docker-ce &>/dev/null; then
                apt-get update
                apt-get install -y ca-certificates curl gnupg
                install -m 0755 -d /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/$1/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$1 $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
                apt-get update
                apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            fi
            ;;
        centos|rhel|fedora|ol)
            if ! rpm -q docker-ce &>/dev/null; then
                yum install -y yum-utils
                yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            fi
            ;;
        *)
            if ! command -v docker &>/dev/null; then
                curl -fsSL https://get.docker.com | sh
            fi
            ;;
    esac
}

# 智能服务管理
manage_service() {
    case "$1" in
        alpine)
            # 检查开机自启
            if ! rc-update show boot | grep -q docker; then
                echo "设置Docker开机自启"
                rc-update add docker boot
            fi
            
            # 检查服务状态
            if ! rc-service docker status &>/dev/null; then
                echo "启动Docker服务"
                rc-service docker start
            else
                echo "Docker 服务已在运行"
            fi
            ;;

        *)
            # 检查开机自启
            if ! systemctl is-enabled docker &>/dev/null; then
                echo "设置Docker开机自启"
                systemctl enable docker
            fi

            # 检查服务状态
            if ! systemctl is-active docker &>/dev/null; then
                echo "启动Docker服务"
                systemctl start docker
            else
                echo "Docker 服务已在运行"
            fi
            ;;
    esac
}

# 智能镜像配置
configure_registry() {
    CONFIG_DIR="/etc/docker"
    CONFIG_FILE="$CONFIG_DIR/daemon.json"
    
    # 创建配置目录
    mkdir -p "$CONFIG_DIR"
    
    # 安装jq
    if ! command -v jq &>/dev/null; then
        case "$OS_TYPE" in
            alpine) apk add --no-cache jq ;;
            debian|ubuntu) apt-get install -y jq ;;
            centos|rhel) yum install -y jq ;;
        esac
    fi

    # 生成临时配置
    CURRENT_CONFIG=$(jq '.' "$CONFIG_FILE" 2>/dev/null || jq -n '{}')
    NEW_CONFIG=$(echo "$CURRENT_CONFIG" | jq --argjson mirrors "$(printf '%s\n' "${MIRRORS[@]}" | jq -R . | jq -s .)" '
        ."registry-mirrors" = (
            (."registry-mirrors" // []) + $mirrors | unique
        )
    ')

    # 比较配置差异
    if ! diff <(echo "$CURRENT_CONFIG") <(echo "$NEW_CONFIG") &>/dev/null; then
        echo "更新镜像加速配置"
        echo "$NEW_CONFIG" > "$CONFIG_FILE.tmp"
        mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"

        # 智能服务重启
        case "$OS_TYPE" in
            alpine)
                if rc-service docker status &>/dev/null; then
                    echo "重启Docker服务应用新配置"
                    rc-service docker restart
                fi
                ;;
            *)
                if systemctl is-active docker &>/dev/null; then
                    echo "重启Docker服务应用新配置"
                    systemctl restart docker
                fi
                ;;
        esac
    else
        echo "镜像配置无需更新"
    fi
}

# 主执行流程
main() {
    OS_TYPE=$(detect_os)
    
    # 安装Docker
    if ! command -v docker &>/dev/null; then
        echo "正在安装Docker..."
        install_docker "$OS_TYPE"
    else
        echo "Docker 已安装"
    fi

    # 管理服务
    manage_service "$OS_TYPE"

    # 配置镜像加速
    configure_registry

    echo "安装完成！当前镜像源配置："
    jq -r '."registry-mirrors"[]' /etc/docker/daemon.json 2>/dev/null || echo "暂无镜像加速配置"
}

# 执行主程序
main "$@"
