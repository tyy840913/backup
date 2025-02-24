#!/bin/bash

# 配置信息
NUTSTORE_DIR="https://dav.jianguoyun.com/dav/backup/docker_data"

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
MAGENTA='\033[35m'
CYAN='\033[36m'
BOLD='\033[1m'
RESET='\033[0m'

# 依赖管理函数
detect_pkg_manager() {
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
    elif command -v apk &> /dev/null; then
        PKG_MANAGER="apk"
    else
        echo -e "${RED}不支持的包管理器！${RESET}"
        exit 1
    fi
}

install_dependencies() {
    local REQUIRED_DEPS=("curl" "ca-certificates")
    echo -e "${CYAN}检测到包管理器：${PKG_MANAGER}${RESET}"
    
    # 更新包索引
    case $PKG_MANAGER in
        "apt") apt-get update -y ;;
        "yum") yum makecache -y ;;
        "apk") apk update ;;
    esac
    
    # 安装依赖
    for pkg in "${REQUIRED_DEPS[@]}"; do
        if ! command -v $pkg &> /dev/null; then
            echo -e "${BLUE}正在安装依赖：$pkg...${RESET}"
            case $PKG_MANAGER in
                "apt") apt-get install -y $pkg ;;
                "yum") yum install -y $pkg ;;
                "apk") apk add --no-cache $pkg ;;
            esac
            if [ $? -ne 0 ]; then
                echo -e "${RED}安装 $pkg 失败，请手动安装后重试！${RESET}"
                exit 1
            fi
        fi
    done
    
    # 特殊处理：Alpine系统需要安装openssl
    if [ "$PKG_MANAGER" = "apk" ] && ! command -v openssl &> /dev/null; then
        echo -e "${BLUE}正在安装OpenSSL...${RESET}"
        apk add --no-cache openssl
    fi
}

# 分隔线函数
print_separator() {
    echo -e "${MAGENTA}===================================================${RESET}"
}

# 初始化系统检测
detect_pkg_manager
install_dependencies

# 主循环
while true; do
    # 显示欢迎界面
    clear
    echo -e "${BOLD}${CYAN}"
    cat << "EOF"
 _           _        _ _       _____ _               ___    ___  ___ _____ 
| |         | |      | | |     /  __ \ |             / _ \  |  \/  ||  ___|
| |     ___ | |_ __ _| | | ___ | /  \/ |__   ___  __/ /_\ \ | .  . || |__  
| |    / _ \| __/ _` | | |/ _ \| |   | '_ \ / _ \/_ |  _  | | |\/| ||  __| 
| |___| (_) | || (_| | | | (_) | \__/\ | | |  __/ (_| | | | | |  | || |___ 
\_____/\___/ \__\__,_|_|_|\___/ \____|_| |_|\___|   \_| |_/ \_|  |_/\____/ 
EOF
    echo -e "${RESET}"
    print_separator
    echo -e "${BOLD}${GREEN} 欢迎使用全能脚本管理平台 ${RESET}"
    echo -e "${YELLOW} * 自动检测到系统包管理器：${PKG_MANAGER}${RESET}"
    echo -e "${YELLOW} * 已确保基础依赖（curl/ssl）正常${RESET}"
    print_separator
    
    # 菜单选项
    menu_items=(
        "1) 自动备份脚本 (auto.sh)"
        "2) 自动下载脚本 (download.sh)"
        "3) 时区修改脚本 (time.sh)"
        "4) 系统源更新脚本 (update.sh)"
        "5) 退出"
    )
    
    # 显示菜单
    for item in "${menu_items[@]}"; do
        case $item in
            *auto.sh*)   color=${CYAN} ;;
            *download.sh*)color=${BLUE} ;;
            *time.sh*)   color=${GREEN} ;;
            *update.sh*) color=${YELLOW} ;;
            *)           color=${RESET} ;;
        esac
        echo -e "  ${color}${item}${RESET}"
    done
    print_separator
    
    # 获取用户选择
    while true; do
        read -p "$(echo -e "${BOLD}${CYAN}请选择操作 [1-5]: ${RESET}")" choice
        case $choice in
            1|2|3|4|5) break ;;
            *) echo -e "${RED}无效输入，请重新选择!${RESET}" ;;
        esac
    done
    
    # 处理用户选择
    case $choice in
        5)
            echo -e "${RED}退出系统...${RESET}"
            exit 0
            ;;
        *)
            case $choice in
                1) script="auto.sh";   need_auth=1 ;;
                2) script="download.sh"; need_auth=1 ;;
                3) script="time.sh";   need_auth=0 ;;
                4) script="update.sh"; need_auth=0 ;;
            esac
            
            # 设置脚本URL
            if [ $need_auth -eq 1 ]; then
                url="${NUTSTORE_DIR}/${script}"
            else
                url="https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/refs/heads/main/${script}"
            fi
            
            # 获取坚果云凭证（如果需要）
            if [ $need_auth -eq 1 ]; then
                if [[ -z $NUTSTORE_USER || -z $NUTSTORE_PASS ]]; then
                    read -p "请输入账号: " NUTSTORE_USER
                    read -s -p "请输入密码: " NUTSTORE_PASS
                    echo
                fi
                curl_args=(-u "${NUTSTORE_USER}:${NUTSTORE_PASS}" -sSL -f "$url")
            else
                curl_args=(-sSL -f "$url")
            fi
            
            # 执行远程脚本
            print_separator
            echo -e "${BOLD}${GREEN}▶ 正在下载并执行 ${script}...${RESET}"
            if bash -c "$(curl "${curl_args[@]}")"; then
                echo -e "${GREEN}✓ 脚本执行完成！${RESET}"
            else
                echo -e "${RED}✗ 操作失败，请检查："
                [ $need_auth -eq 1 ] && echo -e "1. 网络连接\n2. 认证信息"
                echo -e "3. 文件是否存在${RESET}"
            fi
            
            # 等待用户输入
            echo -e "\n${BOLD}${CYAN}按任意键返回主菜单...${RESET}"
            read -n 1 -s -r
            ;;
    esac
done
