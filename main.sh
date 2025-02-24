#!/bin/bash

# 配置信息
NUTSTORE_DIR="https://dav.woskee.nyc.mn:88/jianguoyun/backup"
read -p "请输入坚果云账号: " NUTSTORE_USER
read -sp "请输入坚果云密码: " NUTSTORE_PASS
echo
# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
MAGENTA='\033[35m'
CYAN='\033[36m'
BOLD='\033[1m'
RESET='\033[0m'
# 分隔线函数
print_separator() {
    echo -e "${MAGENTA}===================================================${RESET}"
}
# 主循环
while true; do
    # 显示欢迎界面
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
            *auto.sh*)    color=${CYAN} ;;
            *download.sh*)color=${BLUE} ;;
            *time.sh*)    color=${GREEN} ;;
            *update.sh*)  color=${YELLOW} ;;
            *)            color=${RESET} ;;
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
                1) script="auto.sh" ;;
                2) script="download.sh" ;;
                3) script="time.sh" ;;
                4) script="update.sh" ;;
            esac
            # 设置下载 URL
            if [[ "$script" == "time.sh" || "$script" == "update.sh" ]]; then
                DOWNLOAD_URL="https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/$script"
                AUTH_OPTION="" # 不需要认证
            else
                DOWNLOAD_URL="$NUTSTORE_DIR/$script"
                AUTH_OPTION="-u ${NUTSTORE_USER}:${NUTSTORE_PASS}"
            fi
            # 执行远程脚本
            print_separator
            echo -e "${BOLD}${GREEN}▶ 正在下载并执行 ${script}...${RESET}"
            if bash -c "$(curl $AUTH_OPTION -sSL -f ${DOWNLOAD_URL})"; then
                echo -e "${GREEN}✓ 脚本执行完成！${RESET}"
            else
                echo -e "${RED}✗ 操作失败，请检查："
                echo -e "1. 网络连接"
                echo -e "2. 认证信息"
                echo -e "3. 文件是否存在${RESET}"
            fi
            
            # 等待用户输入
            echo -e "\n${BOLD}${CYAN}按任意键返回主菜单...${RESET}"
            read -n 1 -s -r
            ;;
    esac
done
