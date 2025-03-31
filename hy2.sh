#!/bin/bash
# 设置环境变量，确保脚本在不同语言环境下运行一致
export LC_ALL=C

# 获取主机名和用户名（用户名转换为小写）
HOSTNAME=$(hostname)
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')

# 生成UUID，基于用户名和主机名的MD5哈希
export UUID=${UUID:-$(echo -n "$USERNAME+$HOSTNAME" | md5sum | head -c 32 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')}

# 定义工作目录和文件路径
if [[ "$HOSTNAME" =~ ct8 ]]; then
    CURRENT_DOMAIN="ct8.pl"
elif [[ "$HOSTNAME" =~ useruno ]]; then
    CURRENT_DOMAIN="useruno.com"
else
    CURRENT_DOMAIN="serv00.net"
fi

WORKDIR="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}/logs"
FILE_PATH="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}/public_html"

# 清理并创建必要目录
rm -rf "$WORKDIR" "$FILE_PATH" && mkdir -p "$WORKDIR" "$FILE_PATH" && chmod 777 "$WORKDIR" "$FILE_PATH" >/dev/null 2>&1

# 杀死当前用户的所有非关键进程
bash -c 'ps aux | grep $(whoami) | grep -v "sshd\|bash\|grep" | awk "{print \$2}" | xargs -r kill -9 >/dev/null 2>&1' >/dev/null 2>&1

# 检查并设置下载工具（curl或wget）
command -v curl &>/dev/null && COMMAND="curl -so" || command -v wget &>/dev/null && COMMAND="wget -qO" || { 
    echo "Error: neither curl nor wget found, please install one of them." >&2
    exit 1 
}

# 检查并配置端口
check_port () {
    echo -e "\e[1;35m正在安装中,请稍等...\e[0m"
    port_list=$(devil port list)
    tcp_ports=$(echo "$port_list" | grep -c "tcp")
    udp_ports=$(echo "$port_list" | grep -c "udp")

    # 如果没有可用的UDP端口，则调整
    if [[ $udp_ports -lt 1 ]]; then
        echo -e "\e[1;91m没有可用的UDP端口,正在调整...\e[0m"

        # 如果有3个以上TCP端口，删除一个
        if [[ $tcp_ports -ge 3 ]]; then
            tcp_port_to_delete=$(echo "$port_list" | awk '/tcp/ {print $1}' | head -n 1)
            devil port del tcp $tcp_port_to_delete
            echo -e "\e[1;32m已删除TCP端口: $tcp_port_to_delete\e[0m"
        fi

        # 随机添加一个UDP端口
        while true; do
            udp_port=$(shuf -i 10000-65535 -n 1)
            result=$(devil port add udp $udp_port 2>&1)
            if [[ $result == *"Ok"* ]]; then
                echo -e "\e[1;32m已添加UDP端口: $udp_port"
                udp_port1=$udp_port
                break
            else
                echo -e "\e[1;33m端口 $udp_port 不可用，尝试其他端口...\e[0m"
            fi
        done

        echo -e "\e[1;32m端口已调整完成,如安装完后节点不通,访问 /restart域名重启\e[0m"
        devil binexec on >/dev/null 2>&1
        kill -9 $(ps -o ppid= -p $$) >/dev/null 2>&1
    else
        udp_ports=$(echo "$port_list" | awk '/udp/ {print $1}')
        udp_port1=$(echo "$udp_ports" | sed -n '1p')
    fi

    export PORT=$udp_port1
    echo -e "\e[1;35mhysteria2使用udp端口: $udp_port1\e[0m"
}
check_port

# 根据系统架构设置下载URL
ARCH=$(uname -m)
DOWNLOAD_DIR="."
mkdir -p "$DOWNLOAD_DIR"

if [ "$ARCH" == "arm" ] || [ "$ARCH" == "arm64" ] || [ "$ARCH" == "aarch64" ]; then
    BASE_URL="https://github.com/eooce/test/releases/download/freebsd-arm64"
elif [ "$ARCH" == "amd64" ] || [ "$ARCH" == "x86_64" ] || [ "$ARCH" == "x86" ]; then
    BASE_URL="https://github.com/eooce/test/releases/download/freebsd"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

# 定义要下载的文件（使用固定文件名）
FILES=(
    "$BASE_URL/hy2:hysteria2"  # hysteria2二进制文件
    "$BASE_URL/monitor:monitor" # 监控进程二进制文件
)

# 下载文件函数
download_files() {
    for file in "${FILES[@]}"; do
        url=$(echo "$file" | cut -d ':' -f 1)
        filename=$(echo "$file" | cut -d ':' -f 2)
        
        echo -e "\e[1;32m下载 $filename...\e[0m"
        $COMMAND "$DOWNLOAD_DIR/$filename" "$url"
        chmod +x "$DOWNLOAD_DIR/$filename"
    done
}
download_files

# 生成自签名证书
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout "$WORKDIR/server.key" -out "$WORKDIR/server.crt" -subj "/CN=${CURRENT_DOMAIN}" -days 36500

# 获取可用IP地址函数
get_ip() {
    IP_LIST=($(devil vhost list | awk '/^[0-9]+/ {print $1}'))
    API_URL="https://status.eooce.com/api"
    IP=""
    THIRD_IP=${IP_LIST[2]}
    
    RESPONSE=$(curl -s --max-time 2 "${API_URL}/${THIRD_IP}")
    if [[ $(echo "$RESPONSE" | jq -r '.status') == "Available" ]]; then
        IP=$THIRD_IP
    else
        FIRST_IP=${IP_LIST[0]}
        RESPONSE=$(curl -s --max-time 2 "${API_URL}/${FIRST_IP}")
        
        if [[ $(echo "$RESPONSE" | jq -r '.status') == "Available" ]]; then
            IP=$FIRST_IP
        else
            IP=${IP_LIST[1]}
        fi
    fi
    echo "$IP"
}

echo -e "\e[1;32m获取可用IP中,请稍等...\e[0m"
HOST_IP=$(get_ip)
echo -e "\e[1;35m当前选择IP为: $HOST_IP 如安装完后节点不通可尝试重新安装\e[0m"

# 创建hysteria2配置文件
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

# 创建监控进程配置文件
cat << EOF > monitor_config.json
{
    "processes": [
        {
            "name": "hysteria2",
            "command": "./hysteria2 server config.yaml",
            "args": [],
            "max_restarts": 5,
            "restart_delay": 10,
            "log_file": "$WORKDIR/hysteria2.log"
        }
    ],
    "self_monitoring": {
        "enabled": true,
        "check_interval": 60,
        "max_restarts": 3,
        "restart_delay": 30
    }
}
EOF

# 启动服务函数
start_services() {
    # 启动hysteria2
    nohup ./hysteria2 server config.yaml > "$WORKDIR/hysteria2.log" 2>&1 &
    sleep 1
    if pgrep -x "hysteria2" > /dev/null; then
        echo -e "\e[1;32mhysteria2 启动成功\e[0m"
    else
        echo -e "\e[1;31mhysteria2 启动失败\e[0m"
        return 1
    fi

    # 启动监控进程
    nohup ./monitor -c monitor_config.json > "$WORKDIR/monitor.log" 2>&1 &
    sleep 1
    if pgrep -x "monitor" > /dev/null; then
        echo -e "\e[1;32m监控进程 启动成功\e[0m"
    else
        echo -e "\e[1;31m监控进程 启动失败\e[0m"
        return 1
    fi

    return 0
}
start_services

# 生成服务器名称
get_name() { 
    if [ "$HOSTNAME" = "s1.ct8.pl" ]; then 
        SERVER="CT8"; 
    else 
        SERVER=$(echo "$HOSTNAME" | cut -d '.' -f 1); 
    fi; 
    echo "$SERVER"; 
}
NAME="$(get_name)-hysteria2-${USERNAME}"

# 获取ISP信息
ISP=$(curl -s --max-time 2 https://speed.cloudflare.com/meta | awk -F\" '{print $26}' | sed -e 's/ /_/g' || echo "0")

# 输出配置信息
echo -e "\n\e[1;32mHysteria2安装成功\033[0m\n"
echo -e "\e[1;33mV2rayN 或 Nekobox、小火箭等直接导入,跳过证书验证需设置为true\033[0m\n"

# 创建订阅文件
cat > ${FILE_PATH}/${UUID:0:8}_hy2.log <<EOF
hysteria2://$UUID@$HOST_IP:$PORT/?sni=www.bing.com&alpn=h3&insecure=1#$ISP-$NAME
EOF
cat ${FILE_PATH}/${UUID:0:8}_hy2.log

# 输出Clash配置
echo -e "\n\e[1;35mClash: \033[0m"
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

# 生成二维码
echo ""
QR_URL="https://00.ssss.nyc.mn/qrencode"
$COMMAND "${WORKDIR}/qrencode" "$QR_URL" && chmod +x "${WORKDIR}/qrencode"
"${WORKDIR}/qrencode" -m 2 -t UTF8 "https://${USERNAME}.${CURRENT_DOMAIN}/${UUID:0:8}_hy2.log"
echo -e "\n\e[1;35m节点订阅链接: https://${USERNAME}.${CURRENT_DOMAIN}/${UUID:0:8}_hy2.log  适用于V2ranN/Nekobox/Karing/小火箭/sterisand/Loon 等\033[0m\n"

# 清理临时文件
rm -rf config.yaml monitor_config.json

echo -e "\e[1;35m修改老王serv00|CT8单协议hysteria2无交互一键安装脚本\e[0m"
echo -e "\e[1;35m老王脚本地址: https://github.com/eooce/sing-box\e[0m"
echo -e "\e[1;35m转载请著名出处,请勿滥用\e[0m\n"
echo -e "\e[1;32mRuning done!\033[0m\n"
