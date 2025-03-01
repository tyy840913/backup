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

# 镜像源配置函数
config_debian() {
  local mirror=$1
  local codename=$DIST_CODENAME
  local sources_file="/etc/apt/sources.list"
  
  sudo cp "$sources_file" "${sources_file}.bak"
  sudo sed -i "s/^deb http:\/\/.*\/debian\/ \(.*\)/deb $mirror\/debian\/ \1/" "$sources_file"
  sudo sed -i "s/^deb http:\/\/.*\/ubuntu\/ \(.*\)/deb $mirror\/ubuntu\/ \1/" "$sources_file"
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
      1) 
        case $FAMILY in
          debian) MIRROR="http://mirrors.aliyun.com";;
          rhel) MIRROR="http://mirrors.aliyun.com";;
          arch) MIRROR="http://mirrors.aliyun.com";;
          alpine) MIRROR="http://mirrors.aliyun.com";;
        esac
        break ;;
      2) 
        case $FAMILY in
          debian) MIRROR="http://mirrors.tencentyun.com";;
          rhel) MIRROR="http://mirrors.tencentyun.com";;
          arch) MIRROR="http://mirrors.tencentyun.com";;
          alpine) MIRROR="http://mirrors.tencentyun.com";;
        esac
        break ;;
      3) 
        case $FAMILY in
          debian) MIRROR="http://repo.huaweicloud.com";;
          rhel) MIRROR="http://repo.huaweicloud.com";;
          arch) MIRROR="http://repo.huaweicloud.com";;
          alpine) MIRROR="http://repo.huaweicloud.com";;
        esac
        break ;;
      4) 
        case $FAMILY in
          debian) MIRROR="http://mirrors.163.com";;
          rhel) MIRROR="http://mirrors.163.com";;
          arch) MIRROR="http://mirrors.163.com";;
          alpine) MIRROR="http://mirrors.163.com";;
        esac
        break ;;
      5) 
        case $FAMILY in
          debian) MIRROR="http://mirrors.ustc.edu.cn";;
          rhel) MIRROR="http://mirrors.ustc.edu.cn";;
          arch) MIRROR="http://mirrors.ustc.edu.cn";;
          alpine) MIRROR="http://mirrors.ustc.edu.cn";;
        esac
        break ;;
      6) 
        case $FAMILY in
          debian) MIRROR="http://mirrors.tuna.tsinghua.edu.cn";;
          rhel) MIRROR="http://mirrors.tuna.tsinghua.edu.cn";;
          arch) MIRROR="http://mirrors.tuna.tsinghua.edu.cn";;
          alpine) MIRROR="http://mirrors.tuna.tsinghua.edu.cn";;
        esac
        break ;;
      *) echo -e "${RED}无效选项，请重新输入！${NC}" ;;
    esac
  done
}

# 新增自动更新索引函数
update_index() {
  echo -e "\n${GREEN}正在自动更新软件源索引...${NC}"
  case $PKG_MANAGER in
    apt) sudo apt update -y ;;
    yum) sudo yum makecache ;;
    dnf) sudo dnf makecache ;;
    pacman) sudo pacman -Sy ;;
    apk) sudo apk update ;;
    zypper) sudo zypper refresh ;;
    *) echo -e "${RED}未知的包管理器，无法自动更新${NC}" ;;
  esac
  echo -e "${GREEN}软件源索引更新完成！${NC}"
}

# 主流程
detect_os
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
update_index  # 添加自动更新调用
