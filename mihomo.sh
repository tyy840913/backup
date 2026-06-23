#!/bin/bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; PLAIN='\033[0m'
CONF_DIR="/etc/mihomo"

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

# ========================== Docker 安装 ==========================
install_docker() {
  if command -v docker &>/dev/null; then
    echo -e "${GREEN}Docker 已安装: $(docker --version)${PLAIN}"
    return
  fi
  echo -e "${YELLOW}安装 Docker...${PLAIN}"
  case $OS in
    alpine) apk update && apk add docker docker-compose
      rc-update add docker boot && service docker start ;;
    debian|ubuntu) curl -fsSL https://get.docker.com | sh
      systemctl enable docker && systemctl start docker ;;
  esac
  command -v docker &>/dev/null || handle_error "Docker 安装失败"
  echo -e "${GREEN}Docker 安装成功${PLAIN}"
}

# ========================== 基础工具 ==========================
ensure_tools() {
  local pm; [[ $OS == alpine ]] && pm="apk" || pm="apt-get"
  command -v curl &>/dev/null || { echo -e "${YELLOW}安装 curl...${PLAIN}"; $pm install -y curl 2>/dev/null || true; }
  command -v wget &>/dev/null || { echo -e "${YELLOW}安装 wget...${PLAIN}"; $pm install -y wget 2>/dev/null || true; }
  if [[ $OS == alpine ]] && ! command -v crontab &>/dev/null; then
    apk add cronie; rc-update add crond boot; service crond start
  fi
}

# ========================== 目录创建 ==========================
create_dirs() {
  mkdir -p "$CONF_DIR/ruleset" "$CONF_DIR/ui"
  echo -e "${GREEN}配置目录: $CONF_DIR${PLAIN}"
}

# ========================== 下载 ==========================
dl() {
  local url=$1 out=$2 desc=$3
  echo -e "${YELLOW}下载 $desc...${PLAIN}"
  if curl -fsSL --connect-timeout 30 --max-time 120 "$url" -o "$out"; then
    echo -e "${GREEN}  ✓ $desc${PLAIN}"; return 0
  fi
  echo -e "${RED}  ✗ $desc 失败${PLAIN}"; return 1
}

download_config() {
  [[ -f "$CONF_DIR/config.yaml" ]] && { echo -e "${YELLOW}config.yaml 已存在，跳过${PLAIN}"; return; }
  dl "https://git.luxxk.dpdns.org/raw.githubusercontent.com/tyy840913/mihomo-proxy/refs/heads/master/mihomo-docker/files/config.yaml" \
    "$CONF_DIR/config.yaml" "Mihomo 配置" || echo -e "${YELLOW}  ⚠ 配置下载失败，可手动放置${PLAIN}"
}

download_user_script() {
  local t="$CONF_DIR/user-script.sh"
  [[ -f "$t" ]] && { echo -e "${YELLOW}user-script.sh 已存在，跳过${PLAIN}"; return; }
  dl "https://git.luxxk.dpdns.org/raw.githubusercontent.com/tyy840913/backup/refs/heads/main/mihomo_config.sh" "$t" "用户脚本" \
    && chmod +x "$t" || true
}

download_ui() {
  [[ -f "$CONF_DIR/ui/index.html" ]] && { echo -e "${YELLOW}UI 已存在，跳过${PLAIN}"; return; }
  local tmpd; tmpd=$(mktemp -d)
  if dl "https://git.luxxk.dpdns.org/github.com/MetaCubeX/metacubexd/releases/download/v1.187.1/compressed-dist.tgz" \
    "$tmpd/ui.tgz" "UI 面板"; then
    tar -xzf "$tmpd/ui.tgz" -C "$CONF_DIR/ui" && echo -e "${GREEN}  ✓ UI 解压完成${PLAIN}"
  fi
  rm -rf "$tmpd"
}

