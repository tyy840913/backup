#!/bin/bash

# 原始GitHub URL和镜像URL
GITHUB_RAW_URL="https://raw.githubusercontent.com/tyy840913/backup/main/docker-compose.yml"
MIRROR_URL="https://route.woskee.dpdns.org/raw.githubusercontent.com/tyy840913/backup/main/docker-compose.yml"

# 目标目录和文件
TARGET_DIR="/tmp/docker"
TARGET_FILE="$TARGET_DIR/docker-compose.yml"

# 多仓库镜像加速源配置
MIRROR_CONFIG=(
    "docker.io|https://docker.woskee.nyc.mn"
    "ghcr.io|https://ghcr.nju.edu.cn"
    "k8s.gcr.io|https://registry.aliyuncs.com/google_containers"
    "quay.io|https://quay.mirror.aliyuncs.com"
    "gcr.io|https://gcr.mirror.aliyuncs.com"
    "mcr.microsoft.com|https://dockerhub.azk8s.cn"
)

# 检查系统是否已配置Docker镜像加速器或代理
check_system_config() {
    # 检查 /etc/docker/daemon.json 是否配置了 registry-mirrors
    if [ -f "/etc/docker/daemon.json" ] && grep -q "registry-mirrors" /etc/docker/daemon.json; then
        echo "✅ 检测到系统已配置Docker镜像加速器"
        return 0
    fi
    # 检查Docker服务的systemd配置中是否包含代理设置
    if systemctl cat docker 2>/dev/null | grep -q "Environment=.*_PROXY="; then
        echo "✅ 检测到Docker服务已配置代理"
        return 0
    fi
    return 1
}

# 始终使用镜像URL下载
DOWNLOAD_URL="$MIRROR_URL"

# 创建目标目录
mkdir -p "$TARGET_DIR"

# 使用curl下载文件，并禁用代理
echo "正在从 $DOWNLOAD_URL 下载 docker-compose.yml..."
if ! curl --noproxy '*' -sSL "$DOWNLOAD_URL" -o "$TARGET_FILE"; then
    echo "❌ 文件下载失败！请检查网络连接和URL。"
    exit 1
fi

# 验证文件是否下载成功
if [ ! -s "$TARGET_FILE" ]; then
    echo "❌ 文件下载后为空或不存在。"
    exit 1
fi

# 仅在系统未配置加速器或代理时，才进行镜像地址替换
if ! check_system_config; then
    echo "⚠️ 系统未配置Docker加速器或代理，将使用脚本内置加速源替换镜像地址..."
    
    TEMP_FILE=$(mktemp)
    cp "$TARGET_FILE" "$TEMP_FILE"

    # 遍历加速器配置进行替换
    for config in "${MIRROR_CONFIG[@]}"; do
        IFS='|' read -r registry mirror <<< "$config"
        mirror_host=$(echo "$mirror" | sed 's|https://||')

        # 替换带仓库前缀的镜像，例如 "image: ghcr.io/user/repo"
        sed -i "s|image: ${registry}/|image: ${mirror_host}/|g" "$TEMP_FILE"
        
        # 特别处理docker.io官方镜像（通常不带仓库前缀）
        if [ "$registry" == "docker.io" ]; then
            # 匹配 "image: <image_name>:<tag>" 或 "image: <image_name>"
            # 正则表达式确保只匹配不包含'/'的镜像名，避免错误替换
            sed -i -E "s|image: ([^/:]+):|image: ${mirror_host}/\1:|g" "$TEMP_FILE"
            sed -i -E "s|image: ([^/:]+)$|image: ${mirror_host}/\1|g" "$TEMP_FILE"
        fi
    done
    
    # 将处理后的临时文件作为最终的Compose文件
    TARGET_FILE="$TEMP_FILE"
    echo "✅ 镜像地址替换完成。"
else
    echo "ℹ️ 跳过镜像地址替换，将使用系统配置。"
fi

# 执行docker-compose
echo "正在使用 $TARGET_FILE 启动容器服务..."
cd "$TARGET_DIR" || { echo "❌ 无法进入目录 $TARGET_DIR"; exit 1; }

# 执行docker-compose时，取消所有代理环境变量
if ! env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY docker-compose -f "$TARGET_FILE" up -d; then
    echo "❌ docker-compose 执行失败！"
    # 如果使用了临时文件，则在失败后清理
    [ -n "$TEMP_FILE" ] && rm -f "$TEMP_FILE"
    exit 1
fi

# 清理临时文件
[ -n "$TEMP_FILE" ] && rm -f "$TEMP_FILE"

echo "🎉 容器服务已成功启动！"
