#!/bin/bash

# --- 脚本配置 ---
# 模板配置文件（前半部分）
BASE_CONFIG="/etc/mihomo/mihomo_config.yaml"
# 如果模板不存在，从这个 URL 下载
TEMPLATE_URL="https://cdn.luxxk.dpdns.org/raw.githubusercontent.com/tyy840913/backup/refs/heads/main/mihomo_config.yaml"
# 最终生成的完整配置文件
FINAL_CONFIG="/etc/mihomo/config.yaml"
# 用于获取订阅配置的 URL 地址（后半部分）
REMOTE_CONFIG_URL="http://192.168.1.254:8199/sub/mihomo.yaml"
# --- 配置结束 ---

# 如果任何命令执行失败，立即退出脚本
set -e

# 切换到脚本所在目录，确保路径正确
cd "$(dirname "$0")"

echo "INFO: 开始更新配置文件..."

# 检查模板配置文件是否存在，如果不存在则从指定 URL 下载
if [ ! -f "$BASE_CONFIG" ]; then
    echo "INFO: 模板配置文件 '$BASE_CONFIG' 不存在，正在从 URL 下载..."
    # 使用 curl 下载模板文件
    # -L: 跟随重定向 (对 github raw 链接很重要)
    # -sS: 安静模式但显示错误
    # --fail: 如果服务器返回错误则失败退出
    # -o: 指定输出文件
    if curl -L -sS --fail -o "$BASE_CONFIG" "$TEMPLATE_URL"; then
        echo "INFO: 模板配置文件已成功下载。"
    else
        echo "错误: 无法从 '$TEMPLATE_URL' 下载模板配置文件。请检查网络或链接是否正确。"
        exit 1
    fi
fi

echo "INFO: 正在从 '$BASE_CONFIG' 创建基础配置..."
# 将基础配置文件内容写入最终的配置文件（如果不存在则创建，如果存在则覆盖）
cat "$BASE_CONFIG" > "$FINAL_CONFIG"

# 为了确保拼接正确，在两个文件之间添加一个换行符
echo "" >> "$FINAL_CONFIG"

echo "INFO: 正在从 '$REMOTE_CONFIG_URL' 获取远程订阅并追加..."
# 下载远程订阅并追加到最终的配置文件末尾
if curl -sS --fail "$REMOTE_CONFIG_URL" >> "$FINAL_CONFIG"; then
    echo "INFO: 远程订阅已成功追加。"
else
    echo "错误: 从 '$REMOTE_CONFIG_URL' 下载订阅失败。"
    # 如果下载失败，脚本将因 set -e 而退出
    exit 1
fi

echo "成功: 配置文件 '$FINAL_CONFIG' 已成功生成。"

# 检查并重启 mihomo 服务
if command -v docker &> /dev/null && docker ps -a --format '{{.Names}}' | grep -q "^mihomo$"; then
    echo "INFO: 正在重启 mihomo Docker 容器..."
    docker restart mihomo
    echo "INFO: mihomo 容器已重启。"
else
    echo "INFO: 未检测到名为 mihomo 的 Docker 容器，跳过重启步骤。"
fi

exit 0
