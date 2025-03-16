#!/bin/bash
set -e

DOWNLOAD_URL="https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/docker.txt"  # 替换为真实的配置文件URL

# 内存处理函数
process_in_memory() {
    local content="$1"
    # 过滤注释和空行并处理换行符
    grep -vE '^#|^$' <<< "$content" | tr -d '\r' | while IFS= read -r line; do
        local cmd=$(echo "$line" | sed 's/#.*//')  # 去除行内注释
        local container_name=$(echo "$cmd" | sed -nE 's/.*--name[= ]([^ ]+).*/\1/p')
        
        # 容器名有效性校验
        [ -z "$container_name" ] && continue
        
        # 存在性检查（包含已停止的容器）
        if docker ps -a --format "{{.Names}}" | grep -qxF "$container_name"; then
            continue  # 静默跳过
        fi
        
        echo "正在安装容器: $container_name"
        eval "$cmd" 2>/dev/null || echo "安装失败: $container_name" >&2
    done
}

# 主流程
echo "开始容器安装流程..."
if ! content=$(curl -sSfL "$DOWNLOAD_URL"); then
    echo "配置文件下载失败" >&2
    exit 1
fi

process_in_memory "$content"
echo "所有容器操作已完成"

# 内存清理（Bash会自动回收变量内存)
