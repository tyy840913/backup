#!/bin/bash

REMOTE_URL="https://git.luxxk.dpdns.org/raw.githubusercontent.com/tyy840913/backup/main/docker-compose.yml"
LOCAL_YML="/root/docker-compose.yml"

# 优先从远程下载，失败则试本地
echo "⬇️ 正在下载 docker-compose.yml..."
if curl --fail --silent --show-error "$REMOTE_URL" -o "$LOCAL_YML" && [ -s "$LOCAL_YML" ]; then
    echo "✅ 远程下载成功"
elif [ -f "$LOCAL_YML" ] && [ -s "$LOCAL_YML" ]; then
    echo "⚠️ 使用本地文件"
else
    echo "❌ 获取 docker-compose.yml 失败"
    exit 1
fi

echo "🚀 启动服务..."
cd /root && docker compose -f "$LOCAL_YML" up -d
[ $? -eq 0 ] && echo "🎉 已成功启动" || { echo "❌ 执行失败"; exit 1; }
