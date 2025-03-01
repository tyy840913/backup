#!/bin/bash

# 基础URL配置
base_url="https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main"
catalog_file="/tmp/cata.$$.txt"
script_cache=()
descriptions=()
filenames=()

# 颜色配置
COLOR_TITLE='\033[1;36m'
COLOR_OPTION='\033[1;33m'
COLOR_DESC='\033[1;32m'
COLOR_FILE='\033[1;35m'
COLOR_ERROR='\033[1;31m'
COLOR_RESET='\033[0m'

# 显示宽度计算函数
display_width() {
    local str=$1
    local width=0
    local len=${#str}
    for ((i=0; i<len; i++)); do
        local c="${str:i:1}"
        if [[ "$c" =~ [^[:ascii:]] ]]; then
            width=$((width + 2))
        else
            width=$((width + 1))
        fi
    done
    echo $width
}

# 下载目录文件函数
download_catalog() {
    echo -e "${COLOR_DESC}正在获取脚本目录...${COLOR_RESET}"
    if ! curl -s "${base_url}/cata.txt" -o "$catalog_file"; then
        echo -e "${COLOR_ERROR}错误：目录文件下载失败！${COLOR_RESET}"
        exit 1
    fi
}

# 解析目录文件
parse_catalog() {
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ [[:space:]] ]]; then
            desc="${line% *}"
            file="${line##* }"
            descriptions+=("$desc")
            filenames+=("$file")
        fi
    done < "$catalog_file"
}

# 显示图形界面
show_menu() {
    clear
    echo -e "${COLOR_TITLE}"
    echo "╔══════════════════════════════════════╗"
    echo "║         脚本选择菜单 (v1.1)          ║"
    echo "╠══════════════════════════════════════╣"
    
    for i in "${!descriptions[@]}"; do
        desc="${descriptions[i]}"
        file="${filenames[i]}"
        
        # 计算显示宽度
        desc_width=$(display_width "$desc")
        file_width=$(display_width "$file")
        total=$((desc_width + file_width))
        
        # 计算间距
        space_count=$((33 - total))
        if (( space_count < 0 )); then
            space_count=0
        fi

        # 格式输出
        printf "║ ${COLOR_OPTION}%2d.${COLOR_RESET} ${COLOR_DESC}%s${COLOR_RESET}%${space_count}s${COLOR_FILE}%s${COLOR_RESET} ║\n" \
               $((i+1)) "$desc" "" "$file"
    done

    # 退出选项处理
    exit_desc="退出脚本"
    exit_space=$((33 - $(display_width "$exit_desc")))
    echo -e "${COLOR_TITLE}╠══════════════════════════════════════╣"
    printf "║ ${COLOR_OPTION} 0.${COLOR_RESET} ${COLOR_DESC}%s${COLOR_RESET}%${exit_space}s ║\n" "$exit_desc" ""
    echo "╚══════════════════════════════════════╝"
    echo -e "${COLOR_RESET}"
}

# 运行子脚本
run_script() {
    local index=$(( $1 - 1 ))
    local script_url="${base_url}/${filenames[index]}"
    
    echo -e "\n${COLOR_DESC}正在下载 ${COLOR_FILE}${filenames[index]}${COLOR_RESET}"
    if ! script_content=$(curl -s "$script_url"); then
        echo -e "${COLOR_ERROR}错误：脚本下载失败！${COLOR_RESET}"
        return 1
    fi
    
    echo -e "${COLOR_DESC}正在执行 ${COLOR_FILE}${filenames[index]}${COLOR_RESET}"
    echo -e "${COLOR_TITLE}════════════ 开始执行 ════════════${COLOR_RESET}\n"
    
    # 创建临时脚本文件
    tmp_script=$(mktemp)
    echo "$script_content" > "$tmp_script"
    chmod +x "$tmp_script"
    "$tmp_script"
    rm -f "$tmp_script"
    
    echo -e "\n${COLOR_TITLE}════════════ 执行结束 ════════════${COLOR_RESET}"
}

# 初始化
download_catalog
parse_catalog

# 主循环
while true; do
    show_menu
    
    while true; do
        read -p "请输入选项序号 (0-${#descriptions[@]}): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if (( choice == 0 )); then
                echo -e "${COLOR_DESC}感谢使用，再见！${COLOR_RESET}"
                rm -f "$catalog_file"
                exit 0
            elif (( choice > 0 && choice <= ${#descriptions[@]} )); then
                break
            fi
        fi
        echo -e "${COLOR_ERROR}无效输入，请输入有效序号！${COLOR_RESET}"
    done
    
    run_script "$choice"
    
    echo
    read -p "按回车键返回主菜单..."
done
