#!/bin/bash

DOWNLOAD_URL="https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/docker.txt"
TEMP_FILE=$(mktemp)

echo "正在下载Docker配置..."
if ! curl -sSLf "$DOWNLOAD_URL" -o "$TEMP_FILE"; then
    echo "错误：文件下载失败！"
    exit 1
fi

process_command() {
    local cmd="$1"
    
    # 提取容器名（支持--name=、--name和带引号的情况）
    local container_name=$(echo "$cmd" | grep -oP -- '--name[=\s]+\K[^"\s]+|--name[=\s]+\"\K[^"]+')
    if [ -z "$container_name" ]; then
        echo "错误：无法提取容器名，跳过命令: $cmd"
        return
    fi
    
    # 检查容器是否存在
    if docker ps -a --format '{{.Names}}' | grep -qw "$container_name"; then
        read -p "发现已存在的容器 [$container_name]，是否重新安装？[y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "已跳过容器 [$container_name]"
            return
        fi
        
        # 删除容器
        echo "正在删除容器 [$container_name]..."
        docker rm -f "$container_name" >/dev/null 2>&1
        
        # 删除关联镜像
        local image_name=$(docker inspect --format='{{.Config.Image}}' "$container_name" 2>/dev/null)
        if [ -n "$image_name" ]; then
            echo "正在删除镜像 [$image_name]..."
            docker rmi -f "$image_name" >/dev/null 2>&1
        fi
    fi
    
    # 执行命令
    echo "正在启动容器 [$container_name]..."
    eval "$cmd"
}

while IFS= read -r line; do
    line=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -z "$line" ] && continue
    
    process_command "$line"
done < "$TEMP_FILE"

rm -f "$TEMP_FILE"
echo "所有容器操作已完成！"
