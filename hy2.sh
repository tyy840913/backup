#!/bin/bash
# Hysteria2 服务部署脚本
# 功能：自动部署服务并添加持久化监控进程

#######################################
# 环境变量设置
#######################################
export LC_ALL=C
export HOSTNAME=$(hostname)
export USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')  # 统一小写用户名

# 生成UUID（如果未预设）
export UUID=${UUID:-$(echo -n "$USERNAME+$HOSTNAME" | md5sum | head -c 32 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')}
export SUB_TOKEN=${SUB_TOKEN:-${UUID:0:8}}  # 订阅令牌短码

#######################################
# 域名识别逻辑
#######################################
if [[ "$HOSTNAME" =~ ct8 ]]; then
    CURRENT_DOMAIN="ct8.pl"
elif [[ "$HOSTNAME" =~ useruno ]]; then
    CURRENT_DOMAIN="useruno.com"
else
    CURRENT_DOMAIN="serv00.net"
fi

#######################################
# 目录初始化
#######################################
WORKDIR="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}"
rm -rf "$WORKDIR" && mkdir -p "$WORKDIR"
echo -e "\e[1;32m工作目录已创建：$WORKDIR\e[0m"

#######################################
# 清理旧进程
#######################################
echo -e "\e[1;33m清理旧进程...\e[0m"
pkill -f "hysteria"  # 终止所有hysteria相关进程

#######################################
# 网络端口配置
#######################################
check_port() {
    echo -e "\e[1;36m正在配置网络端口...\e[0m"
    # 获取现有UDP端口
    local udp_port=$(devil port list | awk '/udp/ {print $1; exit}')
    
    # 无可用端口时创建新端口
    if [[ -z "$udp_port" ]]; then
        echo -e "\e[1;33m创建新UDP端口...\e[0m"
        while :; do
            local new_port=$(shuf -i 10000-65535 -n 1)
            if devil port add udp $new_port | grep -q "Ok"; then
                udp_port=$new_port
                devil binexec on >/dev/null  # 启用二进制执行权限
                echo -e "\e[1;32m新端口创建成功：$udp_port\e[0m"
                break
            fi
        done
    fi
    export PORT=$udp_port
}
check_port

#######################################
# 架构检测与文件下载
#######################################
ARCH=$(uname -m)
echo -e "\e[1;36m检测系统架构：$ARCH\e[0m"

# 根据架构选择下载源
if [[ "$ARCH" =~ arm|aarch64 ]]; then
    BINARY_URL="https://github.com/eooce/test/releases/download/freebsd-arm64/hy2"
else
    BINARY_URL="https://github.com/eooce/test/releases/download/freebsd/hy2"
fi

# 下载固定文件名二进制文件
echo -e "\e[1;33m下载程序文件中...\e[0m"
if command -v curl &>/dev/null; then
    curl -sLo "$WORKDIR/hysteria" "$BINARY_URL"
elif command -v wget &>/dev/null; then
    wget -qO "$WORKDIR/hysteria" "$BINARY_URL"
else
    echo -e "\e[1;31m错误：需要curl或wget工具\e[0m"
    exit 1
fi

# 文件权限设置
chmod +x "$WORKDIR/hysteria"
echo -e "\e[1;32m程序文件下载完成\e[0m"

#######################################
# TLS证书生成
#######################################
echo -e "\e[1;36m生成TLS证书...\e[0m"
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
    -keyout "$WORKDIR/server.key" \
    -out "$WORKDIR/server.crt" \
    -subj "/CN=${CURRENT_DOMAIN}" \
    -days 36500

#######################################
# 服务配置生成
#######################################
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

#######################################
# 服务启动函数
#######################################
start_service() {
    echo -e "\e[1;36m启动主服务进程...\e[0m"
    nohup "$WORKDIR/hysteria" server "$WORKDIR/config.yaml" > /dev/null 2>&1 &
    sleep 2  # 等待进程初始化
    
    if ! pgrep -f "hysteria" >/dev/null; then
        echo -e "\e[1;31m服务启动失败！\e[0m"
        return 1
    fi
    return 0
}

#######################################
# 监控进程实现
#######################################
start_monitor() {
    # 持久化监控进程
    (
        while true; do
            sleep 60  # 每分钟检查一次
            
            # 进程状态检测
            if ! pgrep -f "hysteria" >/dev/null; then
                echo -e "\e[1;31m[监控] 检测到服务停止，尝试重启...\e[0m"
                
                # 第一次重启尝试
                if start_service; then
                    echo -e "\e[1;32m[监控] 重启成功\e[0m"
                    continue
                fi
                
                # 重启失败时重新安装
                echo -e "\e[1;31m[监控] 重启失败，触发重新安装...\e[0m"
                UUID="$UUID" bash -c "$(curl -sSL https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/hy.sh)"
                break  # 安装脚本会启动新实例
            fi
        done
    ) &
}

#######################################
# 主程序流程
#######################################
if start_service; then
    echo -e "\e[1;32m服务启动成功！\e[0m"
    start_monitor  # 启动监控后台进程
else
    echo -e "\e[1;31m服务初始化失败，请检查配置\e[0m"
    exit 1
fi

#######################################
# 输出配置信息
#######################################
echo -e "\n\e[1;35m======== 节点配置信息 ========\e[0m"
echo -e "协议类型：\e[1;33mHysteria2\e[0m"
echo -e "服务端口：\e[1;33m$PORT (UDP)\e[0m"
echo -e "连接密码：\e[1;33m$UUID\e[0m"
echo -e "订阅链接：\e[1;36mhttps://${USERNAME}.${CURRENT_DOMAIN}/$SUB_TOKEN\e[0m"
echo -e "\e[1;32m提示：服务监控进程已后台运行\e[0m"
