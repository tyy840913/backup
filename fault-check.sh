#!/bin/bash

# ==============================================================================
# Network Troubleshooting Script (for China mainland)
#
# Author: Gemini
# Version: 1.0
# Description: This script systematically diagnoses network issues, checking
#              both IPv4 and IPv6 stacks. It inspects local configuration,
#              DNS, routing, firewalls, and external connectivity using
#              services reliable within mainland China.
#
# Usage: Run with 'bash network_check.sh'.
#        It's recommended to run with sudo ('sudo bash network_check.sh')
#        for full access, especially for firewall checks.
# ==============================================================================

# --- Configuration ---
# Targets for connectivity checks, chosen for reliability in mainland China.
IPV4_DNS_TARGET="223.5.5.5"    # AliDNS
IPV6_DNS_TARGET="2400:3200::1" # AliDNS IPv6
DOMAIN_TARGET="www.baidu.com"  # Baidu for HTTP/HTTPS checks
PING_COUNT=3                   # Number of pings to send

# --- Color Definitions ---
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

# --- Storage for identified issues ---
issues_found=()

# --- Helper Functions ---
print_header() {
    echo -e "${COLOR_BLUE}======================================================================${COLOR_RESET}"
    echo -e "${COLOR_BLUE} $1 ${COLOR_RESET}"
    echo -e "${COLOR_BLUE}======================================================================${COLOR_RESET}"
}

print_success() {
    echo -e "[ ${COLOR_GREEN}正常${COLOR_RESET} ] $1"
}

print_error() {
    echo -e "[ ${COLOR_RED}故障${COLOR_RESET} ] $1"
    issues_found+=("故障: $1")
}

print_warning() {
    echo -e "[ ${COLOR_YELLOW}警告${COLOR_RESET} ] $1"
    issues_found+=("警告: $1")
}

check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "关键命令 '$1' 未安装。请先安装后再运行此脚本。"
        exit 1
    fi
}

# --- Pre-run Checks ---
check_command ping
check_command ip
check_command dig
check_command curl

if [[ $EUID -ne 0 ]]; then
   print_warning "脚本未使用 root/sudo 权限运行。防火墙等部分系统策略可能无法完全检查。"
fi
echo ""


# ==============================================================================
# 1. LOCAL NETWORK INTERFACE & ROUTING CHECK
# ==============================================================================
print_header "1. 检查本地网络接口与路由"

# --- Check network interfaces ---
interfaces=$(ip -o link show | awk -F': ' '{print $2}')
if [ -z "$interfaces" ]; then
    print_error "未找到任何网络接口。"
else
    print_success "发现网络接口: $interfaces"
    # Check for active interfaces with IP addresses
    active_ipv4=$(ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | xargs)
    active_ipv6=$(ip -6 addr show | grep -oP 'inet6 \K[0-9a-f:]+' | grep -v '::1' | xargs)

    if [ -n "$active_ipv4" ]; then
        print_success "检测到活动的 IPv4 地址: $active_ipv4"
    else
        print_warning "未检测到活动的公共 IPv4 地址。"
    fi
    if [ -n "$active_ipv6" ]; then
        print_success "检测到活动的 IPv6 地址: $active_ipv6"
    else
        print_warning "未检测到活动的 IPv6 地址。"
    fi
fi

# --- Check default gateways ---
gateway_ipv4=$(ip -4 route show default | awk '/default/ {print $3}')
gateway_ipv6=$(ip -6 route show default | awk '/default/ {print $3}')

if [ -n "$gateway_ipv4" ]; then
    print_success "IPv4 默认网关: $gateway_ipv4"
    ping -c 1 -W 2 "$gateway_ipv4" &> /dev/null
    if [ $? -eq 0 ]; then
        print_success "IPv4 网关 ($gateway_ipv4) 可访问。"
    else
        print_error "无法访问 IPv4 网关 ($gateway_ipv4)。内部网络可能存在问题。"
    fi
else
    print_error "未找到 IPv4 默认网关。这是导致无法访问外部网络的主要原因。"
fi

if [ -n "$gateway_ipv6" ]; then
    print_success "IPv6 默认网关: $gateway_ipv6"
    ping -6 -c 1 -W 2 "$gateway_ipv6" &> /dev/null
    if [ $? -eq 0 ]; then
        print_success "IPv6 网关 ($gateway_ipv6) 可访问。"
    else
        print_error "无法访问 IPv6 网关 ($gateway_ipv6)。内部网络可能存在问题。"
    fi
else
    print_warning "未找到 IPv6 默认网关。IPv6 网络将无法访问外网。"
