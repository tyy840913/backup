#!/bin/bash
set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 带颜色输出函数
info() { echo -e "${YELLOW}[信息] $*${NC}"; sleep 0.5; }
success() { echo -e "${GREEN}[成功] $*${NC}"; sleep 0.5; }
error() { echo -e "${RED}[错误] $*${NC}"; exit 1; }
warning() { echo -e "${YELLOW}[警告] $*${NC}"; sleep 0.5; }

# 全局变量
REGISTRY_MIRRORS='[
  "https://docker.1panel.top",
  "https://proxy.1panel.live",
  "https://docker.m.daocloud.io",
  "https://docker.woskee.dns.army",
  "https://docker.woskee.dynv6.net"
]'
SUPPORTED_DISTROS=("debian" "ubuntu" "centos" "rhel" "alpine" "fedora")
DOCKER_DAEMON_JSON="/etc/docker/daemon.json"
DOCKER_CONFIG_DIR="/etc/docker"

# 初始化变量
OS_NAME=""
OS_VERSION=""
PKG_MANAGER=""
INIT_SYSTEM=""


# 检查root权限
check_root() {
  if [[ $(id -u) -ne 0 ]]; then
    error "必须使用root权限运行此脚本"
  fi
}

# 检测系统信息
detect_system() {
  info "正在检测系统信息..."
  
  if [ -f /etc/alpine-release ]; then
    OS_NAME="alpine"
    OS_VERSION=$(cat /etc/alpine-release)
  elif [ -f /etc/os-release ]; then
    source /etc/os-release
    OS_NAME=$ID
    OS_VERSION=$VERSION_ID
  else
    error "无法识别的操作系统"
  fi

  case $OS_NAME in
    debian|ubuntu) 
      PKG_MANAGER="apt"
      INIT_SYSTEM="systemd"
      ;;
    centos|rhel|fedora)
      PKG_MANAGER="yum"
      INIT_SYSTEM="systemd"
      ;;
    alpine)
      PKG_MANAGER="apk"
      INIT_SYSTEM="openrc"
      ;;
    *)
      error "不支持的发行版：$OS_NAME"
      ;;
  esac

  success "检测到系统：${OS_NAME} ${OS_VERSION}"
}

# 检查Docker是否安装
check_docker_installed() {
  if command -v docker &>/dev/null; then
    DOCKER_VERSION=$(docker --version | awk '{print $3}')
    warning "检测到已安装Docker版本：$DOCKER_VERSION"
    read -p "是否重新安装？(y/n) " REINSTALL
    if [[ $REINSTALL =~ ^[Yy]$ ]]; then
      uninstall_docker
      return 1
    else
      info "跳过Docker安装"
      return 0
    fi
  fi
  return 1
}

# 检查Docker Compose是否安装
check_compose_installed() {
  if command -v docker-compose &>/dev/null; then
    COMPOSE_VERSION=$(docker-compose --version | awk '{print $3}')
    warning "检测到已安装Docker Compose版本：$COMPOSE_VERSION"
    read -p "是否重新安装？(y/n) " REINSTALL
    if [[ $REINSTALL =~ ^[Yy]$ ]]; then
      uninstall_compose
      return 1
    else
      info "跳过Docker Compose安装"
      return 0
    fi
  fi
  return 1
}

# 卸载Docker
uninstall_docker() {
  info "开始卸载Docker..."
  
  case $PKG_MANAGER in
    apt)
      apt-get remove -y docker docker-engine docker.io containerd runc
      ;;
    yum)
      yum remove -y docker-ce docker-ce-cli containerd.io
      ;;
    apk)
      apk del docker-cli docker-engine
      ;;
  esac

  # 清理 Docker 相关文件和配置
  rm -rf /var/lib/docker
  rm -rf $DOCKER_CONFIG_DIR
  rm -f /etc/apt/sources.list.d/docker.list
  rm -f /etc/yum.repos.d/docker-ce.repo

  success "Docker已卸载"
}

# 卸载Docker Compose
uninstall_compose() {
  info "开始卸载Docker Compose..."
  rm -f /usr/local/bin/docker-compose
  success "Docker Compose已卸载"
}

