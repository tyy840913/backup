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

# 定时任务相关变量
SCRIPT_PATH="$(readlink -f "$0")" # 获取脚本的绝对路径
CRON_JOB="0 3 * * 0 $SCRIPT_PATH" # 每周日凌晨3点运行，这里可以根据需要调整时间

# --- 函数定义 ---

# 检查是否以 root 权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        exit 1
    fi
}

# 清理临时文件
clean_tmp() {
    echo "正在清理临时文件..."
    for dir in "${TMP_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            find "$dir" -mindepth 1 -maxdepth 1 -type f -mtime +1 -delete 2>/dev/null
            find "$dir" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null
        fi
    done
    echo "临时文件清理完成。"
}

# 清理旧日志文件
clean_logs() {
    echo "正在清理旧日志文件..."
    for log_glob in "${LOG_PATHS[@]}"; do
        find $log_glob -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null
    done

    # 清理 dpkg 日志归档文件
    if [[ -f "/var/log/dpkg.log" ]]; then
        find /var/log/dpkg.log.* -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null
    fi

    # 清理 APT 缓存
    apt clean >/dev/null 2>&1
    echo "旧日志和APT缓存清理完成。"
}

# 清理 root 用户缓存及 Snap 缓存
clean_user_cache() {
    echo "正在清理root用户缓存..."
    for cache_dir in "${USER_CACHE_DIRS[@]}"; do
        if [[ -d "$cache_dir" ]]; then
            find "$cache_dir" -mindepth 1 -maxdepth 1 -type f -mtime +$CACHE_RETENTION_DAYS -delete 2>/dev/null
            find "$cache_dir" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null
        fi
    done

    # 清理 snap 缓存（如果已安装 snap）
    if command -v snap &>/dev/null; then
        echo "正在清理 Snap 缓存和旧版本..."
        set -eu
        for snap_name in $(snap list | awk 'NR > 1 {print $1}'); do
            snap set "$snap_name" system.refresh.hold=false >/dev/null 2>&1
            snap refresh "$snap_name" >/dev/null 2>&1
            snap unset "$snap_name" system.refresh.hold >/dev/null 2>&1
        done

        LANG=C snap list --all | awk 'NR>1 && NF>=5 {print $1, $3, $5}' | while read snapname revision cohort; do
            if [[ "$snapname" = "core" ]] || [[ "$snapname" = "snapd" ]]; then
                continue
            fi
            snap_versions=$(snap list --all "$snapname" | awk 'NR>1 {print $5}' | sort -nr)
            count=0
            for snap_version in $snap_versions; do
                ((count++))
                if [[ $count -gt 2 ]]; then
                    snap remove "$snapname" --revision="$snap_version" >/dev/null 2>&1
                fi
            done
        done
        set +eu
        echo "Snap 缓存和旧版本清理完成。"
    fi
    echo "用户缓存清理完成。"
}

# 安装定时任务函数
install_cron_job() {
    echo "正在尝试安装定时任务..."
    # 检查是否已存在相同的定时任务
    if crontab -l 2>/dev/null | grep -Fq "$CRON_JOB"; then
        echo "WARN: 相同的定时任务已存在，无需重复添加。"
    else
        # 添加定时任务
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
        if [[ $? -eq 0 ]]; then
            echo "定时任务已成功安装：$CRON_JOB"
            echo "您可以通过 'crontab -l' 查看已安装的定时任务。"
        else
            echo "ERROR: 安装定时任务失败。"
        fi
    fi
}

# 显示帮助信息
show_help() {
    echo "使用方法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --install-cron   安装每周自动运行的定时任务"
    echo "  --help           显示此帮助信息"
    echo ""
    echo "不带任何选项运行时，脚本将立即执行系统清理。"
}

# --- 主逻辑执行区 ---
check_root # 确保脚本以root权限运行

# 解析命令行参数
case "$1" in
    --install-cron)
        install_cron_job
        exit 0 # 执行完定时任务安装后退出
        ;;
    --help)
        show_help
        exit 0
        ;;
    "")
        # 不带参数，执行清理逻辑
        echo "系统清理脚本开始运行..."
        clean_tmp
        clean_logs
        clean_user_cache

        # 系统维护命令
        echo "正在执行系统维护命令..."
        apt autoremove -y >/dev/null 2>&1

        # 判断 updatedb 是否存在后再执行
        if command -v updatedb &>/dev/null; then
            updatedb >/dev/null 2>&1
        fi

        sync >/dev/null 2>&1
        echo "系统维护命令执行完成。"
        echo "系统清理脚本运行完毕。"
        ;;
    *)
        echo "ERROR: 未知选项 '$1'。"
        show_help
        exit 1
        ;;
esac

