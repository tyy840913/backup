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

# 检查系统是否已配置Docker镜像加速器
has_system_mirror() {
    if [ -f "/etc/docker/daemon.json" ] && grep -q "registry-mirrors" /etc/docker/daemon.json; then
        return 0 # 0表示true (有)
    fi
    if systemctl cat docker 2>/dev/null | grep -q "Environment=.*_PROXY="; then
        return 0 # 0表示true (有)
    fi
    return 1 # 1表示false (没有)
}

# 下载 docker-compose.yml 文件
download_compose_file() {
    echo "正在从 $MIRROR_URL 下载 docker-compose.yml..." >&2
    mkdir -p "$TARGET_DIR"
    if ! curl --noproxy '*' -sSL "$MIRROR_URL" -o "$TARGET_FILE"; then
        echo "❌ 文件下载失败！请检查网络连接和URL。" >&2
        exit 1
    fi
    if [ ! -s "$TARGET_FILE" ]; then
        echo "❌ 文件下载后为空或不存在。" >&2
        exit 1
    fi
}

# 替换镜像地址
process_images() {
    local temp_file
    temp_file=$(mktemp)
    cp "$TARGET_FILE" "$temp_file"

    echo "🚀 开始处理镜像地址..." >&2

    # 仅在系统未配置加速器时处理 docker.io
    if ! has_system_mirror; then
        echo "⚠️ 系统未配置Docker加速器或代理。" >&2
        # 检查是否存在需要替换的 docker.io 镜像
        if grep -q -E 'image: ([^/:]+:[^/]+)$|image: ([^/:]+)$|image: (([a-zA-Z0-9_-]+)/([a-zA-Z0-9_-]+))' "$temp_file"; then
            echo "   -> 正在为 docker.io 配置镜像加速..." >&2
            local mirror_host
            mirror_host=$(echo "https://docker.woskee.nyc.mn" | sed 's|https://||')
            sed -i -E "s#image: (([a-zA-Z0-9_-]+)/([a-zA-Z0-9_-]+))#image: ${mirror_host}/\1#g" "$temp_file"
            sed -i -E "s#image: ([^/:]+:[^/]+)$#image: ${mirror_host}/\1#g" "$temp_file"
            sed -i -E "s#image: ([^/:]+)$#image: ${mirror_host}/\1#g" "$temp_file"
        fi
    else
        echo "✅ 检测到系统已配置Docker镜像加速器，将跳过 docker.io" >&2
    fi

    # 始终处理其他第三方仓库
    for config in "${MIRROR_CONFIG[@]}"; do
        IFS='|' read -r registry mirror <<< "$config"
        if [ "$registry" == "docker.io" ]; then
            continue # docker.io 已在上面单独处理
        fi

        # 检查是否存在需要替换的镜像，如果存在则替换并打印日志
        if grep -q "image: ${registry}/" "$temp_file"; then
            echo "   -> 正在为 ${registry} 配置镜像加速..." >&2
            local mirror_host
            mirror_host=$(echo "$mirror" | sed 's|https://||')
            sed -i "s#image: ${registry}/#image: ${mirror_host}/#g" "$temp_file"
        fi
    done
    
    # 返回处理后的临时文件名
    echo "$temp_file"
}

# --- 主流程 ---
download_compose_file
PROCESSED_FILE=$(process_images)

echo "✅ 镜像地址处理完成。" >&2
echo "正在使用 $PROCESSED_FILE 启动容器服务..." >&2
cd "$TARGET_DIR" || { echo "❌ 无法进入目录 $TARGET_DIR"; exit 1; }

if ! env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY docker-compose -f "$PROCESSED_FILE" up -d; then
    echo "❌ docker-compose 执行失败！" >&2
    rm -f "$PROCESSED_FILE"
    exit 1
fi

rm -f "$PROCESSED_FILE"
echo "🎉 容器服务已成功启动！" >&2
