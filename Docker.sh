#!/bin/bash

# 颜色定义
YELLOW='\033[1;93m'
GREEN='\033[0;92m'
RED='\033[0;91m'
BLUE='\033[0;94m'
NC='\033[0m' # 恢复默认颜色

# 延迟函数
sleepy() {
    sleep 0.3
}

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：该脚本需要root权限！${NC}"
    exit 1
fi

# 获取发行版信息
OS_ID=$(grep -oP 'ID=\K\w+' /etc/os-release)
OS_ID_LIKE=$(grep -oP 'ID_LIKE=\K\w+' /etc/os-release)

# 安装Docker的函数
install_docker() {
    echo -e "${YELLOW}正在安装Docker...${NC}"
    
    case $OS_ID in
        alpine)
            apk add docker docker-cli-compose docker-openrc
            rc-update add docker boot
            service docker start
            ;;
        debian|ubuntu)
            apt-get update
            apt-get install -y docker.io docker-compose
            systemctl enable --now docker
            ;;
        centos|fedora|rhel)
            if [ "$OS_ID" = "fedora" ]; then
                dnf -y install dnf-plugins-core
                dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
                dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
            else
                yum install -y yum-utils
                yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                yum -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
            fi
            systemctl enable --now docker
            ;;
        *)
            echo -e "${RED}不支持的发行版：$OS_ID${NC}"
            exit 1
            ;;
    esac
    
    # 增加安装后验证
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}严重错误：Docker安装失败！${NC}"
        exit 1
    fi
    
    # 检查服务文件是否存在
    case $OS_ID in
        alpine)
            if [ ! -f "/etc/init.d/docker" ]; then
                echo -e "${RED}错误：Alpine系统docker服务文件未找到${NC}"
                exit 1
            fi
            ;;
        *)
            if [ ! -f "/usr/lib/systemd/system/docker.service" ]; then
                echo -e "${RED}错误：docker.service文件未找到${NC}"
                exit 1
            fi
            ;;
    esac
    echo -e "${GREEN}Docker安装验证通过${NC}"
    sleepy
}

# 检查Docker是否安装
check_docker() {
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version | awk '{print $3}')
        echo -e "${GREEN}检测到已安装Docker版本：${YELLOW}$DOCKER_VERSION${NC}"
        read -p "是否要重新安装？[y/N] " reinstall
        if [[ $reinstall =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}正在卸载旧版本Docker...${NC}"
            case $OS_ID in
                alpine) apk del docker* ;;
                debian|ubuntu) apt-get purge -y docker* ;;
                centos|fedora|rhel) yum remove -y docker* ;;
            esac
            install_docker
        fi
    else
        read -p "未检测到Docker，是否要安装？[Y/n] " install_d
        if [[ ! $install_d =~ ^[Nn]$ ]]; then
            install_docker
        else
            echo -e "${RED}已取消安装，退出脚本${NC}"
            exit 0
        fi
    fi
    sleepy
}

# 检查Docker Compose
check_compose() {
    if docker compose version &> /dev/null; then
        COMPOSE_VERSION=$(docker compose version | awk '{print $4}')
        echo -e "${GREEN}检测到Docker Compose版本：${YELLOW}$COMPOSE_VERSION${NC}"
    else
        read -p "未检测到Docker Compose，是否要安装？[Y/n] " install_c
        if [[ ! $install_c =~ ^[Nn]$ ]]; then
            echo -e "${YELLOW}正在安装Docker Compose...${NC}"
            curl -SL https://add.woskee.nyc.mn/github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m) -o /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
            echo -e "${GREEN}Docker Compose安装完成！${NC}"
        fi
    fi
    sleepy
}

# 设置镜像加速
set_mirror() {
    DAEMON_JSON="/etc/docker/daemon.json"
    MIRRORS=(
        "https://proxy.1panel.live"
        "https://docker.1panel.top"
        "https://docker.m.daocloud.io"
        "https://docker.woskee.dns.army"
        "https://docker.woskee.dynv6.net"
    )

    if [ ! -d "/etc/docker" ]; then
        mkdir -p /etc/docker
    fi

    if [ -f "$DAEMON_JSON" ]; then
        echo -e "${YELLOW}当前镜像配置：${NC}"
        cat "$DAEMON_JSON"
        read -p "是否要替换现有镜像源？[y/N] " replace
        if [[ $replace =~ ^[Yy]$ ]]; then
            rm -f "$DAEMON_JSON"
        else
            return
        fi
    fi

    echo -e "${YELLOW}正在配置镜像加速源...${NC}"
    echo '{ "registry-mirrors": [' > "$DAEMON_JSON"
    for mirror in "${MIRRORS[@]}"; do
        echo "  \"$mirror\"," >> "$DAEMON_JSON"
    done
    sed -i '$ s/,$//' "$DAEMON_JSON"
    echo ']}' >> "$DAEMON_JSON"
    echo -e "${GREEN}镜像加速源配置完成！${NC}"
    sleepy
}

# 增强的服务管理函数
enable_service() {
    echo -e "${YELLOW}设置Docker开机启动...${NC}"
    
    # 检查docker是否真实存在
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}错误：Docker未正确安装，无法设置开机启动${NC}"
        return 1
    fi

    case $OS_ID in
        alpine)
            if rc-update | grep -q docker; then
                echo -e "${YELLOW}Alpine系统已存在docker启动项${NC}"
            else
                rc-update add docker boot
            fi
            if service docker status | grep -q 'stopped'; then
                service docker start
            fi
            ;;
        *)
            if systemctl is-enabled docker &> /dev/null; then
                echo -e "${YELLOW}系统已设置Docker开机启动${NC}"
            else
                systemctl enable docker
            fi
            
            if ! systemctl is-active docker &> /dev/null; then
                systemctl restart docker
            fi
            ;;
    esac
    
    # 二次验证服务状态
    sleepy
    case $OS_ID in
        alpine)
            if ! service docker status | grep -q 'started'; then
                echo -e "${RED}错误：Docker服务启动失败${NC}"
                return 1
            fi
            ;;
        *)
            if ! systemctl is-active docker &> /dev/null; then
                echo -e "${RED}错误：Docker服务启动失败${NC}"
                return 1
            fi
            ;;
    esac
    
    echo -e "${GREEN}Docker服务启动成功！${NC}"
    sleepy
}

# 主程序
echo -e "${BLUE}=== Docker自动安装脚本 ===${NC}"
check_docker
check_compose
set_mirror
enable_service

# 验证安装
    echo -e "${YELLOW}验证安装...${NC}"
            if command -v docker &> /dev/null; then
               docker --version || echo -e "${RED}警告：找到docker命令但无法获取版本${NC}"
    else
    echo -e "${RED}严重错误：docker命令未找到！${NC}"
    exit 1
 fi
    echo -e "${GREEN}所有操作已完成！${NC}"
