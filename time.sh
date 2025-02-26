#!/bin/bash

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RESET='\033[0m'

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误：必须使用root权限运行此脚本！${RESET}" >&2
        exit 1
    fi
}

# 检测系统类型
detect_os() {
    if grep -qi "alpine" /etc/os-release; then
        echo "alpine"
    elif grep -qi "ubuntu\|debian" /etc/os-release; then
        echo "debian"
    elif grep -qi "centos\|rhel" /etc/os-release; then
        echo "centos"
    else
        echo "unknown"
    fi
}

# 检查依赖包
check_dependencies() {
    case $(detect_os) in
        "alpine")
            [ ! -x /usr/sbin/setup-timezone ] && return 1
            ;;
        "debian")
            [ ! -d /usr/share/zoneinfo ] && return 1
            ;;
        "centos")
            ! rpm -q tzdata &> /dev/null && return 1
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

# 安装依赖
install_deps() {
    case $(detect_os) in
        "alpine")
            apk add tzdata
            ;;
        "debian")
            apt-get update && apt-get install -y tzdata
            ;;
        "centos")
            yum install -y tzdata
            ;;
    esac
}

# 获取时区列表
get_timezones() {
    if command -v timedatectl &> /dev/null; then
        timedatectl list-timezones
    else
        find /usr/share/zoneinfo -type f -printf '%P\n' 2>/dev/null | sort
    fi
}

# 智能多列显示
display_columns() {
    local items=("$@")
    local term_width=$(tput cols)
    local max_length=$(printf '%s\n' "${items[@]}" | awk '{ print length }' | sort -nr | head -1)
    
    # 动态计算列数和列宽
    local col_width=$((max_length > 30 ? 35 : 33))
    local cols=$((term_width / col_width))
    cols=$((cols < 1 ? 1 : cols > 4 ? 4 : cols))
    local rows=$(( (${#items[@]} + cols - 1) / cols ))

    # 格式化输出
    for ((row=0; row<rows; row++)); do
        for ((col=0; col<cols; col++)); do
            local index=$((row + col*rows))
            [ $index -ge ${#items[@]} ] && continue
            
            printf "${YELLOW}%3d)${RESET} %-30s " $((index+1)) "${items[index]}"
        done
        echo
    done
}

# 设置时区
set_timezone() {
    local tz=$1
    case $(detect_os) in
        "alpine")
            setup-timezone -z "$tz"
            ;;
        *)
            if command -v timedatectl &> /dev/null; then
                timedatectl set-timezone "$tz"
            else
                ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime
                [ -f /etc/timezone ] && echo "$tz" > /etc/timezone
            fi
            ;;
    esac
}

# 主程序
main() {
    check_root

    # 依赖检查
    if ! check_dependencies; then
        echo -e "${YELLOW}时区数据未安装，可能需要安装tzdata包${RESET}"
        read -p "是否立即安装？[Y/n] " yn
        case "${yn:-Y}" in
            [Yy]*)
                install_deps
                ;;
            *)
                exit 1
                ;;
        esac
    fi

    # 获取时区列表
    echo -e "\n${BLUE}正在加载时区列表...${RESET}"
    mapfile -t timezones < <(get_timezones)

    # 显示当前时区
    current_tz=$(timedatectl 2>/dev/null | grep "Time zone" | cut -d':' -f2 | xargs || ls -l /etc/localtime | awk -F'zoneinfo/' '{print $2}')
    echo -e "\n${GREEN}当前时区：${current_tz}${RESET}"

    # 显示选择界面
    echo -e "\n${BLUE}请选择时区（输入序号）：${RESET}"
    display_columns "${timezones[@]}"

    # 输入验证
    while :; do
        read -p "请输入序号（1-${#timezones[@]}）: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#timezones[@]})); then
            break
        fi
        echo -e "${RED}错误：无效输入，请输入有效序号${RESET}"
    done

    # 设置时区
    selected_tz="${timezones[choice-1]}"
    echo -e "\n${BLUE}正在设置时区为：${YELLOW}${selected_tz}${RESET}"
    set_timezone "$selected_tz"

    # 验证结果
    echo -e "\n${GREEN}时区设置成功！当前时间信息：${RESET}"
    if command -v timedatectl &> /dev/null; then
        timedatectl | grep --color=never "当前时区\|本地时间"
    else
        ls -l /etc/localtime | awk -F'zoneinfo/' '{print "时区文件：" $2}'
        date "+当前时间：%Y-%m-%d %H:%M:%S %Z (%:z)"
    fi
}

# 执行主程序
main "$@"
