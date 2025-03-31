#!/bin/bash
export LC_ALL=C
HOSTNAME=$(hostname)
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')
export UUID=${UUID:-$(echo -n "$USERNAME+$HOSTNAME" | md5sum | head -c 32 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')}

# 环境初始化
WORKDIR="${HOME}/domains/${USERNAME}.$(hostname).logs"
FILE_PATH="${HOME}/domains/${USERNAME}.$(hostname).public_html"
rm -rf "$WORKDIR" "$FILE_PATH" && mkdir -p "$WORKDIR" "$FILE_PATH" && chmod 777 "$WORKDIR" "$FILE_PATH" >/dev/null 2>&1
command -v curl &>/dev/null && COMMAND="curl -so" || command -v wget &>/dev/null && COMMAND="wget -qO" || exit 1

# 端口管理
check_port() {
    clear
    echo -e "\e[1;35m正在安装中，请稍等...\e[0m"
    port_list=$(devil port list)
    tcp_ports=$(echo "$port_list" | grep -c "tcp")
    udp_ports=$(echo "$port_list" | grep -c "udp")

    if [[ $udp_ports -lt 1 ]]; then
        echo -e "\e[1;91m没有可用的UDP端口，正在调整...\e[0m"
        if [[ $tcp_ports -ge 3 ]]; then
            tcp_port_to_delete=$(echo "$port_list" | awk '/tcp/ {print $1}' | head -n 1)
            devil port del tcp $tcp_port_to_delete
            echo -e "\e[1;32m已删除TCP端口: $tcp_port_to_delete\e[0m"
        fi
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
        echo -e "\e[1;32m端口已调整完成，如安装完后节点不通，访问 /restart域名重启\e[0m"
        devil binexec on >/dev/null 2>&1
        kill -9 $(ps -o ppid= -p $$) >/dev/null 2>&1
    else
        udp_port1=$(echo "$port_list" | awk '/udp/ {print $1}' | sed -n '1p')
    fi
    export PORT=$udp_port1
    echo -e "\e[1;35mhysteria2使用udp端口: $udp_port1\e[0m"
}
check_port

# 架构检测与文件下载
ARCH=$(uname -m)
DOWNLOAD_DIR="."
mkdir -p "$DOWNLOAD_DIR"
FILE_INFO=()
case "$ARCH" in
    arm|arm64|aarch64) BASE_URL="https://github.com/eooce/test/releases/download/freebsd-arm64" ;;
    amd64|x86_64|x86) BASE_URL="https://github.com/eooce/test/releases/download/freebsd" ;;
    *) echo "Unsupported architecture: $ARCH" && exit 1 ;;
esac
FILE_INFO=("hy2 web")
for entry in "${FILE_INFO[@]}"; do
    URL=$(echo "$entry" | cut -d ' ' -f 1)
    RANDOM_NAME=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 6 | head -n 1)
    NEW_FILENAME="$DOWNLOAD_DIR/$RANDOM_NAME"
    $COMMAND "$NEW_FILENAME" "$URL"
    echo -e "\e[1;32mDownloading $NEW_FILENAME\e[0m"
    chmod +x "$NEW_FILENAME"
    FILE_MAP[$entry]="$NEW_FILENAME"
done
wait

# 证书生成与配置
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
-keyout "$WORKDIR/server.key" \
-out "$WORKDIR/server.crt" \
-subj "/CN=$(hostname)" \
-days 36500

get_ip() {
    IP_list=($(devil vhost list | awk '/^[0-9]+/ {print $1}'))
    THIRD_IP=${IP_list[2]}
    RESPONSE=$(curl -s --max-time 2 "https://status.eooce.com/api/${THIRD_IP}")
    if [[ $(echo "$RESPONSE" | jq -r '.status') == "Available" ]]; then
        echo $THIRD_IP
    else
        FIRST_IP=${IP_list[0]}
        RESPONSE=$(curl -s --max-time 2 "https://status.eooce.com/api/${FIRST_IP}")
        if [[ $(echo "$RESPONSE" | jq -r '.status') == "Available" ]]; then
            echo $FIRST_IP
        else
            echo ${IP_list[1]}
        fi
    fi
}
HOST_IP=$(get_ip)

cat > config.yaml << EOF
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

