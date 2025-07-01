#!/bin/bash

# 函数：检查是否为 root 用户
check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "此脚本需要root权限。请使用 sudo 运行。"
    exit 1
  fi
}

# 函数：检查 ufw 是否已安装
check_ufw_installed() {
  if ! command -v ufw &> /dev/null
  then
      echo "ufw (Uncomplicated Firewall) 未安装。此脚本需要 ufw。"
      echo "请运行 'sudo apt update && sudo apt install ufw' 来安装它，然后再次运行脚本。"
      exit 1
  fi
}

# 函数：确保 ufw 启用 IPv6 管理
ensure_ufw_ipv6_enabled() {
  # 检查 /etc/default/ufw 中的 UFW_IPV6 设置
  if ! grep -q "^UFW_IPV6=yes" /etc/default/ufw; then
    echo "在 /etc/default/ufw 中未找到 UFW_IPV6=yes。正在尝试启用 IPv6 管理..."
    # 使用 sed 修改配置文件，确保 UFW_IPV6=yes
    sudo sed -i '/^UFW_IPV6=/c\UFW_IPV6=yes' /etc/default/ufw
    if [ $? -eq 0 ]; then
      echo "已成功设置 UFW_IPV6=yes。为了使更改生效，如果 ufw 处于活动状态，将尝试重新加载它。"
      # 尝试重新加载 ufw 以使 IPv6 更改生效
      if ufw status | grep -q "Status: active"; then
        echo "正在重新加载 ufw 以应用 IPv6 配置更改..."
        ufw reload # 这将重新加载规则
        if [ $? -ne 0 ]; then
          echo "警告: 重新加载 ufw 失败。可能需要手动重启 ufw 或系统。"
        fi
      fi
    else
      echo "!!! 警告: 自动设置 UFW_IPV6=yes 失败。请手动检查并编辑 /etc/default/ufw 文件。!!!"
    fi
  else
    echo "ufw 的 IPv6 管理已启用 (UFW_IPV6=yes)。"
  fi
}

# 函数：检查并开放内网访问以及外网常用端口访问 (选项 2)
# 适用于 IPv4 和 IPv6
check_and_open_internal_and_common_external_ports() {
  echo ">>> 正在检查并配置：开放内网访问及外网常用端口访问 (IPv4 和 IPv6) <<<"

  local config_needed=false

  # 检查默认策略
  if ! ufw status verbose | grep -q "Default incoming policy: deny" || \
     ! ufw status verbose | grep -q "Default outgoing policy: allow"; then
    echo "默认策略不符合要求，需要配置。"
    config_needed=true
  fi

  # 检查常用端口规则
  if ! ufw status verbose | grep -q "22/tcp.*ALLOW IN" || \
     ! ufw status verbose | grep -q "80/tcp.*ALLOW IN" || \
     ! ufw status verbose | grep -q "443/tcp.*ALLOW IN"; then
    echo "常用外部端口规则不符合要求，需要配置。"
    config_needed=true
  fi

  # 检查 IPv4 内网规则
  if ! ufw status verbose | grep -q "10.0.0.0/8.*ALLOW IN" || \
     ! ufw status verbose | grep -q "172.16.0.0/12.*ALLOW IN" || \
     ! ufw status verbose | grep -q "192.168.0.0/16.*ALLOW IN"; then
    echo "IPv4 内网规则不符合要求，需要配置。"
    config_needed=true
  fi

  # 检查 IPv6 内网规则
  if ! ufw status verbose | grep -q "fc00::/7.*ALLOW IN"; then
    echo "IPv6 内网规则不符合要求，需要配置。"
    config_needed=true
  fi

  if [ "$config_needed" = false ] && ufw status | grep -q "Status: active"; then
    echo "防火墙配置已符合要求且 ufw 已启用，无需重复配置。"
    ufw status verbose
    return 0
  fi

  echo "正在配置防火墙..."

  # 首先重置规则以确保干净的状态
  echo "正在重置 ufw 规则到默认状态 (IPv4 和 IPv6)..."
  ufw --force reset
  if [ $? -ne 0 ]; then
    echo "重置 ufw 规则失败。请检查错误信息。"
    return 1
  fi
  echo "ufw 规则已成功重置。"

  # 设置默认策略：拒绝传入，允许传出
  echo "正在设置 ufw 默认策略：传入拒绝，传出允许 (IPv4 和 IPv6)..."
  ufw default deny incoming
  ufw default allow outgoing
  if [ $? -ne 0 ]; then
    echo "设置 ufw 默认策略失败。请检查错误信息。"
    return 1
  fi
  echo "ufw 默认策略已设置。"

  # 开放常用的外部端口 (TCP)
  echo "正在开放外网常用端口 (22, 80, 443) (IPv4 和 IPv6)..."
  ufw allow 22/tcp comment '允许 SSH (IPv4/IPv6)'
  ufw allow 80/tcp comment '允许 HTTP (IPv4/IPv6)'
  ufw allow 443/tcp comment '允许 HTTPS (IPv4/IPv6)'
  if [ $? -ne 0 ]; then
    echo "开放外网常用端口失败。请检查错误信息。"
    return 1
  fi
  echo "外网常用端口已开放。"

  # 开放内网（RFC1918 私有地址空间 - IPv4）所有访问
  echo "正在开放内网（私有 IP 地址范围 - IPv4）所有访问..."
  ufw allow from 10.0.0.0/8 comment '允许来自 10.0.0.0/8 的所有连接'
  ufw allow from 172.16.0.0/12 comment '允许来自 172.16.0.0/12 的所有连接'
  ufw allow from 192.168.0.0/16 comment '允许来自 192.168.0.0/16 的所有连接'
  if [ $? -ne 0 ]; then
    echo "开放 IPv4 内网访问失败。请检查错误信息。"
    return 1
  fi
  echo "IPv4 内网访问已开放。"

  # 开放内网（IPv6 ULA - Unique Local Address）所有访问
  # fc00::/7 是 IPv6 的唯一本地地址范围
  echo "正在开放内网（IPv6 ULA 地址范围 fc00::/7）所有访问..."
  ufw allow from fc00::/7 comment '允许来自 fc00::/7 (IPv6 ULA) 的所有连接'
  if [ $? -ne 0 ]; then
    echo "开放 IPv6 内网访问失败。请检查错误信息。"
    return 1
  fi
  echo "IPv6 内网访问已开放。"

  # 启用 ufw
  echo "正在启用 ufw..."
  ufw enable
  if [ $? -eq 0 ]; then
    echo "ufw 已成功启用。"
  else
    echo "启用 ufw 失败。请检查错误信息。"
    return 1
  fi

  echo "防火墙配置完成：内网开放，外网只开放 22, 80, 443 端口 (IPv4 和 IPv6)。"
  echo "当前 ufw 状态:"
  ufw status verbose
  return 0
}

