#!/bin/bash
set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 初始化变量
declare -g PKG_MANAGER=""
declare -g -a SUPPORT_PKGS=()
declare -g OS_ID=""
declare -g OS_VERSION=""

# 处理参数
VERBOSE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            echo "用法: $0 [选项]"
            echo "配置系统的中文环境支持。"
            echo "选项:"
            echo "  -h, --help     显示帮助信息"
            echo "  -v, --verbose  启用详细输出"
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo -e "${RED}[错误] 未知参数: $1${NC}" >&3
            exit 1
            ;;
    esac
done

# 输出控制
exec 3>&1
if $VERBOSE; then
    exec >&3 2>&3
else
    exec >/dev/null 2>&1
fi

# 检测系统发行版
detect_os() {
    echo -e "${CYAN}[信息] 检测系统发行版...${NC}" >&3
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_VERSION="${VERSION_ID:-}"
        case "${ID}" in
            ubuntu|debian)
                PKG_MANAGER="apt"
                SUPPORT_PKGS=("locales" "fonts-wqy-zenhei" "fonts-noto-cjk")
                ;;
            centos|rhel|rocky|almalinux)
                PKG_MANAGER="yum"
                if [[ "${OS_VERSION%%.*}" -ge 8 ]]; then
                    SUPPORT_PKGS=("glibc-langpack-zh" "wqy-zenhei-fonts")
                else
                    SUPPORT_PKGS=("glibc-common" "fonts-chinese")
                fi
                ;;
            fedora)
                PKG_MANAGER="dnf"
                SUPPORT_PKGS=("glibc-langpack-zh" "google-noto-sans-cjk-ttc-fonts")
                ;;
            arch|manjaro)
                PKG_MANAGER="pacman"
                SUPPORT_PKGS=("noto-fonts-cjk" "ttf-arphic-uming")
                ;;
            opensuse*|sles)
                PKG_MANAGER="zypper"
                SUPPORT_PKGS=("glibc-locale-zh" "fonts-config")
                ;;
            *)
                echo -e "${RED}[错误] 不支持的发行版: ${PRETTY_NAME:-$ID}${NC}" >&3
                exit 1
                ;;
        esac
        echo -e "${GREEN}[成功] 检测到系统: ${PRETTY_NAME:-$ID}${NC}" >&3
    else
        echo -e "${RED}[错误] 无法识别系统发行版${NC}" >&3
        exit 1
    fi
}

# 检查sudo权限
check_sudo() {
    echo -e "${CYAN}[信息] 检查sudo权限...${NC}" >&3
    if ! sudo -v >/dev/null 2>&1; then
        echo -e "${RED}[错误] 需要sudo权限来运行此脚本。请以具有sudo权限的用户身份运行。${NC}" >&3
        exit 1
    fi
    echo -e "${GREEN}[成功] 用户具有sudo权限。${NC}" >&3
}

# 检查中文环境
check_locale() {
    echo -e "${CYAN}[信息] 检查语言环境...${NC}" >&3
    local current_lang
    current_lang=$(locale 2>/dev/null | awk -F= '/LANG/{print $2}' | tr -d '"')
    if [[ "${current_lang}" == "zh_CN.UTF-8" ]]; then
        echo -e "${GREEN}[通过] 当前语言环境: zh_CN.UTF-8${NC}" >&3
        return 0
    else
        echo -e "${YELLOW}[警告] 当前语言环境: ${current_lang:-未设置}${NC}" >&3
        return 1
    fi
}

