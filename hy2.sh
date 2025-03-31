#!/bin/bash
# 设置环境变量和系统配置
export LC_ALL=C  # 确保脚本使用C语言环境，避免本地化问题

# 获取系统信息
HOSTNAME=$(hostname)  # 获取主机名
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')  # 获取当前用户名并转为小写

# 生成UUID作为认证密码，基于用户名和主机名的MD5哈希
export UUID=${UUID:-$(echo -n "$USERNAME+$HOSTNAME" | md5sum | head -c 32 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')}
# 生成订阅token，使用UUID的前8个字符
export SUB_TOKEN=${SUB_TOKEN:-${UUID:0:8}}

# 根据主机名确定当前域名
if [[ "$HOSTNAME" =~ ct8 ]]; then
    CURRENT_DOMAIN="ct8.pl"
elif [[ "$HOSTNAME" =~ useruno ]]; then
    CURRENT_DOMAIN="useruno.com"
else
    CURRENT_DOMAIN="serv00.net"
fi

# 设置工作目录和文件路径
WORKDIR="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}/logs"
FILE_PATH="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}/public_html"

# 创建日志目录
LOG_DIR="$HOME/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/hysteria2_monitor.log"

# 记录日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo -e "$1"
}

# 清理并创建必要的目录
log "\e[1;33m[信息] 正在清理并创建工作目录...\e[0m"
rm -rf "$WORKDIR" "$FILE_PATH" && mkdir -p "$WORKDIR" "$FILE_PATH" && chmod 777 "$WORKDIR" "$FILE_PATH" >/dev/null 2>&1

# 杀死当前用户的所有非关键进程(排除sshd、bash和grep进程)
log "\e[1;33m[信息] 正在清理现有进程...\e[0m"
bash -c 'ps aux | grep $(whoami) | grep -v "sshd\|bash\|grep" | awk "{print \$2}" | xargs -r kill -9 >/dev/null 2>&1' >/dev/null 2>&1

# 检查并设置下载工具(curl或wget)
command -v curl &>/dev/null && COMMAND="curl -so" || command -v wget &>/dev/null && COMMAND="wget -qO" || { 
    log "\e[1;31m[错误] 未找到curl或wget，请安装其中一个工具\e[0m"
    exit 1
}

# 检查并配置端口的函数
check_port() {
    log "\e[1;33m[信息] 正在检查可用端口...\e[0m"
    port_list=$(devil port list)  # 获取当前端口列表
    udp_ports=$(echo "$port_list" | grep -c "udp")  # 统计UDP端口数量

    # 如果没有可用的UDP端口，则添加一个
    if [[ $udp_ports -lt 1 ]]; then
        log "\e[1;33m[警告] 没有可用的UDP端口，正在尝试添加...\e[0m"

        # 随机尝试添加UDP端口，直到成功
        while true; do
            udp_port=$(shuf -i 10000-65535 -n 1)  # 生成随机端口号
            result=$(devil port add udp $udp_port 2>&1)  # 尝试添加端口
            if [[ $result == *"Ok"* ]]; then
                log "\e[1;32m[成功] 已添加UDP端口: $udp_port\e[0m"
                udp_port1=$udp_port
                break
            else
                log "\e[1;33m[信息] 端口 $udp_port 不可用，尝试其他端口...\e[0m"
            fi
        done

        log "\e[1;32m[成功] 端口调整完成。如果安装后连接失败，请访问/restart重启\e[0m"
        devil binexec on >/dev/null 2>&1  # 启用二进制执行权限
        kill -9 $(ps -o ppid= -p $$) >/dev/null 2>&1  # 重启脚本
    else
        # 如果已有UDP端口，则使用第一个找到的端口
        udp_ports=$(echo "$port_list" | awk '/udp/ {print $1}')
        udp_port1=$(echo "$udp_ports" | sed -n '1p')
    fi

    export PORT=$udp_port1  # 设置环境变量
    log "\e[1;32m[信息] Hysteria2将使用UDP端口: $udp_port1\e[0m"
}
check_port  # 调用端口检查函数

# 根据系统架构设置下载URL
ARCH=$(uname -m) && DOWNLOAD_DIR="." && mkdir -p "$DOWNLOAD_DIR"
if [ "$ARCH" == "arm" ] || [ "$ARCH" == "arm64" ] || [ "$ARCH" == "aarch64" ]; then
    BASE_URL="https://github.com/eooce/test/releases/download/freebsd-arm64"
    log "\e[1;33m[信息] 检测到ARM架构系统\e[0m"
elif [ "$ARCH" == "amd64" ] || [ "$ARCH" == "x86_64" ] || [ "$ARCH" == "x86" ]; then
    BASE_URL="https://github.com/eooce/test/releases/download/freebsd"
    log "\e[1;33m[信息] 检测到x86架构系统\e[0m"
else
    log "\e[1;31m[错误] 不支持的架构: $ARCH\e[0m"
    exit 1
fi

# 下载Hysteria2二进制文件
log "\e[1;33m[信息] 正在下载Hysteria2二进制文件...\e[0m"
HY2_URL="$BASE_URL/hy2"  # Hysteria2二进制文件URL
RANDOM_NAME=$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)  # 生成6位随机名称
HY2_BINARY="$DOWNLOAD_DIR/$RANDOM_NAME"  # 二进制文件保存路径
$COMMAND "$HY2_BINARY" "$HY2_URL" && chmod +x "$HY2_BINARY"  # 下载并添加执行权限