# 保活服务安装
install_keepalive() {
    echo -e "\n\e[1;35m正在安装保活服务中，请稍等......\e[0m"
    devil www del keep.${USERNAME}.$(hostname) > /dev/null 2>&1
    devil www add keep.${USERNAME}.$(hostname) nodejs /usr/local/bin/node18 > /dev/null 2>&1
    keep_path="$HOME/domains/keep.${USERNAME}.$(hostname)/public_nodejs"
    [ -d "$keep_path" ] || mkdir -p "$keep_path"
    app_file_url="https://hy2.ssss.nyc.mn/hy2.js"
    $COMMAND $COMMAND "${keep_path}/app.js" "$app_file_url"

    cat > ${keep_path}/.env <<EOF
UUID=${UUID}
UPLOAD_URL=${UPLOAD_URL}
TELEGRAM_CHAT_ID=${CHAT_ID}
BOT_TOKEN=${BOT_TOKEN}
SUB_TOKEN=${SUB_TOKEN}
EOF

    devil www add ${USERNAME}.$(hostname) php > /dev/null 2>&1
    index_url="https://github.com/eooce/Sing-box/releases/download/00/index.html"
    [ -f "${FILE_PATH}/index.html" ] || $COMMAND "${FILE_PATH}/index.html" "$index_url"
    ln -fs /usr/local/bin/node18 ~/bin/node > /dev/null 2>&1
    ln -fs /usr/local/bin/npm18 ~/bin/npm > /dev/null 2>&1
    mkdir -p ~/.npm-global
    npm config set prefix '~/.npm-global'
    echo 'export PATH=~/.npm-global/bin:~/bin:$PATH' >> $HOME/.bash_profile && source $HOME/.bash_profile
    rm -rf $HOME/.npmrc > /dev/null 2>&1
    cd ${keep_path} && npm install dotenv axios --silent > /dev/null 2>&1
    rm $HOME/domains/keep.${USERNAME}.$(hostname)/public_nodejs/public/index.html > /dev/null 2>&1

    if curl -skL "http://keep.${USERNAME}.$(hostname)/${USERNAME}" | grep -q "running"; then
        echo -e "\e[1;32m全自动保活服务安装成功\n所有服务运行正常，保活任务添加成功\n"
        echo -e "访问 http://keep.${USERNAME}.$(hostname)/restart 重启进程\n"
        echo -e "访问 http://keep.${USERNAME}.$(hostname)/status 查看进程状态\n"
    else
        echo -e "\e[1;31m全自动保活服务安装失败，请检查进程状态后重试！"
    fi
}

# 服务启动
run() {
    if [ -e "$(basename ${FILE_MAP[web]})" ]; then
        nohup ./"$(basename ${FILE_MAP[web]})" server config.yaml >/dev/null 2>&1 &
        sleep 1
        pgrep -x "$(basename ${FILE_MAP[web]})" > /dev/null && echo -e "\e[1;32mHysteria2 is running"
    fi

    for key in "${!FILE_MAP[@]}"; do
        rm -rf "$(basename ${FILE_MAP[$key]})" >/dev/null 2>&1
    done
}
run

# 输出订阅信息
get_name() {
    echo $(hostname | awk -F. '{print $1}')
}
NAME="$(get_name)-hysteria2-$(whoami)"
ISP=$(curl -s --max-time 2 https://speed.cloudflare.com/meta | awk -F\" '{print $26}' | sed 's/ /_/g' || echo "0")

echo -e "\n\e[1;32mHysteria2安装成功\n"
echo -e "\e[1;33m订阅链接适用于V2RayN/Nekobox/小火箭等工具\n"
cat > ${FILE_PATH}/${SUB_TOKEN}_hy2.log <<EOF
hysteria2://$UUID@$HOST_IP:$PORT/?sni=www.bing.com&alpn=h3&insecure=1#$ISP-$NAME
EOF
cat ${FILE_PATH}/${SUB_TOKEN}_hy2.log
echo -e "\n\e[1;35m节点订阅链接: https://${USERNAME}.$(hostname)/${SUB_TOKEN}_hy2.log\n"

QR_URL="https://00.ssss.nyc.mn/qrencode"
$COMMAND "${WORKDIR}/qrencode" "$QR_URL" && chmod +x "${WORKDIR}/qrencode"
"${WORKDIR}/qrencode" -m 2 -t UTF8 "https://${USERNAME}.$(hostname)/${SUB_TOKEN}_hy2.log"
echo -e "\n\e[1;35m二维码已生成，可直接扫描使用\n"

echo -e "\e[1;35m老王serv00|CT8单协议Hysteria2无交互一键安装脚本\n"
echo -e "\e[1;35m脚本地址: https://github.com/eooce/sing-box\n"
echo -e "\e[1;32mRuning done!\033[0m\n"
