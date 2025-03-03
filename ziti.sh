#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # 恢复默认颜色

# 初始化变量
PKG_MANAGER=""
LANG_PACKAGE=""
SUPPORT_PKGS=()
OS_ID=""

# 检测系统发行版
detect_os() {
    echo -e "${CYAN}[信息] 正在检测系统发行版...${NC}"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        case $ID in
            ubuntu|debian)
                PKG_MANAGER="apt"
                LANG_PACKAGE="language-pack-zh-hans"
                SUPPORT_PKGS=("language-pack-zh-hans" "language-pack-zh-hans-base")
                ;;
            centos|rhel|rocky)
                PKG_MANAGER="yum"
                LANG_PACKAGE="glibc-langpack-zh"
                ;;
            fedora)
                PKG_MANAGER="dnf"
                LANG_PACKAGE="glibc-langpack-zh"
                ;;
            arch|manjaro)
                PKG_MANAGER="pacman"
                LANG_PACKAGE="glibc"
                ;;
            opensuse*|sles)
                PKG_MANAGER="zypper"
                LANG_PACKAGE="glibc-locale-zh"
                ;;
            *)
                echo -e "${RED}[错误] 不支持的Linux发行版: $ID${NC}"
                exit 1
                ;;
        esac
        echo -e "${GREEN}[成功] 检测到系统发行版: $PRETTY_NAME${NC}"
        sleep 0.5
    else
        echo -e "${RED}[错误] 无法检测系统发行版${NC}"
        exit 1
    fi
}

# 检查中文环境是否已配置
check_locale() {
    echo -e "${CYAN}[信息] 正在检查语言环境设置...${NC}"
    if [ "$(locale | grep -w LANG | cut -d= -f2)" = "zh_CN.UTF-8" ]; then
        echo -e "${GREEN}[成功] 中文语言环境已正确设置${NC}"
        return 0
    else
        echo -e "${YELLOW}[警告] 当前未设置中文语言环境${NC}"
        return 1
    fi
    sleep 0.5
}

# 安装中文语言包（含备用方案）
install_lang_pkg() {
    echo -e "${CYAN}[信息] 正在尝试安装中文语言包...${NC}"
    case $PKG_MANAGER in
        apt)
            sudo apt update >/dev/null 2>&1
            for pkg in "${SUPPORT_PKGS[@]}"; do
                echo -e "${BLUE}[操作] 尝试安装包: $pkg${NC}"
                if sudo apt install -y "$pkg" >/dev/null 2>&1; then
                    echo -e "${GREEN}[成功] 安装 $pkg 成功${NC}"
                    return 0
                fi
            done
            ;;
        yum|dnf)
            sudo $PKG_MANAGER install -y "$LANG_PACKAGE" >/dev/null 2>&1
            ;;
        pacman)
            sudo pacman -Sy --noconfirm "$LANG_PACKAGE" >/dev/null 2>&1
            ;;
        zypper)
            sudo zypper in -y "$LANG_PACKAGE" >/dev/null 2>&1
            ;;
    esac

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[成功] 中文语言包安装完成${NC}"
    else
        echo -e "${RED}[错误] 无法安装中文语言包，请手动安装${NC}"
        exit 1
    fi
    sleep 0.5
}

# 配置系统语言环境
configure_locale() {
    echo -e "${CYAN}[信息] 正在配置系统语言环境...${NC}"
    case $OS_ID in
        ubuntu|debian)
            echo -e "${BLUE}[操作] 更新locale配置${NC}"
            sudo update-locale LANG=zh_CN.UTF-8 >/dev/null 2>&1
            sudo locale-gen zh_CN.UTF-8 >/dev/null 2>&1
            ;;
        centos|rhel|fedora|rocky)
            echo -e "${BLUE}[操作] 设置系统级locale${NC}"
            echo 'LANG="zh_CN.UTF-8"' | sudo tee /etc/locale.conf >/dev/null
            sudo localectl set-locale LANG=zh_CN.UTF-8 >/dev/null 2>&1
            ;;
        arch|manjaro)
            echo -e "${BLUE}[操作] 生成locale配置${NC}"
            sudo sed -i 's/#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
            sudo locale-gen >/dev/null 2>&1
            echo 'LANG=zh_CN.UTF-8' | sudo tee /etc/locale.conf >/dev/null
            ;;
        opensuse*|sles)
            echo -e "${BLUE}[操作] 设置系统locale${NC}"
            sudo localectl set-locale LANG=zh_CN.UTF-8 >/dev/null 2>&1
            ;;
    esac

    # 应用环境变量
    export LANG=zh_CN.UTF-8
    echo -e "${GREEN}[成功] 中文语言环境配置完成${NC}"
    sleep 0.5
}

# 验证环境配置
verify_config() {
    echo -e "${CYAN}[信息] 正在验证最终配置...${NC}"
    if check_locale; then
        echo -e "${GREEN}[验证通过] 系统已成功配置中文语言环境${NC}"
    else
        echo -e "${RED}[错误] 语言环境配置失败，请手动检查${NC}"
        exit 1
    fi
    sleep 0.5
}

# 主执行流程
main() {
    detect_os
    if check_locale; then
        echo -e "${GREEN}[信息] 无需额外配置，直接退出${NC}"
        exit 0
    fi
    
    echo -e "${YELLOW}[操作] 需要安装中文语言支持${NC}"
    install_lang_pkg
    configure_locale
    verify_config
    
    echo -e "\n${CYAN}[提示] 部分变更可能需要重新登录或重启后生效${NC}"
    sleep 0.5
}

# 执行主函数
main