# 生成自签名证书
log "\e[1;33m[信息] 正在生成自签名证书...\e[0m"
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout "$WORKDIR/server.key" \
    -out "$WORKDIR/server.crt" \
    -subj "/CN=${CURRENT_DOMAIN}" \
    -days 36500

# 获取最佳可用IP地址的函数
get_ip() {
    IP_LIST=($(devil vhost list | awk '/^[0-9]+/ {print $1}'))  # 获取IP列表
    API_URL="https://status.eooce.com/api"  # IP检查API
    
    # 优先尝试第三个IP
    THIRD_IP=${IP_LIST[2]}
    RESPONSE=$(curl -s --max-time 2 "${API_URL}/${THIRD_IP}")
    if [[ $(echo "$RESPONSE" | jq -r '.status') == "Available" ]]; then
        echo "$THIRD_IP"
        return
    fi
    
    # 然后尝试第一个IP
    FIRST_IP=${IP_LIST[0]}
    RESPONSE=$(curl -s --max-time 2 "${API_URL}/${FIRST_IP}")
    if [[ $(echo "$RESPONSE" | jq -r '.status') == "Available" ]]; then
        echo "$FIRST_IP"
        return
    fi
    
    # 最后使用第二个IP
    echo ${IP_LIST[1]}
}

log "\e[1;33m[信息] 正在获取可用IP地址...\e[0m"
HOST_IP=$(get_ip)  # 调用函数获取最佳IP
log "\e[1;32m[信息] 已选择IP地址: $HOST_IP。如果安装后连接失败，请尝试重新安装。\e[0m"

# 创建Hysteria2配置文件
log "\e[1;33m[信息] 正在创建Hysteria2配置文件...\e[0m"
cat << EOF > config.yaml
listen: $HOST_IP:$PORT  # 监听地址和端口
tls:
  cert: "$WORKDIR/server.crt"  # 证书路径
  key: "$WORKDIR/server.key"   # 私钥路径
auth:
  type: password  # 认证类型
  password: "$UUID"  # 认证密码
fastOpen: true  # 启用快速打开
masquerade:
  type: proxy  # 伪装类型
  proxy:
    url: https://bing.com  # 伪装URL
    rewriteHost: true  # 重写主机头
transport:
  udp:
    hopInterval: 30s  # UDP跳频间隔
EOF

