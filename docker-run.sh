#!/bin/bash

# 定义变量
URL="https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/docker.txt"
DEST_DIR="/data/docker"
DEST_FILE="$DEST_DIR/docker-compose.yml"

# 创建目标目录（如果不存在）
mkdir -p "$DEST_DIR"

# 下载文件
echo "正在下载 docker-compose.yml 文件..."
curl -o "$DEST_FILE" "$URL"

# 检查文件是否下载成功
if [ -f "$DEST_FILE" ]; then
    echo "文件下载成功，保存到 $DEST_FILE"
else
    echo "文件下载失败，请检查链接和网络连接。"
    exit 1
fi

# 运行 docker-compose
echo "正在运行 docker-compose.yml 文件..."
cd "$DEST_DIR"
docker-compose up -d

echo "docker-compose 运行完成。"
