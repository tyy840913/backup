#!/bin/bash
# 设置全局参数
export LC_ALL=C
TMP_DIR=/tmp/docker_install
MIRRORS=(
  "https://docker.m.daocloud.io"
  "https://docker.woskee.dns.army" 
  "https://docker.woskee.dynv6.net"
)

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 初始化环境
init_env() {
  clear
  echo -e "${BLUE}▶ 初始化安装环境...${NC}"
  sleep 0.5
  mkdir -p $TMP_DIR
  [ -f /etc/os-release ] && . /etc/os-release
  detect_pkg_manager
}

# 检测包管理器
detect_pkg_manager() {
  echo -e "${BLUE}▶ 检测系统环境...${NC}"
  case $ID in
    alpine) PKG_MANAGER="apk"; INSTALL_CMD="add";;
    debian|ubuntu) PKG_MANAGER="apt"; INSTALL_CMD="install";;
    centos|rhel|fedora|ol) PKG_MANAGER="yum";;
    *) echo -e "${RED}✗ 不支持的发行版${NC}"; exit 1;;
  esac
  sleep 0.5
}

# 系统服务管理
service_cmd() {
  case $ID in
    alpine) echo "rc-service $1 $2";;
    *) echo "systemctl $2 $1";;
  esac
}

# 安装前准备
pre_install() {
  echo -e "${BLUE}▶ 更新软件索引...${NC}"
  case $PKG_MANAGER in
    apk) apk update;;
    apt) apt update;;
    yum) yum makecache;;
  esac
  sleep 0.5
}

# Docker安装函数
install_docker() {
  echo -e "${BLUE}▶ 开始安装Docker...${NC}"
  case $ID in
    alpine)
      $PKG_MANAGER $INSTALL_CMD docker
      ;;
    debian|ubuntu)
      curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/debian/gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg
      echo "deb [arch=$(dpkg --print-architecture)] https://mirrors.aliyun.com/docker-ce/linux/$ID $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list
      apt update
      apt $INSTALL_CMD docker-ce docker-ce-cli containerd.io
      ;;
    centos|rhel|fedora|ol)
      yum install -y yum-utils
      yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
      yum install -y docker-ce docker-ce-cli containerd.io
      ;;
  esac
  sleep 0.5
}

# Docker Compose安装
install_compose() {
  echo -e "${BLUE}▶ 检测Docker Compose...${NC}"
  if ! command -v docker-compose &> /dev/null; then
    echo -e "${YELLOW}✓ 未检测到Docker Compose${NC}"
    read -t 15 -p "是否安装Docker Compose？[Y/n]" COMPOSE_INSTALL
    case ${COMPOSE_INSTALL:-Y} in
      Y|y)
        echo -e "${BLUE}▶ 开始安装Docker Compose...${NC}"
        curl -L "https://ghproxy.com/https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        ;;
      *) return ;;
    esac
  else
    echo -e "${GREEN}✓ Docker Compose已安装${NC}"
  fi
  sleep 0.5
}

# 配置镜像加速
config_mirror() {
  echo -e "${BLUE}▶ 配置镜像加速...${NC}"
  DOCKER_DAEMON=/etc/docker/daemon.json
  mkdir -p /etc/docker
  
  if [ ! -f $DOCKER_DAEMON ]; then
    echo '{"registry-mirrors":[]}' > $DOCKER_DAEMON
  fi

  current_mirrors=$(jq '."registry-mirrors"' $DOCKER_DAEMON)
  new_mirrors=$(printf '%s\n' "${MIRRORS[@]}" | jq -R . | jq -s .)
  
  if [ "$current_mirrors" != "$new_mirrors" ]; then
    jq --argjson new "$new_mirrors" '."registry-mirrors"=$new' $DOCKER_DAEMON > $TMP_DIR/daemon.json
    mv $TMP_DIR/daemon.json $DOCKER_DAEMON
    echo -e "${GREEN}✓ 镜像加速配置已更新${NC}"
    RESTART_DOCKER=true
  else
    echo -e "${YELLOW}✓ 镜像配置无需修改${NC}"
  fi
  sleep 0.5
}

# 服务管理
manage_service() {
  echo -e "${BLUE}▶ 设置开机启动...${NC}"
  if [ "$ID" = "alpine" ]; then
    rc-update add docker default
  else
    systemctl enable docker
  fi
  sleep 0.5
  
  if [ "$RESTART_DOCKER" = "true" ]; then
    echo -e "${BLUE}▶ 重启Docker服务...${NC}"
    eval $(service_cmd docker restart)
    sleep 1
  fi
}

# 主执行流程
main() {
  init_env
  pre_install

  # 检测Docker安装状态
  if command -v docker &> /dev/null; then
    echo -e "${GREEN}✓ 检测到已安装Docker${NC}"
    read -t 15 -p "是否重新安装？[y/N]" REINSTALL
    case ${REINSTALL:-N} in
      Y|y)
        echo -e "${BLUE}▶ 开始卸载旧版本...${NC}"
        case $ID in
          alpine) apk del docker;;
          debian|ubuntu) apt purge -y docker*;;
          centos|rhel) yum remove -y docker*;;
        esac
        rm -rf /var/lib/docker
        sleep 0.5
        install_docker
        ;;
      *) ;;
    esac
  else
    install_docker
  fi

  install_compose
  config_mirror
  manage_service

  # 验证安装结果
  echo -e "\n${GREEN}✔ 安装完成${NC}"
  echo -e "${BLUE}Docker版本: ${NC}$(docker --version)"
  echo -e "${BLUE}Compose版本: ${NC}$(docker-compose --version)"
}

# 执行主函数
main
