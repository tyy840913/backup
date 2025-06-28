#!/bin/bash

# 配置参数
DOWNLOAD_URL="https://add.woskee.dpdns.org/raw.githubusercontent.com/tyy840913/backup/main/docker-compose.yml"

# 创建临时文件在 /dev/shm (内存文件系统)
TEMP_FILE=$(mktemp /dev/shm/docker-compose-XXXXXX.yml)

# 确保脚本退出时删除临时文件
trap 'rm -f "$TEMP_FILE"' EXIT

# 下载文件
echo "正在下载 docker-compose.yml 到临时文件 $TEMP_FILE..."
if ! curl -sSL "$DOWNLOAD_URL" -o "$TEMP_FILE"; then
    echo "❌ 文件下载失败！"
    exit 1
fi

# 验证文件
if [ ! -f "$TEMP_FILE" ]; then
    echo "❌ 文件下载后验证失败：$TEMP_FILE 不存在"
    exit 1
fi

# 执行docker-compose
echo "✅ 文件已下载到 $TEMP_FILE"
echo "正在启动容器服务..."

if ! docker-compose -f "$TEMP_FILE" up -d; then
    echo "❌ docker-compose 执行失败！请检查Docker服务是否运行或YAML文件格式是否正确。"
    exit 1
fi

# 检查容器运行状态
echo "正在检查容器运行状态..."
# 获取所有容器的状态，并过滤出非运行状态的容器
FAILED_CONTAINERS=$(docker-compose -f "$TEMP_FILE" ps | awk 'NR>2 {if ($NF != "Up") print $1 " (" $NF ")"}')

if [ -z "$FAILED_CONTAINERS" ]; then
    echo "🎉 所有容器运行成功！"
else
    echo "⚠️ 部分容器启动失败或状态异常："
    echo "$FAILED_CONTAINERS"
    echo "请检查以上容器的状态。"
fi

# 临时文件会在脚本退出时自动删除。
