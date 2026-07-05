#!/bin/bash

R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; B='\033[1;34m'; C='\033[1;36m'; N='\033[0m'

XIAOYA_DIR="/etc/xiaoya"
DATA_DIR="/docker_data/xiaoya"
IMG_BRIDGE="docker.1ms.run/xiaoyaliu/alist:latest"
IMG_HOST="docker.1ms.run/xiaoyaliu/alist:hostmode"

check_deps() {
  command -v curl &>/dev/null || {
    echo -e "${Y}安装 curl...${N}"
    if command -v apt-get &>/dev/null; then
      apt-get install -y curl >/dev/null 2>&1
    elif command -v apk &>/dev/null; then
      apk add curl >/dev/null 2>&1
    elif command -v yum &>/dev/null; then
      yum install -y curl >/dev/null 2>&1
    fi
  }
}

check_token()     { [ ${#1} -eq 32 ]; }
check_opentoken() { [ ${#1} -gt 334 ]; }
check_folderid()  { [ ${#1} -eq 40 ]; }

load_config() {
  local dir="$1"
  TOK=$(cat "$dir/mytoken.txt" 2>/dev/null)
  OT=$(cat "$dir/myopentoken.txt" 2>/dev/null)
  FID=$(cat "$dir/temp_transfer_folder_id.txt" 2>/dev/null)
  check_token "$TOK" && check_opentoken "$OT" && check_folderid "$FID"
}

get_local_ip() {
  LOCAL_IP=$(ip -4 addr show scope global 2>/dev/null | awk '/inet/ {print $2; exit}' | cut -d/ -f1)
  [[ -z "$LOCAL_IP" ]] && LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  echo "${LOCAL_IP:-127.0.0.1}"
}

check_status() {
  local ip=$(get_local_ip)
  echo -e "\n${B}========== xiaoya 状态 ==========${N}"

  if ! command -v docker &>/dev/null; then
    echo -e "${R}Docker 未安装${N}"; return
  fi
  local docker_up=false
  if command -v systemctl &>/dev/null; then
    systemctl is-active --quiet docker 2>/dev/null && docker_up=true
  elif command -v rc-service &>/dev/null; then
    rc-service docker status &>/dev/null && docker_up=true
  elif command -v service &>/dev/null; then
    service docker status &>/dev/null && docker_up=true
  fi
  $docker_up && echo -e "Docker: ${G}运行中${N}" || echo -e "Docker: ${R}未运行${N}"

  local cid=$(docker ps -q --filter name=xiaoya 2>/dev/null)
  if [[ -n "$cid" ]]; then
    local start=$(docker inspect -f '{{.State.StartedAt}}' xiaoya 2>/dev/null)
    local sec=0
    [[ -n "$start" ]] && sec=$(( $(date +%s) - $(date -d "$start" +%s) )) 2>/dev/null || true
    local nm=$(docker inspect xiaoya --format '{{.HostConfig.NetworkMode}}' 2>/dev/null)
    echo -e "容器: ${G}运行中${N} | 网络: ${G}$nm${N}"
    echo -e "已运行: $((sec/86400))d $((sec%86400/3600))h $((sec%3600/60))m"
    docker logs xiaoya --tail 3 2>/dev/null | grep -i "error\|warn\|version" || true
  else
    local aid=$(docker ps -aq --filter name=xiaoya 2>/dev/null)
    [[ -n "$aid" ]] && echo -e "容器: ${Y}已停止${N}" || echo -e "容器: ${R}不存在${N}"
  fi

  curl -s -m 3 http://127.0.0.1:5678 &>/dev/null && \
    echo -e "服务: ${G}http://$ip:5678${N}" || \
    echo -e "服务: ${R}不可访问${N}"

  [[ -f "$XIAOYA_DIR/mytoken.txt" ]] && \
    echo -e "配置: ${G}已存在${N}" || echo -e "配置: ${R}不存在${N}"

  echo -e "${B}==============================${N}"
}

init_config() {
  echo -e "\n${B}--- 检查配置 ---${N}"

  if [[ -d "$DATA_DIR" ]] && load_config "$DATA_DIR"; then
    echo -e "${G}从 $DATA_DIR 检测到有效配置${N}"
    mkdir -p "$XIAOYA_DIR"
    local linked=0
    for f in "$DATA_DIR"/*; do
      if [[ -f "$f" ]]; then
        ln -sf "$f" "$XIAOYA_DIR/$(basename "$f")"
        echo -e "${G}  ✓ 已链接 $(basename "$f")${N}"
        linked=1
      fi
    done
    [[ $linked -eq 0 ]] && echo -e "${Y}  ⚠ DATA_DIR 中没有文件需要链接${N}"
    return 0
  fi

  if [[ -d "$XIAOYA_DIR" ]] && load_config "$XIAOYA_DIR"; then
    echo -e "${G}从 $XIAOYA_DIR 检测到有效配置${N}"
    return 0
  fi

  echo -e "${Y}未检测到有效配置，请输入 Token${N}"
  mkdir -p "$XIAOYA_DIR" "$XIAOYA_DIR/data"

  while ! check_token "$(cat "$XIAOYA_DIR/mytoken.txt" 2>/dev/null)"; do
    read -p "$(echo -e "${C}输入阿里云盘 Token（32 位）:${N}") " tk
    [[ ${#tk} -ne 32 ]] && echo "长度不为 32" && continue
    echo "$tk" > "$XIAOYA_DIR/mytoken.txt"
  done

  while ! check_opentoken "$(cat "$XIAOYA_DIR/myopentoken.txt" 2>/dev/null)"; do
    read -p "$(echo -e "${Y}输入 Open Token（至少 335 位）:${N}") " ot
    [[ ${#ot} -le 334 ]] && echo "长度不足 335" && continue
    echo "$ot" > "$XIAOYA_DIR/myopentoken.txt"
  done

  while ! check_folderid "$(cat "$XIAOYA_DIR/temp_transfer_folder_id.txt" 2>/dev/null)"; do
    read -p "$(echo -e "${C}输入转存目录 folder_id（40 位）:${N}") " fid
    [[ ${#fid} -ne 40 ]] && echo "长度不为 40" && continue
    echo "$fid" > "$XIAOYA_DIR/temp_transfer_folder_id.txt"
  done
  echo -e "${G}Token 填写完成${N}"
}

select_network() {
  echo -e "\n${B}--- 网络模式 ---${N}"
  echo "1) bridge（默认）"
  echo "2) host"
  read -p "请选择： " mode_choice
  case "${mode_choice:-1}" in 2|host|HOST) MODE=host ;; *) MODE=bridge ;; esac
  echo -e "${G}已选择 $MODE${N}"
}

start_container() {
  check_deps
  local ip=$(get_local_ip)

  # 已有容器时提示
  if docker ps -aq --filter name=xiaoya | grep -q .; then
    check_status
    echo -e "\n${Y}已存在 xiaoya 容器${N}"
    read -p "是否重新部署？(y/N): " redeploy
    [[ ! "$redeploy" =~ ^[Yy]$ ]] && echo -e "${Y}已取消${N}" && return
    echo "停止并删除旧容器..."
    docker stop xiaoya 2>/dev/null || true
    docker rm xiaoya 2>/dev/null || true
  fi

  init_config
  select_network

  [[ -s "$XIAOYA_DIR/docker_address.txt" ]] || echo "http://${ip}:5678" > "$XIAOYA_DIR/docker_address.txt"

  [[ "$MODE" = "host" ]] && IMG="$IMG_HOST" || IMG="$IMG_BRIDGE"
  PORT_MAP=""
  [[ "$MODE" != "host" ]] && PORT_MAP="-p 5678:80 -p 2345:2345 -p 2346:2346 -p 2347:2347"

  PROXY_ARGS=""
  if [[ -s "$XIAOYA_DIR/proxy.txt" ]]; then
    local pu=$(head -n1 "$XIAOYA_DIR/proxy.txt")
    PROXY_ARGS="--env HTTP_PROXY=$pu --env HTTPS_PROXY=$pu --env NO_PROXY=*.aliyundrive.com,*.alipan.com --env http_proxy=$pu --env https_proxy=$pu --env no_proxy=*.aliyundrive.com,*.alipan.com"
  fi

  echo -e "\n${B}--- 部署容器 ---${N}"
  echo "拉取镜像 $IMG..."
  docker pull "$IMG" || { echo -e "${R}拉取失败${N}"; exit 1; }

  echo "创建容器..."
  docker create --privileged \
    $PORT_MAP \
    $PROXY_ARGS \
    -v "$XIAOYA_DIR:/data" \
    -v "$XIAOYA_DIR/data:/www/data" \
    -v "$DATA_DIR:$DATA_DIR" \
    --restart=always \
    --name=xiaoya \
    "$IMG" || { echo -e "${R}创建失败${N}"; exit 1; }

  echo "启动容器..."
  docker start xiaoya || { echo -e "${R}启动失败${N}"; docker logs xiaoya --tail 20 2>/dev/null; exit 1; }

  echo "等待服务就绪..."
  for i in $(seq 1 15); do
    sleep 2
    if curl -s -m 3 http://127.0.0.1:5678 &>/dev/null; then
      echo -e "${G}服务已就绪，访问地址：http://${ip}:5678${N}"
      return 0
    fi
    echo -n "."
  done
  echo -e "\n${Y}容器已启动但服务未响应，请稍后检查${N}"
  docker logs xiaoya --tail 10 2>/dev/null
}

restart_container() {
  if docker ps -q --filter name=xiaoya | grep -q .; then
    echo -e "${Y}正在重启 xiaoya 容器...${N}"
    docker restart xiaoya && echo -e "${G}已重启${N}" || echo -e "${R}重启失败${N}"
    show_logs
  else
    echo -e "${R}容器未运行${N}"
  fi
}

show_logs() {
  docker logs --tail 50 -f xiaoya 2>/dev/null || echo -e "${Y}无日志${N}"
}

# --- 入口 ---
case "${1:-menu}" in
  status|st)   check_status ;;
  restart)     restart_container ;;
  *)
    if docker ps -q --filter name=xiaoya | grep -q .; then
      while true; do
        clear
        echo -e "${C}===== xiaoya-alist 管理 =====${N}"
        echo " 1) 重新部署容器"
        echo " 2) 状态检查"
        echo " 3) 重启容器"
        echo " 0) 退出"
        read -p "请选择： " ch
        case "$ch" in
          1) start_container && show_logs ;;
          2) check_status ;;
          3) restart_container ;;
          0) exit 0 ;;
        esac
        read -p "按回车键继续..."
      done
    else
start_container && show_logs
    fi
    ;;
esac