#!/bin/bash

# 设置脚本在遇到错误时立即退出
set -e

#############################################################
# Mihomo 安装与配置脚本 (增强版)
# 功能:
# 1. 检查依赖项
# 2. 下载并解压 Mihomo 核心文件
# 3. 运行官方 Docker 安装脚本
# 4. 配置两个 cron 定时任务 (更新与备份)
#############################################################

# --- 配置与变量 ---
URL="https://backup.woskee.dpdns.org/mihomo"
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

# --- 获取凭据 ---
echo -e "${CYAN}--- 步骤 2: 获取下载凭据 ---${PLAIN}"
read -p "请输入下载用户名: " USERNAME
read -sp "请输入下载密码: " PASSWORD
echo

if [[ -z "$USERNAME" || -z "$PASSWORD" ]]; then
    echo -e "${RED}错误: 用户名和密码不能为空。${PLAIN}"
    exit 1
fi
echo -e "${GREEN}凭据已输入。${PLAIN}
"

# --- 下载与解压 ---
echo -e "${CYAN}--- 步骤 3: 下载并解压 Mihomo 文件 ---${PLAIN}"
echo "正在创建目标目录: $DEST_DIR"
mkdir -p "${DEST_DIR}"

echo "正在从 $URL 下载并解压文件到 $DEST_DIR ..."
if curl -u "${USERNAME}:${PASSWORD}" -L "${URL}" | sudo tar -xzf - -C "${DEST_DIR}"; then
    echo -e "${GREEN}文件下载并解压成功。${PLAIN}"
else
    echo -e "${RED}错误: 文件下载或解压失败。请检查URL、用户名、密码或文件格式。${PLAIN}"
    exit 1
fi

# --- 运行配置脚本 ---
echo -e "${CYAN}--- 步骤 4: 运行内部配置脚本 ---${PLAIN}"
CONFIG_SCRIPT="${DEST_DIR}/mihomo_config.sh"
if [[ -f "$CONFIG_SCRIPT" ]]; then
    if bash "$CONFIG_SCRIPT"; then
        echo -e "${GREEN}内部配置脚本执行成功。${PLAIN}
"
    else
        echo -e "${RED}错误: 内部配置脚本 '$CONFIG_SCRIPT' 执行失败。${PLAIN}"
        exit 1
    fi
else
    echo -e "${YELLOW}警告: 未在解压文件中找到 '$CONFIG_SCRIPT'，跳过此步骤。${PLAIN}
"
fi

# --- 运行 mihomo-Docker 安装脚本 ---
echo -e "${CYAN}--- 步骤 5: 运行 Mihomo Docker 安装脚本 ---${PLAIN}"
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
echo -e "${CYAN}--- 步骤 6: 配置定时任务 (Cron Jobs) ---${PLAIN}"
CRON_JOB_1="0 8 * * * /usr/bin/bash /etc/mihomo/mihomo_config.sh && docker restart mihomo >/dev/null 2>&1"
CRON_JOB_2="0 9 * * * tar -czf - -C /etc mihomo | curl -u "${USERNAME}:${PASSWORD}" -T - https://backup.woskee.dpdns.org/update/mihomo >/dev/null 2>&1"

# 使用临时文件来安全地修改 crontab
CURRENT_CRONTAB=$(sudo crontab -l 2>/dev/null || true)

if ! echo "${CURRENT_CRONTAB}" | grep -Fq "/etc/mihomo/mihomo_config.sh"; then
    echo "正在添加每日更新任务..."
    CURRENT_CRONTAB="${CURRENT_CRONTAB}
${CRON_JOB_1}"
    echo -e "${GREEN}更新任务已准备好添加。${PLAIN}"
else
    echo -e "${YELLOW}每日更新任务已存在，跳过。${PLAIN}"
fi

if ! echo "${CURRENT_CRONTAB}" | grep -Fq "/update/mihomo"; then
    echo "正在添加每日备份任务..."
    CURRENT_CRONTAB="${CURRENT_CRONTAB}
${CRON_JOB_2}"
    echo -e "${GREEN}备份任务已准备好添加。${PLAIN}"
else
    echo -e "${YELLOW}每日备份任务已存在，跳过。${PLAIN}"
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
