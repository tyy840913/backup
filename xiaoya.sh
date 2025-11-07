#!/bin/bash
set -e

########################  统一读取账号密码（只问一次）  ########################
read -p "请输入用于远端备份的用户名: " BACKUP_USER
read -s -p "请输入用于远端备份的密码: " BACKUP_PASS
echo
export BACKUP_USER BACKUP_PASS

########################  工具函数  ########################
green=$(echo -e "\033[32m"); yellow=$(echo -e "\033[33m")
cyan=$(echo -e "\033[36m"); reset=$(echo -e "\033[0m")

check_token(){      [ ${#1} -eq 32 ]; }
check_opentoken(){  [ ${#1} -gt 334 ]; }
check_folderid(){   [ ${#1} -eq 40 ]; }

########################  独立定时任务模块（精简无重复）  ########################
add_cron(){
  local cron="$1" desc="$2"
  if crontab -l 2>/dev/null | grep -qF "$cron"; then
    echo ">>> 定时任务已存在：$desc"
  else
    (crontab -l 2>/dev/null; echo "$cron") | crontab -
    echo ">>> 定时任务已创建：$desc"
  fi
}

add_backup_cron(){
  local user="$1" pass="$2"
  add_cron "0 0 */3 * * tar -cf - -C /etc --exclude=xiaoya/data xiaoya | curl -u $user:$pass -T - https://backup.woskee.dpdns.org/update/xiaoya >/dev/null 2>&1" \
           "每3天备份xiaoya目录"
}

add_restart_cron(){
  add_cron "30 2 * * * docker restart xiaoya >/dev/null 2>&1" \
           "每天凌晨2:30重启xiaoya容器"
}

########################  本地配置检查 + 交互选择  ########################
XIAOYA_DIR=/etc/xiaoya
NEED_INIT=0
[ -d "$XIAOYA_DIR" ] || NEED_INIT=1
if [ "$NEED_INIT" -eq 0 ]; then
  TOK=$(cat "$XIAOYA_DIR"/mytoken.txt 2>/dev/null)
  OT=$(cat "$XIAOYA_DIR"/myopentoken.txt 2>/dev/null)
  FID=$(cat "$XIAOYA_DIR"/temp_transfer_folder_id.txt 2>/dev/null)
  check_token "$TOK" && check_opentoken "$OT" && check_folderid "$FID" || NEED_INIT=1
fi

if [ "$NEED_INIT" -eq 1 ]; then
  echo
  echo "检测到本地配置缺失或 Token 长度异常！"
  echo "  1) 自动拉取远端配置（需用户名密码）"
  echo "  2) 手动输入三个 Token（跳过下载）"
  read -p "请选择： " choice
  choice=${choice:-1}
if [ "$choice" -eq 1 ]; then
    echo ">>> 开始拉取远端配置..."
    echo ">>> 正在从远端服务器下载配置..."
    if ! curl -fsSL --connect-timeout 10 --max-time 30 \
         -u "$BACKUP_USER":"$BACKUP_PASS" \
         https://backup.woskee.dpdns.org/xiaoya 2>/dev/null | tar -xf - -C /etc 2>/dev/null; then
        echo ">>> 下载配置失败，请检查网络或账号密码是否正确！"
        exit 1
    fi
  else
    echo "跳过下载，仅手动填写 Token ..."
  fi

  mkdir -p "$XIAOYA_DIR"/data
  touch "$XIAOYA_DIR"/{mytoken.txt,myopentoken.txt,temp_transfer_folder_id.txt}

  while ! check_token "$(cat "$XIAOYA_DIR"/mytoken.txt)"; do
    read -p "${green}输入阿里云盘 Token（32 位）:${reset} " tk
    [ ${#tk} -eq 32 ] || { echo "长度不为 32"; exit 1; }
    echo "$tk" > "$XIAOYA_DIR"/mytoken.txt
  done

  while ! check_opentoken "$(cat "$XIAOYA_DIR"/myopentoken.txt)"; do
    read -p "${yellow}输入阿里云盘 Open Token（335 位）:${reset} " ot
    [ ${#ot} -gt 334 ] || { echo "长度不足 335"; exit 1; }
    echo "$ot" > "$XIAOYA_DIR"/myopentoken.txt
  done

  while ! check_folderid "$(cat "$XIAOYA_DIR"/temp_transfer_folder_id.txt)"; do
    read -p "${cyan}输入阿里云盘转存目录 folder_id（40 位）:${reset} " fid
    [ ${#fid} -eq 40 ] || { echo "长度不为 40"; exit 1; }
    echo "$fid" > "$XIAOYA_DIR"/temp_transfer_folder_id.txt
  done
  echo "阿里云盘信息已全部填写完成。"
else
  echo "配置已存在且 Token 长度正常，直接启动容器..."
fi

########################  网络模式选择  ########################
if command -v ifconfig &>/dev/null; then
  LOCAL_IP=$(ifconfig -a | awk '/inet/&&!/127.0.0.1|172.17/{print $2;exit}')
else
  LOCAL_IP=$(ip addr | awk '/inet/&&!/127.0.0.1|172.17/{print $2;exit}' | cut -d/ -f1)
fi
[ -s /etc/xiaoya/docker_address.txt ] || echo "http://${LOCAL_IP}:5678" > /etc/xiaoya/docker_address.txt

echo
echo ">>> 请选择 Docker 网络模式："
echo "  1 或回车 = bridge（默认）"
echo "  2        = host"
read -p "请选择： " mode_choice
mode_choice=${mode_choice:-1}
case "$mode_choice" in
  2|host|HOST) MODE=host ;;
  *)           MODE=bridge ;;
esac
echo ">>> 已选择 $MODE 模式"

########################  定时任务模块（Docker 之前）  ########################
add_backup_cron "$BACKUP_USER" "$BACKUP_PASS"
add_restart_cron
########################  Docker 部署（存在才删 + 失败即退出）  ########################
########################  Docker 镜像选择（独立两行）  ########################
IMG_BRIDGE=docker.1ms.run/xiaoyaliu/alist:latest
IMG_HOST=docker.1ms.run/xiaoyaliu/alist:hostmode

# 根据模式选用镜像
if [ "$MODE" = "host" ]; then
  IMG="$IMG_HOST"
else
  IMG="$IMG_BRIDGE"
fi

[ "$MODE" = "host" ] && PORT_MAP="" || PORT_MAP="-p 5678:80 -p 2345:2345 -p 2346:2346 -p 2347:2347"
PROXY_ARGS=""
if [ -s /etc/xiaoya/proxy.txt ]; then
  proxy_url=$(head -n1 /etc/xiaoya/proxy.txt)
  PROXY_ARGS="--env HTTP_PROXY=$proxy_url --env HTTPS_PROXY=$proxy_url --env no_proxy=*.aliyundrive.com,*.alipan.com"
fi

echo ">>> 检查并停止旧容器 ..."
if docker ps -aq --filter name=xiaoya | grep -q .; then
  if ! docker stop xiaoya; then
    echo ">>> 停止旧容器失败，请检查 Docker 服务" >&2; exit 1
  fi
  echo ">>> 删除旧容器 ..."
  if ! docker rm xiaoya; then
    echo ">>> 删除旧容器失败" >&2; exit 1
  fi
else
  echo ">>> 容器 xiaoya 不存在，跳过停止/删除"
fi

echo ">>> 检查并删除本地旧镜像 ..."
if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q xiaoyaliu/alist; then
  if ! docker rmi $(docker images --format "{{.Repository}}:{{.Tag}}" | grep xiaoyaliu/alist); then
    echo ">>> 镜像删除失败" >&2; exit 1
  fi
else
  echo ">>> 本地无 xiaoyaliu/alist 镜像，跳过删除"
fi

echo ">>> 正在拉取镜像 $IMG ..."
if ! docker pull "$IMG"; then
  echo ">>> 镜像拉取失败，请检查网络或镜像仓库是否可达" >&2; exit 1
fi

echo ">>> 正在创建容器 ..."
if ! docker create --privileged \
                   $PORT_MAP \
                   $PROXY_ARGS \
                   -v /etc/xiaoya:/data \
                   -v /etc/xiaoya/data:/www/data \
                   --restart=always \
                   --name=xiaoya \
                   "$IMG"; then
  echo ">>> 容器创建失败，请检查端口占用、挂载路径权限或磁盘空间" >&2; exit 1
fi

echo ">>> 正在启动容器 ..."
if ! docker start xiaoya; then
  echo ">>> 容器启动失败，请查看上面 Docker 报错信息" >&2; exit 1
fi

# host 模式限流（可选）
if [ "$MODE" = "host" ]; then
  echo ">>> 正在添加 host 模式连接限流 ..."
  docker exec -i xiaoya iptables -A INPUT -p tcp --dport 5678 -m connlimit --connlimit-above 2 --connlimit-mask 32 -j DROP 2>&1 || true
fi

echo ">>> Docker 容器已启动，访问地址：http://${LOCAL_IP}:5678"
