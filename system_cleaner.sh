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

# --- 函数定义 ---

# 检查是否以 root 权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: 此脚本需要以 root 权限运行。请使用 root 用户或使用 sudo 运行。" >&2
        exit 1
    fi
}

# 辅助输出函数，根据静默模式决定是否打印
log_message() {
    if [[ "$IS_FULLY_SILENT_MODE" = false ]]; then
        echo "$@"
    fi
}

# 执行清理操作的主函数
perform_cleanup() {
    log_message "系统清理脚本开始运行..."
    clean_tmp
    clean_logs
    clean_user_cache

    # 系统维护命令
    log_message "正在执行系统维护命令..."
    apt-get autoremove -y >/dev/null 2>&1
    apt-get clean >/dev/null 2>&1

    # 判断 updatedb 是否存在后再执行
    if command -v updatedb &>/dev/null; then
        updatedb >/dev/null 2>&1
    fi

    sync >/dev/null 2>&1
    log_message "系统维护命令执行完成。"
    log_message "系统清理脚本运行完毕。"
}

# 清理临时文件
clean_tmp() {
    log_message "正在清理临时文件..."
    for dir in "${TMP_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            # 删除超过1天的文件和目录
            find "$dir" -mindepth 1 -mtime +1 -exec rm -rf {} + 2>/dev/null
        fi
    done
    log_message "临时文件清理完成。"
}

# 清理旧日志文件
clean_logs() {
    log_message "正在清理旧日志文件..."
    for log_glob in "${LOG_PATHS[@]}"; do
        # 查找并删除超过指定天数的日志文件
        find $(dirname "$log_glob") -name "$(basename "$log_glob")" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null
    done

    # 清理 dpkg 日志归档文件
    if [[ -f "/var/log/dpkg.log" ]]; then
        find /var/log/ -name "dpkg.log.*" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null
    fi
    log_message "旧日志清理完成。"
}

# 清理 root 用户缓存
clean_user_cache() {
    log_message "正在清理root用户缓存..."
    for cache_dir in "${USER_CACHE_DIRS[@]}"; do
        if [[ -d "$cache_dir" ]];
            # 删除超过指定天数的文件和目录
            then find "$cache_dir" -mindepth 1 -mtime +$CACHE_RETENTION_DAYS -exec rm -rf {} + 2>/dev/null
        fi
    done
}

# 安装定时任务函数
install_cron_job() {
    echo "正在尝试安装定时任务..."
    if [[ ! -f "$INSTALL_PATH" ]]; then
        echo "ERROR: 脚本 '$SCRIPT_NAME' 未安装到 '$INSTALL_PATH'。无法设置定时任务。" >&2
        echo "请确保脚本已成功保存到 $INSTALL_PATH。"
        return 1
    fi

    if crontab -l 2>/dev/null | grep -Fq "$CRON_JOB"; then
        echo "WARN: 相同的定时任务已存在，无需重复添加。"
    else
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
        if [[ $? -eq 0 ]]; then
            echo "定时任务已成功添加：$CRON_JOB"
            echo "您可以通过 'crontab -l' 查看已安装的定时任务。"
        else
            echo "ERROR: 添加定时任务失败。" >&2
            return 1
        fi
    fi
    return 0
}

# 提示用户是否安装脚本并设置定时任务
prompt_install_and_cron() {
    echo ""
    read -p "是否要将此清理脚本安装为系统服务并设置每周自动运行的定时任务？(y/N): " -n 1 -r
    echo ""

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "正在安装脚本到 $INSTALL_PATH ..."
        if [[ -f "$0" ]]; then
            cp "$0" "$INSTALL_PATH"
        else
            echo "ERROR: 无法获取脚本文件路径进行自保存。请先手动保存脚本到文件，再执行安装。" >&2
            return 1
        fi
        
        if [[ $? -eq 0 ]]; then
            chmod +x "$INSTALL_PATH"
            echo "脚本已成功保存到 $INSTALL_PATH 并已赋予执行权限。"
            install_cron_job
        else
            echo "ERROR: 无法保存脚本到 $INSTALL_PATH。请检查权限或磁盘空间。" >&2
            return 1
        fi
    else
        echo "已跳过安装定时任务。"
    fi
    return 0
}

# 【已修正】检查是否存在相同的定时任务（只检查有效的、未被注释的行）
check_existing_cron_job() {
    local current_crontab_jobs
    current_crontab_jobs=$(crontab -l 2>/dev/null)

    if [[ -z "$current_crontab_jobs" ]]; then
        return 1 # crontab 为空，任务肯定不存在
    fi

    # 关键改进：过滤掉注释行再进行精确匹配
    if echo "$current_crontab_jobs" | grep -v '^[[:space:]]*#' | grep -Fq "$CRON_JOB"; then
        return 0 # 存在有效的、匹配的定时任务
    else
        return 1 # 不存在匹配的定时任务
    fi
}

# 显示帮助信息
show_help() {
    echo "使用方法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --cron   作为定时任务运行 (完全静默执行清理，不输出任何信息)"
    echo "  --help   显示此帮助信息"
    echo ""
    echo "不带任何选项运行时，脚本将立即执行系统清理。清理完成后，如果未检测到已安装的定时任务，则会提示安装。"
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
            echo "检测到相同的定时任务已存在，本次运行不提示安装。"
        else
            prompt_install_and_cron 
        fi
        ;;
    *)
        echo "ERROR: 未知或不支持的选项 '$1'。" >&2
        show_help
        exit 1
        ;;
esac
