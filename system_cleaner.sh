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
# SCRIPT_PATH="$(readlink -f "$0")" # 这行在新的逻辑中不再直接使用，而是用 INSTALL_PATH
CRON_JOB="0 3 * * 0 $INSTALL_PATH >/dev/null 2>&1" # 每周日凌晨3点运行，这里可以根据需要调整时间

# --- 函数定义 ---

# 检查是否以 root 权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: 此脚本需要以 root 权限运行。请使用 sudo 或切换到 root 用户。" >&2
        exit 1
    fi
}

# 清理临时文件
clean_tmp() {
    echo "正在清理临时文件..."
    for dir in "${TMP_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            # 删除超过1天的文件
            find "$dir" -mindepth 1 -maxdepth 1 -type f -mtime +1 -delete 2>/dev/null
            # 删除空目录
            find "$dir" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null
        fi
    done
    echo "临时文件清理完成。"
}

# 清理旧日志文件
clean_logs() {
    echo "正在清理旧日志文件..."
    for log_glob in "${LOG_PATHS[@]}"; do
        # 查找并删除超过指定天数的日志文件
        find $log_glob -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null
    done

    # 清理 dpkg 日志归档文件
    if [[ -f "/var/log/dpkg.log" ]]; then
        find /var/log/dpkg.log.* -type f -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null
    fi

    # 清理 APT 缓存
    echo "正在清理 APT 缓存..."
    apt clean >/dev/null 2>&1
    echo "旧日志和APT缓存清理完成。"
}

# 清理 root 用户缓存及 Snap 缓存
clean_user_cache() {
    echo "正在清理root用户缓存..."
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
        echo "正在清理 Snap 缓存和旧版本..."
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
                    echo "  - 移除 ${snapname} 版本 ${snap_version}"
                    snap remove "$snapname" --revision="$snap_version" >/dev/null 2>&1 || true # 移除失败不退出
                fi
            done
        done
        set +eu # 关闭严格模式
        echo "Snap 缓存和旧版本清理完成。"
    fi
    echo "用户缓存清理完成。"
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
            echo "定时任务已成功安装：$CRON_JOB"
            echo "您可以通过 'crontab -l' 查看已安装的定时任务。"
        else
            echo "ERROR: 安装定时任务失败。" >&2
            return 1
        fi
    fi
    return 0
}

# 提示用户是否安装脚本并设置定时任务
prompt_install_and_cron() {
    echo ""
    read -p "是否要将此清理脚本安装为系统服务并设置每周自动运行的定时任务？(y/N): " -n 1 -r
    echo "" # 换行

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "正在安装脚本到 $INSTALL_PATH ..."
        # 将当前执行的脚本内容复制到目标路径
        # $0 在管道执行时是 "/dev/fd/63" 或类似，不能直接复制
        # 我们需要从 stdin (由 curl 管道输入) 读取内容并保存
        
        # 检查是否以管道方式运行
        if [[ -p /dev/stdin ]]; then # -p 检查是否为命名管道
            # 读取标准输入并保存到文件
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

# 显示帮助信息
show_help() {
    echo "使用方法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --install-cron   安装每周自动运行的定时任务 (需要脚本已存在于 $INSTALL_PATH)"
    echo "  --help           显示此帮助信息"
    echo ""
    echo "不带任何选项运行时，脚本将立即执行系统清理。"
    echo "如果脚本通过管道直接执行，在清理完成后会提示是否安装定时任务。"
}

# --- 主逻辑执行区 ---
check_root # 确保脚本以root权限运行

# 判断脚本是否通过管道方式运行
# /proc/self/fd/0 是当前进程的标准输入
# 如果 /proc/self/fd/0 指向的是管道 (pipe)，则说明是通过管道运行
if [[ -p /dev/stdin ]]; then
    IS_PIPED=true
else
    IS_PIPED=false
fi

# 解析命令行参数
case "$1" in
    --install-cron)
        # 如果是直接运行并带 --install-cron 参数
        if [[ ! "$IS_PIPED" = true ]]; then
            install_cron_job
            exit 0 # 执行完定时任务安装后退出
        else
            echo "WARN: 在管道模式下 '--install-cron' 参数通常不直接使用。"
            echo "脚本会在清理完成后自动提示是否安装定时任务。"
            # 继续执行清理流程
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
            
            prompt_install_and_cron # 提示安装定时任务
            exit 0
        fi
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
        
        # 如果是通过管道运行，提示安装定时任务
        if [[ "$IS_PIPED" = true ]]; then
            prompt_install_and_cron
        fi
        ;;
    *)
        echo "ERROR: 未知选项 '$1'。" >&2
        show_help
        exit 1
        ;;
esac
