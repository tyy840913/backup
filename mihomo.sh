#!/bin/bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; PLAIN='\033[0m'

CONF_DIR="/etc/mihomo"
TEMPLATE_URL="https://cdn.luxxk.dpdns.org/raw.githubusercontent.com/tyy840913/backup/refs/heads/main/mihomo_config.yaml"
CONFIG_URL="https://git.luxxk.dpdns.org/raw.githubusercontent.com/tyy840913/mihomo-proxy/refs/heads/master/mihomo-docker/files/config.yaml"
SUB_URL="http://127.0.0.1:8199/sub/mihomo.yaml"
BACKUP_URL="https://backup.woskee.dpdns.org"
GIT_RAW="https://cdn.woskee.dpdns.org/raw.githubusercontent.com/tyy840913/backup/refs/heads/main"
UI_VERSION="v1.187.1"

handle_error() { echo -e "${RED}$1${PLAIN}"; exit 1; }

# ========================== 系统检测 ==========================
detect_os() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release; OS=$ID; VER=$VERSION_ID
  else
    handle_error "无法检测操作系统"
  fi
  [[ "$OS" =~ ^(debian|ubuntu|alpine)$ ]] || handle_error "仅支持 Debian/Ubuntu/Alpine"
  echo -e "${GREEN}系统: $OS $VER, 架构: $(uname -m)${PLAIN}"
}

# ========================== Docker 检查/安装 ==========================
ensure_docker() {
  if command -v docker &>/dev/null; then
    echo -e "${GREEN}Docker 已安装: $(docker --version)${PLAIN}"
    return
  fi
  echo -e "${YELLOW}安装 Docker...${PLAIN}"
  case $OS in
    alpine)
      apk update && apk add docker docker-compose
      rc-update add docker boot && service docker start
      ;;
    debian|ubuntu)
      curl -fsSL https://get.docker.com | sh
      systemctl enable docker && systemctl start docker
      ;;
  esac
  command -v docker &>/dev/null || handle_error "Docker 安装失败"
  echo -e "${GREEN}Docker 安装成功${PLAIN}"
}

# ========================== 基础工具 ==========================
ensure_tools() {
  local tools=(curl wget)
  local pm; [[ $OS == alpine ]] && pm="apk" || pm="apt-get"
  for t in "${tools[@]}"; do
    command -v "$t" &>/dev/null && continue
    echo -e "${YELLOW}安装 $t...${PLAIN}"
    $pm install -y "$t" 2>/dev/null || $pm update && $pm install -y "$t" 2>/dev/null || true
  done
  [[ $OS == alpine ]] && ! command -v crontab &>/dev/null && {
    apk add cronie; rc-update add crond boot; service crond start
  }
}

# ========================== 目录创建 ==========================
create_dirs() {
  mkdir -p "$CONF_DIR/ruleset" "$CONF_DIR/ui"
  echo -e "${GREEN}配置目录已创建: $CONF_DIR${PLAIN}"
}

# ========================== 下载函数 ==========================
dl() {
  local url=$1 out=$2 desc=$3
  echo -e "${YELLOW}下载 $desc...${PLAIN}"
  if curl -fsSL --connect-timeout 30 --max-time 120 "$url" -o "$out"; then
    echo -e "${GREEN}  ✓ $desc${PLAIN}"; return 0
  fi
  echo -e "${RED}  ✗ $desc 失败${PLAIN}"; return 1
}

# ========================== 下载配置 ==========================
download_config() {
  if [[ -f "$CONF_DIR/config.yaml" ]]; then
    echo -e "${YELLOW}config.yaml 已存在，跳过${PLAIN}"
    return
  fi
  dl "$CONFIG_URL" "$CONF_DIR/config.yaml" "Mihomo 配置"
}

