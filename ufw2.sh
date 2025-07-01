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

# 函数：确保 ufw 启用 IPv6 管理 (根据Ubuntu系统特性调整为 IPV6=yes)
ensure_ufw_ipv6_enabled() {
  # 检查 /etc/default/ufw 中的 IPV6 设置
  # 使用更健壮的正则表达式，匹配 IPV6=yes，即使行尾有空格或注释
  if ! grep -qE "^IPV6=yes([[:space:]]*|#.*)?$" /etc/default/ufw; then
    echo "在 /etc/default/ufw 中未找到精确的 IPV6=yes 设置。正在尝试启用 IPv6 管理..."
    # 使用 sed 修改配置文件，确保 IPV6=yes
    # 这个 sed 命令会替换 IPV6=开头的整行
    sudo sed -i 's/^\(IPV6=\).*$/IPV6=yes/' /etc/default/ufw
    if [ $? -eq 0 ]; then
      echo "已成功设置 IPV6=yes。为了使更改生效，如果 ufw 处于活动状态，将尝试重新加载它。"
      # 尝试重新加载 ufw 以使 IPv6 更改生效
      if ufw status | grep -q "Status: active"; then
        echo "正在重新加载 ufw 以应用 IPv6 配置更改..."
        ufw reload # 这将重新加载规则
        if [ $? -ne 0 ]; then
          echo "警告: 重新加载 ufw 失败。可能需要手动重启 ufw 或系统。"
        fi
      fi
    else
      echo "!!! 警告: 自动设置 IPV6=yes 失败。请手动检查并编辑 /etc/default/ufw 文件。!!!"
    fi
  else
    echo "ufw 的 IPv6 管理已启用 (IPV6=yes)。"
  fi
}


# 函数：禁用防火墙并开放所有网络访问限制 (选项 1)
# 适用于 IPv4 和 IPv6
disable_firewall_completely() {
  echo ">>> 正在执行：禁用防火墙并开放所有网络访问限制 (IPv4 和 IPv6) <<<"

  # 确保 ufw 处于活动状态，以便我们可以禁用它
  # 如果 ufw 已经禁用，这里会打印信息但不会报错，重置操作会在后面进行
  if ufw status | grep -q "Status: inactive"; then
    echo "ufw 当前已禁用。为了确保完全开放，我们将重置其规则并设置默认策略。"
  else
    echo "正在禁用 ufw..."
    ufw disable
    if [ $? -eq 0 ]; then
      echo "ufw 已成功禁用。"
    else
      echo "禁用 ufw 失败。请检查错误信息。"
      return 1
    fi
  fi

  # 重置 ufw 规则到默认状态（这将删除所有自定义规则）
  # ufw --force reset 同时重置 IPv4 和 IPv6 规则
  echo "正在重置 ufw 规则到默认状态 (IPv4 和 IPv6)..."
  ufw --force reset
  if [ $? -eq 0 ]; then
    echo "ufw 规则已成功重置。"
  else
    echo "重置 ufw 规则失败。请检查错误信息。"
    return 1
  fi

  # 设置默认策略为允许所有传入和传出连接
  # ufw default allow 命令同时适用于 IPv4 和 IPv6
  echo "正在设置 ufw 默认策略为允许所有传入和传出连接 (IPv4 和 IPv6)..."
  ufw default allow incoming
  ufw default allow outgoing
  ufw default allow routed # 允许转发，如果系统作为路由器
  if [ $? -eq 0 ]; then
    echo "ufw 默认策略已设置为允许所有连接。"
  else
    echo "设置 ufw 默认策略失败。请检查错误信息。"
    return 1
  fi

  echo "防火墙已禁用，并且网络访问限制已完全开放 (IPv4 和 IPv6)。"
  echo "请记住，这会使您的系统面临安全风险，除非您明确知道其含义。"
  ufw status verbose
  return 0
}

# 函数：开放内网访问以及外网常用端口访问 (选项 2)
# 适用于 IPv4 和 IPv6
open_internal_and_common_external_ports() {
  echo ">>> 正在执行：开放内网访问及外网常用端口访问 (IPv4 和 IPv6) <<<"

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

  # 定义常用端口列表，包括 TCP 和 UDP (如果适用)
  local common_ports=(
    "22/tcp" # SSH
    "80/tcp" # HTTP
    "443/tcp" # HTTPS
    "88/tcp" # Kerberos
  )

  echo "正在开放外网常用端口 (22, 80, 443, 88) (IPv4 和 IPv6)..."
  for port_proto in "${common_ports[@]}"; do
    local port=$(echo "$port_proto" | cut -d'/' -f1)
    local proto=$(echo "$port_proto" | cut -d'/' -f2)

    # 检查端口是否已经开放，避免重复添加
    if ufw status verbose | grep -qE "($port_proto[[:space:]]+ALLOW[[:space:]]+Anywhere)|(Anywhere[[:space:]]+$port_proto[[:space:]]+ALLOW)"; then
      echo "  端口 ${port_proto} 已开放，跳过添加。"
    else
      echo "  正在开放端口 ${port_proto} (IPv4 和 IPv6)..."
      ufw allow "${port_proto}" comment "允许 ${port} (${proto}) (IPv4/IPv6)"
      if [ $? -ne 0 ]; then
        echo "!!! 错误: 开放端口 ${port_proto} 失败。请检查错误信息。!!!"
      fi
    fi
  done
  echo "外网常用端口开放操作完成。"

  # 开放内网（RFC1918 私有地址空间 - IPv4）所有访问
  echo "正在开放内网（私有 IP 地址范围 - IPv4）所有访问..."
  ufw allow from 10.0.0.0/8 comment '允许来自 10.0.0.0/8 的所有连接 (IPv4)'
  ufw allow from 172.16.0.0/12 comment '允许来自 172.16.0.0/12 的所有连接 (IPv4)'
  ufw allow from 192.168.0.0/16 comment '允许来自 192.168.0.0/16 的所有连接 (IPv4)'
  if [ $? -ne 0 ]; then
    echo "开放 IPv4 内网访问失败。请检查错误信息。"
    return 1
  fi
  echo "IPv4 内网访问已开放。"

  # 开放内网（IPv6 ULA - Unique Local Address）所有访问
  # fc00::/7 是 IPv6 的唯一本地地址范围
  echo "正在开放内网（IPv6 ULA 地址范围 fc00::/7）所有访问..."
  ufw allow from fc00::/7 comment '允许来自 fc00::/7 (IPv6 ULA) 的所有连接 (IPv6)'
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

  echo "防火墙配置完成：内网开放，外网只开放 22, 80, 443, 88 端口 (IPv4 和 IPv6)。"
  echo "当前 ufw 状态:"
  ufw status verbose
  return 0
}

