#!/bin/bash

# 配置参数
DOWNLOAD_URL="https://route.woskee.dpdns.org/raw.githubusercontent.com/tyy840913/backup/main/docker-compose.yml"
TARGET_DIR="/tmp/docker"
TARGET_FILE="$TARGET_DIR/docker-compose.yml"

# 创建目标目录（如果不存在）
mkdir -p "$TARGET_DIR"

# 下载文件
echo "正在从 $DOWNLOAD_URL 下载 docker-compose.yml..."
if ! curl -sSL "$DOWNLOAD_URL" -o "$TARGET_FILE"; then
    echo "❌ 文件下载失败！请检查："
    echo "1. URL是否正确 ($DOWNLOAD_URL)"
    echo "2. 网络连接是否正常"
    echo "3. 目标目录是否可写 ($TARGET_DIR)"
    exit 1
fi

# 验证文件
if [ ! -f "$TARGET_FILE" ]; then
    echo "❌ 文件下载后验证失败：$TARGET_FILE 不存在"
    exit 1
fi

# 执行docker-compose
echo "✅ 文件已保存到 $TARGET_FILE"
echo "正在启动容器服务..."
cd "$TARGET_DIR" || { echo "❌ 无法进入目录 $TARGET_DIR"; exit 1; }

if ! docker-compose -f "$TARGET_FILE" up -d; then
    echo "❌ docker-compose 执行失败！请检查："
    echo "1. Docker服务是否运行"
    echo "2. YAML文件格式是否正确"
    echo "3. 是否有足够的权限"
    exit 1
fi

echo "🎉 容器服务已成功启动！"
