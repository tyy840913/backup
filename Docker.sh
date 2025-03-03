#!/bin/bash

# 配置变量
MIRRORS=(
    "https://docker.1panel.top",
    "https://proxy.1panel.live",
    "https://docker.m.daocloud.io",
    "https://docker.woskee.dns.army", 
    "https://docker.woskee.dynv6.net"
)
SLEEP_TIME=0.5

# 初始化环境
init() {
    clear
    echo -e "\033[34m初始化检查...\033[0m"
    [ "$EUID" -ne 0 ] && echo -e "\033[31m请使用sudo或root用户运行脚本\033[0m" && exit 1
    
    # 识别发行版
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    else
        OS=$(uname -s)
    fi

    # Alpine特殊处理
    [ -f /etc/alpine-release ] && OS=alpine

    case $OS in
        debian|ubuntu|raspbian) PKG_MGR="apt";;
        centos|rhel|fedora|ol) PKG_MGR="yum";;
        alpine) PKG_MGR="apk";;
        *) echo -e "\033[31m不支持的发行版\033[0m" && exit 1;;
    esac

    sleep $SLEEP_TIME
}

# 输出带样式的信息
msg() {
    echo -e "\033[34m[INFO] $1\033[0m"
    sleep $SLEEP_TIME
}

# 获取最新compose版本
get_compose_version() {
    msg "获取Docker Compose最新版本..."
    local version=$(basename $(curl -Ls -o /dev/null -w %{url_effective} https://mirror.ghproxy.com/https://github.com/docker/compose/releases/latest 2>/dev/null))
    
    if [ -z "$version" ]; then
        echo -e "\033[31m错误：无法获取Docker Compose版本\033[0m"
        exit 1
    fi
    
    echo $version
}

# 安装Docker
install_docker() {
    if command -v docker &>/dev/null; then
        read -rp "检测到已安装Docker，是否重新安装？[y/N] " reinstall
        case $reinstall in
            [Yy]*) 
                msg "开始卸载旧版Docker..."
                case $PKG_MGR in
                    apt) $PKG_MGR purge -y docker*;;
                    yum) $PKG_MGR remove -y docker*;;
                    apk) $PKG_MGR del docker-cli docker-engine;;
                esac
                rm -rf /var/lib/docker /etc/docker
                rm -f /etc/apparmor.d/docker
                groupdel docker 2>/dev/null
                ;;
            *) return 1;;
        esac
    else
        read -rp "是否安装Docker？[Y/n] " install
        case $install in
            [Nn]*) exit 0;;
            *) ;;
        esac
    fi

    msg "开始安装Docker..."
    case $PKG_MGR in
        apt)
            $PKG_MGR update
            $PKG_MGR install -y apt-transport-https ca-certificates curl gnupg
            curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://mirrors.aliyun.com/docker-ce/linux/$OS $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list
            $PKG_MGR update
            $PKG_MGR install -y docker-ce docker-ce-cli containerd.io
            ;;
        yum)
            $PKG_MGR install -y yum-utils
            $PKG_MGR-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
            $PKG_MGR makecache
            $PKG_MGR install -y docker-ce docker-ce-cli containerd.io
            ;;
        apk)
            $PKG_MGR update
            $PKG_MGR add docker
            ;;
    esac
}

# 安装Docker Compose
install_compose() {
    if docker compose version &>/dev/null; then
        msg "检测到Docker已集成Compose插件"
        return 0
    fi

    if command -v docker-compose &>/dev/null; then
        read -rp "检测到已安装Docker Compose，是否重新安装？[y/N] " reinstall
        case $reinstall in
            [Yy]*) rm -f $(which docker-compose);;
            *) return 0;;
        esac
    fi

    local COMPOSE_VERSION=$(get_compose_version)
    msg "开始安装Docker Compose $COMPOSE_VERSION..."
    
    local arch=$(uname -m)
    [ "$arch" == "x86_64" ] && arch="x86_64"
    [ "$arch" == "aarch64" ] && arch="aarch64"

    wget -O /usr/local/bin/docker-compose \
        "https://mirror.ghproxy.com/https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-linux-${arch}"
    chmod +x /usr/local/bin/docker-compose
    ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose 2>/dev/null
}

# 配置服务
setup_service() {
    msg "配置开机启动..."
    if [ "$OS" = "alpine" ]; then
        rc-update add docker boot
        rc-service docker start
    else
        systemctl enable --now docker
    fi
}

# 配置镜像加速
configure_mirror() {
    local config_file="/etc/docker/daemon.json"
    mkdir -p /etc/docker

    if [ -f "$config_file" ]; then
        grep "registry-mirrors" "$config_file" >/dev/null && \
        msg "当前镜像配置：" && cat "$config_file"
        read -rp "是否替换镜像源？[y/N] " replace
        [ "$replace" != "y" ] && return
    fi

    local mirrors=$(printf '"%s",' "${MIRRORS[@]}" | sed 's/,$//')
    cat > "$config_file" << EOF
{
  "registry-mirrors": [$mirrors],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  }
}
EOF
    msg "镜像加速配置完成"
}

# 验证安装
verify_install() {
    msg "重启Docker服务..."
    [ "$OS" = "alpine" ] && rc-service docker restart || systemctl restart docker
    
    docker version && docker-compose --version
    msg "\033[32m安装完成！\033[0m"
}

main() {
    init
    install_docker || return
    install_compose
    setup_service
    configure_mirror
    verify_install
}

main
