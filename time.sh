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

# 安装依赖
install_deps() {
    case $(detect_os) in
        "alpine") apk add tzdata ;;
        "debian") apt-get update && apt-get install -y tzdata ;;
        "centos") yum install -y tzdata ;;
    esac
}

# 获取时区列表
get_timezones() {
    if command -v timedatectl &> /dev/null; then
        timedatectl list-timezones 2>/dev/null || return 1
    else
        find /usr/share/zoneinfo -type f ! -name "*.tab" -printf '%P\n' 2>/dev/null | sort || return 1
    fi
}

# 智能多列显示
display_columns() {
    local items=("$@")
    local term_width=$(tput cols)
    local max_length=$(printf '%s\n' "${items[@]}" | awk '{ print length }' | sort -nr | head -1)
    
    # 动态计算列数
    local col_width=$((max_length > 30 ? 35 : 33))
    local cols=$((term_width / col_width))
    cols=$((cols < 1 ? 1 : cols > 4 ? 4 : cols))

    # 格式化输出
    local rows=$(( (${#items[@]} + cols - 1) / cols ))
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
            setup-timezone -z "$tz" >/dev/null 2>&1
            ;;
        *)
            if command -v timedatectl &> /dev/null; then
                timedatectl set-timezone "$tz" >/dev/null 2>&1
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

    # 安装依赖
    if ! get_timezones >/dev/null; then
        echo -e "${YELLOW}时区数据未安装，正在自动安装tzdata包...${RESET}"
        install_deps || {
            echo -e "${RED}依赖安装失败，请手动安装tzdata包${RESET}"
            exit 1
        }
    fi

    # 获取时区列表
    echo -e "\n${BLUE}正在加载时区列表...${RESET}"
    mapfile -t timezones < <(get_timezones)
    [ ${#timezones[@]} -eq 0 ] && {
        echo -e "${RED}错误：无法获取时区列表，请检查tzdata是否安装${RESET}"
        exit 1
    }

    # 显示当前时区
    current_tz=$(
        if command -v timedatectl &> /dev/null; then
            timedatectl | awk -F': ' '/Time zone/ {print $2}' | xargs
        else
            ls -l /etc/localtime | awk -F'zoneinfo/' '{print $2}'
        fi
    )
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
        timedatectl | awk -F': ' '
            /Time zone/ {gsub(/Time zone/, "当前时区"); print $0}
            /Local time/ {
                gsub(/Local time/, "本地时间");
                split($2, dt, " ");
                printf "%s：%s年%s月%s日 %s\n", $1, dt[3], (index("JanFebMarAprMayJunJulAugSepOctNovDec", dt[2])+2)/3, dt[4], dt[5]
            }'
    else
        echo "时区文件：$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')"
        date +"当前时间：%Y-%m-%d %H:%M:%S %Z (%:z)" | awk '{
            gsub(/Mon/, "星期一");
            gsub(/Tue/, "星期二");
            gsub(/Wed/, "星期三");
            gsub(/Thu/, "星期四");
            gsub(/Fri/, "星期五");
            gsub(/Sat/, "星期六");
            gsub(/Sun/, "星期日");
            print
        }'
    fi
}

# 执行主程序
main "$@"
