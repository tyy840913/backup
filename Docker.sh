#!/bin/bash

# 交互式延时函数
delay() {
    sleep 0.5
}

# 检测系统发行版
detect_os() {
    echo "▌[系统检测] 正在识别操作系统..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    elif [ -f /etc/alpine-release ]; then
        OS=alpine
        VER=$(cat /etc/alpine-release)
    else
        echo "⚠ 错误：不支持的Linux发行版"
        exit 1
    fi
    delay
    echo "▌[系统检测] 识别到系统：$OS $VER"
}

# 设置发行版相关参数
set_dist_params() {
    case $OS in
        debian|ubuntu)
            PKG_MGR="apt-get"
            INSTALL_CMD="install -y"
            DOCKER_PKG="docker.io"
            COMPOSE_PKG="docker-compose"
            SRV_RESTART="systemctl restart docker"
            SRV_ENABLE="systemctl enable docker"
            CONF_DIR="/etc/docker"
            ;;
        centos|fedora|rhel)
            PKG_MGR="yum"
            INSTALL_CMD="install -y"
            DOCKER_PKG="docker-ce"
            COMPOSE_PKG="docker-compose"
            SRV_RESTART="systemctl restart docker"
            SRV_ENABLE="systemctl enable docker"
            CONF_DIR="/etc/docker"
            ;;
        alpine)
            PKG_MGR="apk"
            INSTALL_CMD="add"
            DOCKER_PKG="docker"
            COMPOSE_PKG="docker-compose"
            SRV_RESTART="service docker restart"
            SRV_ENABLE="rc-update add docker default"
            CONF_DIR="/etc/docker"
            ;;
        *)
            echo "⚠ 错误：不支持的发行版"
            exit 1
            ;;
    esac
    delay
}

# 检查已安装组件
check_installed() {
    echo "▌[环境检查] 正在检测已安装组件..."
    if command -v docker &> /dev/null; then
        DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
        echo "▌[环境检查] 已安装Docker版本：$DOCKER_VER"
    else
        DOCKER_VER="未安装"
    fi

    if command -v docker-compose &> /dev/null; then
        COMPOSE_VER=$(docker-compose --version | awk '{print $3}' | tr -d ',')
        echo "▌[环境检查] 已安装Docker Compose版本：$COMPOSE_VER"
    else
        COMPOSE_VER="未安装"
    fi
    delay
}

# 卸载现有组件
uninstall_docker() {
    echo "▌[卸载清理] 开始移除旧版本..."
    case $OS in
        debian|ubuntu)
            apt-get purge -y docker* containerd runc
            rm -rf /var/lib/docker
            ;;
        centos|fedora|rhel)
            yum remove -y docker* containerd.io
            rm -rf /var/lib/docker
            ;;
        alpine)
            apk del docker* containerd runc
            rm -rf /var/lib/docker
            ;;
    esac
    delay
    echo "▌[卸载清理] 旧版本组件已清理完成"
}

# 安装Docker核心
install_docker() {
    echo "▌[安装Docker] 正在配置安装源..."
    case $OS in
        debian|ubuntu)
            curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/$OS/gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture)] https://mirrors.aliyun.com/docker-ce/linux/$OS $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list
            apt-get update
            ;;
        centos|fedora)
            yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
            ;;
        alpine)
            echo "https://mirrors.aliyun.com/alpine/latest-stable/main" > /etc/apk/repositories
            echo "https://mirrors.aliyun.com/alpine/latest-stable/community" >> /etc/apk/repositories
            apk update
            ;;
    esac

    echo "▌[安装Docker] 正在安装核心组件..."
    $PKG_MGR $INSTALL_CMD $DOCKER_PKG
    delay
}

# 安装Docker Compose
install_compose() {
    echo "▌[安装Compose] 正在下载组件..."
    curl -L "https://ghproxy.com/https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)" \
         -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    delay
}

# 配置镜像加速
configure_mirror() {
    echo "▌[镜像加速] 正在配置加速源..."
    MIRRORS=(
        "https://docker.1panel.top"
        "https://proxy.1panel.live"
        "https://docker.m.daocloud.io"
        "https://docker.woskee.dns.army"
        "https://docker.woskee.dynv6.net"
    )

    CONF_FILE="$CONF_DIR/daemon.json"
    if [ ! -d "$CONF_DIR" ]; then
        mkdir -p $CONF_DIR
        echo "▌[镜像加速] 已创建配置目录：$CONF_DIR"
    fi

    if [ -f "$CONF_FILE" ]; then
        echo "▌[镜像加速] 检测到现有配置文件："
        cat $CONF_FILE
        read -p "⚠ 是否覆盖现有配置？[y/N] " OVERRIDE
        if [[ ! $OVERRIDE =~ ^[Yy] ]]; then
            echo "▌[镜像加速] 已跳过配置修改"
            return
        fi
    fi

    cat > $CONF_FILE << EOF
{
    "registry-mirrors": [$(printf '"%s",' "${MIRRORS[@]}" | sed 's/,$//')]
}
EOF
    echo "▌[镜像加速] 加速源已写入配置文件"
    delay
}

# 主执行流程
main() {
    detect_os
    set_dist_params
    check_installed

    # Docker安装判断
    if [ "$DOCKER_VER" != "未安装" ]; then
        read -p "⚠ 检测到已安装Docker，是否重新安装？[y/N] " REINSTALL
        if [[ $REINSTALL =~ ^[Yy] ]]; then
            uninstall_docker
            install_docker
        fi
    else
        read -p "➤ 是否安装Docker？[Y/n] " INSTALL
        if [[ ! $INSTALL =~ ^[Nn] ]]; then
            install_docker
        fi
    fi

    # Compose安装判断
    check_installed
    if [ "$COMPOSE_VER" == "未安装" ]; then
        read -p "➤ 是否安装Docker Compose？[Y/n] " INSTALL_COMPOSE
        if [[ ! $INSTALL_COMPOSE =~ ^[Nn] ]]; then
            install_compose
        fi
    fi

    # 服务管理
    echo "▌[服务管理] 正在设置开机启动..."
    eval $SRV_ENABLE
    delay

    # 镜像加速配置
    configure_mirror

    # 重启服务
    echo "▌[服务重启] 正在应用配置更改..."
    eval $SRV_RESTART
    delay

    # 验证安装
    echo "▌[安装验证] 最终版本检测："
    docker --version
    docker-compose --version
}

# 执行入口
main
