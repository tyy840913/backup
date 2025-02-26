#!/bin/bash

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo "此脚本必须以root权限运行！"
    exit 1
fi

# 检测系统类型
HAS_TIMEDATECTL=$(command -v timedatectl &>/dev/null && echo yes || echo no)
IS_ALPINE=$(grep -qi alpine /etc/os-release && echo yes || echo no)

# 获取当前时区
get_current_timezone() {
    if [[ "$HAS_TIMEDATECTL" == "yes" ]]; then
        timedatectl show --property=Timezone --value
    else
        if [[ -L /etc/localtime ]]; then
            readlink /etc/localtime | sed 's|/usr/share/zoneinfo/||'
        elif [[ -f /etc/timezone ]]; then
            cat /etc/timezone
        else
            echo "未知"
        fi
    fi
}

# 递归选择时区函数
select_tz() {
    local base_path="/usr/share/zoneinfo"
    local current_path="$1"
    local full_path="$base_path/$current_path"

    # 获取目录和文件列表
    local items=()
    while IFS= read -r d; do
        items+=("$d/")
    done < <(find "$full_path" -mindepth 1 -maxdepth 1 -type d -printf "%f/\n" 2>/dev/null | sort)
    
    while IFS= read -r f; do
        items+=("$f")
    done < <(find "$full_path" -mindepth 1 -maxdepth 1 -type f -printf "%f\n" 2>/dev/null | sort)

    # 显示选项
    echo "当前路径: ${current_path:-/}"
    for ((i=0; i<${#items[@]}; i++)); do
        printf "%3d) %s\n" $((i+1)) "${items[$i]}"
    done

    while :; do
        read -p "请选择序号（输入q退出）: " choice
        [[ "$choice" == "q" ]] && return 1
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#items[@]})); then
            local selected="${items[$((choice-1))]%/}"
            local new_path="$current_path/$selected"
            
            if [[ -d "$base_path/$new_path" ]]; then
                if select_tz "$new_path"; then
                    echo "$selected_tz"
                    return 0
                fi
            else
                selected_tz="$new_path"
                return 0
            fi
        else
            echo "无效输入，请重新选择。"
        fi
    done
}

# 主程序
echo "当前系统时区: $(get_current_timezone)"

# 选择时区
if [[ "$HAS_TIMEDATECTL" == "yes" ]]; then
    echo "正在加载时区列表..."
    mapfile -t timezones < <(timedatectl list-timezones)
    echo "可用时区列表:"
    for i in "${!timezones[@]}"; do
        printf "%3d) %s\n" $((i+1)) "${timezones[$i]}"
    done
    
    while :; do
        read -p "请输入序号选择时区: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#timezones[@]})); then
            selected_tz="${timezones[$((choice-1))]}"
            break
        else
            echo "无效输入，请重新选择。"
        fi
    done
else
    echo "正在进入时区选择向导..."
    selected_tz=$(select_tz "")
    [[ -z "$selected_tz" ]] && exit 1
fi

# 设置新时区
echo "正在设置时区为: $selected_tz"

if [[ "$HAS_TIMEDATECTL" == "yes" ]]; then
    timedatectl set-timezone "$selected_tz"
else
    if [[ "$IS_ALPINE" == "yes" ]] && command -v setup-timezone &>/dev/null; then
        setup-timezone -z "$selected_tz"
    else
        ln -sf "/usr/share/zoneinfo/$selected_tz" /etc/localtime
        [[ -f /etc/timezone ]] && echo "$selected_tz" > /etc/timezone
    fi
fi

# 显示结果
echo -e "\n时区设置完成，当前时间信息:"
if [[ "$HAS_TIMEDATECTL" == "yes" ]]; then
    timedatectl
else
    date -R
    echo "系统时区文件: $(readlink /etc/localtime)"
fi