# 启动Hysteria2服务的函数
start_service() {
    log "\e[1;33m[信息] 正在启动Hysteria2服务...\e[0m"
    # 使用nohup在后台启动服务
    nohup ./"$HY2_BINARY" server config.yaml >> "$LOG_FILE" 2>&1 &
    sleep 1  # 等待1秒让进程启动
    
    # 检查进程是否成功启动
    if pgrep -x "$(basename "$HY2_BINARY")" > /dev/null; then
        log "\e[1;32m[成功] Hysteria2服务已启动\e[0m"
        return 0  # 返回成功
    else
        log "\e[1;31m[错误] 无法启动Hysteria2服务\e[0m"
        return 1  # 返回失败
    fi
}

# 监控服务的函数
monitor_service() {
    while true; do
        # 检查进程是否在运行
        if ! pgrep -x "$(basename "$HY2_BINARY")" > /dev/null; then
            log "\e[1;33m[警告] Hysteria2服务未运行，正在尝试重启...\e[0m"
            pkill -f "$(basename "$HY2_BINARY")"  # 确保杀死所有相关进程
            
            # 尝试重启3次
            for i in {1..3}; do
                if start_service; then
                    log "\e[1;32m[成功] Hysteria2服务重启成功\e[0m"
                    break  # 如果启动成功，跳出循环
                elif [ $i -eq 3 ]; then
                    # 如果3次都失败，退出脚本
                    log "\e[1;31m[错误] 重启Hysteria2服务失败，已达到最大重试次数\e[0m"
                    exit 1
                fi
                sleep 5  # 等待5秒再重试
            done
        fi
        sleep 60  # 每分钟检查一次
    done
}

# 启动Hysteria2服务
start_service

# 在后台启动监控进程
log "\e[1;33m[信息] 正在启动服务监控进程...\e[0m"
nohup bash -c 'monitor_service >> "$LOG_FILE" 2>&1' & disown

# 获取ISP信息用于节点命名
ISP=$(curl -s --max-time 2 https://speed.cloudflare.com/meta | awk -F\" '{print $26}' | sed -e 's/ /_/g' || echo "未知")
NAME="$(echo "$HOSTNAME" | cut -d '.' -f 1)-hysteria2-${USERNAME}"  # 生成节点名称

# 显示安装成功信息
log "\n\e[1;32m[成功] Hysteria2安装成功\e[0m\n"
log "\e[1;33m[提示] 在V2rayN或Nekobox中，需要将跳过证书验证设置为true\e[0m\n"

# 创建订阅文件
log "\e[1;33m[信息] 正在生成订阅文件...\e[0m"
cat > ${FILE_PATH}/${SUB_TOKEN}_hy2.log <<EOF
hysteria2://$UUID@$HOST_IP:$PORT/?sni=www.bing.com&alpn=h3&insecure=1#$ISP-$NAME
EOF

# 显示节点配置
log "\e[1;32m[信息] Hysteria2节点配置:\e[0m"
cat ${FILE_PATH}/${SUB_TOKEN}_hy2.log >> "$LOG_FILE"
log "\n\e[1;32m[信息] Clash配置文件:\e[0m"
cat << EOF >> "$LOG_FILE"
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

# 显示订阅链接
log "\n\e[1;32m[信息] 订阅链接: https://${USERNAME}.${CURRENT_DOMAIN}/${SUB_TOKEN}_hy2.log\e[0m\n"
log "\e[1;33m[信息] 脚本来源: https://github.com/eooce/sing-box\e[0m"
log "\e[1;32m[成功] 所有操作已完成!\e[0m\n"

# 持久化运行提示
log "\e[1;33m[重要] 脚本已配置为持久化运行，即使退出终端也不会停止\e[0m"
log "\e[1;33m[信息] 监控日志保存在: $LOG_FILE\e[0m"
log "\e[1;33m[信息] 如需停止服务，请执行: pkill -f \"$HY2_BINARY\" && pkill -f \"$0\"\e[0m"

# 保持脚本运行
while true; do 
    sleep 3600  # 每小时唤醒一次，防止脚本退出
done
