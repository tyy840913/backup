#!/bin/bash
# Proxmox VE 镜像源与系统优化工具 - 终极版
# 功能：
# 1. 快速切换 系统源 / PVE源 / LXC模板源
# 2. 禁用恼人的 "无有效订阅" 网页弹窗提示
# 3. 支持 清华/阿里/中科大/Proxmox官方 等常用源
# 4. 自动检测系统版本与CPU架构，提供兼容的源选项
# 5. 提供配置备份与恢复功能，操作更安全

# --- 全局变量与初始化 ---
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 预加载系统信息
if ! source /etc/os-release; then
    echo -e "${RED}[错误] 无法加载 /etc/os-release，非标准Debian系环境。${NC}"
    exit 1
fi
DEBIAN_VER=${VERSION_CODENAME}
PVE_VER=$(pveversion 2>/dev/null | grep -oP 'pve-manager/\K\d+')
ARCH=$(uname -m)

# --- 核心函数 ---

# 检查运行环境
check_environment() {
  # 1. 权限检查
  if [[ $(id -u) -ne 0 ]]; then
    echo -e "${RED}[错误] 请以 root 用户身份运行此脚本，或使用 'sudo bash $0'。${NC}"
    exit 1
  fi

  # 2. PVE 版本与 Debian 版本兼容性检查
  if [[ -z "$PVE_VER" ]]; then
    echo -e "${RED}[错误] 未检测到 PVE 环境，此脚本专为 Proxmox VE 设计。${NC}"
    exit 1
  fi

  case $PVE_VER in
    7) [[ "$DEBIAN_VER" != "bullseye" ]] && echo -e "${RED}[错误] PVE 7.x 需基于 Debian 11 (bullseye)，当前为 ${DEBIAN_VER}。${NC}" && exit 1 ;;
    8) [[ "$DEBIAN_VER" != "bookworm" ]] && echo -e "${RED}[错误] PVE 8.x 需基于 Debian 12 (bookworm)，当前为 ${DEBIAN_VER}。${NC}" && exit 1 ;;
    *) echo -e "${RED}[错误] 不支持的 PVE 版本: ${PVE_VER}。${NC}" && exit 1 ;;
  esac
  
  # 3. 检查必要的工具
  for cmd in sed grep tee awk; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}[错误] 缺少核心命令: $cmd，请先安装。${NC}"
        exit 1
    fi
  done
}

# 获取配置文件路径
get_config_path() {
  local config_type=$1
  case $config_type in
    1) echo "/etc/apt/sources.list" ;;
    2) echo "/etc/apt/sources.list.d/pve-enterprise.list" ;; # 官方建议的文件名
    3) echo "/usr/share/perl5/PVE/APLInfo.pm" ;;
    *) echo "错误：未知配置类型" >&2; exit 1 ;;
  esac
}

# 备份文件
backup_file() {
    local file_to_backup=$1
    if [[ -f "$file_to_backup" ]]; then
        local backup_file="${file_to_backup}.$(date +%Y%m%d_%H%M%S).bak"
        cp "$file_to_backup" "$backup_file"
        echo -e "${GREEN}已创建备份: ${backup_file}${NC}"
    fi
}

# --- 镜像源配置 ---
declare -A MIRRORS=(
  ["清华大学"]="https://mirrors.tuna.tsinghua.edu.cn"
  ["阿里云"]="https://mirrors.aliyun.com"
  ["中科大"]="https://mirrors.ustc.edu.cn"
  ["Proxmox 官方(无订阅)"]="http://download.proxmox.com"
  ["Proxmox 官方企业订阅源"]="https://enterprise.proxmox.com"
  ["龙芯(LoongArch)"]="http://mirrors.loongnix.cn"
)

# --- 菜单系统 ---

# 主菜单
show_main_menu() {
  while true; do
    clear
    echo -e "${BLUE}--- Proxmox VE 镜像源与系统优化工具 ---${NC}"
    echo -e "系统: ${PRETTY_NAME} (${ARCH}) | PVE: ${PVE_VER}.x"
    echo "------------------------------------------------"
    echo "------------------- APT 源配置 ------------------"
    echo " 1) 修改 Debian 系统源"
    echo " 2) 修改 Proxmox VE 源"
    echo " 3) 修改 LXC 模板源"
    echo "------------------- 系统优化 -------------------"
    echo " 4) 禁用 PVE 网页订阅提示"
    echo "------------------- 维护 -----------------------"
    echo " 5) 从备份恢复配置"
    echo " 0) 退出脚本"
    echo "------------------------------------------------"
    read -p "请输入选项 [0-5]: " main_choice

    case $main_choice in
      1|2|3) show_mirror_menu "$main_choice" ;;
      4) disable_subscription_nag ;;
      5) show_restore_menu ;;
      0) echo "脚本已退出。"; exit 0 ;;
      *) echo -e "${RED}无效选项，请重试。${NC}"; sleep 1 ;;
    esac
  done
}