download_geoip() {
  [[ -f "$CONF_DIR/Country.mmdb" ]] && { echo -e "${YELLOW}GeoIP 已存在，跳过${PLAIN}"; return; }
  for s in \
    "https://git.woskee.dpdns.org/github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country.mmdb" \
    "https://git.woskee.dpdns.org/github.com/Loyalsoldier/geoip/releases/latest/download/Country.mmdb"; do
    dl "$s" "$CONF_DIR/Country.mmdb" "GeoIP" && return
  done
  echo -e "${YELLOW}所有 GeoIP 源失败，容器启动时会自动下载${PLAIN}"
}

# ========================== 启动容器 ==========================
start_container() {
  docker stop mihomo 2>/dev/null || true; docker rm mihomo 2>/dev/null || true
  local host_ip; host_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -z "$host_ip" ]] && host_ip=$(ip route get 1 2>/dev/null | awk '{print $7}' | head -1) || true

  echo -e "${CYAN}尝试 host 网络...${PLAIN}"
  if docker run -d --name=mihomo --restart=unless-stopped --network=host \
    -v "$CONF_DIR:/root/.config/mihomo" metacubex/mihomo:latest &>/dev/null; then
    sleep 5
    if docker ps --filter "name=mihomo" --format "{{.Status}}" | grep -q "Up"; then
      echo -e "${GREEN}  ✓ host 启动成功${PLAIN}"
      print_info "$host_ip"; return
    fi
  fi

  echo -e "${YELLOW}host 失败，尝试桥接模式...${PLAIN}"
  if docker run -d --name=mihomo --restart=unless-stopped \
    -p 7890:7890 -p 7891:7891 -p 7892:7892 -p 9090:9090 \
    -v "$CONF_DIR:/root/.config/mihomo" docker.lms.run/metacubex/mihomo:latest &>/dev/null; then
    sleep 5
    if docker ps --filter "name=mihomo" --format "{{.Status}}" | grep -q "Up"; then
      echo -e "${GREEN}  ✓ 桥接启动成功${PLAIN}"
      print_info "$host_ip"; return
    fi
  fi

  handle_error "启动失败: $(docker logs mihomo --tail 20 2>/dev/null)"
}

print_info() {
  local ip=$1
  echo -e "${GREEN}  ✓ 控制面板: http://$ip:9090/ui${PLAIN}"
  echo -e "${GREEN}  ✓ 混合代理: $ip:7890${PLAIN}"
  echo -e "${GREEN}  ✓ HTTP 代理: $ip:7891${PLAIN}"
  echo -e "${GREEN}  ✓ SOCKS代理: $ip:7892${PLAIN}"
}

# ========================== 设置定时任务 ==========================
setup_cron() {
  local cron_job
  if [[ $OS == alpine ]]; then
    cron_job="0 8 * * * /bin/sh $CONF_DIR/mihomo.sh config && docker restart mihomo >/dev/null 2>&1"
  else
    cron_job="0 8 * * * /usr/bin/bash $CONF_DIR/mihomo.sh config && docker restart mihomo >/dev/null 2>&1"
  fi
  local current; current=$(crontab -l 2>/dev/null || true)
  if ! echo "$current" | grep -Fq "/etc/mihomo/mihomo.sh"; then
    (echo "$current"; echo "$cron_job") | grep -v '^$' | crontab -
    echo -e "${GREEN}定时任务已添加（每日 8:00）${PLAIN}"
  else
    echo -e "${YELLOW}定时任务已存在，跳过${PLAIN}"
  fi
}

