#!/bin/bash

GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; RED=$'\033[0;31m'; CYAN=$'\033[0;36m'; NC=$'\033[0m'

TOOL_BINS=(git gh git-lfs wrangler cloudflared)
TOOL_NAMES=("Git" "GitHub CLI" "Git LFS" "Wrangler CLI" "Cloudflare Tunnel")
TOOL_REQUIRED=(true true false true false)

get_ver() {
  case $1 in
    git)         git --version 2>/dev/null | sed -n 's/.*git version \([0-9.]*\).*/\1/p' ;;
    gh)          gh --version 2>/dev/null | sed -n 's/.*gh version \([0-9.]*\).*/\1/p' ;;
    git-lfs)     git lfs version 2>/dev/null | sed -n 's/.*git-lfs\/\([0-9.]*\).*/\1/p' ;;
    wrangler)    wrangler --version 2>/dev/null | sed -n 's/.*\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p' ;;
    cloudflared) cloudflared --version 2>/dev/null | sed -n 's/.*version \([0-9.]*\).*/\1/p' ;;
  esac
}

installed_bins=(); installed_names=(); installed_vers=()
uninstalled_bins=(); uninstalled_names=()

check_all() {
  installed_bins=(); installed_names=(); installed_vers=()
  uninstalled_bins=(); uninstalled_names=()
  echo ""
  echo -e "  ${YELLOW}⏳ 正在检查工具安装情况...${NC}"
  echo ""
  for i in "${!TOOL_BINS[@]}"; do
    local bin="${TOOL_BINS[$i]}" name="${TOOL_NAMES[$i]}"
    echo -n "    $name ... "
    local ver=$(get_ver "$bin")
    if [[ -n "$ver" ]]; then
      echo -e "${GREEN}v$ver${NC}"
      installed_bins+=("$bin"); installed_names+=("$name"); installed_vers+=("$ver")
    else
      echo -e "${RED}未安装${NC}"
      uninstalled_bins+=("$bin"); uninstalled_names+=("$name")
    fi
  done
  echo ""
  echo -e "  ${GREEN}✓ 检查完成${NC}"
}

show_results() {
  echo ""
  echo -e "  ${CYAN}══════════════════════════════════${NC}"
  echo -e "  ${CYAN}  工具安装状态${NC}"
  echo -e "  ${CYAN}══════════════════════════════════${NC}"
  for i in "${!TOOL_BINS[@]}"; do
    local bin="${TOOL_BINS[$i]}" name="${TOOL_NAMES[$i]}" ver=""
    local flag; ${TOOL_REQUIRED[$i]} && flag="${YELLOW}[必选]${NC}" || flag="${CYAN}[可选]${NC}"
    for j in "${!installed_bins[@]}"; do
      [[ "${installed_bins[$j]}" == "$bin" ]] && ver="${installed_vers[$j]}" && break
    done
    if [[ -n "$ver" ]]; then
      printf "  ${CYAN}│${NC} %s %-22s ${GREEN}v%-12s${NC}\n" "$flag" "$name" "$ver"
    else
      printf "  ${CYAN}│${NC} %s %-22s ${RED}%-14s${NC}\n" "$flag" "$name" "未安装"
    fi
  done
  echo -e "  ${CYAN}══════════════════════════════════${NC}"
  echo ""
}

install_one() {
  local bin=$1 name=$2
  echo -e "${YELLOW}  ↓ 安装 $name ...${NC}"
  case $bin in
    cloudflared)
      curl -sL --connect-timeout 15 --max-time 120 "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb" -o /tmp/cloudflared.deb && dpkg -i /tmp/cloudflared.deb
      ;;
    wrangler)
      npm install -g wrangler
      ;;
    *)
      apt install -y "$bin"
      ;;
  esac
  local ver=$(get_ver "$bin")
  if [[ -n "$ver" ]]; then
    echo -e "${GREEN}  ✓ $name v$ver 安装成功${NC}"
  else
    echo -e "${RED}  ✗ $name 安装失败${NC}"
  fi
}

uninstall_one() {
  local bin=$1 name=$2
  echo -e "${YELLOW}  ↓ 卸载 $name ...${NC}"
  case $bin in
    cloudflared)
      dpkg -r cloudflared
      ;;
    wrangler)
      npm uninstall -g wrangler
      ;;
    *)
      apt purge -y "$bin"
      ;;
  esac
  if ! command -v "$bin" &>/dev/null; then
    echo -e "${GREEN}  ✓ $name 已卸载${NC}"
  else
    echo -e "${RED}  ✗ $name 卸载失败${NC}"
  fi
}