# ========================== 下载 UI ==========================
download_ui() {
  [[ -f "$CONF_DIR/ui/index.html" ]] && { echo -e "${YELLOW}UI 已存在，跳过${PLAIN}"; return; }
  local tmpd; tmpd=$(mktemp -d)
  local u="https://git.luxxk.dpdns.org/github.com/MetaCubeX/metacubexd/releases/download/$UI_VERSION/compressed-dist.tgz"
  if dl "$u" "$tmpd/ui.tgz" "UI 面板"; then
    tar -xzf "$tmpd/ui.tgz" -C "$CONF_DIR/ui" && echo -e "${GREEN}  ✓ UI 解压完成${PLAIN}"
  fi
  rm -rf "$tmpd"
}

# ========================== 下载 GeoIP ==========================
download_geoip() {
  [[ -f "$CONF_DIR/Country.mmdb" ]] && { echo -e "${YELLOW}GeoIP 已存在，跳过${PLAIN}"; return; }
  local sources=(
    "https://git.woskee.dpdns.org/github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb"
    "https://git.woskee.dpdns.org/github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb"
  )
  for s in "${sources[@]}"; do
    dl "$s" "$CONF_DIR/Country.mmdb" "GeoIP" && return
  done
  echo -e "${YELLOW}  所有 GeoIP 源失败，容器启动时会自动下载${PLAIN}"
}

# ========================== 启动容器 ==========================
start_container() {
  docker stop mihomo 2>/dev/null; docker rm mihomo 2>/dev/null
  local host_ip; host_ip=$(hostname -I | awk '{print $1}')
  [[ -z "$host_ip" ]] && host_ip=$(ip route get 1 | awk '{print $7}' | head -1)

  # host 模式
  echo -e "${CYAN}尝试 host 网络模式...${PLAIN}"
  if docker run -d --name=mihomo --restart=unless-stopped --network=host \
    -v "$CONF_DIR:/root/.config/mihomo" metacubex/mihomo:latest &>/dev/null; then
    sleep 5
    if docker ps --filter "name=mihomo" --format "{{.Status}}" | grep -q "Up"; then
      echo -e "${GREEN}  ✓ host 模式启动成功${PLAIN}"
      print_info "$host_ip"; return
    fi
  fi

  # 桥接模式
  echo -e "${YELLOW}host 失败，尝试桥接模式...${PLAIN}"
  if docker run -d --name=mihomo --restart=unless-stopped \
    -p 7890:7890 -p 7891:7891 -p 7892:7892 -p 9090:9090 \
    -v "$CONF_DIR:/root/.config/mihomo" docker.lms.run/metacubex/mihomo:latest &>/dev/null; then
    sleep 5
    if docker ps --filter "name=mihomo" --format "{{.Status}}" | grep -q "Up"; then
      echo -e "${GREEN}  ✓ 桥接模式启动成功${PLAIN}"
      print_info "$host_ip"; return
    fi
  fi

  handle_error "容器启动失败，日志: $(docker logs mihomo --tail 20 2>/dev/null)"
}

print_info() {
  local ip=$1
  echo -e "${GREEN}  ✓ 服务运行正常${PLAIN}"
  echo -e "${GREEN}  ✓ 控制面板: http://$ip:9090/ui${PLAIN}"
  echo -e "${GREEN}  ✓ 混合代理: $ip:7890${PLAIN}"
  echo -e "${GREEN}  ✓ HTTP 代理: $ip:7891${PLAIN}"
  echo -e "${GREEN}  ✓ SOCKS代理: $ip:7892${PLAIN}"
}

