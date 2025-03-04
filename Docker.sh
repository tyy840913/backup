#!/bin/bash

# 颜色定义
RED='\033[0;91m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
BLUE='\033[0;94m'
NC='\033[0m' # 无颜色

# 初始化变量
SUDO=""
DOCKER_INSTALLED=0
COMPOSE_INSTALLED=0
SYSTEM=""
CONFIG_FILE="/etc/docker/daemon.json"
USE_PROXY=1  # 新增代理检测标志
MIRRORS=(
  "https://proxy.1panel.live"
  "https://docker.1panel.top"
  "https://docker.m.daocloud.io"
)

# 新增网络检测函数
check_network() {
  echo -e "${YELLOW}[INFO] 检测网络环境...${NC}"
  if curl -m 5 -s https://mirrors.aliyun.com >/dev/null; then
    echo -e "${GREEN}[INFO] 检测到国内网络环境${NC}"
    USE_PROXY=1
    MIRRORS+=("https://docker.woskee.dns.army" "https://docker.woskee.dynv6.net")
  else
    echo -e "${GREEN}[INFO] 检测到国际网络环境${NC}"
    USE_PROXY=0
    MIRRORS=()  # 国际网络不强制使用镜像
  fi
}

# 修改后的Docker Compose安装
install_compose() {
  echo -e "${YELLOW}[INFO] 开始Docker Compose安装流程...${NC}"
  sleep 0.5

  if command -v docker-compose &> /dev/null; then
    COMPOSE_INSTALLED=1
    echo -e "${YELLOW}当前Docker Compose版本: $(docker-compose --version)${NC}"
    read -p "是否覆盖安装? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo -e "${YELLOW}[INFO] 卸载旧版Docker Compose...${NC}"
      $SUDO rm -f $(which docker-compose)
    fi
  fi

  if [ $COMPOSE_INSTALLED -eq 0 ] || [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}[INFO] 开始安装Docker Compose...${NC}"
    # 根据网络环境选择下载地址
    if [ $USE_PROXY -eq 1 ]; then
      URL="https://ghproxy.com/https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
    else
      URL="https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)"
    fi

    if ! $SUDO curl -L "$URL" -o /usr/local/bin/docker-compose; then
      echo -e "${RED}[ERROR] Docker Compose下载失败，请检查网络连接${NC}"
      exit 1
    fi
    
    $SUDO chmod +x /usr/local/bin/docker-compose
    echo -e "${GREEN}[SUCCESS] Docker Compose安装完成${NC}"
  fi
}

# 改进后的开机启动设置
enable_service() {
  echo -e "${YELLOW}[INFO] 检查服务启动状态...${NC}"
  sleep 0.5
  
  case $SYSTEM in
    alpine)
      if rc-service docker status | grep -q "stopped"; then
        echo -e "${YELLOW}[INFO] 启动Docker服务...${NC}"
        $SUDO rc-service docker start
      fi
      if ! rc-update show | grep -q docker; then
        echo -e "${YELLOW}[INFO] 设置Docker开机启动...${NC}"
        $SUDO rc-update add docker default
      fi
      ;;
    *)
      if ! systemctl is-active docker &> /dev/null; then
        echo -e "${YELLOW}[INFO] 启动Docker服务...${NC}"
        $SUDO systemctl start docker
      fi
      if ! systemctl is-enabled docker &> /dev/null; then
        echo -e "${YELLOW}[INFO] 设置Docker开机启动...${NC}"
        $SUDO systemctl enable docker
      fi
      ;;
  esac
  echo -e "${GREEN}[SUCCESS] 服务状态检查完成${NC}"
}

# 改进后的镜像加速配置
configure_mirror() {
  # 国际网络且没有镜像配置时跳过
  if [ $USE_PROXY -eq 0 ] && [ ${#MIRRORS[@]} -eq 0 ]; then
    echo -e "${YELLOW}[INFO] 未检测到国内镜像配置，跳过加速设置${NC}"
    return
  fi

  echo -e "${YELLOW}[INFO] 配置镜像加速...${NC}"
  $SUDO mkdir -p $(dirname $CONFIG_FILE)
  
  # 保留现有配置
  if [ -f $CONFIG_FILE ]; then
    echo -e "${YELLOW}当前配置文件内容:"
    cat $CONFIG_FILE
    echo -ne "${NC}"
    read -p "是否保留现有配置并添加镜像? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      $SUDO jq '. + {"registry-mirrors": $ARGS.positional}' $CONFIG_FILE --args "${MIRRORS[@]}" > tmp.json
      $SUDO mv tmp.json $CONFIG_FILE
    else
      echo '{ "registry-mirrors": [] }' | $SUDO jq --args '.registry-mirrors = $ARGS.positional' --args "${MIRRORS[@]}" > tmp.json
      $SUDO mv tmp.json $CONFIG_FILE
    fi
  else
    echo '{ "registry-mirrors": [] }' | $SUDO jq --args '.registry-mirrors = $ARGS.positional' --args "${MIRRORS[@]}" > tmp.json
    $SUDO mv tmp.json $CONFIG_FILE
  fi

  # 重启服务应用配置
  case $SYSTEM in
    alpine)
      $SUDO rc-service docker restart
      ;;
    *)
      $SUDO systemctl restart docker
      ;;
  esac
  echo -e "${GREEN}[SUCCESS] 镜像加速配置完成${NC}"
}

# 修改后的主流程
main() {
  check_permission
  check_network  # 新增网络检测
  detect_system
  install_docker
  install_compose
  enable_service
  configure_mirror

  echo -e "\n${GREEN}=== 安装结果 ===${NC}"
  echo -e "Docker状态: $(systemctl is-active docker) | 开机启动: $(systemctl is-enabled docker)"
  echo -e "Docker版本: $(docker --version)"
  echo -e "Docker Compose版本: $(docker-compose --version)"
  [ -f $CONFIG_FILE ] && echo -e "镜像加速配置:\n$(jq .registry-mirrors $CONFIG_FILE)"
  echo -e "${GREEN}=== 安装完成 ===${NC}"
}

# 执行主函数
main
