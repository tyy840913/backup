#!/bin/bash

# 配置下载 URL
DOWNLOAD_URL="https://add.woskee.dpdns.org/raw.githubusercontent.com/tyy840913/backup/main/docker-compose.yml"

# 在 /dev/shm (内存文件系统) 中创建临时文件
TEMP_FILE=$(mktemp /dev/shm/docker-compose-XXXXXX.yml)

# 确保脚本退出时删除临时文件
trap 'rm -f "$TEMP_FILE"' EXIT

# 下载 docker-compose.yml 文件
echo "正在下载 docker-compose.yml 到 $TEMP_FILE..."
if ! curl -sSL "$DOWNLOAD_URL" -o "$TEMP_FILE"; then
    echo "❌ 文件下载失败！请检查 URL 或网络连接。"
    exit 1
fi

# 验证文件是否存在
if [ ! -f "$TEMP_FILE" ]; then
    echo "❌ 文件下载后验证失败：$TEMP_FILE 不存在。"
    exit 1
fi

# 启动容器服务
echo "✅ 文件已下载。"
echo "正在启动容器服务..."
if ! docker-compose -f "$TEMP_FILE" up -d; then
    echo "❌ docker-compose 执行失败！请检查 Docker 服务或 YAML 文件。"
    exit 1
fi

echo "🎉 容器服务启动命令已成功执行！"
