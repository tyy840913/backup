#!/bin/bash

# 美化输出函数
color_echo() {
    case $1 in
        red)    echo -e "\033[31m$2\033[0m" ;;
        green)  echo -e "\033[32m$2\033[0m" ;;
        yellow) echo -e "\033[33m$2\033[0m" ;;
        blue)   echo -e "\033[34m$2\033[0m" ;;
        *)      echo "$2" ;;
    esac
}

# 获取系统信息
get_os_info() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/alpine-release ]; then
        OS_ID="alpine"
        OS_VERSION=$(cat /etc/alpine-release | cut -d'.' -f1-2)
    else
        color_echo red "无法检测操作系统"
        exit 1
    fi
}

# 安装Docker
install_docker() {
    color_echo blue "正在安装Docker..."
    
    case $OS_ID in
        debian|ubuntu)
            apt install -y $DOCKER_PKG
            systemctl enable --now docker
            ;;
        centos|rhel|fedora)
            if [ $OS_ID = "fedora" ]; then
                dnf install -y $DOCKER_PKG
            else
                yum install -y $DOCKER_PKG
            fi
            systemctl enable --now docker
            ;;
        alpine)
            apk add docker
            rc-update add docker boot
            service docker start
            ;;
        *)
            color_echo red "不支持的发行版"
            exit 1
            ;;
    esac
}

# 安装Docker Compose
install_compose() {
    color_echo blue "正在安装Docker Compose..."
    local mirror_url="https://mirrors.aliyun.com/docker-toolbox/linux/compose/v$COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)"
    curl -L $mirror_url -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
}

# 配置镜像加速
config_mirror() {
    local config_file="/etc/docker/daemon.json"
    
    if [ ! -s $config_file ]; then
        color_echo yellow "创建镜像加速配置文件..."
        tee $config_file << EOF
{
"registry-mirrors":[
"https://docker.1panel.top",
"https://proxy.1panel.live",
"https://docker.m.daocloud.io",
"https://docker.woskee.dns.army",
"https://docker.woskee.dynv6.net"
]
}
EOF
        systemctl restart docker
    else
        color_echo yellow "已存在镜像加速配置文件："
        cat $config_file
        read -p "是否覆盖？[y/N]: " overwrite
        if [[ $overwrite =~ [Yy] ]]; then
            tee $config_file << EOF
{
"registry-mirrors":[
"https://docker.1panel.top",
"https://proxy.1panel.live",
"https://docker.m.daocloud.io",
"https://docker.woskee.dns.army",
"https://docker.woskee.dynv6.net"
]
}
EOF
            systemctl restart docker
        fi
    fi
}

# 主流程
main() {
    # 获取系统信息
    get_os_info
    color_echo green "检测到系统：$OS_ID $OS_VERSION"

    # 设置包名
    case $OS_ID in
        debian|ubuntu) DOCKER_PKG="docker.io" ;;
        centos|rhel)   DOCKER_PKG="docker-ce" ;;
        fedora)        DOCKER_PKG="docker-ce" ;;
        alpine)        DOCKER_PKG="docker" ;;
    esac

    # 检查Docker
    if ! command -v docker &> /dev/null; then
        color_echo yellow "未检测到Docker"
        read -p "是否安装Docker？[Y/n]: " confirm
        if [[ ! $confirm =~ [Nn] ]]; then
            install_docker
        fi
    else
        color_echo green "Docker 已安装：$(docker --version)"
    fi

    # 检查Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        color_echo yellow "未检测到Docker Compose"
        read -p "是否安装Docker Compose？[Y/n]: " confirm
        if [[ ! $confirm =~ [Nn] ]]; then
            COMPOSE_VERSION=$(curl -s https://mirrors.aliyun.com/docker-toolbox/linux/compose/latest | grep -oP 'v\d+\.\d+\.\d+')
            install_compose
        fi
    else
        color_echo green "Docker Compose 已安装：$(docker-compose --version)"
    fi

    # 配置镜像加速
    config_mirror

    color_echo green "\n安装完成！"
    color_echo blue "Docker状态：$(systemctl is-active docker)"
    color_echo blue "镜像配置："
    docker info | grep -A1 "Registry Mirrors"
}

# 执行主函数
main
