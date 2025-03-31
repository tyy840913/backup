#!/bin/bash
# 设置环境变量和系统配置
export LC_ALL=C  # 确保脚本使用C语言环境，避免本地化问题

# 文件路径定义（当前目录）
INSTALL_CMD_FILE="./hysteria2_install_cmd.txt"
LOG_DIR="./logs"
LOG_FILE="$LOG_DIR/hysteria2_monitor.log"
MAX_LOG_ENTRIES=100
mkdir -p "$LOG_DIR"

# 工作目录设置（当前目录）
WORKDIR="./workdir"
FILE_PATH="./public"
mkdir -p "$WORKDIR" "$FILE_PATH"
chmod 777 "$WORKDIR" "$FILE_PATH"

# 二进制文件路径（固定名称）
DOWNLOAD_DIR="."
HY2_BINARY="$DOWNLOAD_DIR/hy2"

# 日志记录函数（仅用于重要事件）
log_event() {
    # 保持日志文件不超过100条记录
    [ -f "$LOG_FILE" ] && tail -n $((MAX_LOG_ENTRIES-1)) "$LOG_FILE" > "${LOG_FILE}.tmp"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "${LOG_FILE}.tmp"
    mv "${LOG_FILE}.tmp" "$LOG_FILE" 2>/dev/null
}

# 获取系统信息
HOSTNAME=$(hostname)
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')