fi
echo ""


# ==============================================================================
# 2. DNS & HOSTS FILE CHECK
# ==============================================================================
print_header "2. 检查 DNS 配置与 Hosts 文件"

# --- Check /etc/resolv.conf ---
if [ -f /etc/resolv.conf ]; then
    dns_servers=$(grep -v '^#' /etc/resolv.conf | grep 'nameserver' | awk '{print $2}' | xargs)
    if [ -n "$dns_servers" ]; then
        print_success "在 /etc/resolv.conf 中找到 DNS 服务器: $dns_servers"
    else
        print_error "/etc/resolv.conf 文件中未配置有效的 'nameserver'。"
    fi
else
    print_error "DNS 配置文件 /etc/resolv.conf 不存在。"
fi

# --- Check DNS resolution ---
print_success "正在测试域名解析: $DOMAIN_TARGET"
# Test A record (IPv4)
dig A "$DOMAIN_TARGET" +short +time=3 | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.' &> /dev/null
if [ $? -eq 0 ]; then
    print_success "IPv4 DNS 解析 ($DOMAIN_TARGET) 成功。"
else
    print_error "IPv4 DNS 解析 ($DOMAIN_TARGET) 失败。请检查 DNS 服务器设置或网络连接。"
fi
# Test AAAA record (IPv6)
dig AAAA "$DOMAIN_TARGET" +short +time=3 | grep -E '^[0-9a-fA-F:]+' &> /dev/null
if [ $? -eq 0 ]; then
    print_success "IPv6 DNS 解析 ($DOMAIN_TARGET) 成功。"
else
    print_warning "IPv6 DNS 解析 ($DOMAIN_TARGET) 失败。可能无 IPv6 DNS 服务器或目标无 IPv6 地址。"
fi

# --- Check /etc/hosts file for potential hijacks ---
if [ -f /etc/hosts ]; then
    hijacked_entries=$(grep "$DOMAIN_TARGET" /etc/hosts | grep -v '^#')
    if [ -n "$hijacked_entries" ]; then
        print_warning "/etc/hosts 文件中发现可能影响网络访问的条目:\n$hijacked_entries"
    else
        print_success "/etc/hosts 文件检查正常，未发现针对目标的劫持。"
    fi
else
    print_warning "/etc/hosts 文件不存在。"
fi
echo ""


# ==============================================================================
# 3. EXTERNAL CONNECTIVITY CHECK
# ==============================================================================
print_header "3. 检查外部网络连通性"

# --- Ping external IPs ---
print_success "正在 Ping 外部 IPv4 地址: $IPV4_DNS_TARGET"
ping -c "$PING_COUNT" -W 3 "$IPV4_DNS_TARGET" &> /dev/null
if [ $? -eq 0 ]; then
    print_success "Ping 外部 IPv4 地址成功。"
else
    print_error "Ping 外部 IPv4 地址 ($IPV4_DNS_TARGET) 失败。出站连接可能被阻止。"
fi

if [ -n "$gateway_ipv6" ]; then
    print_success "正在 Ping 外部 IPv6 地址: $IPV6_DNS_TARGET"
    ping -6 -c "$PING_COUNT" -W 3 "$IPV6_DNS_TARGET" &> /dev/null
    if [ $? -eq 0 ]; then
        print_success "Ping 外部 IPv6 地址成功。"
    else
        print_error "Ping 外部 IPv6 地址 ($IPV6_DNS_TARGET) 失败。IPv6 出站连接可能被阻止。"
    fi
else
    print_success "无 IPv6 网关，跳过外部 IPv6 Ping 测试。"
fi

# --- Check HTTP/HTTPS connectivity ---
print_success "正在测试对 $DOMAIN_TARGET 的 HTTP/HTTPS 访问"
# Test IPv4
curl -4 --connect-timeout 5 -s -o /dev/null -w "%{http_code}" "http://$DOMAIN_TARGET" | grep -E '200|30[12]' &> /dev/null
if [ $? -eq 0 ]; then
    print_success "通过 IPv4 访问 HTTP (80端口) 成功。"
else
    print_error "通过 IPv4 访问 HTTP (80端口) 失败。端口可能被防火墙阻止。"
fi
curl -4 --connect-timeout 5 -s -o /dev/null -w "%{http_code}" "https://$DOMAIN_TARGET" | grep -E '200|30[12]' &> /dev/null
if [ $? -eq 0 ]; then
    print_success "通过 IPv4 访问 HTTPS (443端口) 成功。"
