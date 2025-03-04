#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 延时函数
sleepy() {
    echo -e "${BLUE}[INFO]${NC} 等待0.5秒..."
    sleep 0.5
}

# 检测系统类型
detect_os() {
    if [ -f /etc/alpine-release ]; then
        OS="alpine"
    elif [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        echo -e "${RED}[ERROR]${NC} 无法检测操作系统类型"
        exit 1
    fi
}

# 权限检测和sudo处理
check_sudo() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${YELLOW}[WARN]${NC} 需要root权限，将使用sudo"
        SUDO="sudo"
    else
        SUDO=""
    fi
}

# Docker安装
install_docker() {
    case $OS in
        alpine)
            $SUDO apk add --no-cache docker docker-cli docker-compose
            ;;
        debian|ubuntu)
            $SUDO apt-get update
            $SUDO apt-get install -y docker.io docker-compose
            ;;
        centos|rhel|fedora)
            if [ "$OS" = "fedora" ]; then
                $SUDO dnf -y install dnf-plugins-core
                $SUDO dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
                $SUDO dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
            else
                $SUDO yum install -y yum-utils
                $SUDO yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                $SUDO yum -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
            fi
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} 不支持的发行版: $OS"
            exit 1
            ;;
    esac
}

# Docker Compose安装
install_docker_compose() {
    if ! command -v docker-compose &> /dev/null; then
        $SUDO curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
        $SUDO chmod +x /usr/local/bin/docker-compose
    fi
}

# 卸载Docker
uninstall_docker() {
    case $OS in
        alpine)
            $SUDO apk del docker docker-cli docker-compose
            ;;
        debian|ubuntu)
            $SUDO apt-get purge -y docker.io docker-compose
            ;;
        centos|rhel|fedora)
            $SUDO yum remove -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
    esac
    $SUDO rm -rf /var/lib/docker /etc/docker
}

# 设置镜像加速
configure_mirror() {
    DAEMON_JSON="/etc/docker/daemon.json"
    MIRRORS=(
        "https://proxy.1panel.live"
        "https://docker.1panel.top"
        "https://docker.m.daocloud.io"
        "https://docker.woskee.dns.army"
        "https://docker.woskee.dynv6.net"
    )

    if [ -f $DAEMON_JSON ]; then
        echo -e "${YELLOW}[WARN]${NC} 已存在docker配置文件:"
        cat $DAEMON_JSON
        read -p "是否要替换配置文件？[y/N]: " choice
        if [[ $choice =~ ^[Yy]$ ]]; then
            $SUDO rm $DAEMON_JSON
        else
            return
        fi
    fi

    echo -e "${BLUE}[INFO]${NC} 创建新的镜像加速配置"
    $SUDO mkdir -p /etc/docker
    $SUDO tee $DAEMON_JSON > /dev/null <<EOF
{
  "registry-mirrors": [
EOF

    for mirror in "${MIRRORS[@]}"; do
        $SUDO tee -a $DAEMON_JSON > /dev/null <<EOF
    "$mirror",
EOF
    done

    $SUDO sed -i '$ s/,$//' $DAEMON_JSON  # 删除最后一个逗号
    $SUDO tee -a $DAEMON_JSON > /dev/null <<EOF
  ]
}
EOF
}

# 设置开机启动
enable_service() {
    case $OS in
        alpine)
            $SUDO rc-update add docker default
            $SUDO service docker start
            ;;
        *)
            $SUDO systemctl enable --now docker
            ;;
    esac
}

# 主流程
main() {
    echo -e "${GREEN}[START]${NC} 开始安装Docker环境..."
    sleepy

    # 系统检测
    detect_os
    echo -e "${BLUE}[INFO]${NC} 检测到操作系统: $OS"
    sleepy

    # 权限检查
    check_sudo

    # Docker安装检查
    if command -v docker &> /dev/null; then
        echo -e "${YELLOW}[WARN]${NC} 检测到已安装Docker:"
        docker --version
        read -p "是否要重新安装？[y/N]: " choice
        if [[ $choice =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}[INFO]${NC} 开始卸载旧版本..."
            uninstall_docker
            sleepy
        else
            echo -e "${BLUE}[INFO]${NC} 跳过Docker安装"
        fi
    else
        read -p "是否要安装Docker？[Y/n]: " choice
        if [[ ! $choice =~ ^[Nn]$ ]]; then
            echo -e "${BLUE}[INFO]${NC} 开始安装Docker..."
            install_docker
            sleepy
        else
            echo -e "${RED}[ERROR]${NC} 用户取消安装"
            exit 0
        fi
    fi

    # Docker Compose检查
    if ! command -v docker-compose &> /dev/null; then
        read -p "是否要安装Docker Compose？[Y/n]: " choice
        if [[ ! $choice =~ ^[Nn]$ ]]; then
            install_docker_compose
        fi
    else
        echo -e "${YELLOW}[WARN]${NC} 检测到已安装Docker Compose:"
        docker-compose --version
        read -p "是否要重新安装？[y/N]: " choice
        if [[ $choice =~ ^[Yy]$ ]]; then
            install_docker_compose
        fi
    fi
    sleepy

    # 设置镜像加速
    echo -e "${BLUE}[INFO]${NC} 配置镜像加速..."
    configure_mirror
    sleepy

    # 设置开机启动
    echo -e "${BLUE}[INFO]${NC} 设置开机启动..."
    enable_service
    sleepy

    # 重启Docker
    echo -e "${BLUE}[INFO]${NC} 重启Docker服务..."
    case $OS in
        alpine) $SUDO service docker restart ;;
        *) $SUDO systemctl restart docker ;;
    esac

    # 验证安装
    echo -e "${GREEN}[RESULT]${NC} 安装完成，版本信息："
    docker --version
    docker-compose --version
}

# 执行主函数
main
