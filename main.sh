#!/bin/bash

# 配置参数
BASE_URL="https://raw.githubusercontent.com/tyy840913/backup/main"
CACT_FILE="cact.txt"
PROXIES=(
    "https://add.woskee.nyc.mn/"
    "https://cdn.woskee.nyc.mn/"
    "$BASE_URL"  # 原始地址作为最后回退
)

# 颜色配置
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m' # 恢复默认

# 获取内容函数（带代理重试）
fetch_content() {
    local url=$1
    local content
    for proxy in "${PROXIES[@]}"; do
        local proxy_url="${proxy}${url#$BASE_URL}"
        echo -e "${YELLOW}尝试通过代理访问: $proxy_url${NC}"
        content=$(curl -sSL --connect-timeout 10 "$proxy_url") && break
    done
    echo "$content"
}

# 获取脚本列表
get_scripts_list() {
    echo -e "${CYAN}正在获取脚本列表...${NC}"
    local content=$(fetch_content "$BASE_URL/$CACT_FILE")
    if [ -z "$content" ]; then
        echo -e "${RED}错误：无法获取脚本列表${NC}"
        exit 1
    fi
    # 修正此处括号问题
    echo "$content" | awk '{gsub(/^[ \t]+|[ \t]+$/, ""); if(NF>0) print}'
}

# 显示彩色菜单
show_menu() {
    clear
    echo -e "${MAGENTA}"
    echo "╔════════════════════════════════════╗"
    echo "║         ${BLUE}脚本管理中心${MAGENTA}         ║"
    echo "╠════════════════════════════════════╣"
    local count=1
    while IFS= read -r line; do
        name=$(echo "$line" | awk -F' ' '{for(i=2;i<=NF;i++) printf $i" "; print ""}')
        echo -e "║ ${GREEN}$count.${NC} ${CYAN}$name${MAGENTA}"
        ((count++))
    done <<< "$SCRIPT_LIST"
    echo -e "║ ${RED}0. 退出${MAGENTA}"
    echo "╚════════════════════════════════════╝"
    echo -e "${NC}"
}

# 执行子脚本
execute_script() {
    local script_name=$(echo "$SCRIPT_LIST" | sed -n "${1}p" | awk '{print $NF}')
    local script_url="$BASE_URL/$script_name"
    
    echo -e "${YELLOW}正在下载: $script_name ...${NC}"
    local script_content=$(fetch_content "$script_url")
    
    if [ -z "$script_content" ]; then
        echo -e "${RED}错误：无法下载脚本${NC}"
        return 1
    fi
    
    echo -e "${GREEN}执行中... (可能需要sudo权限)${NC}"
    echo "========================================"
    bash -c "$script_content"
    echo "========================================"
    echo -e "${GREEN}脚本执行完成，按回车返回菜单${NC}"
    read -p ""
}

# 主程序
SCRIPT_LIST=$(get_scripts_list)

while true; do
    show_menu
    read -p "请选择操作 (0-$(echo "$SCRIPT_LIST" | wc -l)): " choice
    
    case $choice in
        0) 
            echo -e "${BLUE}感谢使用，再见！${NC}"
            exit 0
            ;;
        [1-9]*) 
            if (( choice <= $(echo "$SCRIPT_LIST" | wc -l) )); then
                execute_script $choice
            else
                echo -e "${RED}无效的选择，请重新输入${NC}"
                sleep 1
            fi
            ;;
        *)
            echo -e "${RED}输入错误，请重新选择${NC}"
            sleep 1
            ;;
    esac
done
