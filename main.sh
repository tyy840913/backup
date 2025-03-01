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
    # 计算最大有效宽度（排除颜色代码）
    local max_width=0
    for i in "${!descriptions[@]}"; do
        raw_text="$((i+1)). ${descriptions[i]} ${filenames[i]}"
        text_width=$(display_width "$raw_text")
        ((text_width > max_width)) && max_width=$text_width
    done

    # 设置最小宽度
    ((max_width < 40)) && max_width=40
    local border_width=$((max_width + 6)) # 补偿边框元素
    
    clear
    echo -e "${COLOR_TITLE}╔$(printf '%0.s═' $(seq 1 $border_width))╗"
    
    # 标题居中
    title="脚本选择菜单 (最终版)"
    title_width=$(display_width "$title")
    padding=$(( (border_width - title_width)/2 ))
    printf "║%${padding}s${COLOR_TITLE}%s%$((border_width - title_width - padding))s║\n" "" "$title" ""
    
    echo -e "╠$(printf '%0.s═' $(seq 1 $border_width))╣"

    # 菜单项输出
    for i in "${!descriptions[@]}"; do
        desc_part="${COLOR_OPTION}$((i+1)).${COLOR_RESET} ${COLOR_DESC}${descriptions[i]}${COLOR_RESET}"
        file_part="${COLOR_FILE}${filenames[i]}${COLOR_RESET}"
        
        # 计算实际显示宽度
        desc_width=$(display_width "${descriptions[i]}")
        num_width=$(display_width "$((i+1)).")
        file_real_width=$(display_width "${filenames[i]}")
        
        # 计算可用空间
        space_available=$((max_width - num_width - desc_width - file_real_width))
        printf "║ %s%*s%s ║\n" \
            "$desc_part" \
            $((space_available + ${#file_part} - $(display_width "${filenames[i]}") )) \
            "" \
            "$file_part"
    done

    # 退出选项
    exit_text="${COLOR_OPTION} 0.${COLOR_RESET} ${COLOR_DESC}退出脚本${COLOR_RESET}"
    exit_width=$(display_width "0. 退出脚本")
    space_count=$((border_width - exit_width - 2))
    echo -e "╠$(printf '%0.s═' $(seq 1 $border_width))╣"
    printf "║ %s%*s ║\n" "$exit_text" $space_count ""
    echo -e "╚$(printf '%0.s═' $(seq 1 $border_width))╝${COLOR_RESET}"
}
