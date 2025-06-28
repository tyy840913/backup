#!/bin/bash

# --- 变量定义 ---
# 日志文件最大保留天数
LOG_RETENTION_DAYS=7
# 缓存文件最大保留天数
CACHE_RETENTION_DAYS=30

# 临时文件目录
TMP_DIRS=(
    "/tmp"
    "/var/tmp"
)

# 日志文件目录和文件（支持通配符）
LOG_PATHS=(
    "/var/log/*.log"
    "/var/log/*.[0-9]"
    "/var/log/*.gz"
    "/var/log/syslog"
    "/var/log/messages"
    "/var/log/kern.log"
    "/var/log/auth.log"
    "/var/log/daemon.log"
    "/var/log/ufw.log"
)

# root 用户缓存目录
USER_CACHE_DIRS=(
    "/root/.cache"
    "/root/.thumbnails"
)

# 定义脚本名称和安装路径
SCRIPT_NAME="system_cleaner.sh" # 脚本将保存为这个名字
INSTALL_PATH="/usr/local/bin/$SCRIPT_NAME" # 建议安装路径

# 定时任务相关变量
# 定时任务将带 --cron 参数运行，以区分手动执行
CRON_JOB="0 3 * * 0 $INSTALL_PATH --cron >/dev/null 2>&1" # 每周日凌晨3点运行

# 内部标志，指示是否为完全静默模式（仅用于 --cron 参数）
IS_FULLY_SILENT_MODE=false

# --- 颜色定义 ---
BLUE='\033[1;34m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m' # 无颜色

# --- 函数定义 ---

# 检查是否以 root 权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        # 错误信息总是需要显示，所以直接用 echo
        echo -e "${RED}ERROR: 此脚本需要以 root 权限运行。请使用 root 用户或使用 sudo 运行。${NC}" >&2
        exit 1
    fi
}

# 辅助输出函数，根据静默模式决定是否打印
log_message() {
    if [[ "$IS_FULLY_SILENT_MODE" = false ]]; then
        # -e 参数让 echo 能够解析颜色代码
        echo -e "$@"
    fi
}

# 执行清理操作的主函数
perform_cleanup() {
    log_message "\n${BLUE}--- 系统清理脚本开始运行 ---${NC}"
    clean_tmp
    clean_logs
    clean_user_cache

    log_message "${BLUE}--- 正在执行系统维护命令 ---${NC}"
    log_message -n "    - 运行 apt autoremove & clean..."
    apt-get autoremove -y >/dev/null 2>&1
    apt-get clean >/dev/null 2>&1
    log_message " ${GREEN}完成.${NC}"

    if command -v updatedb &>/dev/null; then
        log_message -n "    - 运行 updatedb..."
        updatedb >/dev/null 2>&1
        log_message " ${GREEN}完成.${NC}"
    fi

    sync >/dev/null 2>&1
    log_message "${GREEN}--- 系统清理脚本运行完毕 ---${NC}"
}

# 清理临时文件
clean_tmp() {
    log_message -n "[*] 正在清理临时文件..."
    for dir in "${TMP_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            find "$dir" -mindepth 1 -mtime +1 -exec rm -rf {} + 2>/dev/null
        fi
    done
    log_message " ${GREEN}完成.${NC}"
}

# 清理旧日志文件
clean_logs() {
    log_message -n "[*] 正在清理旧日志文件..."
    for log_glob in "${LOG_PATHS[@]}"; do
        find $(dirname "$log_glob") -name "$(basename "$log_glob")" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null
    done

    if [[ -f "/var/log/dpkg.log" ]]; then
        find /var/log/ -name "dpkg.log.*" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null
    fi
    log_message " ${GREEN}完成.${NC}"
}

# 清理 root 用户缓存
clean_user_cache() {
    log_message -n "[*] 正在清理root用户缓存..."
    for cache_dir in "${USER_CACHE_DIRS[@]}"; do
        if [[ -d "$cache_dir" ]]; then
            find "$cache_dir" -mindepth 1 -mtime +$CACHE_RETENTION_DAYS -exec rm -rf {} + 2>/dev/null
        fi
    done
    log_message " ${GREEN}完成.${NC}"
}


# 安装定时任务函数
install_cron_job() {
    log_message "    - 正在尝试安装定时任务..."
    if [[ ! -f "$INSTALL_PATH" ]]; then
        log_message "    ${RED}错误: 脚本 '$SCRIPT_NAME' 未安装到 '$INSTALL_PATH'。${NC}"
        return 1
    fi

    if crontab -l 2>/dev/null | grep -Fq "$CRON_JOB"; then
        log_message "    ${YELLOW}警告: 相同的定时任务已存在，无需重复添加。${NC}"
    else
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
        if [[ $? -eq 0 ]]; then
            log_message "    ${GREEN}成功: 定时任务已添加。${NC}"
        else
            log_message "    ${RED}错误: 添加定时任务失败。${NC}"
            return 1
        fi
    fi
    return 0
}

# 提示用户是否安装脚本并设置定时任务
prompt_install_and_cron() {
    log_message "\n${BLUE}--- 安装选项 ---${NC}"
    read -p "$(echo -e ${YELLOW}"是否要将此脚本安装并设置每周自动运行的定时任务？ (y/N): "${NC})" -n 1 -r
    echo "" # 换行

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_message -n "    - 正在安装脚本到 $INSTALL_PATH..."
        if [[ -f "$0" ]]; then
            cp "$0" "$INSTALL_PATH"
        else
            log_message "\n    ${RED}错误: 无法获取脚本文件路径进行自保存。${NC}"
            return 1
        fi
        
        if [[ $? -eq 0 ]]; then
            chmod +x "$INSTALL_PATH"
            log_message " ${GREEN}完成.${NC}"
            install_cron_job
        else
            log_message "\n    ${RED}错误: 无法保存脚本到 $INSTALL_PATH。${NC}"
            return 1
        fi
    else
        log_message "    - 已跳过安装定时任务。"
    fi
    return 0
}

# 检查是否存在相同的定时任务（只检查有效的、未被注释的行）
check_existing_cron_job() {
    local current_crontab_jobs
    current_crontab_jobs=$(crontab -l 2>/dev/null)

    if [[ -z "$current_crontab_jobs" ]]; then
        return 1
    fi

    if echo "$current_crontab_jobs" | grep -v '^[[:space:]]*#' | grep -Fq "$CRON_JOB"; then
        return 0
    else
        return 1
    fi
}

# 显示帮助信息
show_help() {
    echo "使用方法: $0 [选项]"
    echo ""
    echo "选项:"
    echo -e "  ${GREEN}--cron${NC}   作为定时任务运行 (完全静默执行清理)"
    echo -e "  ${GREEN}--help${NC}   显示此帮助信息"
    echo ""
    echo "不带任何选项运行时，脚本将立即执行清理。清理后，若无有效定时任务，则提示安装。"
}

# --- 主逻辑执行区 ---
check_root

case "$1" in
    --cron)
        IS_FULLY_SILENT_MODE=true
        perform_cleanup
        exit 0
        ;;
    --help)
        show_help
        exit 0
        ;;
    "")
        perform_cleanup
        if check_existing_cron_job; then
            log_message "\n${YELLOW}检测到相同的有效定时任务已存在，本次运行不提示安装。${NC}"
        else
            prompt_install_and_cron 
        fi
        ;;
    *)
        echo -e "${RED}ERROR: 未知或不支持的选项 '$1'。${NC}" >&2
        show_help
        exit 1
        ;;
esac
