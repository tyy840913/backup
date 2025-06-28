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
        echo "ERROR: 此脚本需要以 root 权限运行。请使用 sudo 或切换到 root 用户。" >&2
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
    apt autoremove -y >/dev/null 2>&1

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
            # 删除超过1天的文件
            find "$dir" -mindepth 1 -maxdepth 1 -type f -mtime +1 -delete 2>/dev/null
            # 删除空目录
            find "$dir" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null
        fi
    done
    log_message "临时文件清理完成。"
}

# 清理旧日志文件
clean_logs() {
    log_message "正在清理旧日志文件..."
    for log_glob in "${LOG_PATHS[@]}"; do
        # 查找并删除超过指定天数的日志文件
        find "$log_glob" -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null
    done

    # 清理 dpkg 日志归档文件
    if [[ -f "/var/log/dpkg.log" ]]; then
        find /var/log/dpkg.log.* -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null
    fi

    # 清理 APT 缓存
    log_message "正在清理 APT 缓存..."
    apt clean >/dev/null 2>&1
    log_message "旧日志和APT缓存清理完成。"
}

# 清理 root 用户缓存及 Snap 缓存
clean_user_cache() {
    log_message "正在清理root用户缓存..."
    for cache_dir in "${USER_CACHE_DIRS[@]}"; do
        if [[ -d "$cache_dir" ]]; then
            # 删除超过指定天数的文件
            find "$cache_dir" -mindepth 1 -maxdepth 1 -type f -mtime +$CACHE_RETENTION_DAYS -delete 2>/dev/null
            # 删除空目录
            find "$cache_dir" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null
        fi
    done

    # 清理 snap 缓存（如果已安装 snap）
    if command -v snap &>/dev/null; then
        log_message "正在清理 Snap 缓存和旧版本..."
        set -eu # 开启严格模式，遇到未设置的变量或错误时退出
        
        # 刷新所有snap应用，确保获取最新版本信息
        for snap_name in $(snap list | awk 'NR > 1 {print $1}'); do
            snap refresh "$snap_name" >/dev/null 2>&1 || true # 刷新失败不退出
        done

        # 清理旧版本的snap应用
        LANG=C snap list --all | awk 'NR>1 && NF>=5 {print $1, $3, $5}' | while read snapname revision cohort; do
            # 排除核心snap，避免误删
            if [[ "$snapname" = "core" ]] || [[ "$snapname" = "snapd" ]]; then
                continue
            fi
            
            # 获取指定snap的所有版本并按版本号降序排序
            snap_versions=$(snap list --all "$snapname" | awk 'NR>1 {print $5}' | sort -nr)
            count=0
            for snap_version in $snap_versions; do
                ((count++))
                # 保留最新的2个版本，删除更旧的
                if [[ $count -gt 2 ]]; then
                    log_message "  - 移除 ${snapname} 版本 ${snap_version}"
                    snap remove "$snap_name" --revision="$snap_version" >/dev/null 2>&1 || true # 移除失败不退出
                fi
            done
        done
        set +eu # 关闭严格模式
        log_message "Snap 缓存和旧版本清理完成。"
    fi
    log_message "用户缓存清理完成。"
}

# 安装定时任务函数
install_cron_job() {
    echo "正在尝试安装定时任务..."
    # 检查脚本是否已存在于安装路径
    if [[ ! -f "$INSTALL_PATH" ]]; then
        echo "ERROR: 脚本 '$SCRIPT_NAME' 未安装到 '$INSTALL_PATH'。无法设置定时任务。" >&2
        return 1
    fi

    # 检查是否已存在相同的定时任务
    if crontab -l 2>/dev/null | grep -Fq "$CRON_JOB"; then
        echo "WARN: 相同的定时任务已存在，无需重复添加。"
    else
        # 添加定时任务
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

# 提示用户是否安装脚本并设置定时任务 (仅在非静默模式下调用)
prompt_install_and_cron() {
    echo ""
    read -p "是否要将此清理脚本安装为系统服务并设置每周自动运行的定时任务？(y/N): " -n 1 -r
    echo "" # 换行

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "正在安装脚本到 $INSTALL_PATH ..."
        # 将当前执行的脚本内容复制到目标路径
        # 这里考虑通过管道执行的情况，确保脚本内容能正确写入
        if [[ -p /dev/stdin ]]; then # 检查是否为命名管道
            cat > "$INSTALL_PATH"
        else
            # 否则，从当前文件复制 (如果文件已存在于某个位置)
            cp "$(readlink -f "$0")" "$INSTALL_PATH"
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

# 检查是否存在相同的定时任务（只检查精确匹配的 CRON_JOB 字符串）
check_existing_cron_job() {
    crontab -l 2>/dev/null | grep -Fq "$CRON_JOB"
}

# 显示帮助信息
show_help() {
    echo "使用方法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --cron   作为定时任务运行 (完全静默执行清理，不输出任何信息)"
    echo "  --help   显示此帮助信息"
    echo ""
    echo "不带任何选项运行时，脚本将立即执行系统清理。清理过程中会显示常规输出。"
    echo "如果检测到相同的定时任务已存在，脚本将直接执行清理，不提示安装。"
    echo "如果未检测到定时任务，脚本将执行清理后提示是否安装。"
}

# --- 主逻辑执行区 ---
check_root # 确保脚本以root权限运行

# 解析命令行参数
case "$1" in
    --cron)
        IS_FULLY_SILENT_MODE=true # 设定为完全静默模式
        perform_cleanup            # 执行清理
        exit 0                     # 退出，不进行其他操作
        ;;
    --help)
        show_help
        exit 0
        ;;
    "")
        # 不带参数运行：手动执行，根据是否存在定时任务来决定是否询问安装
        if check_existing_cron_job; then
            echo "检测到相同的定时任务已存在，直接执行清理。"
            perform_cleanup # 已存在，直接清理，不提示安装
        else
            perform_cleanup # 先执行清理
            prompt_install_and_cron # 清理完后提示用户安装
        fi
        ;;
    *)
        # 任何其他参数：视为无效参数，显示帮助信息并退出
        echo "ERROR: 未知或不支持的选项 '$1'。" >&2
        show_help
        exit 1
        ;;
esac
