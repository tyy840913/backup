#!/bin/bash

# 颜色定义
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # 恢复默认

# 初始化变量
DIST_NAME="Unknown"
DIST_ID="unknown"
DIST_VERSION="Unknown"
DIST_CODENAME="Unknown"
PKG_MANAGER="Unknown"
FAMILY="Unknown"

# 检测发行版信息
detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    DIST_ID="${ID}"
    DIST_NAME="${NAME}"
    DIST_VERSION="${VERSION_ID:-$BUILD_ID}"
    DIST_CODENAME="${VERSION_CODENAME:-$VERSION}"
  elif [ -f /etc/centos-release ]; then
    DIST_NAME="CentOS"
    DIST_ID="centos"
    DIST_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/centos-release)
  elif [ -f /etc/alpine-release ]; then
    DIST_NAME="Alpine Linux"
    DIST_ID="alpine"
    DIST_VERSION=$(cat /etc/alpine-release)
  fi

  case $DIST_ID in
    debian|ubuntu|linuxmint|popos|kali) FAMILY="debian";;
    rhel|centos|fedora|rocky|almalinux|ol) FAMILY="rhel";;
    alpine) FAMILY="alpine";;
    arch|manjaro|endeavouros) FAMILY="arch";;
    opensuse*|sled|sles) FAMILY="suse";;
    *) 
      [ -f /etc/redhat-release ] && FAMILY="rhel"
      [ -f /etc/debian_version ] && FAMILY="debian"
      ;;
  esac

  case $FAMILY in
    debian) PKG_MANAGER="apt";;
    rhel) [ "$DIST_ID" = "fedora" ] && PKG_MANAGER="dnf" || PKG_MANAGER="yum";;
    alpine) PKG_MANAGER="apk";;
    arch) PKG_MANAGER="pacman";;
    suse) PKG_MANAGER="zypper";;
  esac
}

# 显示系统信息
show_system_info() {
  # 转换系统家族为友好名称
  case $FAMILY in
    debian) FAMILY_NAME="Debian" ;;
    rhel) FAMILY_NAME="Red Hat" ;;
    alpine) FAMILY_NAME="Alpine" ;;
    arch) FAMILY_NAME="Arch" ;;
    suse) FAMILY_NAME="SUSE" ;;
    *) FAMILY_NAME="$FAMILY" ;;
  esac

  echo -e "\n${BLUE}══════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}                   系统检测信息                   ${NC}"
  echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
  printf "%-12s: ${YELLOW}%s${NC}\n" "母系统" "$FAMILY_NAME"
  printf "%-12s: ${YELLOW}%s${NC}\n" "分支系统" "$DIST_NAME"
  printf "%-12s: ${YELLOW}%s${NC}\n" "版本号" "$DIST_VERSION"
  printf "%-12s: ${YELLOW}%s${NC}\n" "包管理器" "${PKG_MANAGER^^}"
  echo -e "${BLUE}══════════════════════════════════════════════════${NC}\n"
}

# 镜像源配置函数
config_debian() {
  local mirror=$1
  local sources_file="/etc/apt/sources.list"
  
  sudo cp "$sources_file" "${sources_file}.bak"
  sudo sed -i "s|^deb http://.*/debian/|deb $mirror/debian/|" "$sources_file"
  sudo sed -i "s|^deb http://.*/ubuntu/|deb $mirror/ubuntu/|" "$sources_file"
}

config_rhel() {
  local mirror=$1
  case $DIST_ID in
    centos)
      sudo sed -e "s|^mirrorlist=|#mirrorlist=|g" \
               -e "s|^#baseurl=http://mirror.centos.org|baseurl=$mirror|g" \
               -i /etc/yum.repos.d/CentOS-*.repo
      ;;
    fedora)
      sudo sed -e "s|^metalink=|#metalink=|g" \
               -e "s|^#baseurl=http://download.fedoraproject.org/pub/fedora/linux|baseurl=$mirror/fedora|g" \
               -i /etc/yum.repos.d/fedora*.repo
      ;;
  esac
}

config_arch() {
  local mirror="$1/archlinux"
  echo "Server = $mirror/\$repo/os/\$arch" | sudo tee /etc/pacman.d/mirrorlist >/dev/null
}

config_alpine() {
  local mirror="$1/alpine"
  echo "$mirror/$DIST_VERSION/main" | sudo tee /etc/apk/repositories
  echo "$mirror/$DIST_VERSION/community" | sudo tee -a /etc/apk/repositories
}

# 镜像源选择菜单
show_menu() {
  echo -e "\n${BLUE}请选择要使用的镜像源：${NC}"
  options=(
    "阿里云镜像源"
    "腾讯云镜像源"
    "华为云镜像源"
    "网易云镜像源"
    "中科大镜像源"
    "清华大学镜像源"
  )
  
  select opt in "${options[@]}"; do
    case $REPLY in
      1) MIRROR="http://mirrors.aliyun.com"; break ;;
      2) MIRROR="http://mirrors.tencentyun.com"; break ;;
      3) MIRROR="http://repo.huaweicloud.com"; break ;;
      4) MIRROR="http://mirrors.163.com"; break ;;
      5) MIRROR="http://mirrors.ustc.edu.cn"; break ;;
      6) MIRROR="http://mirrors.tuna.tsinghua.edu.cn"; break ;;
      *) echo -e "${RED}无效选项，请重新输入！${NC}" ;;
    esac
  done
}

# 自动更新索引
update_index() {
  echo -e "\n${GREEN}正在更新软件源索引...${NC}"
  case $PKG_MANAGER in
    apt) sudo apt update -y ;;
    yum) sudo yum makecache ;;
    dnf) sudo dnf makecache ;;
    pacman) sudo pacman -Sy ;;
    apk) sudo apk update ;;
    zypper) sudo zypper refresh ;;
    *) echo -e "${RED}未知的包管理器，无法更新索引${NC}" ;;
  esac
  echo -e "${GREEN}软件源索引更新完成！${NC}"
}

# 主流程
detect_os
show_system_info
show_menu

echo -e "\n${GREEN}正在更换镜像源为 [$opt] ...${NC}"
case $FAMILY in
  debian) config_debian "$MIRROR" ;;
  rhel) config_rhel "$MIRROR" ;;
  arch) config_arch "$MIRROR" ;;
  alpine) config_alpine "$MIRROR" ;;
  *) echo -e "${RED}不支持的发行版！${NC}"; exit 1 ;;
esac

echo -e "${GREEN}镜像源更换完成！${NC}"
update_index