update_one() {
  local bin=$1 name=$2
  local ver=$(get_ver "$bin")
  if [[ -z "$ver" ]]; then
    echo -e "${YELLOW}  ✗ $name 未安装，跳过更新${NC}"
    return
  fi
  echo -e "${YELLOW}  ↓ 更新 $name v$ver ...${NC}"
  case $bin in
    cloudflared)
      curl -sL --connect-timeout 15 --max-time 120 "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb" -o /tmp/cloudflared.deb && dpkg -i /tmp/cloudflared.deb
      ;;
    wrangler)
      npm install -g wrangler
      ;;
    *)
      apt install -y "$bin"
      ;;
  esac
  local new_ver=$(get_ver "$bin")
  if [[ -n "$new_ver" ]]; then
    if [[ "$ver" == "$new_ver" ]]; then
      echo -e "${GREEN}  ✓ $name v$ver 已是最新版本${NC}"
    else
      echo -e "${GREEN}  ✓ $name 已更新至 v$ver → v$new_ver${NC}"
    fi
  else
    echo -e "${RED}  ✗ $name 更新失败${NC}"
  fi
}

menu_update() {
  if [[ ${#installed_bins[@]} -eq 0 ]]; then
    echo -e "${YELLOW}没有已安装的工具需要更新${NC}"
    return
  fi
  for i in "${!installed_bins[@]}"; do
    update_one "${installed_bins[$i]}" "${installed_names[$i]}"
  done
  echo ""
  echo -e "${GREEN}全部更新完成${NC}"
  NEED_CHECK=1
}

menu_install() {
  if [[ ${#uninstalled_bins[@]} -eq 0 ]]; then
    echo -e "${YELLOW}所有工具已安装，无需安装${NC}"
    return
  fi
  echo ""
  echo -e "  ${CYAN}可安装的工具列表：${NC}"
  echo ""
  for i in "${!uninstalled_bins[@]}"; do
    local idx=$((i + 1))
    echo -e "  ${CYAN}${idx}${NC}) ${uninstalled_names[$i]}"
  done
  echo ""
  read -p "  按回车安装全部 | 输入序号指定安装 | 0 返回上级: " input

  # 0 = 返回上级
  [[ "$input" == "0" ]] && return

  local any=0
  if [[ -z "$input" ]]; then
    any=1
    for i in "${!uninstalled_bins[@]}"; do
      install_one "${uninstalled_bins[$i]}" "${uninstalled_names[$i]}"
    done
  else
    for ((k=0; k<${#input}; k++)); do
      local ch="${input:$k:1}"
      if [[ "$ch" =~ [1-9] ]] && (( ch <= ${#uninstalled_bins[@]} )); then
        any=1
        local arr_idx=$((ch - 1))
        install_one "${uninstalled_bins[$arr_idx]}" "${uninstalled_names[$arr_idx]}"
      fi
    done
  fi
  if (( any == 1 )); then
    echo ""
    echo -e "${GREEN}操作完成${NC}"
    NEED_CHECK=1
  fi
}

menu_uninstall() {
  if [[ ${#installed_bins[@]} -eq 0 ]]; then
    echo -e "${YELLOW}没有已安装的工具${NC}"
    return
  fi
  echo ""
  echo -e "  ${CYAN}已安装的工具列表：${NC}"
  echo ""
  for i in "${!installed_bins[@]}"; do
    local idx=$((i + 1))
    echo -e "  ${CYAN}${idx}${NC}) ${installed_names[$i]}"
  done
  echo ""
  read -p "  按回车卸载全部 | 输入序号指定卸载 | 0 返回上级: " input

  # 0 = 返回上级
  [[ "$input" == "0" ]] && return

  local any=0
  if [[ -z "$input" ]]; then
    any=1
    for i in "${!installed_bins[@]}"; do
      uninstall_one "${installed_bins[$i]}" "${installed_names[$i]}"
    done
  else
    for ((k=0; k<${#input}; k++)); do
      local ch="${input:$k:1}"
      if [[ "$ch" =~ [1-9] ]] && (( ch <= ${#installed_bins[@]} )); then
        any=1
        local arr_idx=$((ch - 1))
        uninstall_one "${installed_bins[$arr_idx]}" "${installed_names[$arr_idx]}"
      fi
    done
  fi
  if (( any == 1 )); then
    echo ""
    echo -e "${GREEN}操作完成${NC}"
    NEED_CHECK=1
  fi
}

# --- 主流程 ---

NEED_CHECK=1

while true; do
    clear
    if (( NEED_CHECK == 1 )); then
        check_all
        clear
        NEED_CHECK=0
    fi
    show_results
    echo ""
    echo -e "  ${CYAN}━━ 工具管理菜单 ━━━━${NC}"
    echo ""
    echo -e "  ${CYAN}1${NC}) 更新已安装工具"
    echo -e "  ${CYAN}2${NC}) 安装工具"
    echo -e "  ${CYAN}3${NC}) 卸载工具"
    echo -e "  ${CYAN}0${NC}) 退出"
    echo ""
    read -p "  请选择 [0-3]: " choice
    case "$choice" in
        1) menu_update; echo ""; read -p "  按回车返回主菜单..." ;;
        2) menu_install; (( NEED_CHECK == 1 )) && { echo ""; read -p "  按回车返回主菜单..."; } ;;
        3) menu_uninstall; (( NEED_CHECK == 1 )) && { echo ""; read -p "  按回车返回主菜单..."; } ;;
        0) clear; echo -e "${GREEN}再见${NC}"; exit 0 ;;
        *) echo -e "  ${RED}无效选项${NC}"; sleep 1 ;;
    esac
done