# 函数：手动开放端口 (新选项 - 选项 1)
# 适用于 IPv4 和 IPv6
manual_open_ports() {
  echo ">>> 正在执行：手动开放端口 (IPv4 和 IPv6) <<<"

  read -p "请输入要开放的端口或端口范围 (例如: 80 22 5000:6000 7000-8000), 多个请用空格分隔: " ports_input
  if [ -z "$ports_input" ]; then
    echo "未输入端口。操作取消。"
    return 1
  fi

  read -p "选择协议 (tcp/udp/both): " protocol_input
  protocol_input=$(echo "$protocol_input" | tr '[:upper:]' '[:lower:]') # 转换为小写

  case "$protocol_input" in
    tcp|udp|both)
      ;;
    *)
      echo "无效的协议选择。请输入 tcp, udp 或 both。"
      return 1
      ;;
  esac

  echo "正在处理端口规则..."
  for entry in $ports_input; do
    local port_start=""
    local port_end=""
    local is_range=false

    # 检查是否为范围 (支持冒号或横杠)
    if [[ "$entry" =~ ^([0-9]+)[:\-]([0-9]+)$ ]]; then
      port_start=${BASH_REMATCH[1]}
      port_end=${BASH_REMATCH[2]}
      is_range=true
    elif [[ "$entry" =~ ^[0-9]+$ ]]; then
      port_start=$entry
      port_end=$entry # 单个端口也当做范围的特殊情况处理
    else
      echo "警告: 无效的端口或端口范围格式 '$entry'，跳过。"
      continue
    fi

    # 验证端口号
    if (( port_start < 1 || port_start > 65535 )) || \
       (( port_end < 1 || port_end > 65535 )); then
      echo "警告: 端口号 '$entry' 无效 (必须在 1-65535 之间)，跳过。"
      continue
    fi

    if [ "$is_range" = true ] && (( port_start >= port_end )); then
      echo "警告: 端口范围 '$entry' 无效 (起始端口必须小于结束端口)，跳过。"
      continue
    fi

    # 应用 ufw 规则
    local current_protocols=()
    if [ "$protocol_input" == "tcp" ] || [ "$protocol_input" == "both" ]; then
      current_protocols+=("tcp")
    fi
    if [ "$protocol_input" == "udp" ] || [ "$protocol_input" == "both" ]; then
      current_protocols+=("udp")
    fi

    for proto in "${current_protocols[@]}"; do
      if [ "$is_range" = true ]; then
        echo "  正在开放端口范围 ${port_start}:${port_end}/${proto} (IPv4/IPv6)..."
        ufw allow "${port_start}:${port_end}/${proto}" comment "手动开放端口范围 ${port_start}-${port_end} (${proto})"
      else
        echo "  正在开放端口 ${port_start}/${proto} (IPv4/IPv6)..."
        ufw allow "${port_start}/${proto}" comment "手动开放端口 ${port_start} (${proto})"
      fi
      if [ $? -ne 0 ]; then
        echo "!!! 错误: 开放端口 '$entry' 失败 (${proto})。请检查错误信息。!!!"
      fi
    done
  done

  echo "手动开放端口操作完成。建议检查 ufw 状态。"
  ufw status verbose
  return 0
}

# 主菜单
main_menu() {
  check_root
  check_ufw_installed
  ensure_ufw_ipv6_enabled # 确保 IPv6 管理已启用

  # 脚本运行时自动检查并开放内网访问以及常用端口访问
  check_and_open_internal_and_common_external_ports

  while true; do
    echo ""
    echo "--- 防火墙管理脚本 ---"
    echo "请选择一个防火墙配置选项："
    echo "1. 手动开放端口或端口范围 (IPv4 和 IPv6)"
    echo "2. 查看当前 ufw 状态"
    echo "3. 退出"
    echo ""

    read -p "请输入您的选择 [1-3]: " choice

    case $choice in
      1) # 新选项的入口
        manual_open_ports
        ;;
      2)
        echo "当前 ufw 状态:"
        ufw status verbose
        ;;
      3)
        echo "退出脚本。再见！"
        exit 0
        ;;
      *)
        echo "无效的选择。请输入 1 到 3 之间的数字。"
        ;;
    esac
  done
}

# 运行主菜单
main_menu