else
    print_error "通过 IPv4 访问 HTTPS (443端口) 失败。端口可能被防火墙阻止。"
fi

# Test IPv6
if [ -n "$gateway_ipv6" ]; then
    curl -6 --connect-timeout 5 -s -o /dev/null -w "%{http_code}" "https://$DOMAIN_TARGET" | grep -E '200|30[12]' &> /dev/null
    if [ $? -eq 0 ]; then
        print_success "通过 IPv6 访问 HTTPS (443端口) 成功。"
    else
        print_warning "通过 IPv6 访问 HTTPS (443端口) 失败。IPv6 流量可能被阻止。"
    fi
else
    print_success "无 IPv6 网关，跳过外部 IPv6 HTTPS 测试。"
fi
echo ""


# ==============================================================================
# 4. SYSTEM POLICY & CONFIGURATION CHECK
# ==============================================================================
print_header "4. 检查系统策略与配置"

# --- Check for Proxy Settings ---
if [ -n "$http_proxy" ] || [ -n "$https_proxy" ]; then
    print_warning "检测到系统环境变量中设置了 HTTP/HTTPS 代理:"
    [ -n "$http_proxy" ] && echo "  http_proxy=$http_proxy"
    [ -n "$https_proxy" ] && echo "  https_proxy=$https_proxy"
    print_warning "如果代理服务器配置错误或无法连接，将导致网络访问失败。"
else
    print_success "未在环境变量中发现代理设置。"
fi

# --- Check Firewall ---
if [[ $EUID -ne 0 ]]; then
    print_warning "无 root 权限，无法执行防火墙检查。"
else
    print_success "正在检查防火墙规则 (需要 root 权限)..."
    # Check for UFW
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        print_success "检测到 UFW 防火墙处于活动状态。"
        if ufw status | grep -q "Default: deny (outgoing)"; then
            print_error "UFW 防火墙默认策略为 '拒绝所有出站流量'。这会阻止大部分网络访问，除非有明确的允许规则。"
        else
            print_success "UFW 出站策略正常。"
        fi

    # Check for firewalld
    elif command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        print_success "检测到 firewalld 防火墙处于活动状态。"
        # A simple check, a deep dive is complex. We'll just inform the user.
        print_warning "请手动检查 firewalld 规则 ('sudo firewall-cmd --list-all') 以确认没有阻止所需流量。"

    # Check for iptables
    elif command -v iptables &> /dev/null; then
        print_success "正在检查 iptables 规则..."
        # Check IPv4 OUTPUT chain for DROP/REJECT policy or rules
        if iptables -L OUTPUT -n | grep -q "Chain policy DROP" || iptables -L OUTPUT -n | grep -q "REJECT"; then
            print_error "iptables 的 OUTPUT 链策略为 DROP/REJECT 或包含相关规则，可能阻止出站流量。"
        else
            print_success "iptables IPv4 OUTPUT 链策略正常。"
        fi
        # Check IPv6 OUTPUT chain for DROP/REJECT policy or rules
        if command -v ip6tables &> /dev/null; then
            if ip6tables -L OUTPUT -n | grep -q "Chain policy DROP" || ip6tables -L OUTPUT -n | grep -q "REJECT"; then
                print_error "ip6tables 的 OUTPUT 链策略为 DROP/REJECT 或包含相关规则，可能阻止 IPv6 出站流量。"
            else
                print_success "ip6tables IPv6 OUTPUT 链策略正常。"
            fi
        fi
    else
        print_success "未检测到主流防火墙 (UFW, firewalld, iptables)。"
    fi
fi
echo ""


# ==============================================================================
# FINAL REPORT
# ==============================================================================
print_header "5. 排查结果摘要"

if [ ${#issues_found[@]} -eq 0 ]; then
    print_success "恭喜！初步检查未发现明显的网络配置故障点。"
    echo "如果网络依然存在问题，可能由以下更深层原因导致："
    echo "  - 上游网络设备（路由器、交换机）故障。"
    echo "  - ISP (网络服务提供商) 方面的问题。"
    echo "  - 特定应用程序的内部网络设置。"
    echo "  - SELinux/AppArmor 等更强的安全模块限制。"
else
    echo -e "${COLOR_RED}在此次排查中发现了 ${#issues_found[@]} 个潜在问题。请重点关注：${COLOR_RESET}"
    for (( i=0; i<${#issues_found[@]}; i++ )); do
        echo -e "  $((i+1)). ${issues_found[$i]}"
    done
    echo ""
    echo "请根据上述故障点逐一排查和修复。"
fi
echo ""

