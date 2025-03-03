#!/bin/bash

# 颜色定义
YELLOW='\033[93m'
BLUE='\033[94m'
RED='\033[91m'
NC='\033[0m' # 重置颜色

# 延时函数
step_delay() {
    sleep 0.3
}

# 检查 root 权限
check_root() {
    echo -e "${YELLOW}[1/6] 检查 root 权限...${NC}"
    step_delay
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误：必须使用 root 权限运行此脚本！${NC}" >&2
        exit 1
    else
        echo -e "${BLUE}√ 当前为 root 用户${NC}"
    fi
}

# 检测系统发行版
detect_distro() {
    echo -e "${YELLOW}[2/6] 检测系统发行版...${NC}"
    step_delay
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case $ID in
            debian|ubuntu)
                DISTRO="debian"
                echo -e "${BLUE}√ 检测到 Debian/Ubuntu 系统${NC}"
                ;;
            centos|rhel)
                DISTRO="centos"
                echo -e "${BLUE}√ 检测到 CentOS/RHEL 系统${NC}"
                ;;
            fedora)
                DISTRO="fedora"
                echo -e "${BLUE}√ 检测到 Fedora 系统${NC}"
                ;;
            *)
                echo -e "${RED}错误：不支持的发行版 $ID${NC}" >&2
                exit 1
                ;;
        esac
    else
        echo -e "${RED}错误：无法检测系统发行版${NC}" >&2
        exit 1
    fi
}

# 验证中文环境配置
verify_locale_config() {
    echo -e "${YELLOW}[*] 验证中文配置...${NC}"
    step_delay
    
    # 检查语言包
    case $DISTRO in
        debian)
            if ! dpkg -l | grep -q "language-pack-zh-hans"; then
                echo -e "${RED}× 中文语言包未正确安装${NC}"
                return 1
            fi
            ;;
        centos|fedora)
            if ! rpm -q glibc-langpack-zh &>/dev/null; then
                echo -e "${RED}× 中文语言包未正确安装${NC}"
                return 1
            fi
            ;;
    esac

    # 检查配置文件
    case $DISTRO in
        debian)
            if ! grep -q "LANG=zh_CN.UTF-8" /etc/default/locale; then
                echo -e "${RED}× 系统 locale 配置错误${NC}"
                return 1
            fi
            ;;
        centos|fedora)
            if ! grep -q "LANG=zh_CN.UTF-8" /etc/locale.conf; then
                echo -e "${RED}× 系统 locale 配置错误${NC}"
                return 1
            fi
            ;;
    esac

    # 检查可用locale
    if ! locale -a | grep -qi "zh_CN.utf8"; then
        echo -e "${RED}× 中文 locale 未生成${NC}"
        return 1
    fi

    echo -e "${BLUE}√ 中文环境配置完整正确${NC}"
    return 0
}

# 检查当前语言环境
check_current_locale() {
    echo -e "${YELLOW}[3/6] 检查语言环境...${NC}"
    step_delay
    if [[ "$LANG" == *"zh_CN"* ]] || [[ "$LC_ALL" == *"zh_CN"* ]]; then
        echo -e "${BLUE}√ 系统已处于中文环境${NC}"
        if verify_locale_config; then
            exit 0
        else
            echo -e "${YELLOW}⚠ 检测到配置不完整，需要修复...${NC}"
            return 1
        fi
    else
        echo -e "${YELLOW}× 当前不是中文环境${NC}"
        return 1
    fi
}

# 安装中文语言包
install_package() {
    echo -e "${YELLOW}[4/6] 安装语言包...${NC}"
    step_delay
    case $DISTRO in
        debian)
            apt-get update -q
            apt-get install -y language-pack-zh-hans
            ;;
        centos)
            yum install -y glibc-langpack-zh
            ;;
        fedora)
            dnf install -y glibc-langpack-zh
            ;;
    esac
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误：语言包安装失败！${NC}" >&2
        exit 1
    fi
    echo -e "${BLUE}√ 语言包安装成功${NC}"
}

# 配置系统环境
configure_locale() {
    echo -e "${YELLOW}[5/6] 配置系统参数...${NC}"
    step_delay
    case $DISTRO in
        debian)
            locale-gen zh_CN.UTF-8
            update-locale LANG=zh_CN.UTF-8
            ;;
        centos|fedora)
            localectl set-locale LANG=zh_CN.UTF-8
            ;;
    esac
    echo -e "${BLUE}√ 系统参数配置完成${NC}"
}

# 最终验证
final_check() {
    echo -e "${YELLOW}[6/6] 最终验证...${NC}"
    step_delay
    if verify_locale_config; then
        echo -e "${BLUE}✔✔✔ 中文环境配置成功 ✔✔✔${NC}"
        echo -e "${YELLOW}请执行以下命令使环境生效：${NC}"
        echo "source /etc/default/locale # Debian/Ubuntu"
        echo "source /etc/locale.conf    # CentOS/Fedora"
    else
        echo -e "${RED}⚠⚠⚠ 中文环境配置失败 ⚠⚠⚠${NC}"
        exit 1
    fi
}

# 主逻辑
main() {
    check_root
    detect_distro
    check_current_locale
    install_package
    configure_locale
    final_check
}

# 执行主程序
main