# 镜像选择菜单
show_mirror_menu() {
  local config_type=$1
  local config_name
  case $config_type in
    1) config_name="Debian 系统源" ;;
    2) config_name="Proxmox VE 源" ;;
    3) config_name="LXC 模板源" ;;
  esac
  
  local available_mirrors=()
  for name in "${!MIRRORS[@]}"; do
      if [[ "$name" == "龙芯(LoongArch)" && "$ARCH" != "loongarch64" ]]; then
          continue
      fi
      # 仅为Debian系统源提供通用镜像
      if [[ "$config_type" -eq 1 ]]; then
          if [[ "$name" != "Proxmox"* ]]; then
              available_mirrors+=("$name")
          fi
      # 为PVE和LXC源提供Proxmox相关镜像
      else
          if [[ "$name" == "Proxmox"* ]]; then
              available_mirrors+=("$name")
          # 国内镜像也提供PVE和LXC镜像
          elif [[ "$name" == "清华大学" || "$name" == "阿里云" || "$name" == "中科大" || "$name" == "龙芯(LoongArch)" ]]; then
              available_mirrors+=("$name")
          fi
      fi
  done

  clear
  echo -e "${BLUE}--- 正在配置: ${config_name} ---${NC}"
  echo -e "文件路径: $(get_config_path "$config_type")"
  echo "----------------------------------------"
  
  for i in "${!available_mirrors[@]}"; do
    local mirror_name="${available_mirrors[i]}"
    local note=""
    if [[ "$mirror_name" == "Proxmox 官方企业订阅源" ]]; then
        note=" (${YELLOW}需要有效订阅${NC})"
    elif [[ "$mirror_name" == "龙芯(LoongArch)" ]]; then
        note=" (${YELLOW}仅限LoongArch架构${NC})"
    fi
    echo " $((i+1))) ${mirror_name}${note}"
  done
  echo " 0) 返回主菜单"
  echo "----------------------------------------"

  while true; do
    read -p "请选择一个镜像源 [0-$((${#available_mirrors[@]}))]: " mirror_choice
    if [[ "$mirror_choice" == "0" ]]; then
      return
    fi
    if [[ "$mirror_choice" =~ ^[0-9]+$ ]] && [ "$mirror_choice" -gt 0 ] && [ "$mirror_choice" -le "${#available_mirrors[@]}" ]; then
      local selected_name="${available_mirrors[$((mirror_choice-1))]}"
      local selected_url="${MIRRORS[$selected_name]}"
      apply_mirror "$config_type" "$selected_name" "$selected_url"
      read -n 1 -s -r -p "按任意键返回主菜单..."
      return
    else
      echo -e "${RED}无效输入，请输入 0 到 $((${#available_mirrors[@]})) 之间的数字。${NC}"
    fi
  done
}


