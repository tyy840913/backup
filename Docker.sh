#!/bin/bash

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RESET='\033[0m'
BOLD='\033[1m'

# 初始化变量
OS_ID=""
PKG_MANAGER=""
DOCKER_PKG=""
COMPOSE_PKG=""
SERVICE_CMD=""
CONFIRM_MSG=""

# 输出装饰函数
print_header() {
    echo -e "${BLUE}${BOLD}==> $1${RESET}"
}

print_success() {
    echo -e "${GREEN}✓ ${1}${RESET}"
}

print_warning() {
    echo -e "${YELLOW}⚠ ${1}${RESET}"
}

print_error() {
    echo -e "${RED}✗ ${1}${RESET}"
}

# 检测系统信息
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
        case $ID in
            alpine) PKG_MANAGER="apk" ;;
            debian|ubuntu) PKG_MANAGER="apt" ;;
            centos|rhel|ol) PKG_MANAGER="yum" ;;
            fedora) PKG_MANAGER="dnf" ;;
            *) print_error "不支持的发行版" && exit 1 ;;
        esac
    else
        print_error "无法检测操作系统"
        exit 1
    fi

    echo -e "${BOLD}系统信息：${RESET}"
    echo -e "发行版：${BLUE}$(source /etc/os-release && echo $PRETTY_NAME)${RESET}"
    echo -e "内核版本：${BLUE}$(uname -r)${RESET}"
    echo
}

# 安装确认函数
confirm() {
    read -rp "$1 [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Docker安装函数
install_docker() {
    case $OS_ID in
        alpine)
            $PKG_MANAGER add docker docker-openrc
            SERVICE_CMD="rc-update add docker boot && service docker start"
            ;;
        debian|ubuntu)
            $PKG_MANAGER update
            $PKG_MANAGER install -y docker.io docker-compose
            SERVICE_CMD="systemctl enable --now docker"
            ;;
        centos|rhel|ol|fedora)
            $PKG_MANAGER install -y docker docker-compose
            SERVICE_CMD="systemctl enable --now docker"
            ;;
    esac
}

# 主函数
main() {
    # 检查root权限
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用root权限运行脚本"
        exit 1
    fi

    print_header "开始系统检测..."
    detect_os

    # 检查Docker
    print_header "检查Docker安装..."
    if ! command -v docker &> /dev/null; then
        print_warning "未检测到Docker"
        if confirm "是否安装Docker？"; then
            install_docker
            print_success "Docker安装完成"
            eval $SERVICE_CMD
        else
            print_error "用户取消安装"
            exit 1
        fi
    else
        print_success "Docker已安装：$(docker --version)"
    fi

    # 检查Docker Compose
    print_header "检查Docker Compose..."
    if ! command -v docker-compose &> /dev/null; then
        print_warning "未检测到Docker Compose"
        if confirm "是否安装Docker Compose？"; then
            case $PKG_MANAGER in
                apk) $PKG_MANAGER add docker-compose ;;
                apt) $PKG_MANAGER install -y docker-compose ;;
                yum|dnf) $PKG_MANAGER install -y docker-compose ;;
            esac
            print_success "Docker Compose安装完成"
        else
            print_error "用户取消安装"
            exit 1
        fi
    else
        print_success "Docker Compose已安装：$(docker-compose --version)"
    fi

    # 配置镜像加速
    print_header "配置镜像加速源..."
    DAEMON_JSON="/etc/docker/daemon.json"
    CONTENT='{\n  "registry-mirrors": [\n    "https://docker.1panel.top",\n    "https://proxy.1panel.live",\n    "https://docker.m.daocloud.io",\n    "https://docker.woskee.dns.army",\n    "https://docker.woskee.dynv6.net"\n  ]\n}'

    if [ ! -f "$DAEMON_JSON" ] || [ ! -s "$DAEMON_JSON" ]; then
        print_warning "配置文件不存在或为空"
        echo -e "$CONTENT" > "$DAEMON_JSON"
        print_success "已创建配置文件"
        systemctl restart docker
        print_success "Docker服务已重启"
    else
        print_success "配置文件已存在"
        echo -e "${BOLD}当前文件内容：${RESET}"
        cat "$DAEMON_JSON"
        echo
        
        if confirm "是否覆盖现有配置？"; then
            cp "$DAEMON_JSON" "${DAEMON_JSON}.bak"
            echo -e "$CONTENT" > "$DAEMON_JSON"
            print_success "配置已更新（原文件备份为${DAEMON_JSON}.bak）"
            systemctl restart docker
            print_success "Docker服务已重启"
        else
            print_warning "保持现有配置不变"
        fi
    fi

    print_header "${GREEN}所有操作已完成！${RESET}"
}

# 执行主函数
main