# 安装语言包
install_lang_pkg() {
    echo -e "${CYAN}[信息] 安装中文支持...${NC}" >&3
    case "${PKG_MANAGER}" in
        apt)
            sudo apt update
            for pkg in "${SUPPORT_PKGS[@]}"; do
                if ! sudo apt install -y "$pkg"; then
                    echo -e "${YELLOW}[警告] 包 $pkg 安装失败，可能影响后续配置。${NC}" >&3
                fi
            done
            ;;
        yum|dnf)
            for pkg in "${SUPPORT_PKGS[@]}"; do
                if ! sudo "${PKG_MANAGER}" install -y "$pkg"; then
                    echo -e "${YELLOW}[警告] 包 $pkg 安装失败，可能不存在或已安装。${NC}" >&3
                fi
            done
            ;;
        pacman)
            sudo pacman -Sy --noconfirm "${SUPPORT_PKGS[@]}" || {
                echo -e "${RED}[错误] 安装失败，请手动执行: sudo pacman -Sy ${SUPPORT_PKGS[*]}${NC}" >&3
                exit 1
            }
            ;;
        zypper)
            for pkg in "${SUPPORT_PKGS[@]}"; do
                if ! sudo zypper -n in "$pkg"; then
                    echo -e "${YELLOW}[警告] 包 $pkg 安装失败，可能不存在或已安装。${NC}" >&3
                fi
            done
            ;;
    esac
    echo -e "${GREEN}[成功] 中文支持安装完成${NC}" >&3
}

# 生成并配置Locale
configure_locale() {
    echo -e "${CYAN}[信息] 配置语言环境...${NC}" >&3
    case "${OS_ID}" in
        ubuntu|debian)
            sudo sed -i '/zh_CN.UTF-8/s/^#//g' /etc/locale.gen
            sudo locale-gen zh_CN.UTF-8
            sudo update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8
            ;;
        centos|rhel|rocky|almalinux|fedora)
            echo 'LANG="zh_CN.UTF-8"' | sudo tee /etc/locale.conf >/dev/null
            sudo localectl set-locale LANG=zh_CN.UTF-8
            ;;
        arch|manjaro)
            sudo sed -i '/zh_CN.UTF-8/s/^#//g' /etc/locale.gen
            sudo locale-gen
            echo 'LANG=zh_CN.UTF-8' | sudo tee /etc/locale.conf >/dev/null
            ;;
        opensuse*|sles)
            sudo localectl set-locale LANG=zh_CN.UTF-8
            ;;
    esac

    # 全局环境变量
    echo 'export LANG=zh_CN.UTF-8' | sudo tee /etc/profile.d/lang.sh >/dev/null
    echo 'export LC_ALL=zh_CN.UTF-8' | sudo tee -a /etc/profile.d/lang.sh >/dev/null
    source /etc/profile.d/lang.sh
    echo -e "${GREEN}[成功] 语言环境配置完成${NC}" >&3
}

# 验证配置
verify_config() {
    echo -e "${CYAN}[信息] 验证配置...${NC}" >&3
    # 检查生成的locale是否存在
    if ! locale -a | grep -qi "zh_cn.utf8"; then
        echo -e "${RED}[错误] 中文locale未生成，请检查语言包安装。${NC}" >&3
        exit 1
    fi
    # 检查环境变量
    if ! locale | grep -q "zh_CN.UTF-8"; then
        echo -e "${RED}[错误] 配置失败，请检查以下文件：" >&3
        echo -e "  /etc/default/locale (Debian/Ubuntu)" >&3
        echo -e "  /etc/locale.conf (CentOS/Arch)" >&3
        echo -e "  /etc/profile.d/lang.sh${NC}" >&3
        exit 1
    fi
    echo -e "${GREEN}[验证通过] 中文环境已正确配置${NC}" >&3  # 修改为简单提示
}

# 主流程
main() {
    detect_os
    check_sudo
    if check_locale; then
        echo -e "${GREEN}[跳过] 中文环境已配置，无需操作${NC}" >&3
        exit 0
    fi
    
    install_lang_pkg
    configure_locale
    verify_config
    
    echo -e "\n${YELLOW}[提示] 部分变更需要重新登录或重启后生效！${NC}" >&3
    echo -e "  立即重启：${GREEN}sudo reboot${NC}" >&3
    echo -e "  或手动加载环境变量：${GREEN}source /etc/profile.d/lang.sh${NC}" >&3
}

# 执行入口
main "$@"