# ========================== 合并配置 ==========================
merge_config() {
  echo -e "${CYAN}合并配置文件...${PLAIN}"
  local tmp_top; tmp_top=$(mktemp); tmp_btm=$(mktemp)
  trap 'rm -f "$tmp_top" "$tmp_btm"' EXIT

  if [[ ! -f "$CONF_DIR/mihomo_config.yaml" ]]; then
    dl "$TEMPLATE_URL" "$CONF_DIR/mihomo_config.yaml" "配置模板"
  fi

  dl "$SUB_URL" "$tmp_btm" "订阅配置" || handle_error "订阅下载失败，检查 subs 服务是否运行"

  cat "$CONF_DIR/mihomo_config.yaml" > "$CONF_DIR/config.yaml"
  echo "" >> "$CONF_DIR/config.yaml"
  cat "$tmp_btm" >> "$CONF_DIR/config.yaml"
  echo -e "${GREEN}  ✓ 配置合并完成: $CONF_DIR/config.yaml${PLAIN}"

  command -v docker &>/dev/null && docker ps -a --format '{{.Names}}' | grep -q "^mihomo$" && {
    echo -e "${YELLOW}重启 mihomo 容器...${PLAIN}"; docker restart mihomo
  }
}

# ========================== 三合一配置合并 ==========================
merge_config_3way() {
  echo -e "${CYAN}三合一合并配置...${PLAIN}"
  local p1 p2 p3; p1=$(mktemp); p2=$(mktemp); p3=$(mktemp)
  trap 'rm -f "$p1" "$p2" "$p3"' EXIT

  dl "$GIT_RAW/mihomo/config.yaml" "$p1" "基础配置" || handle_error "下载失败"
  dl "https://sub.woskee.nyc.mn/auto?clash" "$p2" "代理节点" || handle_error "下载失败"
  dl "$TEMPLATE_URL" "$p3" "规则配置" || handle_error "下载失败"

  # 提取 proxies 部分
  awk 'BEGIN{p=0} /^proxies:/{p=1;print;next} /^[a-z]/ && !/^[ \t]/ && !/^proxies:/{p=0} p{print}' "$p2" > "${p2}.p"
  mv "${p2}.p" "$p2"

  cat "$p1" > "$CONF_DIR/config.yaml"
  echo -e "\n# ===== 代理节点 =====\n" >> "$CONF_DIR/config.yaml"
  cat "$p2" >> "$CONF_DIR/config.yaml"
  echo -e "\n# ===== 规则 =====\n" >> "$CONF_DIR/config.yaml"
  cat "$p3" >> "$CONF_DIR/config.yaml"
  echo -e "${GREEN}  ✓ 配置合并完成 (3合1)${PLAIN}"
}

# ========================== 状态检查 ==========================
check_status() {
  local host_ip; host_ip=$(hostname -I | awk '{print $1}')
  [[ -z "$host_ip" ]] && host_ip=$(ip route get 1 | awk '{print $7}' | head -1)
  local iface; iface=$(ip route | grep default | awk '{print $5}' | head -1)

  echo -e "${GREEN}============ Mihomo 状态 ============${PLAIN}"
  echo -e "IP: ${GREEN}$host_ip${PLAIN}, 接口: ${GREEN}$iface${PLAIN}"

  # Docker
  if command -v docker &>/dev/null; then
    echo -e "Docker: ${GREEN}已安装${PLAIN}"
    systemctl is-active --quiet docker 2>/dev/null && echo -e "Docker 服务: ${GREEN}运行中${PLAIN}" || echo -e "Docker 服务: ${RED}未运行${PLAIN}"
  else
    echo -e "Docker: ${RED}未安装${PLAIN}"; return
  fi

  # 容器
  if docker ps | grep -q mihomo; then
    local cid; cid=$(docker ps | grep mihomo | awk '{print $1}')
    local nm; nm=$(docker inspect mihomo --format '{{.HostConfig.NetworkMode}}' 2>/dev/null)
    local sa; sa=$(docker inspect -f '{{.State.StartedAt}}' mihomo 2>/dev/null)
    local sec=$(( $(date +%s) - $(date -d "$sa" +%s) ))
    echo -e "容器: ${GREEN}运行中${PLAIN}, ID: ${GREEN}$cid${PLAIN}, 网络: ${GREEN}$nm${PLAIN}"
    echo -e "运行: $((sec/86400))d $((sec%86400/3600))h $((sec%3600/60))m"
  else
    echo -e "容器: ${RED}未运行${PLAIN}"
    docker ps -a | grep -q mihomo && docker start mihomo 2>/dev/null && echo -e "${GREEN}已启动${PLAIN}" || true
    return
  fi

  # 控制面板
  curl -s -m 3 http://127.0.0.1:9090/ui &>/dev/null \
    && echo -e "面板: ${GREEN}可访问 http://$host_ip:9090/ui${PLAIN}" \
    || echo -e "面板: ${RED}无法访问${PLAIN}"

  # 配置文件
  if [[ -f "$CONF_DIR/config.yaml" ]]; then
    echo -e "配置: ${GREEN}已存在${PLAIN}"
    grep -q "external-controller:" "$CONF_DIR/config.yaml" && echo -e "  控制器: $(grep "external-controller:" "$CONF_DIR/config.yaml" | head -1 | xargs)" || echo -e "  控制器: ${YELLOW}未配置${PLAIN}"
    grep -q "bind-address:" "$CONF_DIR/config.yaml" && echo -e "  绑定: $(grep "bind-address:" "$CONF_DIR/config.yaml" | head -1 | xargs)" || echo -e "  绑定: ${YELLOW}未配置${PLAIN}"
  else
    echo -e "配置: ${RED}不存在${PLAIN}"
  fi

  echo -e "${GREEN}============ 检查完毕 ============${PLAIN}"
}

