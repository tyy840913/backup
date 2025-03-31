#!/bin/bash
export LC_ALL=C
HOSTNAME=$(hostname)
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')
export UUID=${UUID:-$(echo -n "$USERNAME+$HOSTNAME" | md5sum | head -c 32 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')}
export CHAT_ID=${CHAT_ID:-''} 
export BOT_TOKEN=${BOT_TOKEN:-''} 
export UPLOAD_URL=${UPLOAD_URL:-''}
export SUB_TOKEN=${SUB_TOKEN:-${UUID:0:8}}

if [[ "$HOSTNAME" =~ ct8 ]]; then
    CURRENT_DOMAIN="ct8.pl"
elif [[ "$HOSTNAME" =~ useruno ]]; then
    CURRENT_DOMAIN="useruno.com"
else
    CURRENT_DOMAIN="serv00.net"
fi
WORKDIR="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}/logs"
FILE_PATH="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}/public_html"
rm -rf "$WORKDIR" "$FILE_PATH" && mkdir -p "$WORKDIR" "$FILE_PATH" && chmod 777 "$WORKDIR" "$FILE_PATH" >/dev/null 2>&1
bash -c 'ps aux | grep $(whoami) | grep -v "sshd\|bash\|grep" | awk "{print \$2}" | xargs -r kill -9 >/dev/null 2>&1' >/dev/null 2>&1
command -v curl &>/dev/null && COMMAND="curl -so" || command -v wget &>/dev/null && COMMAND="wget -qO" || { echo "Error: curl/wget not found" >&2; exit 1; }

check_port () {
  clear
  echo -e "\e[1;35mConfiguring port...\e[0m"
  port_list=$(devil port list)
  udp_ports=$(echo "$port_list" | grep -c "udp")

  if [[ $udp_ports -lt 1 ]]; then
      while true; do
          udp_port=$(shuf -i 10000-65535 -n 1)
          result=$(devil port add udp $udp_port 2>&1)
          [[ $result == *"Ok"* ]] && break
      done
      export PORT=$udp_port
      echo -e "\e[1;32mUDP port: $udp_port\e[0m"
      devil binexec on >/dev/null 2>&1
  else
      export PORT=$(echo "$port_list" | awk '/udp/ {print $1}' | head -1)
  fi
}
check_port

ARCH=$(uname -m)
DOWNLOAD_DIR="."
mkdir -p "$DOWNLOAD_DIR"
if [ "$ARCH" == "arm" ] || [ "$ARCH" == "aarch64" ]; then
    BASE_URL="https://github.com/eooce/test/releases/download/freebsd-arm64"
else
    BASE_URL="https://github.com/eooce/test/releases/download/freebsd"
fi

# Download fixed filename binary
$COMMAND "$DOWNLOAD_DIR/hysteria" "$BASE_URL/hy2"
chmod +x "$DOWNLOAD_DIR/hysteria"

# Generate cert
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout "$WORKDIR/server.key" -out "$WORKDIR/server.crt" -subj "/CN=${CURRENT_DOMAIN}" -days 36500

get_ip() {
  IP_LIST=($(devil vhost list | awk '/^[0-9]+/ {print $1}'))
  API_URL="https://status.eooce.com/api"
  IP=${IP_LIST[1]}
  echo "$IP"
}

HOST_IP=$(get_ip)
echo -e "\e[1;35mSelected IP: $HOST_IP\e[0m"

# Create hysteria config
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
EOF

# Start hysteria service
nohup ./hysteria server config.yaml > "$WORKDIR/hysteria.log" 2>&1 &

# Monitor process
(
    while true; do
        if ! pgrep -x "hysteria" >/dev/null; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') Process not running, restarting..." >> "$WORKDIR/monitor.log"
            nohup ./hysteria server config.yaml >> "$WORKDIR/hysteria.log" 2>&1 &
            sleep 10
            if ! pgrep -x "hysteria" >/dev/null; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') Restart failed, reinstalling..." >> "$WORKDIR/monitor.log"
                $COMMAND "hysteria" "$BASE_URL/hy2"
                chmod +x hysteria
                nohup ./hysteria server config.yaml >> "$WORKDIR/hysteria.log" 2>&1 &
            fi
        fi
        sleep 60
    done
) >/dev/null 2>&1 &

# Output config
echo -e "\n\e[1;32mHysteria2 Config:\033[0m"
echo "hy2://$UUID@$HOST_IP:$PORT/?sni=www.bing.com&insecure=1"
echo -e "\n\e[1;33mSubs: https://${USERNAME}.${CURRENT_DOMAIN}/${SUB_TOKEN}_hy2.log\e[0m"
cat > ${FILE_PATH}/${SUB_TOKEN}_hy2.log <<EOF
hysteria2://$UUID@$HOST_IP:$PORT/?sni=www.bing.com&insecure=1
EOF
