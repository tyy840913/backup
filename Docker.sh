#!/bin/bash

##############################################
# Docker 自动安装配置脚本
# 功能：自动检测系统类型 → 安装Docker → 配置镜像加速 → 设置开机启动
# 支持系统：Alpine/Debian/RedHat 及其衍生版本
# 作者：您的名字
# 版本：v1.2
##############################################

# ██████ 配置区域 ██████████████████████
# 镜像加速器列表（JSON数组格式，可自行增减）
REGISTRY_MIRRORS='[
  "https://docker.1panel.top",
  "https://proxy.1panel.live",
  "https://docker.m.daocloud.io",
  "https://docker.woskee.dns.army",
  "https://docker.woskee.dynv6.net"
]'

# ██████ 功能函数 ███████████████████████

# 检测操作系统类型
detect_os() {
    echo "== 正在检测系统类型..."
    if [ -f /etc/alpine-release ]; then
        echo "检测到 Alpine Linux 系统"
        echo "alpine"
    elif [ -f /etc/debian_version ]; then
        echo "检测到 Debian/Ubuntu 系统"
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "检测到 RedHat/CentOS 系统"
        echo "redhat"
    else
        echo "错误：不支持的操作系统！"
        exit 1
    fi
}

# 检查已安装的组件
check_installed() {
    echo "== 检查已安装组件..."
    
    # 检查Docker
    if command -v docker &> /dev/null; then
        echo "[√] Docker 已安装 - 版本：$(docker --version | awk '{print $3}' | tr -d ',')"
        DOCKER_INSTALLED=true
    else
        echo "[×] Docker 未安装"
        DOCKER_INSTALLED=false
    fi
    
    # 检查Docker Compose
    if command -v docker-compose &> /dev/null; then
        echo "[√] Docker Compose 已安装 - 版本：$(docker-compose --version | awk '{print $3}' | tr -d ',')"
        COMPOSE_INSTALLED=true
    elif docker compose version &> /dev/null; then
        echo "[√] Docker Compose (插件版) 已安装 - 版本：$(docker compose version | awk '/version/{print $3}')"
        COMPOSE_INSTALLED=true
    else
        echo "[×] Docker Compose 未安装"
        COMPOSE_INSTALLED=false
    fi
}

# 卸载旧版本
uninstall() {
    local os_type=$1
    echo "== 开始卸载旧版本..."
    
    case $os_type in
        debian)
            echo "停止 Docker 服务..."
            systemctl stop docker 2>/dev/null
            echo "卸载 Debian 系软件包..."
            apt-get -y remove docker docker-engine docker.io containerd runc
            apt-get -y purge docker-ce docker-ce-cli containerd.io
            ;;

        redhat)
            echo "停止 Docker 服务..."
            systemctl stop docker 2>/dev/null
            echo "卸载 RedHat 系软件包..."
            yum -y remove docker-ce docker-ce-cli containerd.io
            ;;

        alpine)
            echo "停止 Docker 服务..."
            service docker stop 2>/dev/null
            echo "卸载 Alpine 软件包..."
            apk del docker docker-cli docker-compose
            ;;
    esac

    # 清理残留文件
    echo "清理残留文件..."
    rm -rf /var/lib/docker \
           /etc/docker \
           /usr/local/bin/docker-compose \
           /usr/local/bin/docker-compose-plugin

    echo "卸载完成！"
}

# 安装 Docker
install() {
    local os_type=$1
    echo "== 开始安装 Docker..."
    
    case $os_type in
        debian)
            echo "更新软件源..."
            apt-get update
            echo "安装 Docker 官方包..."
            apt-get -y install docker.io docker-compose-plugin
            ;;

        redhat)
            echo "安装必要工具..."
            yum install -y yum-utils
            echo "启用软件仓库..."
            yum-config-manager --enable extras
            echo "安装 Docker 软件包..."
            yum install -y docker docker-compose-plugin
            ;;

        alpine)
            echo "更新软件源..."
            apk update
            echo "安装 Docker 全家桶..."
            apk add docker docker-compose
            ;;
    esac

    # 验证安装结果
    echo "验证安装..."
    if ! command -v docker &> /dev/null; then
        echo "错误：Docker 安装失败！" >&2
        exit 1
    fi
    echo "[√] Docker 安装成功 - 版本：$(docker --version)"
}

# 配置镜像加速
configure_mirror() {
    local os_type=$1
    echo "== 配置镜像加速..."
    
    # 创建配置目录
    mkdir -p /etc/docker

    # 生成配置文件
    echo "生成配置文件 /etc/docker/daemon.json"
    cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": $REGISTRY_MIRRORS,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  }
}
EOF

    # 重启服务使配置生效
    echo "重启 Docker 服务..."
    case $os_type in
        debian|redhat)
            systemctl restart docker
            ;;
        alpine)
            service docker restart
            ;;
    esac

    echo "[√] 镜像加速配置完成"
}

# 设置开机启动
enable_autostart() {
    local os_type=$1
    echo "== 设置开机启动..."
    
    case $os_type in
        debian|redhat)
            if ! systemctl is-enabled docker &> /dev/null; then
                systemctl enable docker
            fi
            ;;
        alpine)
            if ! rc-update show | grep -q docker; then
                rc-update add docker boot
            fi
            ;;
    esac
    echo "[√] 开机启动设置完成"
}

# ██████ 主程序 ███████████████████████

main() {
    echo "██████ Docker 自动安装脚本 █████████"
    
    # 步骤1：检测系统类型
    local os_type
    os_type=$(detect_os)
    
    # 步骤2：检查已安装组件
    check_installed
    
    # 步骤3：处理已安装情况
    if $DOCKER_INSTALLED || $COMPOSE_INSTALLED; then
        echo "检测到已安装的 Docker 组件"
        read -p "是否重新安装？(y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            uninstall "$os_type"
        else
            echo "安装已取消"
            exit 0
        fi
    fi

    # 步骤4：安装 Docker
    install "$os_type"
    
    # 步骤5：设置开机启动
    enable_autostart "$os_type"
    
    # 步骤6：配置镜像加速
    configure_mirror "$os_type"

    # 步骤7：显示最终状态
    echo "██████ 安装完成 ███████████████"
    echo "Docker 版本：$(docker --version)"
    echo "Docker Compose 版本：$(docker compose version)"
    echo "镜像加速配置："
    docker info | grep -A 10 "Registry Mirrors"
}

# 启动主程序
main
