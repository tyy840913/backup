#!/bin/bash

R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; B='\033[1;34m'; C='\033[1;36m'; N='\033[0m'

check_root() {
  [[ $EUID -eq 0 ]] || { echo -e "${R}需要 root 权限${N}"; exit 1; }
}

save_rules() {
  mkdir -p /etc/iptables
  iptables-save > /etc/iptables/rules.v4 2>/dev/null
  ip6tables-save > /etc/iptables/rules.v6 2>/dev/null
  echo -e "${G}规则已保存${N}"
}

show_status() {
  echo -e "\n${B}=== IPv4 规则 ===${N}"
  iptables -L -n --line-numbers 2>/dev/null | head -30
  echo -e "\n${B}=== IPv6 规则 ===${N}"
  ip6tables -L -n --line-numbers 2>/dev/null | head -30
}

option1_disable() {
  echo -e "${Y}放行所有流量...${N}"
  for cmd in iptables ip6tables; do
    $cmd -P INPUT ACCEPT
    $cmd -P FORWARD ACCEPT
    $cmd -P OUTPUT ACCEPT
    $cmd -F
    $cmd -X
  done
  echo -e "${R}所有规则已清空，流量不受限制${N}"
  save_rules
}

option2_secure() {
  echo -e "${Y}配置安全规则...${N}"

  for cmd in iptables ip6tables; do
    $cmd -F; $cmd -X
    $cmd -P INPUT DROP
    $cmd -P FORWARD DROP
    $cmd -P OUTPUT ACCEPT

    $cmd -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    $cmd -A INPUT -i lo -j ACCEPT
  done

  # 开放端口
  for p in 22 80 443 88; do
    iptables -A INPUT -p tcp --dport $p -j ACCEPT
    ip6tables -A INPUT -p tcp --dport $p -j ACCEPT
  done

  # 内网放行
  for net in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
    iptables -A INPUT -s "$net" -j ACCEPT
  done
  ip6tables -A INPUT -s fc00::/7 -j ACCEPT

  echo -e "${G}安全规则已应用${N}"
  show_status
  save_rules
}

option3_reset() {
  echo -e "${Y}重置为默认规则（拒绝入站，允许出站）...${N}"
  for cmd in iptables ip6tables; do
    $cmd -F; $cmd -X
    $cmd -P INPUT DROP
    $cmd -P FORWARD DROP
    $cmd -P OUTPUT ACCEPT
    $cmd -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    $cmd -A INPUT -i lo -j ACCEPT
  done
  echo -e "${G}已重置${N}"
  show_status
  save_rules
}

option4_manual() {
  read -p "端口 (如 80 或 5000:6000，多个用空格分隔): " ports
  [[ -z "$ports" ]] && { echo -e "${Y}已取消${N}"; return; }
  read -p "协议 (tcp/udp/both，默认 both): " proto
  proto=${proto:-both}

  for entry in $ports; do
    local range=""; local is_range=false
    if [[ "$entry" =~ ^([0-9]+)[:\-]([0-9]+)$ ]]; then
      range="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"; is_range=true
    elif [[ "$entry" =~ ^[0-9]+$ ]]; then
      range="$entry"
    else
      echo -e "${R}无效: $entry${N}"; continue
    fi

    for p in $(echo "$proto" | tr ',' '\n'); do
      [[ "$p" == "both" ]] && local protos="tcp udp" || local protos="$p"
      for proto2 in $protos; do
        for cmd in iptables ip6tables; do
          if $cmd -L INPUT -n 2>/dev/null | grep -q "dpt:$range.*$proto2"; then
            $cmd -D INPUT -p $proto2 --dport "$range" -j ACCEPT && \
              echo -e "${Y}$cmd: 关闭 $range/$proto2${N}"
          else
            $cmd -A INPUT -p $proto2 --dport "$range" -j ACCEPT && \
              echo -e "${G}$cmd: 开放 $range/$proto2${N}"
          fi
        done
      done
    done
  done
  show_status
  save_rules
}

main_menu() {
  check_root
  while true; do
    echo -e "\n${B}===== 防火墙管理 (iptables) =====${N}"
    echo "1) 放行所有流量"
    echo "2) 安全配置（内网开放 + 常用端口）"
    echo "3) 重置为默认规则"
    echo "4) 手动开关端口"
    echo "5) 查看规则"
    echo "0) 退出"
    read -p "请选择 [0-5]: " ch
    case "$ch" in
      1) option1_disable ;;
      2) option2_secure ;;
      3) option3_reset ;;
      4) option4_manual ;;
      5) show_status ;;
      0) echo "退出"; exit 0 ;;
      *) echo -e "${R}无效${N}" ;;
    esac
  done
}

main_menu