#!/bin/bash
set -e

# 全局变量
REGISTRY_MIRRORS='[
  "https://docker.m.daocloud.io",
  "https://docker.woskee.dns.army",
  "https://docker.woskee.dynv6.net"
]'
SUPPORTED_DISTROS=("debian" "ubuntu" "centos" "rhel" "alpine" "fedora")
DOCKER_DAEMON_JSON="/etc/docker/daemon.json"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 初始化变量
OS_NAME=""
OS_VERSION=""
PKG_MANAGER=""
INIT_SYSTEM=""

# 检查root权限
check_root() {
  if [[ $(id -u) -ne 0 ]]; then
    echo -e "${RED}错误：必须使用root权限运行此脚本${NC}"
    exit 1
  fi
}

# 检测系统信息
detect_system() {
  echo -e "${YELLOW}[信息] 正在检测系统信息...${NC}"
  
  if [ -f /etc/alpine-release ]; then
    OS_NAME="alpine"
    OS_VERSION=$(cat /etc/alpine-release)
  elif [ -f /etc/os-release ]; then
    source /etc/os-release
    OS_NAME=$ID
    OS_VERSION=$VERSION_ID
  else
    echo -e "${RED}错误：无法识别的操作系统${NC}"
    exit 1
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
      echo -e "${RED}错误：不支持的发行版：$OS_NAME${NC}"
      exit 1
      ;;
  esac

  echo -e "${GREEN}[成功] 检测到系统：${OS_NAME} ${OS_VERSION}${NC}"
}

# 检查Docker是否安装
check_docker_installed() {
  if command -v docker &>/dev/null; then
    DOCKER_VERSION=$(docker --version | awk '{print $3}')
    echo -e "${YELLOW}[警告] 检测到已安装Docker版本：$DOCKER_VERSION${NC}"
    read -p "是否重新安装？(y/n) " REINSTALL
    if [[ $REINSTALL =~ ^[Yy]$ ]]; then
      uninstall_docker
      return 1
    else
      echo -e "${YELLOW}[信息] 跳过Docker安装${NC}"
      return 0
    fi
  fi
  return 1
}

# 检查Docker Compose是否安装
check_compose_installed() {
  if command -v docker-compose &>/dev/null; then
    COMPOSE_VERSION=$(docker-compose --version | awk '{print $3}')
    echo -e "${YELLOW}[警告] 检测到已安装Docker Compose版本：$COMPOSE_VERSION${NC}"
    read -p "是否重新安装？(y/n) " REINSTALL
    if [[ $REINSTALL =~ ^[Yy]$ ]]; then
      uninstall_compose
      return 1
    else
      echo -e "${YELLOW}[信息] 跳过Docker Compose安装${NC}"
      return 0
    fi
  fi
  return 1
}

# 卸载Docker
uninstall_docker() {
  echo -e "${YELLOW}[信息] 开始卸载Docker...${NC}"
  
  case $PKG_MANAGER in
    apt)
      apt-get remove -y docker docker-engine docker.io containerd runc
      ;;
    yum)
      yum remove -y docker-ce docker-ce-cli containerd.io
      ;;
    apk)
      apk del docker-cli docker-engine
      rm -rf /var/lib/docker
      ;;
  esac
  
  echo -e "${GREEN}[成功] Docker已卸载${NC}"
}

# 卸载Docker Compose
uninstall_compose() {
  echo -e "${YELLOW}[信息] 开始卸载Docker Compose...${NC}"
  rm -f /usr/local/bin/docker-compose
  echo -e "${GREEN}[成功] Docker Compose已卸载${NC}"
}

# 安装Docker
install_docker() {
  echo -e "${YELLOW}[信息] 开始安装Docker...${NC}"
  
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
  
  echo -e "${GREEN}[成功] Docker安装完成${NC}"
}

# 安装Docker Compose
install_compose() {
  echo -e "${YELLOW}[信息] 开始安装Docker Compose...${NC}"
  
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
  
  echo -e "${GREEN}[成功] Docker Compose安装完成${NC}"
}

# 配置镜像加速
configure_mirrors() {
  echo -e "${YELLOW}[信息] 正在配置镜像加速...${NC}"
  
  if [ ! -d "/etc/docker" ]; then
    mkdir -p /etc/docker
  fi

  if [ -f "$DOCKER_DAEMON_JSON" ]; then
    mv $DOCKER_DAEMON_JSON $DOCKER_DAEMON_JSON.bak
  fi

  cat <<EOF > $DOCKER_DAEMON_JSON
{
  "registry-mirrors": $REGISTRY_MIRRORS
}
EOF

  echo -e "${GREEN}[成功] 镜像加速配置完成${NC}"
}

# 配置开机启动
enable_service() {
  echo -e "${YELLOW}[信息] 配置Docker开机启动...${NC}"
  
  case $INIT_SYSTEM in
    systemd)
      systemctl enable docker
      systemctl restart docker
      ;;
    openrc)
      rc-update add docker default
      service docker restart
      ;;
  esac
  
  echo -e "${GREEN}[成功] 开机启动配置完成${NC}"
}

# 验证安装
verify_installation() {
  echo -e "\n${YELLOW}[信息] 验证安装...${NC}"
  
  if ! docker --version; then
    echo -e "${RED}错误：Docker安装失败${NC}"
    exit 1
  fi
  
  if ! docker-compose --version; then
    echo -e "${RED}错误：Docker Compose安装失败${NC}"
    exit 1
  fi
  
  echo -e "\n${GREEN}====================================="
  echo "所有组件安装验证成功！"
  echo "Docker版本: $(docker --version)"
  echo "Docker Compose版本: $(docker-compose --version)"
  echo "镜像加速配置:"
  jq .registry-mirrors $DOCKER_DAEMON_JSON
  echo "=====================================${NC}\n"
}

# 主函数
main() {
  check_root
  detect_system
  check_docker_installed || install_docker
  check_compose_installed || install_compose
  configure_mirrors
  enable_service
  verify_installation
}

# 执行主函数
main
