#!/bin/bash

# 定义颜色代码
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 恢复默认颜色

# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：需要root权限，请使用sudo运行此脚本${NC}"
        exit 1
    fi
}

# 检测系统类型
detect_os() {
    if [ -f /etc/alpine-release ]; then
        echo "alpine"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "centos"
    elif [ -f /etc/arch-release ]; then
        echo "arch"
    else
        echo -e "${RED}不支持的发行版${NC}"
        exit 1
    fi
}

# 检查中文环境是否已配置
check_locale_configured() {
    local os_type=$1
    case $os_type in
        "alpine")
            if [ -f /etc/locale.conf ] && grep -q "zh_CN.UTF-8" /etc/locale.conf; then
                echo -e "${GREEN}中文locale已配置${NC}"
                return 0
            else
                echo -e "${YELLOW}未找到中文locale配置${NC}"
                return 1
            fi
            ;;
        *)
            if command -v locale &> /dev/null && locale -a | grep -q "zh_CN.utf8"; then
                echo -e "${GREEN}中文locale已存在${NC}"
                return 0
            else
                echo -e "${YELLOW}未找到中文locale配置${NC}"
                return 1
            fi
            ;;
    esac
}

# 检查中文包是否已安装
check_package_installed() {
    local os_type=$1
    case $os_type in
        "debian")
            dpkg -l | grep -q language-pack-zh-hans && return 0 || return 1
            ;;
        "alpine")
            apk info | grep -q zh-CN-lang && return 0 || return 1
            ;;
        "centos")
            rpm -qa | grep -q glibc-langpack-zh && return 0 || return 1
            ;;
        "arch")
            pacman -Q glibc 2>/dev/null && pacman -Q locale 2>/dev/null && return 0 || return 1
            ;;
    esac
}

# 安装中文包
install_package() {
    local os_type=$1
    case $os_type in
        "debian")
            echo -e "${YELLOW}正在安装language-pack-zh-hans...${NC}"
            apt update && apt install -y language-pack-zh-hans || {
                echo -e "${RED}安装失败，请检查网络连接和仓库配置${NC}"
                exit 1
            }
            ;;
        "alpine")
            echo -e "${YELLOW}正在安装中文语言包...${NC}"
            apk update && apk add --no-cache zh-CN-lang || {
                echo -e "${RED}安装失败，可能原因：\n1. 仓库配置错误\n2. 网络问题\n3. 包名已变更（当前尝试：zh-CN-lang）${NC}"
                exit 1
            }
            ;;
        "centos")
            echo -e "${YELLOW}正在安装glibc-langpack-zh...${NC}"
            yum install -y glibc-langpack-zh || {
                echo -e "${RED}安装失败，请检查yum仓库配置${NC}"
                exit 1
            }
            ;;
        "arch")
            echo -e "${YELLOW}正在安装locale和glibc...${NC}"
            pacman -Sy --noconfirm glibc locale || {
                echo -e "${RED}安装失败，请检查pacman仓库配置${NC}"
                exit 1
            }
            ;;
    esac
}

# 配置locale
configure_locale() {
    local os_type=$1
    case $os_type in
        "debian")
            echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen
            locale-gen zh_CN.UTF-8
            update-locale LANG=zh_CN.UTF-8
            ;;
        "alpine")
            echo "LANG=zh_CN.UTF-8" > /etc/locale.conf
            echo "export LANG=zh_CN.UTF-8" >> /etc/profile.d/lang.sh
            echo "export LC_ALL=zh_CN.UTF-8" >> /etc/profile.d/lang.sh
            chmod 755 /etc/profile.d/lang.sh
            ;;
        "centos")
            localedef -c -f UTF-8 -i zh_CN zh_CN.UTF-8
            echo "LANG=zh_CN.UTF-8" > /etc/locale.conf
            ;;
        "arch")
            echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen
            locale-gen
            echo "LANG=zh_CN.UTF-8" > /etc/locale.conf
            ;;
    esac
}

# 主函数
main() {
    check_root
    echo -e "${GREEN}正在检测系统类型...${NC}"
    os_type=$(detect_os)
    echo -e "系统类型: ${YELLOW}$os_type${NC}"

    echo -e "\n${GREEN}检查中文环境配置...${NC}"
    if check_locale_configured "$os_type"; then
        echo -e "${GREEN}中文环境已正确配置${NC}"
        exit 0
    fi

    echo -e "\n${GREEN}检查中文语言包是否安装...${NC}"
    if check_package_installed "$os_type"; then
        echo -e "${YELLOW}中文包已安装但未配置，正在配置...${NC}"
    else
        echo -e "${YELLOW}未安装中文语言包，正在安装...${NC}"
        install_package "$os_type"
    fi

    echo -e "\n${GREEN}正在配置locale...${NC}"
    configure_locale "$os_type"

    echo -e "\n${GREEN}验证配置...${NC}"
    if check_locale_configured "$os_type"; then
        echo -e "${GREEN}中文环境配置成功！${NC}"
        echo -e "\n请执行以下操作之一："
        echo -e "1. 重新登录系统"
        echo -e "2. 运行: source /etc/profile"
        echo -e "3. 重启系统"
    else
        echo -e "${RED}配置失败，请检查："
        echo "1. 软件包是否安装成功"
        echo "2. 配置文件权限是否正确"
        echo "3. 系统是否支持中文编码${NC}"
        exit 1
    fi
}

# 执行主函数
main