# --- 禁用订阅提示 ---
disable_subscription_nag() {
    clear
    echo -e "${BLUE}--- 禁用 PVE 网页订阅提示 ---${NC}"
    local js_file="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
    local pvemanager_js="/usr/share/pve-manager/js/pvemanagerlib.js"

    # 确定目标文件
    if [[ -f "$pvemanager_js" ]] && grep -q "PVE.UI.Debian.activateSubscription" "$pvemanager_js"; then
        echo -e "\n${YELLOW}检测到 PVE 8.1+ 环境，目标文件为 pvemanagerlib.js。${NC}"
        js_file=$pvemanager_js
    elif [ ! -f "$js_file" ]; then
        echo -e "${RED}错误: 未找到JS目标文件。可能是 proxmox-widget-toolkit 包未安装或路径已更改。${NC}"
        sleep 2
        return
    else
        echo -e "\n${YELLOW}检测到 PVE 7.x/8.0.x 环境，目标文件为 proxmoxlib.js。${NC}"
    fi

    echo "此操作将修改系统文件以禁用“无有效订阅”的弹窗。"
    echo -e "${YELLOW}注意: 相关软件包更新后此修改可能会被覆盖，届时需重新运行此脚本。${NC}"

    # 幂等性检查
    local already_patched=true
    if [[ "$js_file" == "$pvemanager_js" ]]; then
        # PVE 8.1+ check
        if ! grep -q "PVE.UI.Debian.SubscriptionEnabled" "$js_file"; then
            already_patched=false
        fi
    elif [[ $PVE_VER -eq 8 ]]; then
        # PVE 8.0 check
        if grep -q "Ext.Msg.show" "$js_file"; then
            already_patched=false
        fi
    elif [[ $PVE_VER -eq 7 ]]; then
        # PVE 7 check
        if grep -q "data.status !== 'Active'" "$js_file"; then
            already_patched=false
        fi
    fi

    if $already_patched; then
        echo -e "\n${GREEN}检测到订阅提示可能已被禁用，无需重复操作。${NC}"
        read -n 1 -s -r -p "按任意键返回主菜单..."
        return
    fi
    
    read -p "您确定要继续吗? (y/N): " confirm
    if [[ "${confirm,,}" != "y" ]]; then
        echo "操作已取消。"
        sleep 1
        return
    fi

    echo "正在应用补丁..."
    backup_file "$js_file"

    local success=false
    if [[ "$js_file" == "$pvemanager_js" ]]; then
        # PVE 8.1+ patch
        if sed -i "s/PVE.UI.Debian.activateSubscription()/PVE.UI.Debian.SubscriptionEnabled = true;/" "$js_file"; then
            success=true
        fi
    elif [[ $PVE_VER -eq 8 ]]; then
        # PVE 8.0 patch
        sed -i "s/void({ \/\/ PVE-No-Subscription-Hax/Ext.Msg.show({/g" "$js_file" >/dev/null 2>&1
        if sed -i "s/Ext.Msg.show({/void({ \/\/ PVE-No-Subscription-Hax/g" "$js_file"; then
            success=true
        fi
    elif [[ $PVE_VER -eq 7 ]]; then
        # PVE 7 patch
        if sed -i "s/data.status !== 'Active'/false/g" "$js_file"; then
            success=true
        fi
    fi

    if $success; then
        echo -e "${GREEN}补丁应用成功！${NC}"
        echo "正在重启 PVE 网页服务以应用更改..."
        systemctl restart pveproxy.service
        echo -e "\n${YELLOW}重要提示: 请务必清理您的浏览器缓存，然后重新加载网页才能看到效果！${NC}"
        echo "(通常是按 Ctrl + Shift + R 或 Cmd + Shift + R)"
    else
        echo -e "${RED}应用补丁失败。文件可能已被修改或版本不兼容。${NC}"
        echo "如果您之前使用了其他工具，请先从备份中恢复原始文件再试。"
    fi
    
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# 恢复菜单
show_restore_menu() {
    clear
    echo -e "${BLUE}--- 从备份恢复配置 ---${NC}"
    echo "请选择要恢复的配置文件类型："
    echo " 1) Debian 系统源 (/etc/apt/sources.list)"
    echo " 2) Proxmox VE 源 (/etc/apt/sources.list.d/pve-enterprise.list)"
    echo " 3) LXC 模板源 (/usr/share/perl5/PVE/APLInfo.pm)"
    echo " 4) PVE 网页JS文件 (自动检测)"
    echo " 0) 返回主菜单"
    read -p "请输入选项 [0-4]: " restore_choice
    
    [[ "$restore_choice" == "0" ]] && return
    
    local config_file
    case $restore_choice in
        1) config_file=$(get_config_path 1) ;;
        2) config_file=$(get_config_path 2) ;;
        3) config_file=$(get_config_path 3) ;;
        4) 
           local pvemanager_js="/usr/share/pve-manager/js/pvemanagerlib.js"
           local proxmoxlib_js="/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js"
           # 优先检查 pvemanager_js 的备份是否存在
           if compgen -G "${pvemanager_js}.*.bak" > /dev/null; then
               config_file=$pvemanager_js
           else
               config_file=$proxmoxlib_js
           fi
           echo -e "${YELLOW}自动检测到JS文件为: ${config_file}${NC}"
           ;;
        *) echo -e "${RED}无效选项。${NC}"; sleep 1; return ;;
    esac
    
    local backups=($(ls -1 "${config_file}."*.bak 2>/dev/null | sort -r))

    if [ ${#backups[@]} -eq 0 ]; then
        echo -e "${YELLOW}未找到 '${config_file}' 的任何备份文件。${NC}"
        sleep 2; return
    fi

    echo "找到以下备份文件 (按时间倒序):"
    select backup_path in "${backups[@]}" "取消操作"; do
        if [[ "$backup_path" == "取消操作" ]]; then
            echo "操作已取消。"; break
        elif [[ -n "$backup_path" ]]; then
            echo -e "即将用 '${backup_path}'\n覆盖 '${config_file}'"
            read -p "确定要恢复吗? (y/N): " confirm
            if [[ "${confirm,,}" == "y" ]]; then
                cp "$backup_path" "$config_file"
                echo -e "${GREEN}文件已恢复成功！${NC}"
                if [[ "$restore_choice" == "4" ]]; then
                    echo "正在重启pveproxy服务..."
                    systemctl restart pveproxy.service
                    echo -e "${YELLOW}请清理浏览器缓存后查看效果。${NC}"
                fi
            else
                echo "恢复操作已取消。"
            fi
            break
        else
            echo -e "${RED}无效选择，请重试。${NC}"
        fi
    done
    read -n 1 -s -r -p "按任意键返回主菜单..."
}


# --- 应用配置的核心逻辑 ---
apply_mirror() {
  local config_type=$1; local mirror_name=$2; local base_url=$3
  local config_file=$(get_config_path "$config_type")
  echo -e "\n正在应用 '${mirror_name}' 到 '${config_file}' ..."
  backup_file "$config_file"
  case $config_type in
    1) apply_debian_mirror "$config_file" "$base_url" ;;
    2) apply_pve_mirror "$config_file" "$mirror_name" "$base_url" ;;
    3) apply_lxc_mirror "$config_file" "$base_url" ;;
  esac
  echo -e "${GREEN}配置已成功更新！${NC}"
  echo -e "${YELLOW}建议稍后手动执行 'apt update && apt full-upgrade -y' 来应用更改。${NC}"
}
apply_debian_mirror() {
  local config_file=$1; local base_url=$2
  local components="main contrib non-free"
  [[ "$DEBIAN_VER" == "bookworm" ]] && components="main contrib non-free non-free-firmware"
  # 针对龙芯源的特殊处理
  if [[ "$ARCH" == "loongarch64" ]] && [[ "$base_url" == "http://mirrors.loongnix.cn" ]]; then
      base_url="${base_url}/debian"
  fi
  cat > "$config_file" <<EOF
# Debian ${DEBIAN_VER} - Generated by PVE Tool
deb ${base_url}/ ${DEBIAN_VER} ${components}
deb ${base_url}/ ${DEBIAN_VER}-updates ${components}
deb ${base_url}-security/ ${DEBIAN_VER}-security ${components}
EOF
}
apply_pve_mirror() {
  local config_file=$1; local mirror_name=$2; local base_url=$3
  local pve_no_sub_file="/etc/apt/sources.list.d/pve-no-subscription.list"
  
  # 清理旧配置
  sed -i 's/^deb/#deb/' "$config_file" 2>/dev/null
  if [ -f "$pve_no_sub_file" ]; then
    sed -i 's/^deb/#deb/' "$pve_no_sub_file" 2>/dev/null
  fi

  if [[ "$mirror_name" == "Proxmox 官方企业订阅源" ]]; then
    echo "deb ${base_url}/pve ${DEBIAN_VER} pve-enterprise" > "$config_file"
    echo -e "${GREEN}已启用企业订阅源，并注释了其他PVE源。${NC}"
  else
    local pve_path_prefix="proxmox"
    [[ "$mirror_name" == "Proxmox 官方(无订阅)" ]] && pve_path_prefix="pve"
    echo "deb ${base_url}/${pve_path_prefix} ${DEBIAN_VER} pve-no-subscription" > "$pve_no_sub_file"
    echo -e "${GREEN}已启用无订阅源，并注释了企业订阅源。${NC}"
  fi
}
apply_lxc_mirror() {
    local config_file=$1; local base_url=$2
    local lxc_url="${base_url}/proxmox/images/"
    if [[ "$base_url" == "http://download.proxmox.com" ]]; then
        lxc_url="${base_url}/images/"
    fi
    sed -i "s|^our \$default_base_url = .*|our \$default_base_url = \"${lxc_url}\";|" "$config_file"
}

# --- 脚本入口 ---
check_environment
show_main_menu
