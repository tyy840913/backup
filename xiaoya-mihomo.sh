#!/bin/bash
set -e

# 配置
DOWNLOAD_URL="https://backup.woskee.dpdns.org"
UPLOAD_URL="https://backup.woskee.dpdns.org/update"

# 获取用户名和密码
read -p "请输入用户名: " USERNAME
read -s -p "请输入密码: " PASSWORD
echo

# 下载并解压备份
download_and_extract() {
    local service=$1
    local target_dir="/etc/$service"
    
    # 创建目录
    echo "创建目录: $target_dir"
    mkdir -p "$target_dir"
    
    # 下载
    echo "正在从 $DOWNLOAD_URL/$service 下载 $service 备份..."
    echo "使用命令: curl -u $USERNAME:****** -f -O $DOWNLOAD_URL/$service"
    
    if curl -u "$USERNAME:$PASSWORD" -f -O "$DOWNLOAD_URL/$service"; then
        echo "✓ $service 下载成功"
        
        # 检查文件是否存在
        if [[ -f "$service" ]]; then
            echo "文件大小: $(du -h "$service" | cut -f1)"
            echo "正在解压到 $target_dir..."
            
            # 解压
            if tar -xf "$service" -C "$target_dir"; then
                echo "✓ $service 解压成功"
                echo "解压文件列表:"
                ls -la "$target_dir" | head -20
            else
                echo "⚠ $service 解压失败，可能不是压缩文件"
            fi
            
            # 删除下载的文件
            rm -f "$service"
            echo "已删除下载文件: $service"
        else
            echo "⚠ 下载的文件不存在"
        fi
    else
        echo "✗ $service 下载失败"
        echo "请检查:"
        echo "  1. 网络连接"
        echo "  2. URL地址: $DOWNLOAD_URL/$service"
        echo "  3. 用户名密码是否正确"
    fi
    
    echo "----------------------------------------"
}

# 设置定时上传任务
setup_upload_cron() {
    local service=$1
    local current_cron=$(crontab -l 2>/dev/null || true)
    local cron_pattern="$UPLOAD_URL/$service"
    
    # 检查是否已有该服务的定时上传任务
    if echo "$current_cron" | grep -q "$cron_pattern"; then
        echo "$service 定时上传任务已存在，跳过添加"
        return
    fi
    
    # 添加上传定时任务
    if [ "$service" = "xiaoya" ]; then
        # xiaoya: 排除xiaoya/data目录
        local upload_cmd="0 0 */3 * * /usr/bin/tar -cf - -C /etc --exclude=xiaoya/data xiaoya | /usr/bin/curl -u $USERNAME:$PASSWORD -T - $UPLOAD_URL/$service >/dev/null 2>&1"
    else
        # mihomo: 上传整个目录
        local upload_cmd="0 0 */3 * * /usr/bin/tar -cf - -C /etc $service | /usr/bin/curl -u $USERNAME:$PASSWORD -T - $UPLOAD_URL/$service >/dev/null 2>&1"
    fi
    
    (echo "$current_cron"; echo "$upload_cmd") | crontab -
    echo "✓ $service 定时上传任务已添加"
    echo "命令: $upload_cmd"
}

# 主流程
main() {
    echo "========================================"
    echo "开始自动下载备份并设置定时上传任务"
    echo "========================================"
    
    # 下载两个服务
    echo ""
    echo "=== 下载备份文件 ==="
    download_and_extract "xiaoya"
    download_and_extract "mihomo"
    
    echo ""
    echo "=== 设置定时上传任务 ==="
    setup_upload_cron "xiaoya"
    setup_upload_cron "mihomo"
    
    echo ""
    echo "=== 完成 ==="
    echo "当前所有定时任务:"
    echo "----------------------------------------"
    crontab -l
    echo "----------------------------------------"
    echo "已成功完成下载和定时任务设置"
}

# 执行
main "$@"
