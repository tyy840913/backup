#!/bin/bash

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo -e "\033[31mError: This script must be run as root!\033[0m"
    exit 1
fi

# 检测系统类型
detect_os() {
    if grep -qi "alpine" /etc/os-release; then
        echo "alpine"
    elif grep -qi "debian" /etc/os-release; then
        echo "debian"
    elif grep -qi "centos" /etc/os-release; then
        echo "centos"
    else
        echo "other"
    fi
}

# 检查时区数据
check_tzdata() {
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
    esac
    return 0
}

# 安装依赖
install_deps() {
    case $(detect_os) in
        "alpine") apk add tzdata ;;
        "debian") apt-get install -y tzdata ;;
        "centos") yum install -y tzdata ;;
    esac
}

# 获取终端尺寸
get_term_size() {
    TERM_WIDTH=$(tput cols)
    TERM_HEIGHT=$(tput lines)
}

# 自适应列数显示时区
show_timezones() {
    local timezones=($(timedatectl list-timezones 2>/dev/null || find /usr/share/zoneinfo -type f | sed 's|/usr/share/zoneinfo/||' | sort))
    local max_length=$(printf '%s\n' "${timezones[@]}" | awk '{ print length }' | sort -nr | head -1)
    
    # 动态计算显示参数
    get_term_size
    local item_width=$((max_length > 30 ? 35 : 33))
    local cols=$((TERM_WIDTH / (item_width + 2)))
    cols=$((cols < 1 ? 1 : cols))
    local rows=$(( (${#timezones[@]} + cols - 1) / cols ))

    # 格式化输出
    for ((i=0; i<rows; i++)); do
        for ((j=0; j<cols; j++)); do
            index=$((i + j*rows))
            [ $index -ge ${#timezones[@]} ] && break
            printf "\033[33m%3d)\033[0m %-*s" $((index+1)) 30 "${timezones[index]}"
        done
        echo
    done
}

# 主程序
if ! check_tzdata; then
    read -p "Timezone data not found. Install now? [Y/n] " yn
    case $yn in
        [Nn]* ) exit 1;;
        * ) install_deps;;
    esac
fi

echo -e "\nCurrent time zone:"
if command -v timedatectl &> /dev/null; then
    timedatectl | grep "Time zone"
else
    ls -l /etc/localtime | awk -F'zoneinfo/' '{print "Timezone: "$2}'
fi

echo -e "\n\033[34mAvailable time zones:\033[0m"
show_timezones

# 获取用户输入
while :; do
    read -p "Enter selection number: " choice
    [[ $choice =~ ^[0-9]+$ ]] && ((choice > 0 && choice <= ${#timezones[@]})) && break
    echo -e "\033[31mInvalid input, please try again.\033[0m"
done
selected_tz=${timezones[choice-1]}

# 设置时区
echo -e "\nSetting timezone to: \033[36m$selected_tz\033[0m"
if command -v timedatectl &> /dev/null; then
    timedatectl set-timezone "$selected_tz"
elif [ "$(detect_os)" == "alpine" ]; then
    setup-timezone -z "$selected_tz"
else
    ln -sf "/usr/share/zoneinfo/$selected_tz" /etc/localtime
    [ -f /etc/timezone ] && echo "$selected_tz" > /etc/timezone
fi

# 显示结果
echo -e "\n\033[32mTime zone updated successfully:\033[0m"
if command -v timedatectl &> /dev/null; then
    timedatectl | grep "Time zone" | awk -F': ' '{print "System time zone: "$2}'
else
    echo "System time zone: $(readlink /etc/localtime | sed 's|.*/zoneinfo/||')"
fi
date +"Current time: %Y-%m-%d %H:%M:%S %Z (UTC%:z)"
