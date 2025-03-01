#!/bin/bash

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RESET='\033[0m'

# 检查Docker和Docker Compose是否已安装
check_installed() {
    docker_installed=$(command -v docker &> /dev/null && echo "yes" || echo "no")
    compose_installed=$(command -v docker-compose &> /dev/null && echo "yes" || echo "no")
    
    if [ "$docker_installed" = "yes" ] && [ "$compose_installed" = "yes" ]; then
        echo -e "${GREEN}Docker和Docker Compose已安装，跳过安装步骤${RESET}"
        return 0
    else
        return 1
    fi
}

# 检查开机自启状态
check_autostart() {
    echo -e "\n${BLUE}=== 检查开机自启配置 ===${RESET}"
    
    if grep -iq "alpine" /etc/os-release; then
        if rc-update show boot | grep -q docker; then
            echo -e "${GREEN}Alpine系统docker已配置开机自启${RESET}"
        else
            echo -e "${YELLOW}警告：未配置docker开机自启，正在自动设置...${RESET}"
            rc-update add docker boot
        fi
    else
        if systemctl is-enabled docker &> /dev/null; then
            echo -e "${GREEN}Systemd系统docker已配置开机自启${RESET}"
        else
            echo -e "${YELLOW}警告：未配置docker开机自启，正在自动设置...${RESET}"
            systemctl enable --now docker
        fi
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
    systemctl enable --now docker
}

# 验证镜像加速配置
validate_mirrors() {
    declare -a required_mirrors=(
        "https://proxy.1panel.live"
        "https://docker.1panel.top"
        "https://docker.woskee.dns.army"
        "https://docker.woskee.dynv6.net"
    )

    echo -e "\n${BLUE}=== 检查镜像加速配置 ===${RESET}"
    
    if [ ! -f /etc/docker/daemon.json ]; then
        echo -e "${YELLOW}未找到镜像加速配置，正在创建...${RESET}"
        configure_mirrors
        return
    fi

    for mirror in "${required_mirrors[@]}"; do
        if ! grep -q "$mirror" /etc/docker/daemon.json; then
            echo -e "${YELLOW}检测到缺少镜像源 $mirror，正在更新配置...${RESET}"
            configure_mirrors
            return
        fi
    done
    echo -e "${GREEN}所有镜像加速源已正确配置${RESET}"
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
    if [ "$(command -v systemctl)" ]; then
        systemctl restart docker
    else
        service docker restart
    fi
    echo -e "${GREEN}镜像加速配置已更新，服务已重启${RESET}"
}

# 主流程
if check_installed; then
    check_autostart    # 新增：检查自启动配置
    validate_mirrors   # 新增：验证镜像源
else
    confirm_install
    
    if grep -iq "alpine" /etc/os-release; then
        install_alpine
    else
        install_linux
    fi

    check_autostart
    validate_mirrors
    
    echo -e "\n${GREEN}安装完成！Docker版本：$(docker --version)${RESET}"
    echo -e "${GREEN}Docker Compose版本：$(docker-compose --version)${RESET}"
fi
