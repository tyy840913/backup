#!/bin/bash

# 原始GitHub URL和镜像URL
GITHUB_RAW_URL="https://raw.githubusercontent.com/tyy840913/backup/main/docker-compose.yml"
MIRROR_URL="https://route.woskee.dpdns.org/raw.githubusercontent.com/tyy840913/backup/main/docker-compose.yml"

# 目标目录和文件
TARGET_DIR="/tmp/docker"
TARGET_FILE="$TARGET_DIR/docker-compose.yml"

# 多仓库镜像加速源配置（仅在系统未配置加速器或代理时使用）
MIRROR_CONFIG=(
    # docker.io 镜像加速源
    "docker.io|docker.woskee.nyc.mn"
    "docker.io|hdocker.luxxk.dpdns.org"
    "docker.io|docker.woskee.dpdns.org"
    "docker.io|docker.wosken.dpdns.org"
    
    # ghcr.io 镜像加速源
    "ghcr.io|ghcr.nju.edu.cn"
    "ghcr.io|ghcr.linkos.org"
    
    # k8s.gcr.io 镜像加速源
    "k8s.gcr.io|registry.aliyuncs.com/google_containers"
    
    # quay.io 镜像加速源
    "quay.io|quay.mirror.aliyuncs.com"
    
    # gcr.io 镜像加速源
    "gcr.io|gcr.mirror.aliyuncs.com"
    
    # mcr.microsoft.com 镜像加速源
    "mcr.microsoft.com|dockerhub.azk8s.cn"
)

# 检查终端是否配置了代理
check_terminal_proxy() {
    if [ -n "$http_proxy" ] || [ -n "$https_proxy" ] || 
       [ -n "$HTTP_PROXY" ] || [ -n "$HTTPS_PROXY" ]; then
        echo "✅ 检测到终端已配置代理，将使用原始GitHub URL"
        DOWNLOAD_URL="$GITHUB_RAW_URL"
        return 0
    else
        echo "⚠️ 未检测到终端代理配置，将使用镜像URL加速下载"
        DOWNLOAD_URL="$MIRROR_URL"
        return 1
    fi
}

# 检查系统是否已配置Docker镜像加速器或代理
check_system_config() {
    local has_config=1
    
    # 检查镜像加速器配置
    if [ -f "/etc/docker/daemon.json" ]; then
        if grep -q "registry-mirrors" /etc/docker/daemon.json; then
            echo "✅ 检测到系统已配置Docker镜像加速器"
            has_config=0
        fi
    fi
    
    # 检查Docker服务代理配置
    if systemctl cat docker | grep -q "Environment=.*_PROXY="; then
        echo "✅ 检测到Docker服务已配置代理"
        has_config=0
    fi
    
    return $has_config
}

# 设置下载URL
check_terminal_proxy

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

# 处理镜像加速（仅在系统未配置加速器或代理时执行）
if ! check_system_config; then
    echo "⚠️ 系统未配置Docker镜像加速器或代理，将使用脚本内置加速源"
    
    TEMP_FILE=$(mktemp)
    cp "$TARGET_FILE" "$TEMP_FILE"
    
    # 处理所有配置的镜像仓库
    for config in "${MIRROR_CONFIG[@]}"; do
        IFS='|' read -r registry mirror <<< "$config"
        
        # 处理带仓库前缀的镜像
        sed -i "s|image: ${registry}/|image: ${mirror#https://}/|g" "$TEMP_FILE"
        
        # 处理docker.io官方镜像(无前缀)
        if [ "$registry" == "docker.io" ]; then
            sed -i "s|image: $$[^/]*$$:$$[^ ]*$$$|image: ${mirror#https://}/\1:\2|g" "$TEMP_FILE"
            sed -i "s|image: $$[^/]*$$$|image: ${mirror#https://}/\1|g" "$TEMP_FILE"
        fi
        
        # 检查是否替换成功
        if grep -q "image: ${mirror#https://}/" "$TEMP_FILE"; then
            echo "✅ ${registry} 镜像加速成功: ${mirror}"
        fi
    done
    
    TARGET_FILE="$TEMP_FILE"
else
    echo "ℹ️ 跳过镜像加速处理，使用系统配置的镜像加速器或代理"
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
    [ -n "$TEMP_FILE" ] && rm -f "$TEMP_FILE"
    exit 1
fi

# 清理临时文件
[ -n "$TEMP_FILE" ] && rm -f "$TEMP_FILE"

echo "🎉 容器服务已成功启动！"