# 安装Docker
install_docker() {
  info "开始安装Docker..."
  
  read -p "是否要安装Docker？(y/n) " ANSWER
  [[ ! $ANSWER =~ ^[Yy]$ ]] && { info "已取消Docker安装"; return; }

  case $PKG_MANAGER in
    apt)
      apt-get update
      apt-get install -y apt-transport-https ca-certificates curl gnupg
      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/$OS_NAME/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/$OS_NAME $OS_VERSION stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
      apt-get update
      apt-get install -y docker-ce docker-ce-cli containerd.io
      ;;
    yum)
      yum install -y yum-utils
      yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
      yum install -y docker-ce docker-ce-cli containerd.io
      ;;
    apk)
      apk add docker
      ;;
  esac
  
  success "Docker安装完成"
}

# 安装Docker Compose
install_compose() {
  info "开始安装Docker Compose..."
  
  read -p "是否要安装Docker Compose？(y/n) " ANSWER
  [[ ! $ANSWER =~ ^[Yy]$ ]] && { info "已取消Docker Compose安装"; return; }

  case $PKG_MANAGER in
    apk)
      apk add docker-compose
      ;;
    *)
      COMPOSE_URL="https://mirror.ghproxy.com/https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
      curl -L $COMPOSE_URL -o /usr/local/bin/docker-compose
      chmod +x /usr/local/bin/docker-compose
      ;;
  esac
  
  success "Docker Compose安装完成"
}

# 配置开机启动
enable_service() {
  info "正在检查Docker开机启动配置..."
  sleep 0.5

  case $INIT_SYSTEM in
    systemd)
      if systemctl is-enabled docker &>/dev/null; then
        success "Docker已设置开机启动（systemd）"
        return
      else
        info "未检测到开机启动配置，正在设置..."
        systemctl enable docker
        systemctl restart docker
      fi
      ;;
    openrc)
      if rc-update show default | grep -q docker; then
        success "Docker已设置开机启动（openrc）"
        return
      else
        info "未检测到开机启动配置，正在设置..."
        rc-update add docker default
        service docker restart
      fi
      ;;
  esac
  
  # 二次验证配置结果
  if docker ps &>/dev/null; then
    success "Docker开机启动配置完成"
  else
    error "Docker服务开机启动失败，请检查配置"
  fi
}

# 配置镜像加速
configure_mirrors() {
  info "正在配置镜像加速..."
  
  read -p "是否要配置镜像加速？(y/n) " ANSWER
  [[ ! $ANSWER =~ ^[Yy]$ ]] && { info "已取消镜像加速配置"; return; }

  # 检查现有配置
  if [ -f "$DOCKER_DAEMON_JSON" ]; then
    warning "检测到已存在的Docker配置: $DOCKER_DAEMON_JSON"
    if grep -q "registry-mirrors" "$DOCKER_DAEMON_JSON"; then
      warning "当前已配置以下镜像加速地址:"
      grep "registry-mirrors" -A 5 "$DOCKER_DAEMON_JSON"
      read -p "是否要覆盖现有配置？(y/n) " OVERWRITE
      [[ ! $OVERWRITE =~ ^[Yy]$ ]] && { info "保留现有镜像加速配置"; return; }
    fi
    mv $DOCKER_DAEMON_JSON $DOCKER_DAEMON_JSON.bak
    info "已备份原配置文件: $DOCKER_DAEMON_JSON.bak"
  fi

  mkdir -p $DOCKER_CONFIG_DIR
  cat <<EOF > $DOCKER_DAEMON_JSON
{
  "registry-mirrors": $REGISTRY_MIRRORS
}
EOF

  success "镜像加速配置完成"
}

# 验证安装
verify_installation() {
  info "验证安装..."
  
  if ! docker --version; then
    error "Docker安装失败"
  fi
  
  if ! docker-compose --version; then
    error "Docker Compose安装失败"
  fi
  
  echo -e "\n${GREEN}====================================="
  echo "所有组件安装验证成功！"
  echo "Docker版本: $(docker --version)"
  echo "Docker Compose版本: $(docker-compose --version)"
  echo "镜像加速配置:"
  docker info | grep "Registry Mirrors" -A 5 | sed 's/Registry Mirrors://g' | tr -d '\\'
  echo -e "=====================================${NC}"
}

# 主函数
main() {
  check_root
  detect_system
  
  if check_docker_installed; then
    info "Docker已安装，跳过安装步骤"
  else
    install_docker
  fi
  
  if check_compose_installed; then
    info "Docker Compose已安装，跳过安装步骤"
  else
    install_compose
  fi
  
  configure_mirrors
  enable_service
  verify_installation
}

# 执行主函数
main
