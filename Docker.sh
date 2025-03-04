#!/bin/bash
set -e

# 常量定义
REGISTRY=(
  "https://docker.1panel.top"
  "https://proxy.1panel.live"
  "https://docker.m.daocloud.io"
  "https://docker.woskee.dns.army"
  "https://docker.woskee.dynv6.net"
)
PROXY_URL="https://add.woskee.nyc.mn/"

# 文本颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 系统信息检测
detect_os() {
  echo -e "${BLUE}▶ 检测系统信息...${NC}"
  sleep 0.5
  
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
  elif type lsb_release >/dev/null 2>&1; then
    OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    VER=$(lsb_release -sr)
  elif [ -f /etc/alpine-release ]; then
    OS=alpine
    VER=$(cat /etc/alpine-release)
  else
    echo -e "${RED}× 无法检测操作系统${NC}"
    exit 1
  fi

  # 设置包管理器
  case $OS in
    ubuntu|debian)
      PKG_INSTALL="apt-get install -y"
      PKG_REMOVE="apt-get purge -y"
      UPDATE_CMD="apt-get update"
      ;;
    centos|rhel|fedora)
      PKG_INSTALL="yum install -y"
      PKG_REMOVE="yum remove -y"
      UPDATE_CMD="yum update -y"
      ;;
    alpine)
      PKG_INSTALL="apk add --no-cache"
      PKG_REMOVE="apk del"
      UPDATE_CMD="apk update"
      ;;
    *)
      echo -e "${RED}× 不支持的发行版: $OS${NC}"
      exit 1
      ;;
  esac

  echo -e "${GREEN}✓ 系统类型: $OS $VER${NC}"
  sleep 0.5
}

# 服务管理命令
service_cmd() {
  case $OS in
    ubuntu|debian|centos|rhel|fedora)
      echo "systemctl $1 docker"
      ;;
    alpine)
      echo "rc-service docker $1"
      ;;
  esac
}

# 检查是否安装
check_installed() {
  if command -v docker &>/dev/null; then
    DOCKER_VER=$(docker --version | awk '{print $3}' | tr -d ',')
    echo -e "${GREEN}✓ Docker 已安装 - 版本: $DOCKER_VER${NC}"
    return 0
  else
    echo -e "${YELLOW}⚠ Docker 未安装${NC}"
    return 1
  fi
}

# 卸载Docker
uninstall_docker() {
  echo -e "${BLUE}▶ 开始卸载旧版本...${NC}"
  sleep 0.5

  case $OS in
    ubuntu|debian)
      $PKG_REMOVE docker-ce docker-ce-cli containerd.io docker-buildx-plugin
      rm -rf /var/lib/docker /etc/docker
      ;;
    centos|rhel|fedora)
      $PKG_REMOVE docker-ce docker-ce-cli containerd.io
      rm -rf /var/lib/docker
      ;;
    alpine)
      $PKG_REMOVE docker-cli docker-engine
      rm -rf /etc/docker
      ;;
  esac

  echo -e "${GREEN}✓ 旧版本已卸载${NC}"
  sleep 0.5
}

# 安装Docker
install_docker() {
  echo -e "${BLUE}▶ 开始安装Docker...${NC}"
  sleep 0.5

  case $OS in
    ubuntu|debian)
      # 添加Docker源
      curl -fsSL ${PROXY_URL}https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://mirrors.aliyun.com/docker-ce/linux/$OS $VER stable" > /etc/apt/sources.list.d/docker.list
      $UPDATE_CMD
      $PKG_INSTALL docker-ce docker-ce-cli containerd.io docker-buildx-plugin
      ;;
    centos|rhel|fedora)
      yum-config-manager --add-repo ${PROXY_URL}https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
      sed -i 's+download.docker.com+mirrors.aliyun.com/docker-ce+' /etc/yum.repos.d/docker-ce.repo
      $PKG_INSTALL docker-ce docker-ce-cli containerd.io
      ;;
    alpine)
      $PKG_INSTALL docker
      ;;
  esac

  echo -e "${GREEN}✓ Docker安装完成${NC}"
  sleep 0.5
}

# 设置开机启动
set_service() {
  echo -e "${BLUE}▶ 设置开机启动...${NC}"
  case $OS in
    ubuntu|debian|centos|rhel|fedora)
      systemctl enable docker
      ;;
    alpine)
      rc-update add docker default
      ;;
  esac
  echo -e "${GREEN}✓ 已设置开机启动${NC}"
  sleep 0.5
}

# 配置镜像加速
config_daemon() {
  echo -e "${BLUE}▶ 配置镜像加速...${NC}"
  sleep 0.5

  DAEMON_JSON=/etc/docker/daemon.json
  mkdir -p $(dirname $DAEMON_JSON)

  # 生成镜像加速配置
  registry_str=$(printf ',\n      "%s"' "${REGISTRY[@]}")
  registry_str=${registry_str:2}

  new_content=$(cat <<EOF
{
  "registry-mirrors": [
    $registry_str
  ]
}
EOF
)

  # 检查是否需要修改
  if [ -f $DAEMON_JSON ]; then
    current_content=$(cat $DAEMON_JSON | tr -d '[:space:]')
    compare_content=$(echo "$new_content" | tr -d '[:space:]')

    if [ "$current_content" == "$compare_content" ]; then
      echo -e "${GREEN}✓ 镜像配置无需修改${NC}"
      return
    fi

    echo -e "${YELLOW}⚠ 检测到现有配置文件:"
    cat $DAEMON_JSON
    read -p "是否覆盖配置？(y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo -e "${YELLOW}⚠ 跳过镜像加速配置${NC}"
      return
    fi
  fi

  echo "$new_content" > $DAEMON_JSON
  echo -e "${GREEN}✓ 镜像加速已配置${NC}"
  
  # 重启Docker
  echo -e "${BLUE}▶ 重启Docker服务...${NC}"
  $(service_cmd restart)
  sleep 2
}

# 主执行流程
main() {
  detect_os

  # 检查Docker安装状态
  if check_installed; then
    read -p "检测到已安装Docker，是否重新安装？(y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      uninstall_docker
      install_docker
    fi
  else
    read -p "是否安装Docker？(Y/n) " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Nn]$ ]] && install_docker
  fi

  # 设置开机启动
  set_service

  # 配置镜像加速
  config_daemon

  # 验证安装结果
  echo -e "\n${GREEN}✅ 安装完成！"
  docker --version
  echo -e "${NC}"
}

main
