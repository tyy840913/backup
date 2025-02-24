#!/bin/bash

# 请根据需要修改正确时区（例如：Asia/Shanghai）
TZ_CORRECT="Asia/Shanghai"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # 恢复默认颜色

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：此脚本必须以root权限运行！${NC}"
    exit 1
fi

# 获取当前时区函数
get_current_tz() {
    if command -v timedatectl >/dev/null 2>&1; then
        current_tz=$(LANG=C timedatectl | awk -F': ' '/Time zone:/ {print $2}' | awk '{print $1}')
    elif [ -f /etc/timezone ]; then
        current_tz=$(cat /etc/timezone | xargs)
    else
        tz_path=$(readlink -f /etc/localtime 2>/dev/null || realpath /etc/localtime)
        current_tz=${tz_path#/usr/share/zoneinfo/}
    fi
    echo "$current_tz" | tr -d '\n'
}

# 主程序
CURRENT_TZ=$(get_current_tz)

verify_timezone() {
    [ "$(get_current_tz)" = "$TZ_CORRECT" ]
}

show_status() {
    if verify_timezone; then
        echo -e "${GREEN}时区正确：${TZ_CORRECT}${NC}"
        return 0
    else
        echo -e "${RED}当前时区：${CURRENT_TZ}${NC}"
        echo -e "${YELLOW}目标时区：${TZ_CORRECT}${NC}"
        return 1
    fi
}

set_timezone() {
    echo -e "${YELLOW}正在尝试设置时区...${NC}"
    
    # Systemd系统
    if command -v timedatectl >/dev/null 2>&1; then
        timedatectl set-timezone "$TZ_CORRECT"
    # Alpine Linux
    elif [ -f /etc/alpine-release ]; then
        setup-timezone -z "$TZ_CORRECT"
    # Debian系
    elif [ -f /etc/debian_version ]; then
        echo "$TZ_CORRECT" > /etc/timezone
        ln -sf "/usr/share/zoneinfo/$TZ_CORRECT" /etc/localtime
        dpkg-reconfigure -f noninteractive tzdata >/dev/null 2>&1
    # RedHat系
    elif [ -f /etc/redhat-release ]; then
        rm -f /etc/localtime
        ln -sf "/usr/share/zoneinfo/$TZ_CORRECT" /etc/localtime
    # 通用方法
    else
        ln -sf "/usr/share/zoneinfo/$TZ_CORRECT" /etc/localtime 2>/dev/null
    fi

    # 二次验证
    if verify_timezone; then
        echo -e "${GREEN}时区已成功设置为：${TZ_CORRECT}${NC}"
        return 0
    else
        echo -e "${RED}错误：时区设置失败！${NC}"
        return 1
    fi
}

# 主流程
if show_status; then
    read -p "时区已正确，按任意键退出..." -n1 -s
    echo
    exit 0
else
    read -p "检测到时区不正确，是否要自动修正？[Y/n] " -n1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [ -z "$REPLY" ]; then
        if set_timezone; then
            read -p "操作成功完成，按任意键退出..." -n1 -s
            echo
            exit 0
        else
            read -p "修正时区失败，按任意键退出..." -n1 -s
            echo
            exit 1
        fi
    else
        echo -e "${YELLOW}已取消操作。${NC}"
        exit 0
    fi
fi