# 生成UUID
export UUID=${UUID:-$(echo -n "$USERNAME+$HOSTNAME" | md5sum | head -c 32 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')}
export SUB_TOKEN=${SUB_TOKEN:-${UUID:0:8}}

# 域名判断
if [[ "$HOSTNAME" =~ ct8 ]]; then
    CURRENT_DOMAIN="ct8.pl"
elif [[ "$HOSTNAME" =~ useruno ]]; then
    CURRENT_DOMAIN="useruno.com"
else
    CURRENT_DOMAIN="serv00.net"
fi

# 清理并创建工作目录
echo -e "\e[1;33m[信息] 正在清理并创建工作目录...\e[0m"
rm -rf "$WORKDIR" "$FILE_PATH" && mkdir -p "$WORKDIR" "$FILE_PATH" && chmod 777 "$WORKDIR" "$FILE_PATH" >/dev/null 2>&1

echo -e "\e[1;33m[信息] 正在清理现有进程...\e[0m"
bash -c 'ps aux | grep $(whoami) | grep -v "sshd\|bash\|grep" | awk "{print \$2}" | xargs -r kill -9 >/dev/null 2>&1' >/dev/null 2>&1

# 检查下载工具
command -v curl &>/dev/null && COMMAND="curl -so" || command -v wget &>/dev/null && COMMAND="wget -qO" || { 
    echo -e "\e[1;31m[错误] 未找到curl或wget，请安装其中一个工具\e[0m"
    exit 1
}

# 端口检查函数
check_port() {
    echo -e "\e[1;33m[信息] 正在检查可用端口...\e[0m"
    port_list=$(devil port list)
    udp_ports=$(echo "$port_list" | grep -c "udp")

    if [[ $udp_ports -lt 1 ]]; then
        echo -e "\e[1;33m[警告] 没有可用的UDP端口，正在尝试添加...\e[0m"
        while true; do
            udp_port=$(shuf -i 10000-65535 -n 1)
            result=$(devil port add udp $udp_port 2>&1)
            if [[ $result == *"Ok"* ]]; then
                echo -e "\e[1;32m[成功] 已添加UDP端口: $udp_port\e[0m"
                udp_port1=$udp_port
                break
            else
                echo -e "\e[1;33m[信息] 端口 $udp_port 不可用，尝试其他端口...\e[0m"
            fi
        done
        echo -e "\e[1;32m[成功] 端口调整完成\e[0m"
        devil binexec on >/dev/null 2>&1
        kill -9 $(ps -o ppid= -p $$) >/dev/null 2>&1
    else
        udp_ports=$(echo "$port_list" | awk '/udp/ {print $1}')
        udp_port1=$(echo "$udp_ports" | sed -n '1p')
    fi

    export PORT=$udp_port1
    echo -e "\e[1;32m[信息] Hysteria2将使用UDP端口: $udp_port1\e[0m"
}
check_port

# 系统架构判断
ARCH=$(uname -m) && mkdir -p "$DOWNLOAD_DIR"
if [ "$ARCH" == "arm" ] || [ "$ARCH" == "arm64" ] || [ "$ARCH" == "aarch64" ]; then
    BASE_URL="https://github.com/eooce/test/releases/download/freebsd-arm64"
    echo -e "\e[1;33m[信息] 检测到ARM架构系统\e[0m"
elif [ "$ARCH" == "amd64" ] || [ "$ARCH" == "x86_64" ] || [ "$ARCH" == "x86" ]; then
    BASE_URL="https://github.com/eooce/test/releases/download/freebsd"
    echo -e "\e[1;33m[信息] 检测到x86架构系统\e[0m"
else
    echo -e "\e[1;31m[错误] 不支持的架构: $ARCH\e[0m"
    exit 1
fi

# 下载二进制文件（固定文件名hy2）
echo -e "\e[1;33m[信息] 正在下载Hysteria2二进制文件...\e[0m"
HY2_URL="$BASE_URL/hy2"
$COMMAND "$HY2_BINARY" "$HY2_URL" && chmod +x "$HY2_BINARY"

# 生成证书
echo -e "\e[1;33m[信息] 正在生成自签名证书...\e[0m"
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout "$WORKDIR/server.key" \
    -out "$WORKDIR/server.crt" \
    -subj "/CN=${CURRENT_DOMAIN}" \
    -days 36500

# 获取IP函数
get_ip() {
    IP_LIST=($(devil vhost list | awk '/^[0-9]+/ {print $1}'))
    API_URL="https://status.eooce.com/api"
    
    THIRD_IP=${IP_LIST[2]}
    RESPONSE=$(curl -s --max-time 2 "${API_URL}/${THIRD_IP}")
    if [[ $(echo "$RESPONSE" | jq -r '.status') == "Available" ]]; then
        echo "$THIRD_IP"
        return
    fi
    
    FIRST_IP=${IP_LIST[0]}
    RESPONSE=$(curl -s --max-time 2 "${API_URL}/${FIRST_IP}")
    if [[ $(echo "$RESPONSE" | jq -r '.status') == "Available" ]]; then
        echo "$FIRST_IP"
        return
    fi
    
    echo ${IP_LIST[1]}
}

echo -e "\e[1;33m[信息] 正在获取可用IP地址...\e[0m"
HOST_IP=$(get_ip)
echo -e "\e[1;32m[信息] 已选择IP地址: $HOST_IP\e[0m"

# 配置文件
echo -e "\e[1;33m[信息] 正在创建Hysteria2配置文件...\e[0m"
cat << EOF > config.yaml
listen: $HOST_IP:$PORT
tls:
  cert: "$WORKDIR/server.crt"
  key: "$WORKDIR/server.key"
auth:
  type: password
  password: "$UUID"
fastOpen: true
masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
transport:
  udp:
    hopInterval: 30s
EOF

# 启动服务函数
start_service() {
    echo -e "\e[1;33m[信息] 正在启动Hysteria2服务...\e[0m"
    nohup ./"$HY2_BINARY" server config.yaml >/dev/null 2>&1 &
    sleep 1
    
    if pgrep -x "$(basename "$HY2_BINARY")" > /dev/null; then
        echo -e "\e[1;32m[成功] Hysteria2服务已启动\e[0m"
        return 0
    else
        echo -e "\e[1;31m[错误] 无法启动Hysteria2服务\e[0m"
        return 1
    fi
}

# 监控服务函数
monitor_service() {
    # 保存安装命令
    echo "$(realpath $0)" > "$INSTALL_CMD_FILE"
    chmod 600 "$INSTALL_CMD_FILE"
    
    while true; do
        if ! pgrep -x "$(basename "$HY2_BINARY")" > /dev/null; then
            log_event "服务停止，尝试重启"
            echo -e "\e[1;33m[警告] Hysteria2服务未运行，正在尝试重启...\e[0m"
            pkill -f "$(basename "$HY2_BINARY")"
            
            for i in {1..3}; do
                if start_service; then
                    log_event "服务重启成功"
                    echo -e "\e[1;32m[成功] Hysteria2服务重启成功\e[0m"
                    break
                elif [ $i -eq 3 ]; then
                    log_event "重启失败，尝试重新安装"
                    echo -e "\e[1;31m[错误] 重启失败，尝试重新安装...\e[0m"
                    
                    if [ -f "$INSTALL_CMD_FILE" ]; then
                        bash "$(cat "$INSTALL_CMD_FILE")"
                    else
                        echo "$(realpath $0)" > "$INSTALL_CMD_FILE"
                        chmod 600 "$INSTALL_CMD_FILE"
                        bash "$(realpath $0)"
                    fi
                    exit 1
                fi
                sleep 5
            done
        fi
        sleep 60
    done
}

# 启动服务
start_service

# 显示节点信息
ISP=$(curl -s --max-time 2 https://speed.cloudflare.com/meta | awk -F\" '{print $26}' | sed -e 's/ /_/g' || echo "未知")
NAME="$(echo "$HOSTNAME" | cut -d '.' -f 1)-hysteria2-${USERNAME}"

echo -e "\n\e[1;32m[成功] Hysteria2安装成功\e[0m\n"
echo -e "\e[1;33m[提示] 在V2rayN或Nekobox中，需要将跳过证书验证设置为true\e[0m\n"

# 创建订阅文件
echo -e "\e[1;33m[信息] 正在生成订阅文件...\e[0m"
cat > ${FILE_PATH}/${SUB_TOKEN}_hy2.log <<EOF
hysteria2://$UUID@$HOST_IP:$PORT/?sni=www.bing.com&alpn=h3&insecure=1#$ISP-$NAME
EOF


# 显示配置信息
echo -e "\e[1;32m[信息] Hysteria2节点配置:\e[0m"
cat ${FILE_PATH}/${SUB_TOKEN}_hy2.log
echo -e "\n\e[1;32m[信息] Clash配置文件:\e[0m"
cat << EOF
- name: $ISP-$NAME
  type: hysteria2
  server: $HOST_IP
  port: $PORT
  password: $UUID
  alpn:
    - h3
  sni: www.bing.com
  skip-cert-verify: true
  fast-open: true
EOF

# 启动监控进程（后台运行）
echo -e "\n\e[1;33m[信息] 监控进程将在后台运行\e[0m"
nohup bash -c 'monitor_service' >/dev/null 2>&1 &
disown

exit 0
