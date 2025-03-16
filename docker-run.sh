#!/bin/bash
set -eo pipefail

DOWNLOAD_URL="https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/docker.txt"  # 替换为实际配置文件URL

# 内存处理函数（兼容不同Shell版本）
process_in_memory() {
    local content="$1"
    # 过滤注释/空行并处理换行符（兼容Windows格式）
    grep -vE '^#|^$' <<< "$content" | sed 's/#.*//;s/\r$//' | while IFS= read -r line; do
        local cmd=$(echo "$line" | xargs)  # 去除首尾空白
        [ -z "$cmd" ] && continue
        
        # 解析容器名称（兼容--name=和--name两种格式）
        local container_name=$(echo "$cmd" | sed -nE 's/.*--name[= ]([^ ]+).*/\1/p')
        [ -z "$container_name" ] && continue
        
        # 存在性检查（包含已停止的容器）
        if docker ps -a --format "{{.Names}}" | grep -qxF "$container_name"; then
            continue  # 静默跳过
        fi
        
        echo "正在安装容器: $container_name"
        # 执行命令并抑制输出（错误信息仍显示）
        if ! eval "$cmd" >/dev/null; then
            echo "错误：容器 [$container_name] 启动失败" >&2
            echo "失败命令: $cmd" >&2
        fi
    done
}

# 主流程
main() {
    echo "开始容器安装流程..."
    
    # 下载配置到内存（启用失败重试）
    if ! content=$(curl -sSfL --retry 3 "$DOWNLOAD_URL"); then
        echo "配置文件下载失败，请检查:" >&2
        echo "1. URL有效性 [$DOWNLOAD_URL]" >&2
        echo "2. 网络连接状态" >&2
        exit 1
    fi
    
    process_in_memory "$content"
    
    echo "所有容器操作已完成"
}

main
