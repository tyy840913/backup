#!/bin/bash

# 颜色定义
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # 恢复默认

# 系统架构检测
ARCH=$(uname -m)

# 初始化变量
DIST_NAME="Unknown"
DIST_ID="unknown"
DIST_VERSION="Unknown"
DIST_CODENAME="Unknown"
PKG_MANAGER="Unknown"
FAMILY="Unknown"

# 检测发行版信息
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

# 检测系统家族和包管理器
case $DIST_ID in
    debian|ubuntu|linuxmint|popos|kali)
        FAMILY="debian"
        PKG_MANAGER="apt"
        ;;
    rhel|centos|fedora|rocky|almalinux|ol)
        FAMILY="rhel"
        [ "$DIST_ID" = "fedora" ] && PKG_MANAGER="dnf" || PKG_MANAGER="yum"
        ;;
    alpine)
        FAMILY="alpine"
        PKG_MANAGER="apk"
        ;;
    arch|manjaro|endeavouros)
        FAMILY="arch"
        PKG_MANAGER="pacman"
        ;;
    opensuse*|sled|sles)
        FAMILY="suse"
        PKG_MANAGER="zypper"
        ;;
    *)
        # 回退检测
        if [ -f /etc/redhat-release ]; then
            FAMILY="rhel"
            PKG_MANAGER="yum"
        elif [ -f /etc/debian_version ]; then
            FAMILY="debian"
            PKG_MANAGER="apt"
        fi
        ;;
esac

# 显示检测结果
echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}系统检测报告${NC}"
echo -e "${BLUE}══════════════════════════════════════════════════${NC}"
printf "%-15s: ${YELLOW}%s${NC}\n" "发行版名称" "$DIST_NAME"
printf "%-15s: ${YELLOW}%s${NC}\n" "发行版ID" "$DIST_ID"
printf "%-15s: ${YELLOW}%s${NC}\n" "版本号" "$DIST_VERSION"
printf "%-15s: ${YELLOW}%s${NC}\n" "版本代号" "$DIST_CODENAME"
printf "%-15s: ${YELLOW}%s${NC}\n" "系统架构" "$ARCH"
printf "%-15s: ${YELLOW}%s${NC}\n" "系统家族" "$FAMILY"
printf "%-15s: ${YELLOW}%s${NC}\n" "包管理器" "$PKG_MANAGER"
echo -e "${BLUE}══════════════════════════════════════════════════${NC}"

# 包管理器使用示例
echo -e "\n${GREEN}安装软件包示例：${NC}"
case $PKG_MANAGER in
    apt)     echo "sudo apt update && sudo apt install <package>" ;;
    yum)     echo "sudo yum install <package>" ;;
    dnf)     echo "sudo dnf install <package>" ;;
    apk)     echo "sudo apk add <package>" ;;
    pacman)  echo "sudo pacman -S <package>" ;;
    zypper)  echo "sudo zypper install <package>" ;;
    *)       echo "无法确定包管理命令" ;;
esac
