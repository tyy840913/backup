#!/bin/bash

# 彩色输出定义
COLOR_RED="\033[1;91m"
COLOR_GREEN="\033[1;92m"
COLOR_YELLOW="\033[1;93m"
COLOR_BLUE="\033[1;94m"
COLOR_CYAN="\033[1;96m"
COLOR_RESET="\033[0m"

# 代理服务器配置（可自行添加）
PROXY_ENDPOINTS=(
    "https://add.woskee.nyc.mn/"
    "https://cdn.woskee.nyc.mn/"
)

# 基础配置
BASE_URL="https://raw.githubusercontent.com/tyy840913/backup/main/"
CATALOG_FILE="cact.txt"
SCRIPT_TIMEOUT=5

# 动态内容存储
script_map=()
script_names=()
current_proxy=""

# 获取最快代理
get_fastest_proxy() {
    echo -e "${COLOR_CYAN}[系统] 正在检测最优代理服务器...${COLOR_RESET}"
    
    local tmp_file=$(mktemp)
    local url_list=()
    local proxy_map=()

    # 生成测试URL列表
    for proxy in "${PROXY_ENDPOINTS[@]}"; do
        local test_url="${proxy}${BASE_URL}${CATALOG_FILE}"
        url_list+=("$test_url")
        proxy_map["$test_url"]="$proxy"
    done

    # 并行测试
    for url in "${url_list[@]}"; do
    (
        local start_time=$(date +%s%3N)
        if curl -fsSL --max-time $SCRIPT_TIMEOUT "$url" &>/dev/null; then
            local latency=$(( $(date +%s%3N) - start_time ))
            echo "$latency $url" >> $tmp_file
        else
            echo "999999 $url" >> $tmp_file
        fi
    ) &
    done
    wait

    # 分析结果
    local fastest=$(sort -n $tmp_file | head -n1 | cut -d' ' -f2)
    rm -f $tmp_file

    current_proxy="${proxy_map[$fastest]}"
    echo -e "${COLOR_GREEN}[网络] 使用代理节点: ${current_proxy:-直连}${COLOR_RESET}"
}

# 获取脚本目录
fetch_scripts() {
    local target_url="${current_proxy}${BASE_URL}${CATALOG_FILE}"
    
    if ! catalog_content=$(curl -fsSL --max-time $SCRIPT_TIMEOUT "$target_url" 2>/dev/null); then
        echo -e "${COLOR_RED}[错误] 无法获取脚本目录，请检查网络连接${COLOR_RESET}"
        exit 1
    fi

    # 解析目录内容
    script_map=()
    script_names=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^([^ ]+[ ]+)([^ ]+\.sh)$ ]]; then
            script_name="${BASH_REMATCH[1]}"
            script_file="${BASH_REMATCH[2]}"
            script_names+=("$script_name")
            script_map["$script_name"]="$script_file"
        fi
    done <<< "$catalog_content"
}

# 执行子脚本
execute_script() {
    local script_name=$1
    local script_file=$2
    local script_url="${current_proxy}${BASE_URL}${script_file}"
    
    echo -e "\n${COLOR_CYAN}[下载] 正在获取 ${script_name}...${COLOR_RESET}"
    local tmp_script=$(mktemp)
    
    if curl -fsSL --max-time $SCRIPT_TIMEOUT "$script_url" -o "$tmp_script"; then
        chmod +x "$tmp_script"
        echo -e "${COLOR_GREEN}[执行] 启动 ${script_name}...${COLOR_RESET}"
        "$tmp_script"
        rm -f "$tmp_script"
    else
        echo -e "${COLOR_RED}[错误] 下载失败: ${script_url}${COLOR_RESET}"
    fi
}

# 显示图形界面
show_menu() {
    while true; do
        clear
        echo -e "${COLOR_BLUE}"
        echo "███████╗ ██████╗██████╗ ██╗   ██╗██████╗ ███████╗"
        echo "██╔════╝██╔════╝██╔══██╗╚██╗ ██╔╝██╔══██╗██╔════╝"
        echo "███████╗██║     ██████╔╝ ╚████╔╝ ██████╔╝█████╗  "
        echo "╚════██║██║     ██╔══██╗  ╚██╔╝  ██╔═══╝ ██╔══╝  "
        echo "███████║╚██████╗██║  ██║   ██║   ██║     ███████╗"
        echo "╚══════╝ ╚═════╝╚═╝  ╚═╝   ╚═╝   ╚═╝     ╚══════╝"
        echo -e "${COLOR_RESET}"
        echo -e "${COLOR_YELLOW}════════════════ 脚本管理中心 ════════════════${COLOR_RESET}"
        
        # 显示脚本列表
        local index=1
        for name in "${script_names[@]}"; do
            printf "${COLOR_CYAN}%2d. ${COLOR_GREEN}%-20s ${COLOR_YELLOW}➔ ${COLOR_RESET}%s\n" \
                   $index "$name" "${script_map[$name]}"
            ((index++))
        done
        
        # 退出选项
        echo -e "\n${COLOR_YELLOW} 0. 退出系统${COLOR_RESET}"
        echo -e "${COLOR_YELLOW}══════════════════════════════════════════════${COLOR_RESET}"
        
        # 用户输入
        read -p "请输入选项序号: " choice
        
        case $choice in
            0)
                echo -e "${COLOR_GREEN}[系统] 感谢使用，再见！${COLOR_RESET}"
                exit 0
                ;;
            [1-9]|1[0-9])
                local selected=$((choice-1))
                if [ $selected -lt ${#script_names[@]} ]; then
                    local name=${script_names[$selected]}
                    execute_script "$name" "${script_map[$name]}"
                else
                    echo -e "${COLOR_RED}[错误] 无效的选项，请重新输入！${COLOR_RESET}"
                    sleep 1
                fi
                ;;
            *)
                echo -e "${COLOR_RED}[错误] 无效的输入，请输入数字序号！${COLOR_RESET}"
                sleep 1
                ;;
        esac
        
        # 返回前等待
        read -n 1 -s -r -p "按任意键返回主菜单..."
    done
}

# 主流程
main() {
    get_fastest_proxy
    fetch_scripts
    show_menu
}

# 启动
main
