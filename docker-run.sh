#!/bin/bash

# 设置下载链接（请替换为实际的docker.txt文件URL）
DOCKER_TXT_URL="https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/docker.txt"

# 下载docker.txt文件
echo "正在从github下载配置文件........."
curl -s -OJ "$DOCKER_TXT_URL"

if [ $? -ne 0 ]; then
    echo "下载失败，请检查URL或网络连接！"
    exit 1
fi

# 定义处理容器的函数
install_container() {
    local CMD="$1"
    local CONTAINER_NAME=$(echo "$CMD" | grep -oP '(?<=--name )[^ ]+')
    
    # 检查容器是否存在
    if docker ps -a -f "name=$CONTAINER_NAME" --format "{{.Names}}" | grep -wq "$CONTAINER_NAME"; then
        read -p "容器 [$CONTAINER_NAME] 已存在，是否删除并重新安装？(Y/n): " choice
        case "$choice" in
            [Yy]* )
                echo "正在删除容器: $CONTAINER_NAME"
                docker rm -f "$CONTAINER_NAME" &> /dev/null || true
                
                # 获取镜像名（假设是命令的最后一个参数）
                local IMAGE_NAME=$(echo "$CMD" | awk '{print $NF}')
                echo "正在删除镜像: $IMAGE_NAME"
                docker rmi -f "$IMAGE_NAME" &> /dev/null || true
                ;;
            * )
                echo "跳过安装 $CONTAINER_NAME"
                return 1
                ;;
        esac
    fi

    # 执行命令
    echo "正在部署容器: $CONTAINER_NAME"
    eval "$CMD"
    
    if [ $? -eq 0 ]; then
        echo "✅ $CONTAINER_NAME 安装成功！"
    else
        echo "❌ $CONTAINER_NAME 安装失败！"
    fi
}

# 读取并处理每个命令
echo "开始部署容器..."
while IFS= read -r line; do
    # 跳过空行和注释行
    if [[ -z "$line" || "$line" =~ ^\ *# ]]; then
        continue
    fi
    
    install_container "$line"
done < docker.txt

echo "所有容器部署完成！"
