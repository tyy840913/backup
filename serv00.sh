#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

# 辅助函数
red() {
    echo -e "${RED}$1${RESET}"
}

green() {
    echo -e "${GREEN}$1${RESET}"
}

yellow() {
    echo -e "${YELLOW}$1${RESET}"
}

# 清理cron任务
cleanCron() {
    echo "" > null
    crontab null
    rm null
}

# 结束所有用户进程
killUserProc() {
    local user=$(whoami)
    pkill -kill -u $user
}

# 系统初始化函数
initServer() {
    green "清理cron任务..."
    cleanCron

    green "清理用户进程..."
    killUserProc

    green "清理磁盘..."
    rm -rf ~/* ~/.* 2>/dev/null

    yellow "系统初始化完成"
    exit 0
}

# 直接执行清理操作
initServer
