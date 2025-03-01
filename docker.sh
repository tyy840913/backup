#!/bin/bash

# 检查Docker和Docker Compose是否已安装
check_installed() {
    docker_installed=$(command -v docker &> /dev/null && echo "yes" || echo "no")
    compose_installed=$(command -v docker-compose &> /dev/null && echo "yes" || echo "no")
    
    if [ "$docker_installed" = "yes" ] && [ "$compose_installed" = "yes" ]; then
        echo -e "\033[32mDocker和Docker Compose已安装，跳过安装步骤\033[0m"
        return 0
    else
        return 1
    fi
}

# 用户确认提示
confirm_install() {
    while true; do
        read -rp "检测到未安装Docker或Docker Compose，是否继续安装？(Y/N) " answer
        case $answer in
            [Yy]* ) return 0;;
            [Nn]* ) exit 1;;
            * ) echo "请输入 Y 或 N";;
        esac
    done
}

# Alpine系统安装
install_alpine() {
    apk update
    apk add docker docker-compose
    rc-update add docker boot
    service docker start
}

# 其他Linux发行版安装
install_linux() {
    # 识别包管理器
    if command -v apt &> /dev/null; then
        apt update
        apt install -y apt-transport-https ca-certificates curl software-properties-common
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
        add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    elif command -v yum &> /dev/null; then
        yum install -y yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    elif command -v dnf &> /dev/null; then
        dnf -y install dnf-plugins-core
        dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
        dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    fi

    # 设置开机启动
    systemctl enable --now docker
}

# 配置镜像加速
configure_mirrors() {
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
    "registry-mirrors": [
        "https://proxy.1panel.live",
        "https://docker.1panel.top",
        "https://docker.m.daocloud.io",
        "https://docker.woskee.nyc.mn",
        "https://docker.woskee.dns.army",
        "https://docker.woskee.dynv6.net"
    ]
}
EOF
    # 重启服务
    if [ "$(command -v systemctl)" ]; then
        systemctl restart docker
    else
        service docker restart
    fi
}

# 主流程
if ! check_installed; then
    confirm_install
    
    # 识别系统类型
    if grep -iq "alpine" /etc/os-release; then
        install_alpine
    else
        install_linux
    fi

    # 配置镜像加速
    configure_mirrors
    
    echo -e "\033[32m安装完成！Docker版本：$(docker --version)\033[0m"
    echo -e "\033[32mDocker Compose版本：$(docker-compose --version)\033[0m"
fi
