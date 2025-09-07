#!/bin/bash

# 设置脚本在遇到错误时立即退出
set -e

#############################################################
# Mihomo 安装与配置脚本 (精简版)
# 功能:
# 1. 检查依赖项
# 2. 运行官方 Docker 安装脚本
# 3. 配置两个 cron 定时任务 (更新与备份)
#############################################################

DEST_DIR="/etc/mihomo"

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

# --- 函数定义 ---

# 函数：检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}错误: 命令 '$1' 未找到。请先安装它再运行此脚本。${PLAIN}"
        exit 1
    fi
}

# --- 脚本开始 ---

echo -e "${CYAN}--- 步骤 1: 检查系统依赖 ---${PLAIN}"
check_command "curl"
check_command "tar"
check_command "docker"
check_command "crontab"
echo -e "${GREEN}所有依赖项均已安装。${PLAIN}
"

# --- 运行 mihomo-Docker 安装脚本 ---
echo -e "${CYAN}--- 步骤 2: 运行 Mihomo Docker 安装脚本 ---${PLAIN}"
DOCKER_SCRIPT_URL="https://route.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/refs/heads/main/mihomo.sh"
echo "正在从网络下载并执行脚本..."
if bash -c "$(curl -sSL $DOCKER_SCRIPT_URL)"; then
    echo -e "${GREEN}Mihomo Docker 安装脚本执行成功。${PLAIN}
"
else
    echo -e "${RED}错误: Mihomo Docker 安装脚本执行失败。${PLAIN}"
    exit 1
fi

# --- 配置定时任务 ---
echo -e "${CYAN}--- 步骤 3: 配置定时任务 (Cron Jobs) ---${PLAIN}"
CRON_JOB_1="0 8 * * * /usr/bin/bash /etc/mihomo/mihomo.sh && docker restart mihomo >/dev/null 2>&1"

# 使用临时文件来安全地修改 crontab
CURRENT_CRONTAB=$(sudo crontab -l 2>/dev/null || true)

if ! echo "${CURRENT_CRONTAB}" | grep -Fq "/etc/mihomo/mihomo.sh"; then
    echo "正在添加每日更新任务..."
    CURRENT_CRONTAB="${CURRENT_CRONTAB}
${CRON_JOB_1}"
    echo -e "${GREEN}更新任务已准备好添加。${PLAIN}"
else
    echo -e "${YELLOW}每日更新任务已存在，跳过。${PLAIN}"
fi

# 清理空行并应用
echo -e "${CURRENT_CRONTAB}" | grep -v '^$' | sudo crontab -
if [ $? -eq 0 ]; then
    echo -e "${GREEN}定时任务配置成功。${PLAIN}
"
else
    echo -e "${RED}错误: 定时任务配置失败。${PLAIN}"
    exit 1
fi

# --- 完成 ---
echo -e "${GREEN}=================================================${PLAIN}"
echo -e "${GREEN}      所有操作均已成功完成! 🎉${PLAIN}"
echo -e "${GREEN}=================================================${PLAIN}"
