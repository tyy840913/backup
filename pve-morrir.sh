#!/bin/bash
# 版本检测函数
check_compatibility() {
  # 获取系统信息
  source /etc/os-release
  DEBIAN_VER=${VERSION_CODENAME}
  PVE_VER=$(pveversion | grep -oP 'pve-manager/\K\d+\.\d+')
  
  # 版本兼容校验
  case $PVE_VER in
    7.*) [[ $DEBIAN_VER != "bullseye" ]] && echo "[错误] PVE 7.x需基于Debian 11(bullseye)" && exit 1 ;;
    8.*) [[ $DEBIAN_VER != "bookworm" ]] && echo "[错误] PVE 8.x需基于Debian 12(bookworm)" && exit 1 ;;
    *) echo "[错误] 不支持的PVE版本" && exit 1 ;;
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

# 镜像源配置库（修正为正确的基础URL）
declare -A MIRRORS=(
  ["清华镜像站"]="https://mirrors.tuna.tsinghua.edu.cn/"
  ["阿里云镜像"]="https://mirrors.aliyun.com/"
  ["龙芯专线"]="http://mirrors.loongnix.cn/"
  ["官方源"]="https://enterprise.proxmox.com/"
)
mirror_names=("清华镜像站" "阿里云镜像" "龙芯专线" "官方源") # 固定显示顺序

# 交互菜单系统
show_main_menu() {
  while true; do
    clear
    echo -e "\033[34m当前系统: ${PRETTY_NAME} | PVE版本: ${PVE_VER}\033[0m"
    echo "请选择配置类型："
    echo "1) 系统源 (/etc/apt/sources.list)"
    echo "2) PVE源 (/etc/apt/sources.list.d/pve.list)"
    echo "3) 模板源 (LXC模板库)"
    echo "q) 退出"
    read -p "选择: " main_choice

    case $main_choice in
      1|2|3) show_mirror_menu $main_choice ;;
      q) exit 0 ;;
      *) echo "无效输入"; sleep 1 ;;
    esac
  done
}

show_mirror_menu() {
  local config_type=$1
  while true; do
    clear
    echo -e "\033[32m当前配置路径: $(get_config_path $config_type)\033[0m"
    echo "可用镜像站："
    local i=1
    for name in "${mirror_names[@]}"; do
      echo "$i) $name"
      ((i++))
    done
    echo "$i) 自定义URL"
    echo "b) 返回上级"
    
    read -p "选择镜像站: " mirror_choice
    [[ $mirror_choice == "b" ]] && return
    
    if [[ $mirror_choice -eq $i ]]; then
      read -p "输入镜像站URL（以/结尾）: " custom_url
      apply_mirror $config_type "$custom_url"
      break
    else
      local selected_mirror=${mirror_names[$((mirror_choice-1))]}
      apply_mirror $config_type "${MIRRORS[$selected_mirror]}"
      break
    fi
  done
}

# 应用配置函数
apply_mirror() {
  local config_type=$1
  local base_url=$2
  local config_file=$(get_config_path $config_type)
  
  # 根据配置类型生成URL
  case $config_type in
    1) # 系统源：Debian基础源
      new_url="deb ${base_url}debian/ $DEBIAN_VER main contrib non-free non-free-firmware"
      new_url+="\ndeb ${base_url}debian-security $DEBIAN_VER-security main contrib non-free non-free-firmware"
      new_url+="\ndeb ${base_url}debian $DEBIAN_VER-updates main contrib non-free non-free-firmware"
      sudo cp "$config_file" "${config_file}.bak"
      echo -e "$new_url" | sudo tee "$config_file" >/dev/null
      ;;
    2) # PVE源
      new_url="deb ${base_url}proxmox/debian/pve/ $DEBIAN_VER pve-no-subscription"
      sudo sed -i.bak "s|^deb.*pve-no-subscription.*$|$new_url|" "$config_file"
      ;;
    3) # 模板源
      new_url="${base_url}proxmox/images/"
      sudo sed -i.bak "s|\(our \$default_base_url = \)\".*\"|\1\"$new_url\"|" "$config_file"
      ;;
  esac

  echo -e "\033[32m源配置已更新！建议执行 apt update && apt dist-upgrade\033[0m"
  read -p "按回车键继续..."
}

# 初始化检测
check_compatibility
show_main_menu
