#!/bin/bash
# Proxmox VE 镜像源管理工具 - 修正版
# 功能：快速切换系统源/PVE源/LXC模板源，支持清华/阿里云/龙芯/官方源

# 预加载系统信息
source /etc/os-release
export PRETTY_NAME DEBIAN_VER=${VERSION_CODENAME}
export PVE_VER=$(pveversion 2>/dev/null | grep -oP 'pve-manager/\K\d+\.\d+')

# 版本检测函数
check_compatibility() { 
  case $PVE_VER in
    7.*) [[ $DEBIAN_VER != "bullseye" ]] && echo "[错误] PVE 7.x需基于Debian 11(bullseye)" && exit 1 ;;
    8.*) [[ $DEBIAN_VER != "bookworm" ]] && echo "[错误] PVE 8.x需基于Debian 12(bookworm)" && exit 1 ;;
    *) [[ -z $PVE_VER ]] && echo "[错误] 非PVE环境" && exit 1 || echo "[错误] 不支持的PVE版本" && exit 1 ;;
  esac
}

# 获取配置文件路径
get_config_path() {
  case $1 in
    1) echo "/etc/apt/sources.list" ;;
    2) echo "/etc/apt/sources.list.d/pve.list" ;;
    3) echo "/usr/share/perl5/PVE/APLInfo.pm" ;;
    *) echo "错误：未知配置类型" >&2; exit 1 ;;
  esac
}

# 镜像源配置（修正URL）
declare -A MIRRORS=(
  ["清华镜像站"]="https://mirrors.tuna.tsinghua.edu.cn/"
  ["阿里云镜像"]="https://mirrors.aliyun.com/"
  ["龙芯专线"]="http://mirrors.loongnix.cn/"
  ["官方源"]="https://enterprise.proxmox.com/"
)
mirror_names=("清华镜像站" "阿里云镜像" "龙芯专线" "官方源")

# 交互菜单系统
show_main_menu() {
  while true; do
    clear
    echo -e "\033[34m当前系统: ${PRETTY_NAME} | PVE版本: ${PVE_VER}\033[0m"
    echo "请选择配置类型："
    echo "1) 系统源 (/etc/apt/sources.list)"
    echo "2) PVE源 (/etc/apt/sources.list.d/pve.list)"
    echo "3) 模板源 (LXC模板库)"
    echo "0) 退出"
    read -p "选择: " -t 60 main_choice

    case $main_choice in
      1|2|3) show_mirror_menu $main_choice ;;
      0) exit 0 ;;
      *) echo -e "\033[31m错误：无效选项\033[0m"; sleep 0.5 ;;
    esac
  done
}

show_mirror_menu() {
  local config_type=$1
  clear
  echo -e "\033[32m当前配置路径: $(get_config_path $config_type)\033[0m"
  echo "可用镜像站："
  for ((i=0; i<${#mirror_names[@]}; i++)); do
    echo "$((i+1))) ${mirror_names[i]}"
  done
  echo "0) 返回上级"

  while :; do
    read -p "选择镜像站: " -t 60 mirror_choice
    case $mirror_choice in
      0) return ;;
      [1-4])
        local index=$((mirror_choice-1))
        [[ $index -lt ${#mirror_names[@]} ]] && {
          apply_mirror $config_type "${MIRRORS[${mirror_names[index]}]}"
          return
        }
        ;;
    esac
    echo -e "\033[31m错误：请输入0-4的有效选项\033[0m"
  done
}

apply_mirror() {
  local config_type=$1 base_url=$2
  local config_file=$(get_config_path $config_type)
  local backup_ext=$(date +%s).bak

  case $config_type in
    1)  # 系统源处理
      sudo sed -i.${backup_ext} "
        s|^#\?deb.*https://.*/debian |deb ${base_url}debian/|;
        s|^#\?deb.*https://.*/debian-security |deb ${base_url}debian-security/|;
        s|^#\?deb.*https://.*/debian \([^ ]*\)-updates |deb ${base_url}debian/\1-updates |
      " "$config_file"
      # 确保完整组件
      sudo sed -i "s/ main.*$/ main contrib non-free non-free-firmware/" "$config_file"
      ;;
    2)  # PVE源处理
      [[ "$base_url" == "https://enterprise.proxmox.com/" ]] && 
        local repo_line="deb ${base_url}pve/debian/pve/ $DEBIAN_VER pve-enterprise" ||
        local repo_line="deb ${base_url}proxmox/debian/pve/ $DEBIAN_VER pve-no-subscription"
      echo "$repo_line" | sudo tee "$config_file" >/dev/null
      ;;
    3)  # 模板源处理
      sudo sed -i.${backup_ext} \
        "s|\(our \$default_base_url = \).*|\1\"${base_url}proxmox/images/\";|" "$config_file"
      ;;
  esac

  echo -e "\033[32m配置已更新！备份文件: ${config_file}.${backup_ext}\033[0m"
  echo -e "\033[33m建议执行：apt update && apt upgrade -y\033[0m"
  read -p "按回车键返回主菜单"
}

# 初始化检测
check_compatibility
show_main_menu
