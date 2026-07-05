#!/bin/bash

R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; B='\033[1;34m'; C='\033[1;36m'; N='\033[0m'

CONF_DIR="/etc/mihomo"
DATA_DIR="/docker_data/mihomo"
GH_PROXY="https://git.woskee.nyc.mn/"

handle_error() { echo -e "${R}$1${N}"; exit 1; }

# ========================== 系统检测 ==========================
detect_os() {
  source /etc/os-release 2>/dev/null || handle_error "无法检测操作系统"
  OS=$ID
  [[ "$OS" =~ ^(debian|ubuntu|alpine)$ ]] || handle_error "仅支持 Debian/Ubuntu/Alpine"
  echo -e "${G}系统: $OS $VERSION_ID, 架构: $(uname -m)${N}"
}

# ========================== Docker 安装 ==========================
install_docker() {
  command -v docker &>/dev/null && echo -e "${G}Docker 已安装: $(docker --version)${N}" && return
  echo -e "${Y}安装 Docker...${N}"
  case $OS in
    alpine) apk update && apk add docker && rc-update add docker boot && service docker start ;;
    debian|ubuntu) curl -fsSL "${GH_PROXY}https://get.docker.com" | sh -s -- --mirror Aliyun && systemctl enable docker && systemctl start docker ;;
  esac
  command -v docker &>/dev/null || handle_error "Docker 安装失败"
  echo -e "${G}Docker 安装成功${N}"
}

# ========================== 基础工具 ==========================
ensure_tools() {
  local pm; [[ $OS == alpine ]] && pm="apk" || pm="apt-get"
  command -v curl &>/dev/null || { echo -e "${Y}安装 curl...${N}"; $pm install -y curl 2>/dev/null || true; }
  command -v tar &>/dev/null || { echo -e "${Y}安装 tar...${N}"; $pm install -y tar 2>/dev/null || true; }
}

