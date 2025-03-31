#!/bin/bash

# 设置环境变量
export LC_ALL=C
export HOSTNAME=$(hostname)
export USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')

# 生成UUID
export UUID=${UUID:-$(echo -n "$USERNAME+$HOSTNAME" | md5sum | head -c 32 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')}
export SUB_TOKEN=${SUB_TOKEN:-${UUID:0:8}}

# 域名识别
if [[ "$HOSTNAME" =~ ct8 ]]; then
    CURRENT_DOMAIN="ct8.pl"
elif [[ "$HOSTNAME" =~ useruno ]]; then
    CURRENT_DOMAIN="useruno.com"
else
    CURRENT_DOMAIN="serv00.net"
fi

# 创建工作目录
WORKDIR="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}"
rm -rf "$WORKDIR" && mkdir -p "$WORKDIR"
echo -e "\e[1;32m工作目录: $WORKDIR\e[0m"

# 清理旧进程
pkill -f "hysteria"

# 检查依赖
check_deps() {
    for cmd in openssl curl wget; do
        if ! command -v $cmd &>/dev/null; then
            echo -e "\e[1;31m缺少依赖: $cmd\e[0m"
            exit 1
        fi
    done
}
check_deps

# 配置端口
check_port() {
    local udp_port=$(devil port list | awk '/udp/ {print $1; exit}')
    
    if [[ -z "$udp_port" ]]; then
        while :; do
            local new_port=$(shuf -i 10000-65535 -n 1)
            if devil port add udp $new_port | grep -q "Ok"; then
                udp_port=$new_port
                devil binexec on >/dev/null
                break
            fi
        done
    fi
    
    export PORT=$udp_port
    echo -e "\e[1;32m使用端口: $PORT (UDP)\e[0m"
}
check_port

# 下载二进制
ARCH=$(uname -m)
if [[ "$ARCH" =~ arm|aarch64 ]]; then
    BINARY_URL="https://github.com/eooce/test/releases/download/freebsd-arm64/hy2"
else
    BINARY_URL="https://github.com/eooce/test/releases/download/freebsd/hy2"
fi

echo -e "\e[1;33m下载程序中...\e[0m"
if ! curl -sLo "$WORKDIR/hysteria" "$BINARY_URL"; then
    echo -e "\e[1;31m下载失败!\e[0m"
    exit 1
fi

chmod +x "$WORKDIR/hysteria"

# 验证二进制
if ! "$WORKDIR/hysteria" --version &>/dev/null; then
    echo -e "\e[1;31m二进制文件验证失败!\e[0m"
    exit 1
fi

# 生成证书
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout "$WORKDIR/server.key" -out "$WORKDIR/server.crt" \
    -subj "/CN=${CURRENT_DOMAIN}" -days 36500

# 生成配置
cat > "$WORKDIR/config.yaml" <<EOF
listen: 0.0.0.0:$PORT
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

# 启动服务
start_service() {
    echo -e "\e[1;36m启动服务...\e[0m"
    nohup "$WORKDIR/hysteria" server "$WORKDIR/config.yaml" > "$WORKDIR/hysteria.log" 2>&1 &
    sleep 3
    
    if ! pgrep -f "hysteria" >/dev/null; then
        echo -e "\e[1;31m启动失败! 日志:\e[0m"
        cat "$WORKDIR/hysteria.log"
        return 1
    fi
    
    echo -e "\e[1;32m启动成功! PID: $(pgrep -f "hysteria")\e[0m"
    return 0
}

# 监控进程
start_monitor() {
    (
        while true; do
            sleep 60
            if ! pgrep -f "hysteria" >/dev/null; then
                echo -e "\e[1;31m[监控] 服务停止,尝试重启...\e[0m"
                if ! start_service; then
                    echo -e "\e[1;31m[监控] 重启失败,重新安装...\e[0m"
                    exec bash -c "$(curl -sSL https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/hy.sh)"
                fi
            fi
        done
    ) &
}

# 主流程
if start_service; then
    start_monitor
    echo -e "\n\e[1;35m=== 配置信息 ===\e[0m"
    echo -e "协议: \e[1;33mHysteria2\e[0m"
    echo -e "端口: \e[1;33m$PORT (UDP)\e[0m"
    echo -e "密码: \e[1;33m$UUID\e[0m"
    echo -e "订阅: \e[1;36mhttps://${USERNAME}.${CURRENT_DOMAIN}/$SUB_TOKEN\e[0m"
else
    echo -e "\e[1;31m初始化失败!\e[0m"
    exit 1
fi
