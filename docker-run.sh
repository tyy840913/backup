#!/bin/bash

set -e

DOWNLOAD_URL="https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/docker.txt"
echo "正在下载docker.txt文件..."
if ! curl -sSfL "$DOWNLOAD_URL" -o docker.txt; then
    echo "下载失败，请检查网络连接或URL有效性"
    exit 1
fi

process_line() {
    local cmd="$1"
    local container_name=$(echo "$cmd" | sed -nE 's/.*--name[= ]([^ ]+).*/\1/p')
    if [ -z "$container_name" ]; then
        echo "错误：未检测到容器名称，跳过命令: $cmd"
        return
    fi

    # 检查容器是否存在
    if docker ps -a --format "{{.Names}}" | grep -qxF "$container_name"; then
        # 新增默认值逻辑：用户直接回车则视为 'n'
        read -p "发现已存在容器 [$container_name]，是否重新安装？(y/N 默认N): " answer </dev/tty
        answer="${answer:-n}"  # 如果用户直接回车，自动填充默认值 'n'
        if [[ "${answer,,}" != "y" && "${answer,,}" != "yes" ]]; then
            echo "已跳过容器 [$container_name] 安装"
            return
        fi

        echo "正在移除旧容器 [$container_name]..."
        docker rm -f "$container_name" 2>/dev/null || true

        local image_name=$(echo "$cmd" | awk '{print $NF}' | tr -d '\r')
        if [ -n "$image_name" ]; then
            echo "正在清理旧镜像 [$image_name]..."
            docker rmi -f "$image_name" 2>/dev/null || true
        fi
    fi

    echo "正在启动容器 [$container_name]..."
    eval "$cmd"
    echo "--------------------------------------"
}

# 使用文件描述符3读取文件，保留标准输入用于用户交互
exec 3< <(grep -vE '^#|^$' docker.txt)
while IFS= read -r -u3 line; do
    process_line "$(echo "$line" | tr -d '\r')"
done
exec 3<&-

echo "所有容器操作已完成"
rm -f docker.txt
