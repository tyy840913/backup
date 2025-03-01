#!/bin/bash

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RESET='\033[0m'

# 等待Docker服务就绪
wait_for_docker() {
    echo -e "${BLUE}=== 等待Docker启动 ===${RESET}"
    local timeout=30
    local interval=2
    local attempts=$((timeout/interval))

    for ((i=1; i<=attempts; i++)); do
        if docker info &>/dev/null; then
            echo -e "${GREEN}Docker服务已就绪${RESET}"
            return 0
        fi
        echo -e "${YELLOW}等待Docker启动中...（尝试 $i/$attempts）${RESET}"
        sleep $interval
    done

    echo -e "${RED}错误：Docker服务启动超时${RESET}"
    return 1
}

# 检查Docker和Docker Compose是否已安装
check_installed() {
    echo -e "\n${BLUE}=== 检查Docker及Docker Compose ===${RESET}"
    
    docker_installed=$(command -v docker &> /dev/null && echo "yes" || echo "no")
    compose_installed=$(command -v docker-compose &> /dev/null && echo "yes" || echo "no")

    if [ "$docker_installed" = "yes" ] && [ "$compose_installed" = "yes" ]; then
        echo -e "${GREEN}已安装组件："
        docker --version | awk '{print "Docker 版本："$3}'
        docker-compose --version | awk '{print "Docker Compose 版本："$3}'
        echo -e "${RESET}"
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
user_confirm() {
    local prompt=$1
    while true; do
        read -rp "$prompt (Y/N) " answer
        case $answer in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo -e "${YELLOW}请输入 Y 或 N${RESET}";;
        esac
    done
}

# Alpine系统安装
install_alpine() {
    echo -e "${BLUE}开始Alpine系统安装...${RESET}"
    
    # 配置国内镜像源
    echo -e "${YELLOW}配置Alpine国内镜像源...${RESET}"
    sed -i 's#http://dl-cdn.alpinelinux.org#https://mirrors.aliyun.com#g' /etc/apk/repositories
    apk update
    
    # 安装Docker
    apk add docker docker-compose
    rc-update add docker boot
    service docker start
    wait_for_docker || return 1
}

# 其他Linux发行版安装
install_linux() {
    echo -e "${BLUE}开始Linux通用安装...${RESET}"
    
    if command -v apt &> /dev/null; then
        # Debian/Ubuntu安装流程
        echo -e "${YELLOW}检测到APT包管理器，使用国内镜像源安装...${RESET}"
        
        # 安装依赖
        apt update
        apt install -y apt-transport-https ca-certificates curl software-properties-common gnupg

        # 尝试多个GPG密钥源
        GPG_SUCCESS=0
        GPG_SOURCES=(
            "https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg"
            "https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu/gpg"
            "https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu/gpg"
            "https://download.docker.com/linux/ubuntu/gpg"
        )

        for source in "${GPG_SOURCES[@]}"; do
            echo -e "${YELLOW}尝试从 ${source} 下载GPG密钥...${RESET}"
            if curl -fsSL "${source}" | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg; then
                GPG_SUCCESS=1
                break
            fi
        done

        if [ $GPG_SUCCESS -ne 1 ]; then
            echo -e "${RED}错误：无法下载GPG密钥，所有镜像源尝试失败${RESET}"
            return 1
        fi

        # 尝试多个APT源
        APT_SOURCES=(
            "https://mirrors.aliyun.com/docker-ce/linux/ubuntu"
            "https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/ubuntu"
            "https://mirrors.ustc.edu.cn/docker-ce/linux/ubuntu"
            "https://download.docker.com/linux/ubuntu"
        )

        LSBCS=$(lsb_release -cs)
        for apt_source in "${APT_SOURCES[@]}"; do
            echo -e "${YELLOW}尝试使用APT源：${apt_source}...${RESET}"
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] ${apt_source} ${LSBCS} stable" > /etc/apt/sources.list.d/docker.list
            if apt update &>/dev/null; then
                break
            fi
        done

        # 安装Docker
        apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then
        # RHEL/CentOS/Fedora安装流程
        echo -e "${YELLOW}检测到YUM/DNF包管理器，使用国内镜像源安装...${RESET}"
        
        # 安装依赖
        yum install -y yum-utils device-mapper-persistent-data lvm2

        # 配置仓库
        REPO_URLS=(
            "https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo"
            "https://mirrors.tuna.tsinghua.edu.cn/docker-ce/linux/centos/docker-ce.repo"
            "https://mirrors.ustc.edu.cn/docker-ce/linux/centos/docker-ce.repo"
            "https://download.docker.com/linux/centos/docker-ce.repo"
        )

        for repo_url in "${REPO_URLS[@]}"; do
            echo -e "${YELLOW}尝试使用仓库源：${repo_url}...${RESET}"
            if yum-config-manager --add-repo "${repo_url}" &>/dev/null; then
                # 替换为国内镜像源
                sed -i 's#download.docker.com#mirrors.aliyun.com/docker-ce#g' /etc/yum.repos.d/docker-ce.repo
                if yum makecache &>/dev/null; then
                    break
                fi
            fi
        done

        # 安装Docker
        yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    fi

    # 启动服务
    systemctl enable --now docker
    wait_for_docker || return 1
}

