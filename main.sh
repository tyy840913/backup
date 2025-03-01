#!/bin/bash

# 基础配置
base_url="https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main"
catalog_file="/tmp/cata.$$.txt"
descriptions=()
filenames=()

# 颜色配置
COLOR_TITLE='\033[1;36m'
COLOR_OPTION='\033[1;33m'
COLOR_DESC='\033[1;32m'
COLOR_FILE='\033[1;35m'
COLOR_ERROR='\033[1;31m'
COLOR_RESET='\033[0m'

# 显示宽度计算（支持中文）
display_width() {
    local str=$(echo "$1" | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g")
    local width=0
    for ((i=0; i<${#str}; i++)); do
        local c="${str:i:1}"
        [[ $c == [[:ascii:]] ]] && ((width++)) || ((width+=2))
    done
    echo $width
}

# 生成边框线
generate_border() {
    local width=$1
    printf "╔"; for ((i=0; i<$width; i++)); do printf "═"; done; printf "╗\n"
}

# 下载目录文件
download_catalog() {
    echo -e "${COLOR_DESC}正在获取脚本目录...${COLOR_RESET}"
    curl -s "${base_url}/cata.txt" -o "$catalog_file" || {
        echo -e "${COLOR_ERROR}目录下载失败!${COLOR_RESET}"
        exit 1
    }
}

# 解析目录
parse_catalog() {
    while IFS= read -r line; do
        if [[ "$line" =~ [[:space:]] ]]; then
            descriptions+=("${line% *}")
            filenames+=("${line##* }")
        fi
    done < "$catalog_file"
}

# 显示动态菜单
show_menu() {
    # 计算最大宽度
    local max_width=0
    for i in "${!descriptions[@]}"; do
        item_text="${COLOR_OPTION}$((i+1)).${COLOR_RESET} ${COLOR_DESC}${descriptions[i]}${COLOR_RESET} ${COLOR_FILE}${filenames[i]}${COLOR_RESET}"
        item_width=$(display_width "$item_text")
        ((item_width > max_width)) && max_width=$item_width
    done

    # 设置最小宽度
    ((max_width < 40)) && max_width=40
    local border_width=$((max_width + 2))
    
    clear
    echo -e "${COLOR_TITLE}$(generate_border $border_width)"
    
    # 居中显示标题
    title="脚本选择菜单 (v3.0)"
    title_width=$(display_width "$title")
    padding=$(( (border_width - title_width)/2 ))
    printf "║%${padding}s${COLOR_TITLE}%s%$((border_width - title_width - padding))s║\n" "" "$title" ""
    
    echo -e "${COLOR_TITLE}╠$(printf '%0.s═' $(seq 1 $border_width))╣${COLOR_RESET}"

    # 显示菜单项
    for i in "${!descriptions[@]}"; do
        desc_part="${COLOR_OPTION}$((i+1)).${COLOR_RESET} ${COLOR_DESC}${descriptions[i]}${COLOR_RESET}"
        file_part="${COLOR_FILE}${filenames[i]}${COLOR_RESET}"
        
        desc_width=$(display_width "$desc_part")
        file_width=$(display_width "$file_part")
        space_count=$((max_width - desc_width - file_width))
        
        printf "║ %s%*s%s ║\n" "$desc_part" $space_count "" "$file_part"
    done

    # 退出选项
    exit_text="${COLOR_OPTION} 0.${COLOR_RESET} ${COLOR_DESC}退出脚本${COLOR_RESET}"
    exit_width=$(display_width "$exit_text")
    space_count=$((max_width - exit_width))
    echo -e "${COLOR_TITLE}╠$(printf '%0.s═' $(seq 1 $border_width))╣${COLOR_RESET}"
    printf "║ %s%*s ║\n" "$exit_text" $space_count ""
    echo -e "${COLOR_TITLE}╚$(printf '%0.s═' $(seq 1 $border_width))╝${COLOR_RESET}\n"
}

# 运行子脚本
run_script() {
    local script_url="${base_url}/${filenames[$1]}"
    echo -e "\n${COLOR_DESC}正在下载: ${COLOR_FILE}${filenames[$1]}${COLOR_RESET}"
    
    if content=$(curl -s $script_url); then
        tmp_script=$(mktemp)
        echo "$content" > $tmp_script
        chmod +x $tmp_script
        echo -e "${COLOR_TITLE}══════════ 开始执行 ══════════${COLOR_RESET}"
        $tmp_script
        echo -e "${COLOR_TITLE}══════════ 执行结束 ══════════${COLOR_RESET}"
        rm -f $tmp_script
    else
        echo -e "${COLOR_ERROR}脚本下载失败!${COLOR_RESET}"
    fi
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
    
    run_script $((choice-1))
    read -p "按回车键继续..."
done