# ========================== 配置检查 + 软链 ==========================
setup_config() {
  echo -e "\n${B}--- 检查配置 ---${N}"

  if [[ -d "$DATA_DIR" ]] && [[ -f "$DATA_DIR/config.yaml" ]]; then
    echo -e "${G}从 $DATA_DIR 检测到配置${N}"
    mkdir -p "$CONF_DIR"
    local linked=0
    for f in "$DATA_DIR"/*; do
      if [[ -f "$f" ]]; then
        ln -sf "$f" "$CONF_DIR/$(basename "$f")"
        echo -e "${G}  ✓ 已链接 $(basename "$f")${N}"
        linked=1
      fi
    done
    [[ $linked -eq 0 ]] && echo -e "${Y}  ⚠ DATA_DIR 中没有文件需要链接${N}"
    return 0
  fi

  if [[ -d "$CONF_DIR" ]] && [[ -f "$CONF_DIR/config.yaml" ]]; then
    echo -e "${G}使用现有 $CONF_DIR${N}"
    return 0
  fi

  # 需要下载
  echo -e "${Y}未检测到配置，开始下载...${N}"
  mkdir -p "$CONF_DIR/ruleset" "$CONF_DIR/ui"
  echo -e "${G}配置目录: $CONF_DIR${N}"

  dl() {
    local url=$1 out=$2 desc=$3
    echo -n "下载 $desc... "
    if curl -fsSL --connect-timeout 30 --max-time 120 "$url" -o "$out"; then
      echo -e "${G}✓${N}"; return 0
    fi
    echo -e "${R}✗${N}"; return 1
  }

  dl "https://git.luxxk.dpdns.org/raw.githubusercontent.com/tyy840913/mihomo-proxy/refs/heads/master/mihomo-docker/files/config.yaml" \
    "$CONF_DIR/config.yaml" "Mihomo 配置" || echo -e "${Y}  ⚠ 配置下载失败${N}"

  dl "https://git.luxxk.dpdns.org/raw.githubusercontent.com/tyy840913/backup/refs/heads/main/mihomo_config.sh" \
    "$CONF_DIR/user-script.sh" "用户脚本" && chmod +x "$CONF_DIR/user-script.sh" || true

  if [[ ! -f "$CONF_DIR/ui/index.html" ]]; then
    local tmpd=$(mktemp -d)
    if dl "https://git.luxxk.dpdns.org/github.com/MetaCubeX/metacubexd/releases/download/v1.187.1/compressed-dist.tgz" \
      "$tmpd/ui.tgz" "UI 面板"; then
      tar -xzf "$tmpd/ui.tgz" -C "$CONF_DIR/ui" && echo -e "${G}  ✓ UI 解压完成${N}"
    fi
    rm -rf "$tmpd"
  fi

  if [[ ! -f "$CONF_DIR/Country.mmdb" ]]; then
    for s in \
      "https://git.woskee.dpdns.org/github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb" \
      "https://git.woskee.dpdns.org/github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb"; do
      dl "$s" "$CONF_DIR/Country.mmdb" "GeoIP" && break
    done
  fi
}

# ========================== 启动容器 ==========================
start_container() {
  local host_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -z "$host_ip" ]] && host_ip=$(ip route get 1 2>/dev/null | awk '{print $7}' | head -1) || true

  setup_config

  echo -e "\n${B}--- 部署容器 ---${N}"

  # 先尝试 host 网络
  echo -e "${C}尝试 host 网络模式...${N}"
  if docker run -d --name=mihomo --restart=unless-stopped --network=host \
    -v "$CONF_DIR:/root/.config/mihomo" \
    -v "$DATA_DIR:$DATA_DIR" metacubex/mihomo:latest &>/dev/null; then
    sleep 5
    if docker ps --filter "name=mihomo" --format "{{.Status}}" | grep -q "Up"; then
      echo -e "${G}  ✓ host 模式启动成功${N}"
      print_info "$host_ip"; return
    fi
  fi

  # host 失败则桥接
  echo -e "${Y}host 失败，尝试桥接模式...${N}"
  if docker run -d --name=mihomo --restart=unless-stopped \
    -p 7890:7890 -p 7891:7891 -p 7892:7892 -p 9090:9090 \
    -v "$CONF_DIR:/root/.config/mihomo" \
    -v "$DATA_DIR:$DATA_DIR" metacubex/mihomo:latest &>/dev/null; then
    sleep 5
    if docker ps --filter "name=mihomo" --format "{{.Status}}" | grep -q "Up"; then
      echo -e "${G}  ✓ 桥接模式启动成功${N}"
      print_info "$host_ip"; return
    fi
  fi

  handle_error "启动失败: $(docker logs mihomo --tail 20 2>/dev/null)"
}

print_info() {
  local ip=$1
  echo -e "${G}  ✓ 控制面板: http://$ip:9090/ui${N}"
  echo -e "${G}  ✓ 混合代理: $ip:7890${N}"
  echo -e "${G}  ✓ HTTP 代理: $ip:7891${N}"
  echo -e "${G}  ✓ SOCKS代理: $ip:7892${N}"
}

# ========================== 安装 ==========================
cmd_install() {
  echo -e "\n${C}══════════ 开始安装 ══════════${N}"
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^mihomo$"; then
    printf "${Y}已检测到 mihomo 容器，是否重新安装？[y/N]: ${N}"
    read -r reinstall
    [[ ! "$reinstall" =~ ^[yY] ]] && echo -e "${Y}已取消${N}" && return
    echo -e "${C}→ 删除旧容器...${N}"
    docker stop mihomo 2>/dev/null || true
    docker rm mihomo 2>/dev/null || true
  fi
  detect_os
  echo -e "${C}→ 检测工具...${N}"; ensure_tools
  echo -e "${C}→ Docker...${N}"; install_docker
  echo -e "${C}→ 启动容器...${N}"; start_container
  echo -e "\n${G}══════════ 安装完成 ══════════${N}"
}

# ========================== 状态检查 ==========================
check_status() {
  local host_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -z "$host_ip" ]] && host_ip=$(ip route get 1 2>/dev/null | awk '{print $7}' | head -1) || true
  local iface=$(ip route | grep default | awk '{print $5}' | head -1)

  echo -e "\n${G}========== Mihomo 状态 ==========${N}"
  echo -e "IP: ${G}$host_ip${N}, 接口: ${G}$iface${N}"

  if command -v docker &>/dev/null; then
    echo -e "Docker: ${G}已安装${N}"
    local docker_up=false
    if command -v systemctl &>/dev/null; then
      systemctl is-active --quiet docker 2>/dev/null && docker_up=true
    elif command -v rc-service &>/dev/null; then
      rc-service docker status &>/dev/null && docker_up=true
    elif command -v service &>/dev/null; then
      service docker status &>/dev/null && docker_up=true
    fi
    $docker_up && echo -e "Docker 服务: ${G}运行中${N}" \
              || echo -e "Docker 服务: ${R}未运行${N}"
  else
    echo -e "Docker: ${R}未安装${N}"; return
  fi

  local cid=$(docker ps -q --filter name=mihomo 2>/dev/null) || true
  if [[ -n "$cid" ]]; then
    local nm=$(docker inspect mihomo --format '{{.HostConfig.NetworkMode}}' 2>/dev/null) || true
    local sa=$(docker inspect -f '{{.State.StartedAt}}' mihomo 2>/dev/null) || true
    local sec=0
    [[ -n "$sa" ]] && sec=$(( $(date +%s) - $(date -d "$sa" +%s) )) 2>/dev/null || true
    echo -e "容器: ${G}运行中${N} | 网络: ${G}$nm${N}"
    echo -e "运行: $((sec/86400))d $((sec%86400/3600))h $((sec%3600/60))m"
  else
    local aid=$(docker ps -aq --filter name=mihomo 2>/dev/null) || true
    if [[ -n "$aid" ]]; then
      echo -e "容器: ${Y}已停止${N}"
      docker start mihomo &>/dev/null && echo -e "${G}  ✓ 已启动${N}" || echo -e "${Y}  ⚠ 启动失败${N}"
    else
      echo -e "容器: ${R}不存在${N}"
    fi
  fi

  curl -s -m 3 http://127.0.0.1:9090 &>/dev/null \
    && echo -e "面板: ${G}可访问 http://$host_ip:9090/ui${N}" \
    || echo -e "面板: ${R}无法访问${N}"

  [[ -f "$CONF_DIR/config.yaml" ]] && \
    echo -e "配置: ${G}已存在${N}" || echo -e "配置: ${R}不存在${N}"

  echo -e "${G}==============================${N}"
}

# ========================== 主入口 ==========================
case "${1:-menu}" in
  install|i)   cmd_install ;;
  status|st)   check_status ;;
  restart)     docker restart mihomo && echo -e "${G}已重启${N}" ;;
  logs)        docker logs --tail 50 -f mihomo 2>/dev/null || echo -e "${R}容器不存在${N}" ;;
  *)
    if docker ps -q --filter name=mihomo 2>/dev/null | grep -q .; then
      while true; do
        clear
        echo -e "${C}===== Mihomo 管理 =====${N}"
        echo " 1) 重新部署容器"
        echo " 2) 状态检查"
        echo " 3) 重启容器"
        echo " 4) 查看日志"
        echo " 0) 退出"
        read -p "请选择： " ch
        case "$ch" in
          1) cmd_install ;;
          2) check_status ;;
          3) docker restart mihomo && echo -e "${G}已重启${N}" ;;
          4) docker logs --tail 50 -f mihomo 2>/dev/null ;;
          0) exit 0 ;;
        esac
        read -p "按回车键继续..."
      done
    else
      cmd_install
    fi
    ;;
esac