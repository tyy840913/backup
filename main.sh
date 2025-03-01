#!/bin/bash

# 基础配置
base_url="https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main"
catalog_file="/tmp/cata.$$.txt"
descriptions=()
filenames=()

# 颜色配置
COLOR_TITLE=$'\033[1;36m'
COLOR_OPTION=$'\033[1;33m'
COLOR_DIVIDER=$'\033[1;34m'
COLOR_INPUT=$'\033[1;35m'
COLOR_ERROR=$'\033[1;31m'
COLOR_RESET=$'\033[0m'

# 下载目录文件
download_catalog() {
    if [ ! -f "$catalog_file" ]; then
        echo -e "${COLOR_TITLE}正在获取脚本目录...${COLOR_RESET}"
        if ! curl -s "${base_url}/cata.txt" -o "$catalog_file"; then
            echo -e "${COLOR_ERROR}错误：目录文件下载失败！${COLOR_RESET}" >&2
            exit 1
        fi
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

# 打印分割线
print_divider() {
    echo -e "${COLOR_DIVIDER}===============================================${COLOR_RESET}"
}

# 显示用户界面
show_interface() {
    clear
    # 显示标题
    echo -e "${COLOR_TITLE}"
    print_divider
    echo "             智能脚本平台"
    print_divider
    echo -e "${COLOR_RESET}"

    # 显示菜单项
    for i in "${!descriptions[@]}"; do
        printf "${COLOR_OPTION}%2d.${COLOR_RESET} ${COLOR_TITLE}%-30s${COLOR_RESET}\n" \
               $((i+1)) "${descriptions[i]}"
    done

    # 底部操作提示
    echo
    print_divider
    echo -e "${COLOR_INPUT}请输入序号选择脚本 (0 退出):${COLOR_RESET}"
}

# 执行子脚本
run_script() {
    local index=$(($1 - 1))
    local script_url="${base_url}/${filenames[index]}"
    local tmp_script=$(mktemp)
    
    echo -e "\n${COLOR_TITLE}正在获取 ${COLOR_OPTION}${filenames[index]}${COLOR_RESET}"
    if curl -s "$script_url" -o "$tmp_script"; then
        chmod +x "$tmp_script"
        
        # 根据后缀选择执行方式
        case "${filenames[index]##*.}" in
            sh) bash "$tmp_script" ;;
            py) python "$tmp_script" ;;
            *)  echo -e "${COLOR_ERROR}不支持的脚本格式！${COLOR_RESET}" ;;
        esac
        
        rm -f "$tmp_script"
    else
        echo -e "${COLOR_ERROR}脚本下载失败！${COLOR_RESET}"
    fi
    
    echo -e "\n${COLOR_DIVIDER}════════════ 操作完成 ════════════${COLOR_RESET}"
}

# 主程序
download_catalog
parse_catalog

# 主循环
while true; do
    show_interface
    
    # 输入验证
    while :; do
        read -p " " choice
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if ((choice == 0)); then
                echo -e "${COLOR_TITLE}感谢使用，再见！${COLOR_RESET}"
                rm -f "$catalog_file"
                exit 0
            elif ((choice > 0 && choice <= ${#descriptions[@]})); then
                break
            fi
        fi
        echo -e "${COLOR_ERROR}无效输入，请重新输入！${COLOR_RESET}"
    done

    run_script "$choice"
    read -p "按回车键继续..."
done
