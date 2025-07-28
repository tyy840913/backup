#!/bin/bash

# 设置目标URL和本地路径
COMPOSE_URL="https://raw.githubusercontent.com/tyy840913/backup/main/docker-compose.yml"
TARGET_DIR="/tmp"
TARGET_FILE="$TARGET_DIR/docker-compose.yml"

# 创建目标目录
echo "🛠️ 创建临时目录: $TARGET_DIR"
mkdir -p "$TARGET_DIR"

# 下载docker-compose文件
echo "⬇️ 正在从 $COMPOSE_URL 下载docker-compose.yml文件..."
if ! curl --fail --silent --show-error "$COMPOSE_URL" -o "$TARGET_FILE"; then
    echo "❌ 下载失败！请检查URL和网络连接"
    exit 1
fi

# 检查文件是否下载成功
if [ ! -f "$TARGET_FILE" ]; then
    echo "❌ 文件下载后不存在"
    exit 1
fi

if [ ! -s "$TARGET_FILE" ]; then
    echo "❌ 下载的文件为空"
    exit 1
fi

echo "✅ 文件下载成功，保存到: $TARGET_FILE"

# 运行docker-compose
echo "🚀 正在启动docker-compose服务..."
cd "$TARGET_DIR" || { echo "❌ 无法进入目录 $TARGET_DIR"; exit 1; }

docker-compose -f "$TARGET_FILE" up -d

if [ $? -eq 0 ]; then
    echo "🎉 容器服务已成功启动！"
else
    echo "❌ docker-compose执行失败"
    exit 1
fi
