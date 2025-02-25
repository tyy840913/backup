#!/bin/bash

# ======================
# 全局配置
# ======================
NUTSTORE_DIR="https://dav.woskee.nyc.mn:88/jianguoyun/backup"
declare -g NUTSTORE_USER NUTSTORE_PASS  # 声明全局变量

# ======================
# 颜色定义
# ======================
RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'
BLUE='\033[34m'; MAGENTA='\033[35m'; CYAN='\033[36m'
BOLD='\033[1m'; RESET='\033[0m'

# ======================
# 功能函数
# ======================
print_separator() {
    echo -e "${MAGENTA}===================================================${RESET}"
}

get_credentials() {
    read -p "请输入账号: " NUTSTORE_USER
    read -sp "请输入密码: " NUTSTORE_PASS
    echo
}

execute_script() {
    local script=$1
    local auth_opt=$2
    
    print_separator
    echo -e "${BOLD}${GREEN}▶ 正在下载并执行 ${script}...${RESET}"
    
    if bash -c "$(curl $auth_opt -sSL -f ${DOWNLOAD_URL})"; then
        echo -e "${GREEN}✓ 脚本执行完成！${RESET}"
    else
        echo -e "${RED}✗ 操作失败，请检查：\n1. 网络连接\n2. 认证信息\n3. 文件是否存在${RESET}"
    fi
}

# ======================
# 主程序
# ======================
while true; do
    clear
    echo -e "${BOLD}${CYAN}"
    cat << "EOF"
  _   _ _   _ _ _____ ___   ___ _____ _     
 | | | | |_/ / |  _  | _ \ / _ \_   _| |    
 | | | | ___ \ | | | | |_/ / /_\ \| | | |    
 | | | | |_/ / | | | |  __/|  _  || | | |____
  \___/ \____/\_\_| |_\_|   \_| |_/\_/ \_____/
EOF
    echo -e "${RESET}"
    print_separator
    echo -e "${BOLD}${GREEN} 欢迎使用全能脚本管理平台 ${RESET}"
    print_separator

    # 菜单项
    menu_items=(
        "1) 自动备份脚本 (auto.sh)"
        "2) 自动下载脚本 (download.sh)"
        "3) 时区修改脚本 (time.sh)"
        "4) 系统源更新脚本 (update.sh)"
        "5) 卸载系统工具脚本 (uninstall.sh)"
        "6) 退出"
    )

    # 显示菜单
    for item in "${menu_items[@]}"; do
        case $item in
            *auto.sh*)      color=${CYAN} ;;
            *download.sh*)  color=${BLUE} ;;
            *time.sh*)      color=${GREEN} ;;
            *update.sh*)    color=${YELLOW} ;;
            *uninstall.sh*) color=${CYAN} ;;
            *)              color=${RESET} ;;
        esac
        echo -e "  ${color}${item}${RESET}"
    done
    print_separator

    # 获取用户选择
    while true; do
        read -p "$(echo -e "${BOLD}${CYAN}请选择操作 [1-6]: ${RESET}")" choice
        [[ $choice =~ ^[1-6]$ ]] && break
        echo -e "${RED}无效输入，请重新选择!${RESET}"
    done

    case $choice in
        6)
            echo -e "${RED}退出系统...${RESET}"
            exit 0
            ;;
        *)
            case $choice in
                1) script="auto.sh" ;;
                2) script="download.sh" ;;
                3) script="time.sh" ;;
                4) script="update.sh" ;;
                5) script="uninstall.sh" ;;
            esac

            # 设置下载参数
            if [[ "$script" == "time.sh" || "$script" == "update.sh" || "$script" == "uninstall.sh" ]]; then
                DOWNLOAD_URL="https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/$script"
                AUTH_OPTION=""
            else
                DOWNLOAD_URL="$NUTSTORE_DIR/$script"
                AUTH_OPTION=""
                get_credentials  # 延迟认证
                AUTH_OPTION="-u ${NUTSTORE_USER}:${NUTSTORE_PASS}"
            fi

            execute_script "$script" "$AUTH_OPTION"
            
            echo -e "\n${BOLD}${CYAN}按任意键返回主菜单...${RESET}"
            read -n 1 -s -r
            ;;
    esac
done
