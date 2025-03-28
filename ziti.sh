#!/bin/bash
# 多发行版中文环境配置脚本
# 功能：自动检测并配置系统中文环境，支持主流Linux发行版
# 作者：Shell脚本专家
# 版本：2.1
# 最后更新：2023-10-20

set -eo pipefail  # 遇到错误立即退出，管道命令错误处理

# 颜色定义用于输出美化
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 初始化变量
SUPPORTED_DISTROS=("debian" "ubuntu" "centos" "fedora" "arch" "opensuse")
PKG_MANAGER=""
CHINESE_PKGS=()
CURRENT_DISTRO=""
CONFIG_FILE="/etc/locale.conf"
LANG_SETTING="zh_CN.UTF-8"
DEPENDENCY_INSTALLED=false

# 日志输出函数
log() {
    local level=$1
    local message=$2
    case $level in
        "INFO") echo -e "${BLUE}[INFO]${NC} - $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} - $message" ;;
        "WARNING") echo -e "${YELLOW}[WARNING]${NC} - $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} - $message" >&2 ;;
    esac
}

# 错误处理函数
error_exit() {
    log "ERROR" "$1"
    exit 1
}

# 检测系统发行版
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        CURRENT_DISTRO=$ID
    else
        error_exit "无法检测系统发行版"
    fi

    if ! printf '%s\n' "${SUPPORTED_DISTROS[@]}" | grep -q "^$CURRENT_DISTRO$"; then
        error_exit "不支持的发行版: $CURRENT_DISTRO"
    fi
}

# 检测并设置包管理器
set_pkg_manager() {
    case $CURRENT_DISTRO in
        debian|ubuntu)
            PKG_MANAGER="apt-get"
            CHINESE_PKGS=("locales" "fonts-wqy-microhei")
            ;;
        centos|fedora)
            PKG_MANAGER="yum"
            [ "$CURRENT_DISTRO" == "fedora" ] && PKG_MANAGER="dnf"
            CHINESE_PKGS=("glibc-langpack-zh" "wqy-microhei-fonts")
            ;;
        arch)
            PKG_MANAGER="pacman"
            CHINESE_PKGS=("glibc" "wqy-microhei")
            ;;
        opensuse)
            PKG_MANAGER="zypper"
            CHINESE_PKGS=("glibc-locale" "wqy-microhei-fonts")
            ;;
    esac

    # 验证包管理器是否可用
    if ! command -v $PKG_MANAGER &> /dev/null; then
        error_exit "找不到包管理器: $PKG_MANAGER"
    fi
}

# 权限检测与提权处理
check_privilege() {
    if [ "$EUID" -ne 0 ]; then
        log "WARNING" "需要root权限"
        if command -v sudo &> /dev/null; then
            log "INFO" "尝试使用sudo提权"
            exec sudo "$0" "$@"
        else
            error_exit "需要root权限且未找到sudo命令"
        fi
    fi
}

# 检查中文locale是否已生成
check_locale_available() {
    if locale -a | grep -q "$LANG_SETTING"; then
        log "INFO" "中文locale已存在"
        return 0
    else
        log "WARNING" "中文locale未生成"
        return 1
    fi
}

# 检查是否已配置中文环境
check_current_lang() {
    if [ -f $CONFIG_FILE ] && grep -q "^LANG=.*zh_CN" $CONFIG_FILE; then
        log "INFO" "系统已配置中文环境"
        return 0
    elif [ "$LANG" = "$LANG_SETTING" ]; then
        log "INFO" "当前会话已使用中文环境"
        return 0
    else
        log "WARNING" "中文环境未配置"
        return 1
    fi
}

# 安装语言包
install_packages() {
    log "INFO" "开始安装中文支持包"
    local install_cmd

    case $CURRENT_DISTRO in
        debian|ubuntu)
            $PKG_MANAGER update >/dev/null || error_exit "包索引更新失败"
            $PKG_MANAGER install -y "${CHINESE_PKGS[@]}" >/dev/null
            dpkg-reconfigure --frontend=noninteractive locales >/dev/null
            ;;
        centos|fedora)
            $PKG_MANAGER install -y langpacks-zh glibc-langpack-zh >/dev/null
            localedef -v -c -i zh_CN -f UTF-8 zh_CN.UTF-8 >/dev/null
            ;;
        arch)
            $PKG_MANAGER -Sy --noconfirm "${CHINESE_PKGS[@]}" >/dev/null
            sed -i 's/#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
            locale-gen >/dev/null
            ;;
        opensuse)
            $PKG_MANAGER -n install -l -y "${CHINESE_PKGS[@]}" >/dev/null
            localectl set-locale LANG=$LANG_SETTING
            ;;
    esac || error_exit "包安装失败"

    DEPENDENCY_INSTALLED=true
    log "SUCCESS" "中文包安装完成"
}

# 配置系统语言环境
configure_locale() {
    log "INFO" "开始配置系统语言环境"
    
    # 多发行版兼容配置
    case $CURRENT_DISTRO in
        debian|ubuntu)
            update-locale LANG=$LANG_SETTING LC_ALL=$LANG_SETTING
            ;;
        centos|fedora|opensuse)
            localectl set-locale LANG=$LANG_SETTING
            ;;
        arch)
            echo "LANG=$LANG_SETTING" > $CONFIG_FILE
            ;;
    esac

    # 环境变量立即生效
    export LANG=$LANG_SETTING
    export LC_ALL=$LANG_SETTING
    source /etc/profile.d/locale.sh >/dev/null 2>&1 || true
}

# 验证配置结果
verify_configuration() {
    if check_current_lang; then
        log "SUCCESS" "中文环境配置验证成功"
        return 0
    else
        log "ERROR" "环境配置验证失败"
        return 1
    fi
}

# 主执行流程
main() {
    log "INFO" "开始中文环境配置流程"
    detect_distro
    log "INFO" "检测到系统发行版: $CURRENT_DISTRO"
    set_pkg_manager
    check_privilege "$@"

    if check_current_lang; then
        log "SUCCESS" "系统已正确配置中文环境，无需操作"
        exit 0
    fi

    if check_locale_available; then
        log "INFO" "尝试使用现有locale配置"
        configure_locale
        if verify_configuration; then
            log "SUCCESS" "成功使用现有包配置中文环境"
            exit 0
        fi
    fi

    install_packages
    configure_locale

    if ! verify_configuration; then
        error_exit "最终配置验证失败，请手动检查"
    fi

    log "SUCCESS" "中文环境配置完成，当前LANG: $LANG"
}

# 异常处理陷阱
trap 'log "ERROR" "脚本在行号 $LINENO 被中断，退出状态 $?"' ERR
trap 'log "WARNING" "用户中断操作"; exit 1' INT TERM

# 执行主函数
main "$@"
