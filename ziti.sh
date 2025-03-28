#!/bin/bash

# 功能: 自动检测和配置系统中文环境
# 支持系统: Debian/Ubuntu, RHEL/CentOS, Fedora, openSUSE, Arch Linux, Alpine

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${YELLOW}需要root权限，尝试使用sudo提权...${NC}"
        if command -v sudo >/dev/null 2>&1; then
            exec sudo "$0" "$@"
        else
            echo -e "${RED}错误: 需要root权限且未找到sudo命令。${NC}"
            echo -e "请使用root用户运行此脚本或安装sudo。"
            exit 1
        fi
    fi
}

# 检测系统发行版
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        DISTRO="rhel"
        VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release)
    elif [ -f /etc/alpine-release ]; then
        DISTRO="alpine"
        VERSION=$(cat /etc/alpine-release)
    elif [ -f /etc/arch-release ]; then
        DISTRO="arch"
        VERSION="rolling"
    else
        echo -e "${RED}错误: 无法识别的Linux发行版${NC}"
        exit 1
    fi

    echo -e "${GREEN}检测到系统: $DISTRO $VERSION${NC}"
}

# 检查当前locale设置
check_current_locale() {
    current_locale=$(locale | grep -E "LANG=|LC_ALL=" | grep -i "zh_CN")
    if [ -n "$current_locale" ]; then
        echo -e "${GREEN}当前已配置中文环境:${NC}"
        locale | grep -E "LANG|LC_CTYPE|LC_NUMERIC|LC_TIME|LC_COLLATE|LC_MONETARY|LC_MESSAGES|LC_ALL"
        
        # 检查是否有locale设置错误
        if locale | grep -q "Cannot set LC_"; then
            return 1
        fi
        return 0
    else
        echo -e "${YELLOW}当前未配置中文环境或配置不正确${NC}"
        return 1
    fi
}

# 安装必要依赖
install_dependencies() {
    echo -e "${GREEN}正在安装必要依赖...${NC}"
    
    case $DISTRO in
        debian|ubuntu)
            if ! command -v locale-gen >/dev/null 2>&1; then
                apt-get update && apt-get install -y locales
            fi
            # 确保安装中文语言包
            apt-get install -y language-pack-zh-hans language-pack-zh-hans-base
            ;;
        rhel|centos|fedora)
            if ! command -v localedef >/dev/null 2>&1; then
                yum install -y glibc-common
            fi
            yum install -y glibc-langpack-zh
            ;;
        opensuse|opensuse-leap|opensuse-tumbleweed)
            if ! command -v localedef >/dev/null 2>&1; then
                zypper install -y glibc-locale
            fi
            zypper install -y glibc-locale-zh
            ;;
        arch)
            if ! command -v locale-gen >/dev/null 2>&1; then
                pacman -Sy --noconfirm glibc
            fi
            sed -i 's/^#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
            locale-gen
            ;;
        alpine)
            if ! command -v setup-locale >/dev/null 2>&1; then
                apk add --no-cache musl-locales musl-locales-lang
            fi
            ;;
        *)
            echo -e "${RED}错误: 不支持的发行版${NC}"
            exit 1
            ;;
    esac
}

# 生成中文locale
generate_chinese_locale() {
    echo -e "${GREEN}正在生成中文locale...${NC}"
    
    case $DISTRO in
        debian|ubuntu)
            # 确保zh_CN.UTF-8在locale.gen中启用
            if ! grep -q "^[^#]*zh_CN.UTF-8" /etc/locale.gen; then
                echo "zh_CN.UTF-8 UTF-8" >> /etc/locale.gen
            fi
            locale-gen zh_CN.UTF-8
            ;;
        rhel|centos|fedora)
            localedef -c -f UTF-8 -i zh_CN zh_CN.UTF-8
            ;;
        opensuse|opensuse-leap|opensuse-tumbleweed)
            localedef -c -f UTF-8 -i zh_CN zh_CN.UTF-8
            ;;
        arch)
            locale-gen
            ;;
        alpine)
            # Alpine使用不同的方法
            echo "zh_CN.UTF-8 UTF-8" > /etc/locale.gen
            setup-locale LANG=zh_CN.UTF-8
            ;;
    esac
}