# ========================== 安装 ==========================
cmd_install() {
  echo -e "\n${CYAN}══════════ 开始完整安装 ══════════${PLAIN}"
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^mihomo$"; then
    printf "${YELLOW}已检测到 mihomo 容器，是否重新安装？[y/N]: ${PLAIN}"
    read -r reinstall
    if [[ "$reinstall" =~ ^[yY] ]]; then
      echo -e "${CYAN}→ 删除旧容器...${PLAIN}"
      docker stop mihomo 2>/dev/null || true
      docker rm mihomo 2>/dev/null || true
    else
      echo -e "${YELLOW}已取消安装${PLAIN}"
      return
    fi
  fi
  detect_os
  echo -e "${CYAN}→ 检测工具...${PLAIN}"; ensure_tools
  echo -e "${CYAN}→ Docker...${PLAIN}"; install_docker
  echo -e "${CYAN}→ 创建目录...${PLAIN}"; create_dirs
  echo -e "${CYAN}→ 下载配置...${PLAIN}"; download_config
  echo -e "${CYAN}→ 下载用户脚本...${PLAIN}"; download_user_script
  echo -e "${CYAN}→ 下载 UI 面板...${PLAIN}"; download_ui
  echo -e "${CYAN}→ 下载 GeoIP...${PLAIN}"; download_geoip
  echo -e "${CYAN}→ 设置定时任务...${PLAIN}"; setup_cron
  echo -e "${CYAN}→ 启动容器...${PLAIN}"; start_container
  echo -e "\n${GREEN}══════════ 安装完成 ══════════${PLAIN}"
}

# ========================== 状态检查 ==========================
check_status() {
  local host_ip; host_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  [[ -z "$host_ip" ]] && host_ip=$(ip route get 1 2>/dev/null | awk '{print $7}' | head -1) || true
  local iface; iface=$(ip route | grep default | awk '{print $5}' | head -1)

  echo -e "${GREEN}========== Mihomo 状态 ==========${PLAIN}"
  echo -e "IP: ${GREEN}$host_ip${PLAIN}, 接口: ${GREEN}$iface${PLAIN}"

  if command -v docker &>/dev/null; then
    echo -e "Docker: ${GREEN}已安装${PLAIN}"
    systemctl is-active --quiet docker 2>/dev/null && echo -e "Docker 服务: ${GREEN}运行中${PLAIN}" \
      || echo -e "Docker 服务: ${RED}未运行${PLAIN}"
  else
    echo -e "Docker: ${RED}未安装${PLAIN}"; return
  fi

  local cid; cid=$(docker ps -q --filter name=mihomo 2>/dev/null) || true
  if [[ -n "$cid" ]]; then
    local nm; nm=$(docker inspect mihomo --format '{{.HostConfig.NetworkMode}}' 2>/dev/null) || true
    local sa; sa=$(docker inspect -f '{{.State.StartedAt}}' mihomo 2>/dev/null) || true
    local sec=0
    if [[ -n "$sa" ]]; then
      sec=$(( $(date +%s) - $(date -d "$sa" +%s) )) 2>/dev/null || true
    fi
    echo -e "容器: ${GREEN}运行中${PLAIN} | ID: ${GREEN}$cid${PLAIN} | 网络: ${GREEN}$nm${PLAIN}"
    echo -e "运行: $((sec/86400))d $((sec%86400/3600))h $((sec%3600/60))m"
  else
    local aid; aid=$(docker ps -aq --filter name=mihomo 2>/dev/null) || true
    if [[ -n "$aid" ]]; then
      echo -e "容器: ${YELLOW}已停止${PLAIN}"
      docker start mihomo &>/dev/null && echo -e "${GREEN}  ✓ 已启动${PLAIN}" || echo -e "${YELLOW}  ⚠ 启动失败${PLAIN}"
    else
      echo -e "容器: ${RED}不存在${PLAIN}"
    fi
  fi

  curl -s -m 3 http://127.0.0.1:9090/ui &>/dev/null \
    && echo -e "面板: ${GREEN}可访问 http://$host_ip:9090/ui${PLAIN}" \
    || echo -e "面板: ${RED}无法访问${PLAIN}"

  if [[ -f "$CONF_DIR/config.yaml" ]]; then
    echo -e "配置: ${GREEN}已存在${PLAIN}"
    if grep -q "external-controller:" "$CONF_DIR/config.yaml"; then
      local cip; cip=$(grep "external-controller:" "$CONF_DIR/config.yaml" | awk -F':' '{print $2}' | awk -F':' '{print $1}' | tr -d ' ')
      if [[ "$cip" == "127.0.0.1" || "$cip" == "0.0.0.0" ]]; then
        echo -e "  控制器: ${GREEN}配置正确 ($cip)${PLAIN}"
      else
        echo -e "  控制器: ${YELLOW}$cip (建议 127.0.0.1/0.0.0.0)${PLAIN}"
      fi
    else
      echo -e "  控制器: ${RED}未配置 external-controller${PLAIN}"
    fi
    if grep -q "bind-address:" "$CONF_DIR/config.yaml"; then
      local ba; ba=$(grep "bind-address:" "$CONF_DIR/config.yaml" | awk '{print $2}' | tr -d '"' | tr -d "'")
      echo -e "  绑定地址: ${GREEN}$ba${PLAIN}"
    else
      echo -e "  绑定地址: ${YELLOW}未配置${PLAIN}"
    fi
  else
    echo -e "配置: ${RED}不存在${PLAIN}"
  fi

  echo -e "${GREEN}========== 检查完毕 ==========${PLAIN}"
}

