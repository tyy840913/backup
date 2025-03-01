 
#!/bin/bash

# 基础配置
base_url="https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main"
catalog_file="/tmp/cata.$$.txt"
descriptions=()

# 颜色配置（使用$'...'格式确保转义生效）
COLOR_TITLE=$'\033[1;36m'
COLOR_OPTION=$'\033[1;33m'
COLOR_DESC=$'\033[1;32m'
COLOR_ERROR=$'\033[1;31m'
COLOR_RESET=$'\033[0m'

# 下载目录文件
download_catalog() {
    echo -e "${COLOR_DESC}正在获取脚本目录...${COLOR_RESET}"
    curl -s "${base_url}/cata.txt" -o "$catalog_file" || {
        echo -e "${COLOR_ERROR}目录下载失败!${COLOR_RESET}" >&2
        exit 1
    }
}

# 解析目录
parse_catalog() {
    while IFS= read -r line; do
        if [[ "$line" =~ [[:space:]] ]]; then
            descriptions+=("${line% *}")  # 只提取描述部分
        fi
    done < "$catalog_file"
}

# 修正后的显示函数
show_menu() {
    clear
    # 固定40字符宽度边框
    echo -e "${COLOR_TITLE}╔════════════════════════════════════╗"
    echo -e "║          脚本选择菜单               ║"
    echo -e "╠════════════════════════════════════╣"
    
    # 显示菜单项（使用%b处理转义）
    for i in "${!descriptions[@]}"; do
        item="${COLOR_OPTION}$((i+1)).${COLOR_RESET} ${COLOR_DESC}${descriptions[i]}${COLOR_RESET}"
        printf "║ %-36b ║\n" "$item"  # 使用%b格式解析转义字符
    done
    
    # 退出选项
    echo -e "╠════════════════════════════════════╣"
    echo -e "║ ${COLOR_OPTION} 0.${COLOR_RESET} ${COLOR_DESC}退出脚本${COLOR_RESET}               ║"
    echo -e "╚════════════════════════════════════╝${COLOR_RESET}"
}

# 运行子脚本（保持原功能）
run_script() {
    filename=$(sed -n "${1}p" "$catalog_file" | awk '{print $NF}')
    script_url="${base_url}/${filename}"
    
    echo -e "\n${COLOR_DESC}正在执行: ${COLOR_OPTION}${descriptions[$(( $1 - 1 ))]}${COLOR_RESET}"
    echo -e "${COLOR_TITLE}════════════ 开始执行 ════════════${COLOR_RESET}"
    
    if content=$(curl -s $script_url); then
        tmp_script=$(mktemp)
        echo "$content" > $tmp_script
        chmod +x $tmp_script
        $tmp_script
        rm -f $tmp_script
    else
        echo -e "${COLOR_ERROR}脚本下载失败!${COLOR_RESET}" >&2
    fi
    
    echo -e "${COLOR_TITLE}════════════ 执行结束 ════════════${COLOR_RESET}"
}

# 主程序
download_catalog
parse_catalog

while :; do
    show_menu
    while :; do
        read -p "请输入选择 (0-${#descriptions[@]}): " choice
        [[ $choice =~ ^[0-9]+$ ]] || continue
        ((choice >=0 && choice <= ${#descriptions[@]})) && break
    done
    
    ((choice == 0)) && {
        rm -f $catalog_file
        echo -e "${COLOR_DESC}再见!${COLOR_RESET}"
        exit 0
    }
    
    run_script $choice
    read -p "按回车键继续..."
done
