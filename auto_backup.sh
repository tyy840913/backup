#!/bin/bash
set -e

# 配置
DOWNLOAD_URL="https://backup.woskee.dpdns.org"
BACKUP_SCRIPT_PATH="/docker_data/backup.sh"
AUTO_SCRIPT_URL="https://backup.woskee.dpdns.org/auto.sh"

# 全局变量
USERNAME=""
PASSWORD=""

# 获取凭据函数（支持重试）
get_credentials() {
    local attempt=1
    local MAX_ATTEMPTS=3
    
    while [ $attempt -le $MAX_ATTEMPTS ]; do
        read -p "请输入用户名: " USERNAME
        read -s -p "请输入密码: " PASSWORD
        echo
        
        if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
            echo -e "\n错误：用户名和密码不能为空" >&2
        else
            # 测试凭据有效性
            if curl -s -u "$USERNAME:$PASSWORD" -f "$DOWNLOAD_URL" >/dev/null; then
                echo "✓ 认证成功"
                return 0
            else
                echo -e "\n错误：认证失败，请检查用户名和密码" >&2
            fi
        fi
        
        ((attempt++))
        if [ $attempt -le $MAX_ATTEMPTS ]; then
            echo "还有$((MAX_ATTEMPTS - attempt + 1))次尝试机会"
        fi
    done

    echo -e "\n错误：超过最大尝试次数" >&2
    return 1
}

# 直接下载文件到指定位置
download_file() {
    local url=$1
    local output=$2
    local description=$3
    
    echo "正在下载 $description..."
    
    if curl -u "$USERNAME:$PASSWORD" -f -L -o "$output" "$url"; then
        if [ -s "$output" ]; then
            if grep -q "<html" "$output" 2>/dev/null; then
                echo "✗ 下载失败：认证错误或文件不存在"
                rm -f "$output"
                return 1
            else
                echo "✓ $description 下载成功"
                return 0
            fi
        else
            echo "✗ 下载文件为空"
            rm -f "$output"
            return 1
        fi
    else
        echo "✗ 下载失败：网络错误或认证失败"
        return 1
    fi
}

# 下载并解压到指定目录
download_and_extract() {
    local service=$1
    local target_dir="/etc/$service"
    
    echo "正在处理 $service 备份..."
    
    # 先创建目标目录
    echo "创建目录: $target_dir"
    mkdir -p "$target_dir"
    
    # 流式下载并直接解压到目标目录（不保存临时文件）
    echo "正在流式下载并解压到 $target_dir..."
    if curl -u "$USERNAME:$PASSWORD" -f -L "$DOWNLOAD_URL/${service}.tar" | tar -x -C "$target_dir" 2>/dev/null; then
        echo "✓ $service 流式下载和解压成功"
        return 0
    else
        echo "✗ $service 流式下载或解压失败"
        return 1
    fi
}

# 设置定时任务（避免重复）
setup_cron_job() {
    local job="$1"
    local comment="$2"
    local current_cron=$(crontab -l 2>/dev/null || true)
    
    if echo "$current_cron" | grep -q "$comment"; then
        echo "定时任务已存在，跳过添加"
        return
    fi
    
    (echo "$current_cron"; echo "$job $comment") | crontab -
    echo "✓ 定时任务添加成功"
}

# 下载并执行自动脚本
download_and_execute_auto_script() {
    local script_path="/root/auto.sh"
    local attempt=1
    local MAX_ATTEMPTS=3
    
    echo ""
    echo "=== 下载并执行自动脚本 ==="
    
    while [ $attempt -le $MAX_ATTEMPTS ]; do
        echo "尝试 $attempt/$MAX_ATTEMPTS"
        
        # 直接下载到目标位置
        if download_file "$AUTO_SCRIPT_URL" "$script_path" "自动脚本"; then
            # 检查文件格式
            if grep -q $'\r' "$script_path"; then
                echo "检测到Windows换行符，正在转换..."
                sed -i 's/\r$//' "$script_path"
            fi
            
            chmod +x "$script_path"
            echo "✓ 脚本已保存到: $script_path"
            
            # 立即执行脚本
            echo "正在执行下载的脚本..."
            if bash "$script_path"; then
                echo "✓ 脚本执行成功"
                
                # 设置定时任务
                setup_cron_job "0 0 * * * /bin/bash $script_path >/dev/null 2>&1" "# 每天执行auto.sh脚本"
                return 0
            else
                echo "⚠ 脚本执行失败，尝试重新下载"
                rm -f "$script_path"
            fi
        else
            echo "⚠ 自动脚本下载失败"
        fi
        
        ((attempt++))
        if [ $attempt -le $MAX_ATTEMPTS ]; then
            echo "等待3秒后重试..."
            sleep 3
        fi
    done

    echo "⚠ 自动脚本处理失败，跳过此步骤"
    return 1
}

# 获取内存临时目录路径
get_memory_temp_dir() {
    # 优先使用 /dev/shm (共享内存)
    if [ -d "/dev/shm" ]; then
        echo "/dev/shm/backup_$$"  # 使用PID避免冲突
    # 其次使用 /run/shm (某些系统的共享内存)
    elif [ -d "/run/shm" ]; then
        echo "/run/shm/backup_$$"
    # 最后使用 /tmp (可能使用tmpfs内存文件系统)
    else
        echo "/tmp/backup_$$"
    fi
}

# 处理服务备份
process_service_backup() {
    local service=$1
    
    echo ""
    echo "=== 处理 $service 备份 ==="
    
    if download_and_extract "$service"; then
        # 获取内存临时目录
        local memory_dir=$(get_memory_temp_dir)
        
        # 设置定时上传任务（使用内存临时目录，完成后清除整个目录）
        if [ "$service" = "xiaoya" ]; then
            # xiaoya: 排除data目录
            local upload_cmd="55 5 * * * (mkdir -p $memory_dir && cd $memory_dir && /usr/bin/tar -cf xiaoya.tar -C /etc/xiaoya --exclude=data . && $BACKUP_SCRIPT_PATH update xiaoya.tar && cd / && rm -rf $memory_dir)"
        else
            # mihomo: 排除cache.db和Country.mmdb
            local upload_cmd="30 5 * * * (mkdir -p $memory_dir && cd $memory_dir && /usr/bin/tar -cf mihomo.tar -C /etc/mihomo --exclude=cache.db --exclude=Country.mmdb . && $BACKUP_SCRIPT_PATH update mihomo.tar && cd / && rm -rf $memory_dir)"
        fi
        
        setup_cron_job "$upload_cmd" "# 每天上传$service备份"
        echo "✓ $service 定时上传任务设置完成"
        echo "✓ 使用内存临时目录: $memory_dir"
        echo "打包命令: $upload_cmd"
    else
        echo "⚠ $service 备份处理失败，跳过定时任务设置"
    fi
}

# 主流程
main() {
    echo "========================================"
    echo "开始自动下载和设置定时任务（内存优化版）"
    echo "========================================"
    
    # 获取认证信息
    if ! get_credentials; then
        echo "认证失败，退出脚本"
        exit 1
    fi
    
    # 下载并执行自动脚本
    download_and_execute_auto_script
    
    # 处理服务备份
    process_service_backup "xiaoya"
    process_service_backup "mihomo"

    echo "✓ 所有操作已完成。"
}

# 执行主函数
main "$@"