# ========================== 重置 ==========================
cmd_reset() {
  rm -f "$CONF_DIR/config.yaml" "$CONF_DIR/Country.mmdb"
  download_config
  download_geoip
  start_container
  echo -e "${GREEN}配置已重置${PLAIN}"
}

# ========================== 交互菜单 ==========================
show_menu() {
  local W=38 hl
  hl=$(printf '═%.0s' $(seq 1 $W) 2>/dev/null) || hl=$(printf '%*s' $W '' | tr ' ' '═')
  while true; do
    printf "\e[36m╔%s╗\e[0m\n" "$hl"
    printf "\e[36m║\e[0m%*s\e[36m%s\e[0m%*s\e[36m║\e[0m\n" \
      $(( (W-$(echo "Mihomo 管理菜单" | wc -L))/2 )) "" "Mihomo 管理菜单" \
      $(( W - (W-$(echo "Mihomo 管理菜单" | wc -L))/2 - $(echo "Mihomo 管理菜单" | wc -L) )) ""
    printf "\e[36m╠%s╣\e[0m\n" "$hl"
    for i in "1. 完整安装" "2. 状态检查" "3. 重启容器" "4. 重置配置" "0. 退出"; do
      local d; d=$(echo "$i" | wc -L)
      printf "\e[36m║\e[0m %s%*s\e[36m║\e[0m\n" "$i" $((W-2-d)) ""
    done
    printf "\e[36m╚%s╝\e[0m\n" "$hl"
    printf "${YELLOW}请选择 [0-4]: ${PLAIN}"
    read -r choice
    case $choice in
      1) cmd_install ;;
      2) check_status ;;
      3) docker restart mihomo && echo -e "${GREEN}已重启${PLAIN}" ;;
      4) cmd_reset ;;
      0) exit 0 ;;
      *) echo -e "${RED}无效选择，请重新输入${PLAIN}" ;;
    esac
    echo
  done
}

# ========================== 主入口 ==========================
case "${1:-menu}" in
  install|i)   cmd_install ;;
  status|st)   check_status ;;
  restart)     docker restart mihomo && echo -e "${GREEN}已重启${PLAIN}" ;;
  reset)       cmd_reset ;;
  help|h)
    echo -e "${CYAN}用法: $0 <命令>${PLAIN}"
    echo -e "  install   完整安装（Docker + 配置 + UI + GeoIP + 定时任务）"
    echo -e "  status/st 状态检查"
    echo -e "  restart   重启容器"
    echo -e "  reset     重置配置并重启"
    echo -e "  menu      显示交互菜单"
    ;;
  menu)      show_menu ;;
  *)         show_menu ;;
esac
