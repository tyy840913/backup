#!/bin/bash
#############################################################
# Hysteria2 安装与管理脚本
# 功能：自动安装配置Hysteria2代理服务，包含监控和自修复功能
# 版本：2.0
# 主要变更：
# 1. 使用固定文件名替代随机生成
# 2. 规范化日志和配置存储路径
# 3. 添加详细注释说明
#############################################################

### 基础环境配置 ###
export LC_ALL=C  # 强制使用C语言环境，避免本地化导致的格式问题

### 文件路径配置 ###
# 安装命令记录文件（用于服务崩溃时重新安装）
INSTALL_CMD_FILE="./hysteria2_install_cmd.txt"

# 日志系统配置
LOG_DIR="./hysteria2_logs"          # 日志目录
LOG_FILE="$LOG_DIR/hysteria2_monitor.log"  # 日志文件路径
MAX_LOG_ENTRIES=100                 # 日志最大记录条数
mkdir -p "$LOG_DIR"                 # 创建日志目录

# 清理旧的二进制文件（如果存在）
[ -f "./hysteria2_binary" ] && rm -f "./hysteria2_binary"

### 日志记录函数 ###
# 参数：$1 - 要记录的日志信息
# 功能：记录日志并控制日志文件大小
log_event() {
    # 滚动日志：保留最新的MAX_LOG_ENTRIES-1条记录
    [ -f "$LOG_FILE" ] && tail -n $((MAX_LOG_ENTRIES-1)) "$LOG_FILE" > "${LOG_FILE}.tmp"
    
    # 添加时间戳和新日志条目
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "${LOG_FILE}.tmp"
    
    # 替换原日志文件
    mv "${LOG_FILE}.tmp" "$LOG_FILE" 2>/dev/null
}

### 系统信息收集 ###
HOSTNAME=$(hostname)  # 获取主机名
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')  # 获取当前用户名并转为小写