# 配置镜像源（保持原有加速源不变）
configure_mirrors() {
    echo -e "${YELLOW}更新镜像加速配置...${RESET}"
    
    mkdir -p /etc/docker

    if [ -s "/etc/docker/daemon.json" ]; then
        echo -e "${BLUE}当前配置文件内容：${RESET}"
        jq . /etc/docker/daemon.json 2>/dev/null || cat /etc/docker/daemon.json
        echo
    fi

    if ! user_confirm "是否覆盖现有配置？"; then
        echo -e "${YELLOW}已保留原有配置${RESET}"
        return 0
    fi

    if tee /etc/docker/daemon.json << EOF
{
  "registry-mirrors": [
    "https://docker.1panel.top",
    "https://proxy.1panel.live",
    "https://docker.m.daocloud.io",
    "https://docker.woskee.dns.army",
    "https://docker.woskee.dynv6.net"
  ]
}
EOF
    then
        echo -e "${GREEN}镜像加速配置写入成功${RESET}"
        
        # 服务重启
        echo -e "${YELLOW}重启Docker服务...${RESET}"
        if grep -iq "alpine" /etc/os-release; then
            service docker restart >/dev/null 2>&1
        else
            systemctl restart docker >/dev/null 2>&1 || service docker restart >/dev/null 2>&1
        fi
        wait_for_docker || return 1
    else
        echo -e "${RED}错误：配置文件写入失败${RESET}"
        return 1
    fi
}

# 验证镜像配置
validate_mirrors() {
    echo -e "\n${BLUE}=== 检查镜像配置文件 ===${RESET}"

    if [ ! -f "/etc/docker/daemon.json" ] || [ ! -s "/etc/docker/daemon.json" ]; then
        echo -e "${YELLOW}配置文件不存在或为空，自动创建${RESET}"
        configure_mirrors || return 1
    else
        echo -e "${GREEN}镜像配置文件已存在${RESET}"
        echo -e "${BLUE}当前配置内容：${RESET}"
        jq .registry-mirrors /etc/docker/daemon.json 2>/dev/null || cat /etc/docker/daemon.json
        echo
        
        if user_confirm "是否强制更新为指定镜像源？"; then
            configure_mirrors || return 1
        else
            echo -e "${YELLOW}保持现有镜像配置${RESET}"
        fi
    fi
}

# 主执行流程
main() {
    if check_installed; then
        check_autostart
        validate_mirrors
    else
        if user_confirm "检测到未安装Docker，是否继续安装？"; then
            if grep -iq "alpine" /etc/os-release; then
                install_alpine || exit 1
            else
                install_linux || exit 1
            fi
            check_autostart
            validate_mirrors || exit 1
            echo -e "\n${GREEN}安装完成！${RESET}"
        else
            echo -e "${YELLOW}已取消安装${RESET}"
            exit 0
        fi
    fi

    # 最终状态检查
    echo -e "\n${BLUE}=== 最终状态检查 ===${RESET}"
    if docker info &>/dev/null; then
        echo -e "${GREEN}Docker运行状态："
        docker info --format '{{.RegistryConfig.Mirrors}}' | tr ' ' '\n' | grep -v '^$'
    else
        echo -e "${RED}无法获取Docker信息，请检查服务状态${RESET}"
        exit 1
    fi
}

# 执行主函数
main "$@"
