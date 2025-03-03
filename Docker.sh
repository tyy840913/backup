#!/bin/bash
# Docker自动安装脚本 版本：2.1.3 (2025-03-04)
# 支持系统：Ubuntu/CentOS/Alpine/Debian

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

# 国内镜像配置
MIRRORS=(
    "https://docker.1panel.top"
    "https://proxy.1panel.live"
    "https://docker.m.daocloud.io"
    "https://docker.woskee.dns.army"
    "https://docker.woskee.dynv6.net"
)
GITHUB_PROXY="https://mirror.ghproxy.com/"

# 日志记录初始化
LOG_FILE="/var/log/docker_install_$(date +%Y%m%d).log"
exec 3>&1 4>&2
trap 'exec 2>&4 1>&3' 0 1 2 3
exec &> >(tee -a "$LOG_FILE")

# 系统检测函数
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        OS_VERSION=$(lsb_release -sr)
    elif [ -f /etc/redhat-release ]; then
        OS=centos
        OS_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release)
    elif [ -f /etc/alpine-release ]; then
        OS=alpine
        OS_VERSION=$(cat /etc/alpine-release)
    else
        echo -e "${RED}无法检测操作系统类型${NC}" >&2
        exit 1
    fi
    [[ "$OS" =~ "ubuntu|debian" ]] && PKG_MGR=apt
    [[ "$OS" =~ "centos|rhel|fedora" ]] && PKG_MGR=yum
    [ "$OS" == "alpine" ] && PKG_MGR=apk
}

# 服务管理函数
service_manager() {
    case $OS in
        ubuntu|debian|centos)
            systemctl $1 docker ;;
        alpine)
            case $1 in
                start) service docker start ;;
                restart) service docker restart ;;
                enable) rc-update add docker boot ;;
                status) service docker status ;;
            esac ;;
    esac
}

# Docker安装核心函数
install_docker() {
    case $PKG_MGR in
        apt)
            export DOWNLOAD_URL="https://mirrors.aliyun.com/docker-ce"
            curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun ;;
        yum)
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce ;;
        apk)
            apk add docker docker-cli-compose
            rc-update add docker boot
            service docker start ;;
    esac
}

# 主安装流程
main() {
    # 系统检测
    detect_os
    echo -e "${GREEN}检测到系统：${OS} ${OS_VERSION}${NC}"
    sleep 0.5

    # 检查现有安装
    if command -v docker &>/dev/null; then
        echo -e "${YELLOW}检测到已安装Docker版本：$(docker --version | cut -d' ' -f3 | tr -d ',')${NC}"
        read -p "是否重新安装？[y/N] " reinstall
        if [[ $reinstall =~ [Yy] ]]; then
            echo -e "${BLUE}开始卸载旧版本...${NC}"
            case $PKG_MGR in
                apt) sudo apt purge -y docker* ;;
                yum) sudo yum remove -y docker* ;;
                apk) apk del docker* ;;
            esac
            sleep 0.5
        else
            exit 0
        fi
    fi

    # Docker安装
    echo -e "${BLUE}开始安装Docker...${NC}"
    install_docker
    sleep 0.5

    # 验证安装
    if ! command -v docker &>/dev/null; then
        echo -e "${RED}Docker安装失败，请检查日志：$LOG_FILE${NC}"
        exit 1
    fi

    # Docker Compose安装
    if ! command -v docker-compose &>/dev/null; then
        echo -e "${BLUE}安装Docker Compose...${NC}"
        compose_url="${GITHUB_PROXY}https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
        sudo curl -L "$compose_url" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
        sleep 0.5
    fi

    # 镜像加速配置
    DAEMON_JSON="/etc/docker/daemon.json"
    if [ ! -f "$DAEMON_JSON" ]; then
        echo -e "${BLUE}创建镜像加速配置文件...${NC}"
        sudo mkdir -p /etc/docker
        sudo tee $DAEMON_JSON <<EOF
{
    "registry-mirrors": ${MIRRORS[@]}
}
EOF
    else
        echo -e "${YELLOW}检测到现有镜像配置："
        cat $DAEMON_JSON
        read -p "是否覆盖配置？[y/N] " overwrite
        if [[ $overwrite =~ [Yy] ]]; then
            sudo tee $DAEMON_JSON <<EOF
{
    "registry-mirrors": ${MIRRORS[@]}
}
EOF
        fi
    fi

    # 服务重启
    echo -e "${BLUE}重启Docker服务...${NC}"
    service_manager restart
    sleep 2

    # 最终验证
    echo -e "${GREEN}安装完成！"
    echo "Docker版本：$(docker --version | cut -d' ' -f3 | tr -d ',')"
    echo "Docker Compose版本：$(docker-compose --version | cut -d' ' -f3 | tr -d ',')"
    echo -e "镜像加速源已配置：\n${MIRRORS[@]}${NC}"
}

# 执行主函数
main "$@"