# 函数：重置防火墙规则为默认规则 (选项 3)
# 适用于 IPv4 和 IPv6
reset_firewall_to_default() {
  echo ">>> 正在执行：重置防火墙规则为默认规则 (IPv4 和 IPv6) <<<"

  # 保存重置前的 ufw 状态，以便后续检查额外端口
  local pre_reset_status_file=$(mktemp)
  ufw status verbose > "$pre_reset_status_file"

  # 禁用 ufw
  if ufw status | grep -q "Status: active"; then
    echo "正在禁用 ufw..."
    ufw disable
    if [ $? -ne 0 ]; then
      echo "禁用 ufw 失败。请检查错误信息。"
      rm -f "$pre_reset_status_file"
      return 1
    fi
    echo "ufw 已成功禁用。"
  else
    echo "ufw 当前已禁用。"
  fi

  # 重置 ufw 规则到默认状态
  echo "正在重置 ufw 规则到默认状态 (IPv4 和 IPv6)..."
  ufw --force reset
  if [ $? -eq 0 ]; then
    echo "ufw 规则已成功重置。"
    echo "默认规则通常是拒绝所有传入连接，允许所有传出连接。"
  else
    echo "重置 ufw 规则失败。请检查错误信息。"
    rm -f "$pre_reset_status_file"
    return 1
  fi

  echo "ufw 已重置为默认规则 (IPv4 和 IPv6)。您可以选择 'ufw enable' 来重新启用它。"
  echo "当前 ufw 状态:"
  ufw status verbose

  # 检查重置前是否存在额外开放端口并输出
  local common_ports_regex="(22|80|443|88)/(tcp|udp)" # 常用端口正则
  echo ""
  echo "--- 重置前发现的额外开放端口信息 ---"
  local extra_ports_found=false
  while IFS= read -r line; do
    # 查找包含 ALLOW 的行，排除 IP 地址范围和常用端口
    if echo "$line" | grep -q "ALLOW" && \
       ! echo "$line" | grep -qE "10.0.0.0/8|172.16.0.0/12|192.168.0.0/16|fc00::/7" && \
       ! echo "$line" | grep -qE "$common_ports_regex"; then
      echo "  - $line"
      extra_ports_found=true
    fi
  done < "$pre_reset_status_file"

  if [ "$extra_ports_found" = false ]; then
    echo "  重置前未发现额外的开放端口。"
  else
    echo "  请注意：这些端口在重置前是开放的，现在已随重置操作关闭。"
  fi
  echo "------------------------------------"
  rm -f "$pre_reset_status_file"
  return 0
}

# 函数：手动开放端口 (新选项 - 选项 4)
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
      # 检查手动端口是否已经开放，避免重复添加
      local check_port_entry="${port_start}"
      if [ "$is_range" = true ]; then
        check_port_entry="${port_start}:${port_end}"
      fi

      if ufw status verbose | grep -qE "(^$check_port_entry/$proto[[:space:]]+ALLOW[[:space:]]+Anywhere)|(^Anywhere[[:space:]]+$check_port_entry/$proto[[:space:]]+ALLOW)"; then
        echo "  端口或范围 ${check_port_entry}/${proto} 已开放，跳过添加。"
      else
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

  while true; do
    echo ""
    echo "--- 防火墙管理脚本 ---"
    echo "请选择一个防火墙配置选项："
    echo "1. 禁用防火墙并开放所有网络访问限制 ( 不安全！)"
    echo "2. 开放内网访问及外网常用端口访问"
    echo "3. 重置防火墙规则为默认规则 (通常是拒绝传入，允许传出)"
    echo "4. 手动开放端口或端口范围"
    echo "5. 查看当前 ufw 状态"
    echo "6. 退出"
    echo ""

    read -p "请输入您的选择 [1-6]: " choice

    case $choice in
      1)
        disable_firewall_completely
        ;;
      2)
        open_internal_and_common_external_ports
        ;;
      3)
        reset_firewall_to_default
        ;;
      4) # 新选项的入口
        manual_open_ports
        ;;
      5)
        echo "当前 ufw 状态:"
        ufw status verbose
        ;;
      6)
        echo "退出脚本。再见！"
        exit 0
        ;;
      *)
        echo "无效的选择。请输入 1 到 6 之间的数字。"
        ;;
    esac
  done
}

# 运行主菜单
main_menu
