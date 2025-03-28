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
declare -g -a REQUIRED_PKGS=()
declare -g -a OPTIONAL_PKGS=()
declare -g OS_ID=""
declare -g OS_VERSION=""

# 静默输出控制
exec 3>&1
exec >/dev/null 2>&1

# 检查sudo权限
check_sudo() {
    echo -e "${CYAN}[信息] 检查sudo权限...${NC}" >&3
    if ! sudo -v; then
        echo -e "${RED}[错误] 需要sudo权限或认证失败，请确保用户具有sudo权限${NC}" >&3
        exit 1
    fi
}

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
                REQUIRED_PKGS=("locales")
                OPTIONAL_PKGS=("fonts-wqy-zenhei" "fonts-noto-cjk")
                ;;
            centos|rhel|rocky|almalinux)
                PKG_MANAGER="yum"
                REQUIRED_PKGS=("glibc-langpack-zh")
                OPTIONAL_PKGS=("fonts-chinese")
                # 检查并启用EPEL仓库
                if ! rpm -q epel-release >/dev/null 2>&1; then
                    echo -e "${CYAN}[信息] 启用EPEL仓库...${NC}" >&3
                    sudo yum install -y epel-release || {
                        echo -e "${RED}[错误] 无法启用EPEL仓库，可能影响后续安装${NC}" >&3
                    }
                fi
                ;;
            fedora)
                PKG_MANAGER="dnf"
                REQUIRED_PKGS=("glibc-langpack-zh")
                OPTIONAL_PKGS=("google-noto-sans-cjk-ttc-fonts")
                ;;
            arch|manjaro)
                PKG_MANAGER="pacman"
                REQUIRED_PKGS=("noto-fonts-cjk")
                OPTIONAL_PKGS=("ttf-arphic-uming")
                ;;
            opensuse*|sles)
                PKG_MANAGER="zypper"
                REQUIRED_PKGS=("glibc-locale")
                OPTIONAL_PKGS=("fonts-config")
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

