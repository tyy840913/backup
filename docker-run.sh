#!/bin/bash

# 定义下载链接和临时文件路径
DOWNLOAD_URL="https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/docker.txt"
TEMP_FILE=$(mktemp)

# 使用curl下载文件
echo "正在下载Docker配置..."
if ! curl -sSLf "$DOWNLOAD_URL" -o "$TEMP_FILE"; then
    echo "错误：文件下载失败！"
    exit 1
fi

# 处理容器操作
process_command() {
    local cmd="$1"
    
    # 提取容器名称
    local container_name=$(echo "$cmd" | sed -n 's/.*--name \([^ ]*\).*/\1/p')
    [ -z "$container_name" ] && return
    
    # 检查容器是否存在
    if docker ps -a --format '{{.Names}}' | grep -qw "$container_name"; then
        read -p "发现已存在的容器 [$container_name]，是否重新安装？[y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "已跳过容器 [$container_name]"
            return
        fi
        
        # 删除现有容器
        echo "正在删除容器 [$container_name]..."
        docker rm -f "$container_name" >/dev/null 2>&1
        
        # 提取并删除镜像
        local image_name=$(echo "$cmd" | awk '{print $NF}')
        if [ -n "$image_name" ]; then
            echo "正在删除镜像 [$image_name]..."
            docker rmi -f "$image_name" >/dev/null 2>&1
        fi
    fi
    
    # 执行Docker命令
    echo "正在启动容器 [$container_name]..."
    eval "$cmd"
}

# 逐行处理命令文件
while IFS= read -r line; do
    # 过滤注释和空行
    line=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -z "$line" ] && continue
    
    process_command "$line"
done < "$TEMP_FILE"

# 清理临时文件
rm -f "$TEMP_FILE"
echo "所有容器操作已完成！"