### 身份标识生成 ###
# 生成UUID（基于用户名+主机名的MD5哈希）
export UUID=${UUID:-$(echo -n "$USERNAME+$HOSTNAME" | md5sum | head -c 32 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')}
# 生成订阅令牌（取UUID前8位）
export SUB_TOKEN=${SUB_TOKEN:-${UUID:0:8}}

### 域名判断逻辑 ###
# 根据主机名特征判断使用的域名
if [[ "$HOSTNAME" =~ ct8 ]]; then
    CURRENT_DOMAIN="ct8.pl"
elif [[ "$HOSTNAME" =~ useruno ]]; then
    CURRENT_DOMAIN="useruno.com"
else
    CURRENT_DOMAIN="serv00.net"  # 默认域名
fi

### 工作目录设置 ###
WORKDIR="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}/logs"      # 工作目录
FILE_PATH="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}/public_html"  # 网页文件目录

# 清理并重建工作目录
echo -e "\e[1;33m[信息] 正在清理并创建工作目录...\e[0m"
rm -rf "$WORKDIR" "$FILE_PATH" && mkdir -p "$WORKDIR" "$FILE_PATH" && chmod 777 "$WORKDIR" "$FILE_PATH" >/dev/null 2>&1

# 清理可能存在的旧进程
echo -e "\e[1;33m[信息] 正在清理现有进程...\e[0m"
bash -c 'ps aux | grep $(whoami) | grep -v "sshd\|bash\|grep" | awk "{print \$2}" | xargs -r kill -9 >/dev/null 2>&1' >/dev/null 2>&1

### 下载工具检查 ###
# 优先使用curl，其次尝试wget
command -v curl &>/dev/null && COMMAND="curl -so" || command -v wget &>/dev/null && COMMAND="wget -qO" || { 
    echo -e "\e[1;31m[错误] 未找到curl或wget，请安装其中一个工具\e[0m"
    exit 1
}

### 端口管理函数 ###
check_port() {
    echo -e "\e[1;33m[信息] 正在检查可用端口...\e[0m"
    port_list=$(devil port list)  # 获取当前端口列表
    udp_ports=$(echo "$port_list" | grep -c "udp")  # 统计UDP端口数量

    # 如果没有可用UDP端口，则尝试添加
    if [[ $udp_ports -lt 1 ]]; then
        echo -e "\e[1;33m[警告] 没有可用的UDP端口，正在尝试添加...\e[0m"
        while true; do
            # 随机生成端口号（10000-65535）
            udp_port=$(shuf -i 10000-65535 -n 1)
            # 尝试添加端口
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
        devil binexec on >/dev/null 2>&1  # 启用二进制执行权限
        kill -9 $(ps -o ppid= -p $$) >/dev/null 2>&1  # 重启脚本
    else
        # 使用第一个可用的UDP端口
        udp_ports=$(echo "$port_list" | awk '/udp/ {print $1}')
        udp_port1=$(echo "$udp_ports" | sed -n '1p')
    fi

    export PORT=$udp_port1  # 设置环境变量
    echo -e "\e[1;32m[信息] Hysteria2将使用UDP端口: $udp_port1\e[0m"
}
check_port  # 执行端口检查

### 系统架构检测 ###
ARCH=$(uname -m) && DOWNLOAD_DIR="." && mkdir -p "$DOWNLOAD_DIR"
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

### 下载Hysteria2二进制文件 ###
echo -e "\e[1;33m[信息] 正在下载Hysteria2二进制文件...\e[0m"
HY2_URL="$BASE_URL/hy2"
HY2_BINARY="./hysteria2_binary"  # 固定文件名
$COMMAND "$HY2_BINARY" "$HY2_URL" && chmod +x "$HY2_BINARY"  # 下载并添加执行权限

# 生成证书（完全保留原有代码）
echo -e "\e[1;33m[信息] 正在生成自签名证书...\e[0m"
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout "$WORKDIR/server.key" -out "$WORKDIR/server.crt" -subj "/CN=${CURRENT_DOMAIN}" -days 36500

### IP地址选择逻辑 ###
get_ip() {
    IP_LIST=($(devil vhost list | awk '/^[0-9]+/ {print $1}'))  # 获取可用IP列表
    API_URL="https://status.eooce.com/api"  # IP检测API
    
    # 优先尝试第三个IP
    THIRD_IP=${IP_LIST[2]}
    RESPONSE=$(curl -s --max-time 2 "${API_URL}/${THIRD_IP}")
    if [[ $(echo "$RESPONSE" | jq -r '.status') == "Available" ]]; then
        echo "$THIRD_IP"
        return
    fi
    
    # 其次尝试第一个IP
    FIRST_IP=${IP_LIST[0]}
    RESPONSE=$(curl -s --max-time 2 "${API_URL}/${FIRST_IP}")
    if [[ $(echo "$RESPONSE" | jq -r '.status') == "Available" ]]; then
        echo "$FIRST_IP"
        return
    fi
    
    # 最后使用第二个IP
    echo ${IP_LIST[1]}
}

echo -e "\e[1;33m[信息] 正在获取可用IP地址...\e[0m"
HOST_IP=$(get_ip)
echo -e "\e[1;32m[信息] 已选择IP地址: $HOST_IP\e[0m"

### 配置文件生成 ###
echo -e "\e[1;33m[信息] 正在创建Hysteria2配置文件...\e[0m"
cat << EOF > config.yaml
listen: $HOST_IP:$PORT  # 监听地址和端口
tls:
  cert: "$WORKDIR/server.crt"  # 证书路径
  key: "$WORKDIR/server.key"   # 私钥路径
auth:
  type: password              # 认证类型
  password: "$UUID"           # 认证密码
fastOpen: true                # 启用TCP快速打开
masquerade:                   # 伪装配置
  type: proxy
  proxy:
    url: https://bing.com     # 伪装网址
    rewriteHost: true         # 重写Host头
transport:
  udp:
    hopInterval: 30s          # UDP端口跳变间隔
EOF

### 服务管理函数 ###
start_service() {
    echo -e "\e[1;33m[信息] 正在启动Hysteria2服务...\e[0m"
    # 后台启动服务
    nohup ./"$HY2_BINARY" server config.yaml >/dev/null 2>&1 &
    sleep 1  # 等待进程启动
    
    # 检查进程是否运行
    if pgrep -x "$(basename "$HY2_BINARY")" > /dev/null; then
        echo -e "\e[1;32m[成功] Hysteria2服务已启动\e[0m"
        return 0
    else
        echo -e "\e[1;31m[错误] 无法启动Hysteria2服务\e[0m"
        return 1
    fi
}


### 服务监控函数 ###
monitor_service() {
    # 保存安装命令用于崩溃恢复
    echo "$(realpath $0)" > "$INSTALL_CMD_FILE"
    chmod 600 "$INSTALL_CMD_FILE"  # 限制权限
    
    # 监控循环
    while true; do
        if ! pgrep -x "$(basename "$HY2_BINARY")" > /dev/null; then
            log_event "服务停止，尝试重启"
            echo -e "\e[1;33m[警告] Hysteria2服务未运行，正在尝试重启...\e[0m"
            pkill -f "$(basename "$HY2_BINARY")"  # 确保杀死残留进程
            
            # 最多尝试3次重启
            for i in {1..3}; do
                if start_service; then
                    log_event "服务重启成功"
                    echo -e "\e[1;32m[成功] Hysteria2服务重启成功\e[0m"
                    break
                elif [ $i -eq 3 ]; then
                    log_event "重启失败，尝试重新安装"
                    echo -e "\e[1;31m[错误] 重启失败，尝试重新安装...\e[0m"
                    
                    # 使用保存的安装命令重新安装
                    if [ -f "$INSTALL_CMD_FILE" ]; then
                        bash "$(cat "$INSTALL_CMD_FILE")"
                    else
                        # 如果安装命令文件丢失，重新创建
                        echo "$(realpath $0)" > "$INSTALL_CMD_FILE"
                        chmod 600 "$INSTALL_CMD_FILE"
                        bash "$(realpath $0)"
                    fi
                    exit 1
                fi
                sleep 5  # 重试间隔
            done
        fi
        sleep 60  # 检查间隔
    done
}

### 主程序流程 ###
start_service  # 启动服务

### 节点信息展示 ###
# 获取ISP信息
ISP=$(curl -s --max-time 2 https://speed.cloudflare.com/meta | awk -F\" '{print $26}' | sed -e 's/ /_/g' || echo "未知")
# 生成节点名称
NAME="$(echo "$HOSTNAME" | cut -d '.' -f 1)-hysteria2-${USERNAME}"

echo -e "\n\e[1;32m[成功] Hysteria2安装成功\e[0m\n"
echo -e "\e[1;33m[提示] 在V2rayN或Nekobox中，需要将跳过证书验证设置为true\e[0m\n"

### 订阅文件生成 ###
echo -e "\e[1;33m[信息] 正在生成订阅文件...\e[0m"
cat > ${FILE_PATH}/${SUB_TOKEN}_hy2.log <<EOF
hysteria2://$UUID@$HOST_IP:$PORT/?sni=www.bing.com&alpn=h3&insecure=1#$ISP-$NAME
EOF

### 配置信息输出 ###
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

### 启动监控进程 ###
echo -e "\n\e[1;33m[信息] 监控进程将在后台运行\e[0m"
nohup bash -c 'monitor_service' >/dev/null 2>&1 &
disown  # 分离进程

exit 0