# 检查中文环境
check_locale() {
    echo -e "${CYAN}[信息] 检查语言环境...${NC}" >&3
    local current_lang
    current_lang=$(locale | awk -F= '/LANG/{print $2}' | tr -d '"' | tr -d "'")
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
            sudo apt update || {
                echo -e "${RED}[错误] 软件源更新失败，请检查网络连接${NC}" >&3
                exit 1
            }
            # 安装必须包
            sudo apt install -y "${REQUIRED_PKGS[@]}" || {
                echo -e "${RED}[错误] 必须的软件包安装失败: ${REQUIRED_PKGS[*]}${NC}" >&3
                exit 1
            }
            # 安装可选包
            if [[ ${#OPTIONAL_PKGS[@]} -gt 0 ]]; then
                sudo apt install -y "${OPTIONAL_PKGS[@]}" || {
                    echo -e "${YELLOW}[警告] 可选软件包安装失败: ${OPTIONAL_PKGS[*]}${NC}" >&3
                }
            fi
            ;;
        yum|dnf)
            sudo "${PKG_MANAGER}" install -y "${REQUIRED_PKGS[@]}" || {
                echo -e "${RED}[错误] 必须的软件包安装失败: ${REQUIRED_PKGS[*]}${NC}" >&3
                exit 1
            }
            if [[ ${#OPTIONAL_PKGS[@]} -gt 0 ]]; then
                sudo "${PKG_MANAGER}" install -y "${OPTIONAL_PKGS[@]}" --skip-broken || {
                    echo -e "${YELLOW}[警告] 部分可选软件包安装失败${NC}" >&3
                }
            fi
            ;;
        pacman)
            sudo pacman -Sy --noconfirm "${REQUIRED_PKGS[@]}" || {
                echo -e "${RED}[错误] 必须的软件包安装失败: ${REQUIRED_PKGS[*]}${NC}" >&3
                exit 1
            }
            if [[ ${#OPTIONAL_PKGS[@]} -gt 0 ]]; then
                sudo pacman -Sy --noconfirm "${OPTIONAL_PKGS[@]}" || {
                    echo -e "${YELLOW}[警告] 可选软件包安装失败: ${OPTIONAL_PKGS[*]}${NC}" >&3
                }
            fi
            ;;
        zypper)
            sudo zypper -n in "${REQUIRED_PKGS[@]}" || {
                echo -e "${RED}[错误] 必须的软件包安装失败: ${REQUIRED_PKGS[*]}${NC}" >&3
                exit 1
            }
            if [[ ${#OPTIONAL_PKGS[@]} -gt 0 ]]; then
                sudo zypper -n in "${OPTIONAL_PKGS[@]}" || {
                    echo -e "${YELLOW}[警告] 可选软件包安装失败: ${OPTIONAL_PKGS[*]}${NC}" >&3
                }
            fi
            ;;
    esac
    echo -e "${GREEN}[成功] 中文支持安装完成${NC}" >&3
}

# 生成并配置Locale
configure_locale() {
    echo -e "${CYAN}[信息] 配置语言环境...${NC}" >&3
    case "${OS_ID}" in
        ubuntu|debian)
            echo -e "${BLUE}[操作] 生成中文locale...${NC}" >&3
            sudo sed -i '/zh_CN.UTF-8/s/^#//g' /etc/locale.gen || {
                echo -e "${RED}[错误] 无法修改/etc/locale.gen${NC}" >&3
                exit 1
            }
            sudo locale-gen zh_CN.UTF-8 || {
                echo -e "${RED}[错误] 生成locale失败${NC}" >&3
                exit 1
            }
            sudo update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 || {
                echo -e "${RED}[错误] 更新locale设置失败${NC}" >&3
                exit 1
            }
            ;;
        centos|rhel|rocky|almalinux|fedora)
            echo 'LANG="zh_CN.UTF-8"' | sudo tee /etc/locale.conf >/dev/null || {
                echo -e "${RED}[错误] 无法写入/etc/locale.conf${NC}" >&3
                exit 1
            }
            sudo localectl set-locale LANG=zh_CN.UTF-8 || {
                echo -e "${RED}[错误] 设置locale失败${NC}" >&3
                exit 1
            }
            ;;
        arch|manjaro)
            sudo sed -i '/zh_CN.UTF-8/s/^#//g' /etc/locale.gen || {
                echo -e "${RED}[错误] 无法修改/etc/locale.gen${NC}" >&3
                exit 1
            }
            sudo locale-gen || {
                echo -e "${RED}[错误] 生成locale失败${NC}" >&3
                exit 1
            }
            echo 'LANG=zh_CN.UTF-8' | sudo tee /etc/locale.conf >/dev/null || {
                echo -e "${RED}[错误] 无法写入/etc/locale.conf${NC}" >&3
                exit 1
            }
            ;;
        opensuse*|sles)
            sudo localectl set-locale LANG=zh_CN.UTF-8 || {
                echo -e "${RED}[错误] 设置locale失败${NC}" >&3
                exit 1
            }
            ;;
    esac

    # 全局环境变量
    echo 'export LANG=zh_CN.UTF-8' | sudo tee /etc/profile.d/lang.sh >/dev/null
    echo 'export LC_ALL=zh_CN.UTF-8' | sudo tee -a /etc/profile.d/lang.sh >/dev/null
    source /etc/profile.d/lang.sh
    echo -e "${GREEN}[成功] 语言环境配置完成${NC}" >&3
}

验证配置
verify_config() {
    echo -e "${CYAN}[信息] 验证配置...${NC}" >&3
    local config_ok=1
    case "${OS_ID}" in
        ubuntu|debian)
            if grep -q "LANG=zh_CN.UTF-8" /etc/default/locale; then
                config_ok=0
            fi
            ;;
        centos|rhel|rocky|almalinux|fedora|arch|manjaro)
            if grep -q "LANG=zh_CN.UTF-8" /etc/locale.conf; then
                config_ok=0
            fi
            ;;
        opensuse*|sles)
            if localectl status | grep -q "zh_CN.UTF-8"; then
                config_ok=0
            fi
            ;;
    esac

    if [[ $config_ok -eq 0 ]]; then
        echo -e "${GREEN}[系统配置验证通过] 中文环境已正确设置${NC}" >&3
    else
        echo -e "${RED}[错误] 系统配置文件未正确设置${NC}" >&3
        exit 1
    fi

检查当前环境
    if locale | grep -q "zh_CN.UTF-8"; then
        echo -e "${GREEN}[当前环境验证通过] 语言环境已生效${NC}" >&3
    else
        echo -e "${YELLOW}[警告] 当前会话环境未生效，请检查以下文件：" >&3
        echo -e "  /.bashrc, /.profile, ~/.bash_profile 等是否覆盖了LANG设置${NC}" >&3
        echo -e "  可执行以下命令立即生效: ${GREEN}source /etc/profile.d/lang.sh${NC}" >&3
    fi
}

主流程
main() {
    check_sudo
    detect_os
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

执行入口
main "$@"
