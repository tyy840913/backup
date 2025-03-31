#!/bin/bash
# 设置环境变量为C本地化，避免潜在的语言或区域设置问题
export LC_ALL=C
# 获取当前主机名和用户名（转换为小写）
HOSTNAME=$(hostname)
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')
# 生成基于用户名和主机名的UUID（格式化为标准UUID结构）
export UUID=${UUID:-$(echo -n "$USERNAME+$HOSTNAME" | md5sum | head -c 32 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')}
# 定义必要的环境变量（清理哪吒监控相关变量）
export CHAT_ID=${CHAT_ID:-''} 
export BOT_TOKEN=${BOT_TOKEN:-''} 
export UPLOAD_URL=${UPLOAD_URL:-''}
export SUB_TOKEN=${SUB_TOKEN:-${UUID:0:8}}

# 根据主机名匹配域名
if [[ "$HOSTNAME" =~ ct8 ]]; then
    CURRENT_DOMAIN="ct8.pl"
elif [[ "$HOSTNAME" =~ useruno ]]; then
    CURRENT_DOMAIN="useruno.com"
else
    CURRENT_DOMAIN="serv00.net"
fi

# 创建工作目录和文件目录
WORKDIR="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}/logs"
FILE_PATH="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}/public_html"
rm -rf "$WORKDIR" "$FILE_PATH" && mkdir -p "$WORKDIR" "$FILE_PATH" && chmod 777 "$WORKDIR" "$FILE_PATH" >/dev/null 2>&1

# 杀死用户所有非关键进程
bash -c 'ps aux | grep $(whoami) | grep -v "sshd\|bash\|grep" | awk "{print \$2}" | xargs -r kill -9 >/dev/null 2>&1' >/dev/null 2>&1

# 检查并获取下载工具（curl或wget）
command -v curl &>/dev/null && COMMAND="curl -so" || command -v wget &>/dev/null && COMMAND="wget -qO" || { 
    echo "错误：未找到curl或wget，请安装其中一个工具。" >&2
    exit 1 
}

#######################################
# 检查并配置UDP端口
# 功能：确保至少有一个可用UDP端口，不足时自动创建
#######################################
check_port () {
    echo -e "\e[1;35m正在检查端口配置...\e[0m"
    port_list=$(devil port list)
    udp_ports=$(echo "$port_list" | grep -c "udp")

    # 如果UDP端口不足，优先删除TCP端口并创建UDP端口
    if [[ $udp_ports -lt 1 ]]; then
        echo -e "\e[1;91m未找到可用UDP端口，正在调整...\e[0m"
        # 尝试删除第一个TCP端口（如有3个以上）
        tcp_ports=$(echo "$port_list" | grep -c "tcp")
        if [[ $tcp_ports -ge 3 ]]; then
            tcp_port_to_delete=$(echo "$port_list" | awk '/tcp/ {print $1}' | head -n 1)
            devil port del tcp $tcp_port_to_delete
            echo -e "\e[1;32m已删除TCP端口: $tcp_port_to_delete\e[0m"
        fi

        # 随机尝试添加UDP端口直到成功
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

        # 重启服务并退出父进程
        devil binexec on >/dev/null 2>&1
        kill -9 $(ps -o ppid= -p $$) >/dev/null 2>&1
    else
        # 获取第一个现有UDP端口
        udp_ports=$(echo "$port_list" | awk '/udp/ {print $1}')
        udp_port1=$(echo "$udp_ports" | sed -n '1p')
    fi

    export PORT=$udp_port1
    echo -e "\e[1;35mHysteria2将使用UDP端口: $udp_port1\e[0m"
}
check_port

#######################################
# 下载必要文件
# 变更：使用固定文件名替代随机生成
#######################################
ARCH=$(uname -m)
DOWNLOAD_DIR="."
mkdir -p "$DOWNLOAD_DIR"

# 根据架构设置下载基础URL
if [[ "$ARCH" == "arm"* || "$ARCH" == "aarch64" ]]; then
    BASE_URL="https://github.com/eooce/test/releases/download/freebsd-arm64"
elif [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
    BASE_URL="https://github.com/eooce/test/releases/download/freebsd"
else
    echo "不支持的架构: $ARCH"
    exit 1
fi

# 定义下载列表（固定文件名）
declare -A FILE_MAP=(
    ["hy2"]="${BASE_URL}/hy2"
    ["php"]="${BASE_URL}/v1"
)

# 下载文件并设置可执行权限
for key in "${!FILE_MAP[@]}"; do
    filename="$DOWNLOAD_DIR/$key"
    echo -e "\e[1;32m正在下载 $filename...\e[0m"
    $COMMAND "$filename" "${FILE_MAP[$key]}"
    chmod +x "$filename"
done

#######################################
# 生成TLS证书
#######################################
echo -e "\e[1;35m正在生成TLS证书...\e[0m"
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout "$WORKDIR/server.key" \
    -out "$WORKDIR/server.crt" \
    -subj "/CN=${CURRENT_DOMAIN}" \
    -days 36500

#######################################
# 获取最佳可用IP
#######################################
get_ip() {
    IP_LIST=($(devil vhost list | awk '/^[0-9]+/ {print $1}'))
    API_URL="https://status.eooce.com/api"
    
    # 优先测试第三个IP
    THIRD_IP=${IP_LIST[2]}
    if curl -s --max-time 2 "${API_URL}/${THIRD_IP}" | grep -q "Available"; then
        echo $THIRD_IP
        return
    fi

    # 测试第一个IP
    FIRST_IP=${IP_LIST[0]}
    if curl -s --max-time 2 "${API_URL}/${FIRST_IP}" | grep -q "Available"; then
        echo $FIRST_IP
    else
        echo ${IP_LIST[1]}
    fi
}

echo -e "\e[1;32m正在检测可用IP...\e[0m"
HOST_IP=$(get_ip)
echo -e "\e[1;35m选定IP: $HOST_IP （不通时可重新安装）\e[0m"

#######################################
# 生成Hysteria2配置文件
#######################################
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

#######################################
# 安装保活服务
#######################################
install_keepalive () {
    echo -e "\n\e[1;35m正在配置保活服务...\e[0m"
    devil www del keep.${USERNAME}.${CURRENT_DOMAIN} > /dev/null 2>&1
    devil www add keep.${USERNAME}.${CURRENT_DOMAIN} nodejs /usr/local/bin/node18 > /dev/null 2>&1
    
    # 部署Node.js保活脚本
    keep_path="$HOME/domains/keep.${USERNAME}.${CURRENT_DOMAIN}/public_nodejs"
    mkdir -p "$keep_path"
    $COMMAND "${keep_path}/app.js" "https://hy2.ssss.nyc.mn/hy2.js"

    # 生成环境配置文件
    cat > ${keep_path}/.env <<EOF
UUID=${UUID}
SUB_TOKEN=${SUB_TOKEN}
UPLOAD_URL=${UPLOAD_URL}
TELEGRAM_CHAT_ID=${CHAT_ID}
TELEGRAM_BOT_TOKEN=${BOT_TOKEN}
EOF

    # 配置NPM环境
    ln -fs /usr/local/bin/node18 ~/bin/node > /dev/null 2>&1
    mkdir -p ~/.npm-global
    npm config set prefix '~/.npm-global'
    echo 'export PATH=~/.npm-global/bin:~/bin:$PATH' >> $HOME/.bash_profile
    source $HOME/.bash_profile

    # 安装依赖并验证
    cd ${keep_path} && npm install dotenv axios --silent > /dev/null 2>&1
    devil www restart keep.${USERNAME}.${CURRENT_DOMAIN} > /dev/null 2>&1
    
    # 验证服务状态
    if curl -skL "http://keep.${USERNAME}.${CURRENT_DOMAIN}/${USERNAME}" | grep -q "running"; then
        echo -e "\e[1;32m保活服务运行成功\e[0m"
    else
        echo -e "\e[1;31m保活服务配置失败，请检查日志\e[0m"
    fi
}

#######################################
# 启动核心服务
#######################################
run() {
    # 启动Hysteria2服务
    nohup ./hy2 server config.yaml >/dev/null 2>&1 &
    sleep 1
    if pgrep -x "hy2" > /dev/null; then
        echo -e "\e[1;32mHysteria2服务已启动\e[0m"
    else
        echo -e "\e[1;31mHysteria2启动失败，请检查配置\e[0m"
    fi

    # 清理临时文件
    rm -rf hy2 php  # 固定文件名清理
}
run

#######################################
# 生成订阅信息
#######################################
ISP=$(curl -s --max-time 2 https://speed.cloudflare.com/meta | awk -F\" '{print $26}' | sed -e 's/ /_/g' || echo "Unknown")
echo -e "\n\e[1;32m安装成功！节点信息：\033[0m"
cat > ${FILE_PATH}/${SUB_TOKEN}_hy2.log <<EOF
