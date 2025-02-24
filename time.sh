#!/bin/bash
TZ_CORRECT="Asia/Shanghai"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}错误：此脚本必须以root权限运行！${NC}"
    exit 1
fi

# 获取当前时区函数（增强兼容性）
get_current_tz() {
    if command -v timedatectl >/dev/null 2>&1; then
        current_tz=$(LANG=C timedatectl | awk -F': ' '/Time zone:/ {print $2}' | awk '{print $1}')
    elif [ -f /etc/timezone ]; then
        current_tz=$(cat /etc/timezone | xargs)
    else
        tz_path=$( (readlink -f /etc/localtime 2>/dev/null || realpath /etc/localtime) )
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
    local success=0

    # 通用方法优先尝试
    if ln -sf "/usr/share/zoneinfo/$TZ_CORRECT" /etc/localtime 2>/dev/null; then
        [ $? -eq 0 ] && success=1
    fi

    # 发行版特定方法（当通用方法失败时）
    if [ $success -eq 0 ]; then
        # Systemd系统
        if command -v timedatectl >/dev/null 2>&1; then
            timedatectl set-timezone "$TZ_CORRECT" && success=1
        # Alpine Linux（需安装tzdata）
        elif [ -f /etc/alpine-release ]; then
            apk --update add tzdata && \
            cp "/usr/share/zoneinfo/$TZ_CORRECT" /etc/localtime && \
            echo "$TZ_CORRECT" > /etc/timezone && \
            success=1
        # Debian系（含Ubuntu）
        elif [ -f /etc/debian_version ]; then
            echo "$TZ_CORRECT" > /etc/timezone
            ln -sf "/usr/share/zoneinfo/$TZ_CORRECT" /etc/localtime
            dpkg-reconfigure -f noninteractive tzdata >/dev/null 2>&1 && success=1
        # RedHat系（含CentOS/EulerOS）
        elif { [ -f /etc/redhat-release ] || [ -f /etc/centos-release ] || [ -f /etc/euleros-release ]; }; then
            rm -f /etc/localtime
            ln -sf "/usr/share/zoneinfo/$TZ_CORRECT" /etc/localtime && success=1
        # 其他Linux发行版
        else
            ln -sf "/usr/share/zoneinfo/$TZ_CORRECT" /etc/localtime 2>/dev/null && success=1
        fi
    fi

    # 最终验证
    if verify_timezone; then
        echo -e "${GREEN}时区已成功设置为：${TZ_CORRECT}${NC}"
        return 0
    else
        echo -e "${RED}错误：时区设置失败！${NC}"
        return 1
    fi
}

# 主流程（保持不变）
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
