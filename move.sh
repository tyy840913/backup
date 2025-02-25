#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# 依赖检查及安装
check_dependencies() {
    local missing=()
    
    # 检测 tput (ncurses)
    if ! command -v tput &> /dev/null; then
        missing+=("ncurses")
    fi
    
    # 检测 Alpine 系统的 bash
    if [[ -f /etc/alpine-release ]] && ! command -v bash &> /dev/null; then
        missing+=("bash")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}缺少必要依赖：${missing[*]}${NC}"
        read -p "是否自动安装？[Y/n] " confirm
        confirm=${confirm:-Y}
        if [[ "${confirm^^}" == "Y" ]]; then
            install_dependencies "${missing[@]}"
        else
            echo -e "${RED}依赖不完整，脚本终止${NC}"
            exit 1
        fi
    fi
}

install_dependencies() {
    echo -e "${YELLOW}正在安装依赖：$*${NC}"
    
    if command -v apk &> /dev/null; then
        apk update && apk add --no-cache "$@" || {
            echo -e "${RED}Alpine 依赖安装失败${NC}"
            exit 1
        }
    elif command -v apt &> /dev/null; then
        apt-get update -qq && apt-get install -y "$@" > /dev/null || {
            echo -e "${RED}Debian/Ubuntu 依赖安装失败${NC}"
            exit 1
        }
    elif command -v dnf &> /dev/null; then
        dnf install -y -q "$@" > /dev/null || {
            echo -e "${RED}Fedora 依赖安装失败${NC}"
            exit 1
        }
    elif command -v yum &> /dev/null; then
        yum install -y -q "$@" > /dev/null || {
            echo -e "${RED}CentOS 依赖安装失败${NC}"
            exit 1
        }
    elif command -v pacman &> /dev/null; then
        pacman -Sy --noconfirm "$@" > /dev/null || {
            echo -e "${RED}Arch 依赖安装失败${NC}"
            exit 1
        }
    else
        echo -e "${RED}不支持的包管理器${NC}"
        exit 1
    fi
    echo -e "${GREEN}依赖安装完成${NC}"
}

# 包管理器检测
detect_pkgmgr() {
    declare -g PKGMGR PKG_LIST_CMD PKG_REMOVE_CMD
    
    if command -v apk &> /dev/null; then
        PKGMGR="apk"
        PKG_LIST_CMD="apk info | sort"
        PKG_REMOVE_CMD="apk del --no-progress"
    elif command -v apt &> /dev/null; then
        PKGMGR="apt"
        PKG_LIST_CMD="apt list --installed 2>/dev/null | awk -F'/' '/\\/]/{print \$1}' | sort"
        PKG_REMOVE_CMD="apt remove -y"
    elif command -v dnf &> /dev/null; then
        PKGMGR="dnf"
        PKG_LIST_CMD="dnf list installed | awk '{print \$1}' | cut -d'-' -f1 | sort"
        PKG_REMOVE_CMD="dnf remove -y"
    elif command -v yum &> /dev/null; then
        PKGMGR="yum"
        PKG_LIST_CMD="yum list installed | awk '{print \$1}' | cut -d'-' -f1 | sort"
        PKG_REMOVE_CMD="yum remove -y"
    elif command -v pacman &> /dev/null; then
        PKGMGR="pacman"
        PKG_LIST_CMD="pacman -Qq | sort"
        PKG_REMOVE_CMD="pacman -Rns --noconfirm"
    else
        echo -e "${RED}不支持的发行版${NC}"
        exit 1
    fi
}

# 多列显示
show_pkg_list() {
    clear
    echo -e "${YELLOW}已安装软件包列表 ($PKGMGR)：${NC}"
    echo "======================================================================"

    # 获取终端尺寸
    local term_width=80
    if command -v tput &> /dev/null; then
        term_width=$(tput cols)
        [[ $term_width -lt 80 ]] && term_width=80
    fi

    local max_width=30
    local cols=$(( (term_width - 4) / (max_width + 4) ))
    [[ $cols -lt 1 ]] && cols=1

    local i=0
    for index in "${!INSTALLED_PKGS[@]}"; do
        printf "%-4s%-${max_width}s" "$((index+1))" "${INSTALLED_PKGS[index]}"
        ((i++))
        if ((i % cols == 0)); then
            printf "\n"
        fi
    done
    [[ $((i % cols)) -ne 0 ]] && printf "\n"
    
    echo "======================================================================"
}

# 主逻辑
main() {
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}需要root权限运行，请使用sudo执行！${NC}"
        exit 1
    fi

    check_dependencies
    detect_pkgmgr

    # 获取包列表
    mapfile -t INSTALLED_PKGS < <(eval "$PKG_LIST_CMD")
    local count=${#INSTALLED_PKGS[@]}
    [[ $count -eq 0 ]] && {
        echo -e "${YELLOW}没有找到已安装的软件包${NC}"
        exit 0
    }

    show_pkg_list

    # 用户输入处理
    while true; do
        read -p "请输入要卸载的软件包序号（多个用空格分隔，q退出）: " input
        [[ "$input" == "q" ]] && exit 0
        
        read -ra selections <<< "$input"
        local valid=true
        declare -a to_remove

        for sel in "${selections[@]}"; do
            if [[ $sel =~ ^[0-9]+$ ]] && ((sel >= 1 && sel <= count)); then
                to_remove+=("${INSTALLED_PKGS[sel-1]}")
            else
                echo -e "${RED}无效序号：$sel${NC}"
                valid=false
            fi
        done

        if $valid && [[ ${#to_remove[@]} -gt 0 ]]; then
            echo -e "\n${YELLOW}即将卸载以下软件包：${NC}"
            printf "%s\n" "${to_remove[@]}"
            read -p "确认卸载？[y/N] " confirm
            confirm=${confirm:-N}
            if [[ "${confirm^^}" == "Y" ]]; then
                echo -e "${YELLOW}正在卸载...${NC}"
                if ! eval "$PKG_REMOVE_CMD ${to_remove[*]}"; then
                    echo -e "${RED}卸载过程中发生错误${NC}"
                    exit 1
                fi
                echo -e "${GREEN}卸载完成${NC}"
                exit 0
            else
                echo -e "${YELLOW}取消操作${NC}"
                exit 0
            fi
        else
            echo -e "${RED}输入有误，请重新选择${NC}"
        fi
    done
}

main "$@"
