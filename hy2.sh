#!/bin/bash
# Hysteria2 一键安装脚本
# 功能：自动配置端口、生成证书、部署节点服务，并添加进程监控

# 通用设置
export LC_ALL=C
HOSTNAME=$(hostname)
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')  # 统一小写用户名

# 生成UUID（如果未预设）
export UUID=${UUID:-$(echo -n "$USERNAME+$HOSTNAME" | md5sum | head -c 32 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')}
export SUB_TOKEN=${SUB_TOKEN:-${UUID:0:8}}  # 订阅令牌

# 域名识别
if [[ "$HOSTNAME" =~ ct8 ]]; then
    CURRENT_DOMAIN="ct8.pl"
elif [[ "$HOSTNAME" =~ useruno ]]; then
    CURRENT_DOMAIN="useruno.com"
else
    CURRENT_DOMAIN="serv00.net"
fi

# 工作目录设置
WORKDIR="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}/logs"
FILE_PATH="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}/public_html"
rm -rf "$WORKDIR" "$FILE_PATH" && mkdir -p "$WORKDIR" "$FILE_PATH" && chmod 777 "$WORKDIR" "$FILE_PATH"

# 清理旧进程
bash -c 'ps aux | grep $(whoami) | grep -v "sshd\|bash\|grep" | awk "{print \$2}" | xargs -r kill -9 >/dev/null 2>&1'

# 下载工具检测
command -v curl &>/dev/null && COMMAND="curl -so" || command -v wget &>/dev/null && COMMAND="wget -qO" || {
    echo -e "\033[1;31m错误：需要 curl 或 wget 工具\033[0m"
    exit 1
}

# ================== 端口配置 ==================
check_port() {
    echo -e "\033[1;36m[1/5] 正在配置网络端口...\033[0m"
    local port_list=$(devil port list)
    local udp_ports=$(echo "$port_list" | grep -c "udp")

    # 如果没有可用UDP端口则创建
    if (( udp_ports < 1 )); then
        echo -e "\033[1;33m未找到可用UDP端口，正在创建...\033[0m"
        while :; do
            local udp_port=$(shuf -i 10000-65535 -n 1)
            if devil port add udp $udp_port | grep -q "Ok"; then
                export PORT=$udp_port
                echo -e "\033[1;32m已创建UDP端口：$udp_port\033[0m"
                devil binexec on >/dev/null  # 启用二进制执行权限
                break
            fi
        done
    else
        export PORT=$(echo "$port_list" | awk '/udp/ {print $1; exit}')
        echo -e "\033[1;32m使用现有UDP端口：$PORT\033[0m"
    fi
}
check_port

# ================== 架构检测 & 文件下载 ==================
ARCH=$(uname -m)
DOWNLOAD_DIR="."
echo -e "\033[1;36m[2/5] 下载程序文件...\033[0m"

# 根据架构选择下载源
if [[ "$ARCH" =~ arm|aarch64 ]]; then
    BINARY_URL="https://github.com/eooce/test/releases/download/freebsd-arm64/hy2"
else 
    BINARY_URL="https://github.com/eooce/test/releases/download/freebsd/hy2"
fi

# 下载固定文件名程序
$COMMAND "$DOWNLOAD_DIR/hysteria" "$BINARY_URL" || {
    echo -e "\033[1;31m文件下载失败！\033[0m"
    exit 1
}
chmod +x "$DOWNLOAD_DIR/hysteria"

# ================== 证书生成 ==================
echo -e "\033[1;36m[3/5] 生成TLS证书...\033[0m"
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout "$WORKDIR/server.key" \
    -out "$WORKDIR/server.crt" \
    -subj "/CN=${CURRENT_DOMAIN}" \
    -days 36500 || {
    echo -e "\033[1;31m证书生成失败！\033[0m"
    exit 1
}

# ================== 获取服务器IP ==================
get_ip() {
    echo -e "\033[1;36m[4/5] 获取服务器IP...\033[0m"
    local IP_LIST=($(devil vhost list | awk '/^[0-9]+/ {print $1}'))
    echo -e "\033[1;33m候选IP列表：${IP_LIST[@]}\033[0m"
    
    # 简单选择第一个可用IP（可根据需要添加检测逻辑）
    echo ${IP_LIST[0]}
}
HOST_IP=$(get_ip)
[[ -z "$HOST_IP" ]] && {
    echo -e "\033[1;31m无法获取有效IP地址！\033[0m"
    exit 1
}
echo -e "\033[1;32m使用IP地址：$HOST_IP\033[0m"

# ================== 生成配置文件 ==================
echo -e "\033[1;36m[5/5] 生成配置文件...\033[0m"
cat > config.yaml <<EOF
listen: $HOST_IP:$PORT
tls:
  cert: "$WORKDIR/server.crt"
  key: "$WORKDIR/server.key"
auth:
  type: password
  password: "$UUID"
masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
# 性能优化参数
fastOpen: true
transport:
  udp:
    hopInterval: 30s
EOF

# ================== 启动服务 ==================
echo -e "\033[1;36m启动Hysteria服务...\033[0m"
nohup ./hysteria server config.yaml > "$WORKDIR/hysteria.log" 2>&1 &
sleep 2  # 等待进程启动

# 检查启动状态
if ! pgrep -x "hysteria" >/dev/null; then
    echo -e "\033[1;31m服务启动失败！查看日志：$WORKDIR/hysteria.log\033[0m"
    exit 1
fi

# ================== 进程监控 ==================
(
    echo -e "\033[1;36m启用进程监控...\033[0m"
    while true; do
        if ! pgrep -x "hysteria" >/dev/null; then
            # 记录重启时间
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 进程异常停止，尝试重启..." >> "$WORKDIR/monitor.log"
            
            # 首次重启尝试
            nohup ./hysteria server config.yaml >> "$WORKDIR/hysteria.log" 2>&1 &
            sleep 10
            
            # 检查重启状态
            if ! pgrep -x "hysteria" >/dev/null; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] 重启失败，尝试重新安装..." >> "$WORKDIR/monitor.log"
                
                # 重新下载二进制文件
                $COMMAND "hysteria" "$BINARY_URL" && chmod +x hysteria
                nohup ./hysteria server config.yaml >> "$WORKDIR/hysteria.log" 2>&1 &
            fi
        fi
        sleep 60  # 每分钟检查一次
    done
) >/dev/null 2>&1 &

# ================== 生成配置信息 ==================
# 获取地理位置信息
ISP=$(curl -s --max-time 2 https://speed.cloudflare.com/meta | awk -F\" '{print $26}' | sed 's/ /_/g' || echo "未知")
SERVER_NAME=$(echo "$HOSTNAME" | cut -d '.' -f 1)
NODE_NAME="${SERVER_NAME}-hysteria2-${USERNAME}"

# 生成节点配置
echo -e "\n\033[1;35m============== 节点配置 ==============\033[0m"
CONFIG_URI="hysteria2://$UUID@$HOST_IP:$PORT/?sni=www.bing.com&insecure=1#${ISP}-${NODE_NAME}"
echo -e "\033[1;32mURI 配置：\033[0m$CONFIG_URI"

# 生成订阅文件
SUB_FILE="${FILE_PATH}/${SUB_TOKEN}_hy2.log"
echo "$CONFIG_URI" > "$SUB_FILE"
echo -e "\033[1;32m订阅链接：\033[0mhttps://${USERNAME}.${CURRENT_DOMAIN}/${SUB_TOKEN}_hy2.log"

# 显示二维码
QR_URL="https://00.ssss.nyc.mn/qrencode"
if $COMMAND "/tmp/qrencode" "$QR_URL"; then
    chmod +x "/tmp/qrencode"
    echo -e "\n\033[1;36m配置二维码：\033[0m"
    "/tmp/qrencode" -m 2 -t UTF8 "$CONFIG_URI"
else
    echo -e "\033[1;33m无法生成二维码\033[0m"
fi

echo -e "\n\033[1;32m安装完成！服务日志：$WORKDIR/hysteria.log\033[0m"