# 配置中文环境
configure_chinese_locale() {
    echo -e "${GREEN}正在配置中文环境...${NC}"
    
    case $DISTRO in
        debian|ubuntu)
            update-locale LANG=zh_CN.UTF-8
            update-locale LANGUAGE=zh_CN:zh
            update-locale LC_ALL=zh_CN.UTF-8
            ;;
        rhel|centos|fedora|opensuse|opensuse-leap|opensuse-tumbleweed)
            localectl set-locale LANG=zh_CN.UTF-8
            ;;
        arch)
            echo "LANG=zh_CN.UTF-8" > /etc/locale.conf
            echo "LC_ALL=zh_CN.UTF-8" >> /etc/locale.conf
            ;;
        alpine)
            echo "export LANG=zh_CN.UTF-8" > /etc/profile.d/locale.sh
            echo "export LC_ALL=zh_CN.UTF-8" >> /etc/profile.d/locale.sh
            chmod +x /etc/profile.d/locale.sh
            ;;
    esac
    
    # 设置环境变量立即生效
    export LANG=zh_CN.UTF-8
    export LANGUAGE=zh_CN:zh
    export LC_ALL=zh_CN.UTF-8
}

# 验证配置
verify_configuration() {
    echo -e "${GREEN}验证配置...${NC}"
    
    # 检查locale命令是否有错误输出
    if locale 2>&1 | grep -q "Cannot set LC_"; then
        echo -e "${RED}错误: locale配置存在问题${NC}"
        locale 2>&1 | grep "Cannot set LC_"
        return 1
    fi
    
    # 检查是否所有locale组件都设置为中文
    incomplete_config=$(locale | grep -v "zh_CN" | grep -vE "LC_ALL=|LANG=|LANGUAGE=|^$")
    if [ -n "$incomplete_config" ]; then
        echo -e "${YELLOW}警告: 部分locale组件未设置为中文:${NC}"
        echo "$incomplete_config"
        return 1
    fi
    
    echo -e "${GREEN}中文环境配置成功!${NC}"
    return 0
}

# 主函数
main() {
    check_root "$@"
    detect_distro
    
    # 检查是否已配置中文环境
    if check_current_locale; then
        if verify_configuration; then
            echo -e "${GREEN}系统已正确配置中文环境，无需更改。${NC}"
            exit 0
        else
            echo -e "${YELLOW}当前中文环境配置不完整，尝试修复...${NC}"
        fi
    fi
    
    # 安装必要依赖
    install_dependencies
    
    # 生成中文locale
    generate_chinese_locale
    
    # 配置中文环境
    configure_chinese_locale
    
    # 验证配置
    if ! verify_configuration; then
        echo -e "${RED}错误: 中文环境配置失败${NC}"
        echo -e "可能原因:"
        echo -e "1. 您的系统镜像不包含中文语言包"
        echo -e "2. 网络问题导致无法下载语言包"
        echo -e "3. 系统软件源配置不正确"
        echo -e "4. 缺少必要的locale数据文件"
        
        # 对于Ubuntu/Debian系统，尝试更彻底的修复
        if [[ "$DISTRO" == "ubuntu" || "$DISTRO" == "debian" ]]; then
            echo -e "${YELLOW}尝试更彻底的修复...${NC}"
            # 重新配置locales包
            dpkg-reconfigure locales
            # 重新生成locale
            locale-gen zh_CN.UTF-8
            # 重新配置
            configure_chinese_locale
            # 再次验证
            if verify_configuration; then
                echo -e "${GREEN}修复成功!${NC}"
                exit 0
            fi
        fi
        
        exit 1
    fi
    
     echo -e "\n${YELLOW}中文环境配置完成！某些更改需要重启才能完全生效。${NC}"
     echo -e "${YELLOW}按 Enter 回车键 立即重启，或输入 n 取消:${NC} "
     read -p "[默认: 立即重启] " choice
     case "$choice" in
          n|N ) 
         echo -e "${YELLOW}已取消重启，请稍后手动执行 'reboot' 命令。${NC}"
         ;;
        * ) 
        echo -e "${GREEN}正在准备重启系统...${NC}"
        reboot
        ;;
    esac
}

main "$@"
