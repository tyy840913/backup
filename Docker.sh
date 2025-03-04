#!/bin/bash
# Docker & Docker Compose 自动安装脚本
# 支持系统：Ubuntu/Debian/CentOS/Alpine
# 最后更新：2025-03-04

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

# 镜像加速配置
MIRRORS=(
  "https://docker.m.daocloud.io"
  "https://kso3rgcp.mirror.aliyuncs.com"
  "https://registry.docker-cn.com"
  "https://mirror.baidubce.com"
  "https://hub-mirror.c.163.com"
)

# 系统检测
detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
  elif type lsb_release >/dev/null 2>&1; then
    OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
  else
    OS=$(uname -s)
  fi
  echo $OS
}

# 步骤执行状态检查
check_status() {
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}[OK]${NC} $1"
  else
    echo -e "${RED}[FAILED]${NC} $1"
    exit 1
  fi
}

# Docker安装
install_docker() {
  case $OS in
    ubuntu|debian)
      echo -e "${YELLOW}[INFO]${NC} 检测到 Debian 系系统"
      # 卸载旧版本
      sudo apt-get remove -y docker docker-engine docker.io containerd runc >/dev/null 2>&1
      # 安装依赖
      sudo apt-get update >/dev/null && \
      sudo apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common
      # 添加镜像源
      curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/$OS/gpg | sudo apt-key add - && \
      sudo add-apt-repository "deb [arch=amd64] https://mirrors.aliyun.com/docker-ce/linux/$OS $(lsb_release -cs) stable"
      # 安装
      sudo apt-get update >/dev/null && \
      sudo apt-get install -y docker-ce docker-ce-cli containerd.io
      ;;
    centos|rhel)
      echo -e "${YELLOW}[INFO]${NC} 检测到 RedHat 系系统"
      sudo yum remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine
      sudo yum install -y yum-utils
      sudo yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
      sudo yum install -y docker-ce docker-ce-cli containerd.io
      ;;
    alpine)
      echo -e "${YELLOW}[INFO]${NC} 检测到 Alpine 系统"
      sudo apk add docker docker-compose
      sudo rc-update add docker boot
      sudo service docker start
      ;;
    *)
      echo -e "${RED}[ERROR]${NC} 不支持的系统类型"
      exit 1
      ;;
  esac
  check_status "Docker 安装"
}

# Docker Compose安装
install_compose() {
  if docker compose version >/dev/null 2>&1; then
    echo -e "${YELLOW}[INFO]${NC} 检测到 Docker 集成 Compose"
    return
  fi

  COMPOSE_URL="https://mirror.ghproxy.com/https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)"
  sudo curl -L $COMPOSE_URL -o /usr/local/bin/docker-compose && \
  sudo chmod +x /usr/local/bin/docker-compose
  check_status "Docker Compose 安装"
}

# 配置镜像加速
config_mirrors() {
  sudo mkdir -p /etc/docker
  if [ -f /etc/docker/daemon.json ]; then
    sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.bak
  fi

  # 生成镜像加速配置
  MIRROR_STR=$(printf ", \"%s\"" "${MIRRORS[@]}")
  MIRROR_STR=${MIRROR_STR:2}

  sudo tee /etc/docker/daemon.json >/dev/null <<EOF
{
  "registry-mirrors": [${MIRROR_STR}]
}
EOF

  sudo systemctl restart docker
  check_status "镜像加速配置"
}

# 主流程
main() {
  OS=$(detect_os)
  echo -e "${GREEN}========== 开始安装 ==========${NC}"

  # 检查Docker是否安装
  if command -v docker >/dev/null; then
    echo -e "${YELLOW}[WARN]${NC} 检测到已安装 Docker"
    read -p "是否重新安装？(y/N)" choice
    case "$choice" in
      y|Y)
        echo -e "${YELLOW}[INFO]${NC} 开始卸载旧版本..."
        sudo rm -rf /var/lib/docker
        sudo rm -rf /etc/docker
        ;;
      *)
        echo -e "${YELLOW}[INFO]${NC} 跳过 Docker 安装"
        ;;
    esac
  else
    install_docker
  fi

  # 安装后配置
  if [ "$OS" != "alpine" ]; then
    sudo systemctl enable docker
    sudo systemctl start docker
  fi

  install_compose
  config_mirrors

  # 验证安装
  echo -e "\n${GREEN}========== 验证安装 ==========${NC}"
  docker --version
  docker compose version
  echo -e "${GREEN}=============================${NC}"
}

# 执行主函数
main
