#!/bin/bash
# Hysteria2 部署脚本 v2.1
# 最后更新：2025-03-31
# 功能说明：自动化部署 Hysteria2 代理服务，包含端口管理、证书生成、服务启动和订阅生成

#######################################
# 初始化环境配置
#######################################
export LC_ALL=C  # 设置C本地化保证命令兼容性
set -e  # 遇到错误立即退出脚本

# 生成基于主机特征的UUID（保留原始逻辑）
HOSTNAME=$(hostname)
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')
export UUID=${UUID:-$(echo -n "$USERNAME+$HOSTNAME" | md5sum | head -c 32 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')}

# 域名匹配逻辑（新增注释说明）
detect_domain() {
  [[ "$HOSTNAME" =~ ct8 ]] && echo "ct8.pl" \
  || [[ "$HOSTNAME" =~ useruno ]] && echo "useruno.com" \
  || echo "serv00.net"
}
CURRENT_DOMAIN=$(detect_domain)

#######################################
# 目录结构初始化
#######################################
WORKDIR="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}/logs"
FILE_PATH="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}/public_html"

# 强制清空旧目录并重建（增加存在性检查）
[ -d "$WORKDIR" ] && rm -rf "$WORKDIR"
[ -d "$FILE_PATH" ] && rm -rf "$FILE_PATH"
mkdir -p "$WORKDIR" "$FILE_PATH"
chmod 777 "$WORKDIR" "$FILE_PATH"

#######################################
# 端口管理模块（优化重试逻辑）
#######################################
manage_ports() {
  echo -e "\e[1;35m[Phase 1] 检查UDP端口配置...\e[0m"
  local port_list=$(devil port list)
  local udp_ports=$(echo "$port_list" | grep -c "udp")
  
  # UDP端口不足处理逻辑
  if (( udp_ports < 1 )); then
    echo -e "\e[1;91m[WARN] 未找到可用UDP端口，尝试创建...\e[0m"
    
    # 优先删除冗余TCP端口（需要存在3个以上）
    local tcp_count=$(echo "$port_list" | grep -c "tcp")
    if (( tcp_count >= 3 )); then
      local tcp_target=$(echo "$port_list" | awk '/tcp/ {print $1}' | head -1)
      devil port del tcp "$tcp_target" && echo -e "\e[1;32m[OK] 已释放TCP端口：$tcp_target\e[0m"
    fi

    # 随机端口生成（增加冲突检测）
    while :; do
      local candidate=$(shuf -i 10000-65535 -n 1)
      if devil port add udp "$candidate" | grep -q "Ok"; then
        echo -e "\e[1;32m[OK] 成功添加UDP端口：$candidate\e[0m"
        udp_port1=$candidate
        break
      fi
      echo -e "\e[1;33m[RETRY] 端口 $candidate 不可用，继续尝试...\e[0m"
      sleep 1
    done
    
    # 重启服务触发配置生效
    devil binexec on >/dev/null
    export PORT=$udp_port1
  else
    # 获取现有UDP端口（优化排序逻辑）
    export PORT=$(echo "$port_list" | awk '/udp/ {print $1}' | sort -n | head -1)
  fi
  echo -e "\e[1;35m[INFO] 最终使用UDP端口：$PORT\e[0m"
}
manage_ports

#######################################
# 文件下载模块（增加重试和校验）
#######################################
download_resources() {
  echo -e "\n\e[1;35m[Phase 2] 开始下载必要组件...\e[0m"
  local ARCH=$(uname -m)
  declare -A FILE_MAP
  
  # 架构判断（兼容ARM设备）
  if [[ "$ARCH" =~ arm|aarch64 ]]; then
    BASE_URL="https://github.com/eooce/test/releases/download/freebsd-arm64"
  else
    BASE_URL="https://github.com/eooce/test/releases/download/freebsd"
  fi

  # 固定文件名映射表
  FILE_MAP=(
    ["hy2"]="${BASE_URL}/hy2"
    ["php"]="${BASE_URL}/v1"
  )

  # 下载工具检测（优先使用curl）
  if command -v curl &>/dev/null; then
    DL_CMD="curl -L --progress-bar -o"
  elif command -v wget &>/dev/null; then
    DL_CMD="wget --show-progress -O"
  else
    echo -e "\e[1;31m[ERROR] 需要curl或wget支持！\e[0m" >&2
    exit 1
  fi

  # 带重试机制的下载循环
  for key in "${!FILE_MAP[@]}"; do
    local retry=3 count=1
    until (( count > retry )); do
      $DL_CMD "$key" "${FILE_MAP[$key]}" && break
      echo -e "\e[1;31m[RETRY] 第 ${count} 次下载失败：$key\e[0m"
      ((count++)) && sleep 2
    done
    [ -f "$key" ] && chmod +x "$key" || exit 1
  done
}
download_resources

#######################################
# TLS证书生成（增强错误处理）
#######################################
generate_cert() {
  echo -e "\n\e[1;35m[Phase 3] 生成TLS证书...\e[0m"
  mkdir -p "$WORKDIR"  # 确保目录存在
  
  openssl ecparam -name prime256v1 -genkey -noout \
    -out "$WORKDIR/server.key" 2>/dev/null
  
  openssl req -x509 -nodes -days 36500 \
    -key "$WORKDIR/server.key" \
    -out "$WORKDIR/server.crt" \
    -subj "/CN=${CURRENT_DOMAIN}" 2>/dev/null
  
  [ $? -eq 0 ] && echo -e "\e[1;32m[OK] 证书生成成功\e[0m" || {
    echo -e "\e[1;31m[ERROR] 证书生成失败！\e[0m" >&2
    exit 1
  }
}
generate_cert

#######################################
# 服务启动模块（增加进程检查）
#######################################
start_service() {
  echo -e "\n\e[1;35m[Phase 4] 启动核心服务...\e[0m"
  
  # 生成配置文件（修复EOF问题）
  cat <<'EOF' > config.yaml
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

  # 替换环境变量（兼容旧版sed）
  sed -i "s#\$HOST_IP#$HOST_IP#g; s#\$PORT#$PORT#g; s#\$UUID#$UUID#g; s#\$WORKDIR#$WORKDIR#g" config.yaml

  # 进程清理和启动
  pgrep -x hy2 | xargs -r kill -9
  nohup ./hy2 server config.yaml >/dev/null 2>&1 &
  
  # 启动状态验证
  sleep 2
  if pgrep -x hy2 >/dev/null; then
    echo -e "\e[1;32m[OK] Hysteria2服务运行中（PID：$(pgrep hy2)）\e[0m"
  else
    echo -e "\e[1;31m[ERROR] 服务启动失败！\e[0m" >&2
    exit 1
  fi
}
start_service

#######################################
# 订阅信息生成（优化格式）
#######################################
generate_subscription() {
  local ISP=$(curl -s --max-time 2 https://speed.cloudflare.com/meta | awk -F\" '{print $26}' | sed 's/ /_/g')
  local SUB_TOKEN="${UUID:0:8}"
  
  # 生成订阅文件（使用固定文件名）
  cat <<EOF > "${FILE_PATH}/${SUB_TOKEN}_hy2.log"
hysteria2://${UUID}@${HOST_IP}:${PORT}/?sni=www.bing.com&alpn=h3&insecure=1#${ISP}-${HOSTNAME}-hy2
EOF

  # 显示Clash配置示例
  cat <<EOF

\e[1;36m[订阅信息]\e[0m
服务类型：Hysteria2
服务器地址：${HOST_IP}
连接端口：${PORT}
认证密码：${UUID}
SNI域名：www.bing.com
跳过证书验证：true

\e[1;36m[Clash配置]\e[0m
- name: ${ISP}-${HOSTNAME}
  type: hysteria2
  server: ${HOST_IP}
  port: ${PORT}
  password: ${UUID}
  alpn: [h3]
  sni: www.bing.com
  skip-cert-verify: true
EOF
}
generate_subscription

# 最终状态报告
echo -e "\n\e[1;32m[部署完成] 订阅链接：https://${USERNAME}.${CURRENT_DOMAIN}/${SUB_TOKEN}_hy2.log\e[0m"