# ========================== 备份 ==========================
backup() {
  local user pass
  read -p "用户名: " user
  read -s -p "密码: " pass; echo

  local f="/tmp/mihomo-backup.tar.gz"
  tar -czf "$f" -C /etc mihomo
  curl -u "$user:$pass" -T "$f" "$BACKUP_URL/update/mihomo" && echo -e "${GREEN}备份上传成功${PLAIN}" || echo -e "${RED}上传失败${PLAIN}"
  rm -f "$f"
}

restore() {
  local user pass
  read -p "用户名: " user
  read -s -p "密码: " pass; echo

  local f="/tmp/mihomo-restore.tar.gz"
  curl -u "$user:$pass" -f -o "$f" "$BACKUP_URL/mihomo" || handle_error "下载失败"
  tar -xzf "$f" -C /etc
  echo -e "${GREEN}备份恢复成功${PLAIN}"
  rm -f "$f"
}

# ========================== 安装 ==========================
cmd_install() {
  detect_os
  ensure_tools
  ensure_docker
  create_dirs
  download_config
  download_ui
  download_geoip
  start_container
  echo -e "\n${GREEN}====== 安装完成 ======${PLAIN}"
}

# ========================== 主入口 ==========================
case "${1:-help}" in
  install|i)   cmd_install ;;
  status|st)   check_status ;;
  restart)     docker restart mihomo && echo -e "${GREEN}已重启${PLAIN}" ;;
  config|c)    merge_config ;;
  config3|c3)  merge_config_3way ;;
  reset)
    rm -f "$CONF_DIR/config.yaml"
    download_config
    start_container
    echo -e "${GREEN}配置已重置${PLAIN}"
    ;;
  backup|bak)
    backup
    ;;
  restore|rec)
    restore
    ;;
  ui)
    rm -f "$CONF_DIR/ui/index.html"
    download_ui
    ;;
  geoip)
    rm -f "$CONF_DIR/Country.mmdb"
    download_geoip
    ;;
  *)
    echo -e "${CYAN}用法: $0 <命令>${PLAIN}"
    echo -e "  install   完整安装（默认）"
    echo -e "  status/st 状态检查"
    echo -e "  restart   重启容器"
    echo -e "  config/c  合并配置（基础+订阅）"
    echo -e "  config3   三合一合并（基础+代理+规则）"
    echo -e "  reset     重置配置并重启"
    echo -e "  backup    备份并上传"
    echo -e "  restore   从备份恢复"
    echo -e "  ui        重新下载 UI"
    echo -e "  geoip     重新下载 GeoIP"
    ;;
esac
