#!/bin/bash

# ==============================================================================
# 网络故障排查脚本 (适用于中国大陆)
#
# 作者: Gemini
# 版本: 2.0 (增强版)
# 描述: 此脚本系统地诊断网络问题，检查 IPv4 和 IPv6 协议栈。
#              它会检查本地配置、DNS、路由、防火墙和外部连接，
#              使用在中国大陆地区可靠的服务进行测试。
#              在发现问题时，会尝试进行深入检查以定位具体原因。
#
# 用法: 运行 'bash network_check.sh'。
#        建议使用 sudo 运行 ('sudo bash network_check.sh')，
#        以便获得完整访问权限，尤其是防火墙检查。
# ==============================================================================

# --- 配置 ---
# 用于连通性检查的目标，选择在中国大陆地区可靠的服务。
IPV4_DNS_TARGET="223.5.5.5"    # 阿里DNS
IPV6_DNS_TARGET="2400:3200::1" # 阿里DNS IPv6
DOMAIN_TARGET="www.baidu.com"  # 百度，用于 HTTP/HTTPS 检查
PING_COUNT=3                   # 发送的 ping 次数

# --- 颜色定义 ---
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RESET='\033[0m'

# --- 存储已识别的问题 ---
issues_found=()

# --- 辅助函数 ---
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
        print_error "关键命令 '$1' 未安装。请先安装后再运行此脚本。例如: sudo apt install $1 或 sudo yum install $1"
        exit 1
    fi
}

# --- 深入检查函数 ---

# 深入检查网关可达性
deep_check_gateway() {
    local ip_version=$1
    local gateway_ip=$2
    print_header "深入检查: 网关 ($gateway_ip) 可达性问题"
    echo "尝试使用不同的包大小和计数再次 ping 网关..."
    if [ "$ip_version" == "ipv4" ]; then
        ping -c 5 -s 64 -W 2 "$gateway_ip"
    else
        ping -6 -c 5 -s 64 -W 2 "$gateway_ip"
    fi
    if [ $? -ne 0 ]; then
        print_error "多次尝试后网关 ($gateway_ip) 仍无法访问。请检查网线连接、本地网络配置（IP地址、子网掩码）以及路由器状态。"
        echo "建议: 检查路由器的指示灯，尝试重启路由器。如果虚拟机，请检查虚拟网络设置。"
    else
        print_success "网关 ($gateway_ip) 已恢复可达或间歇性问题。"
    fi
    echo ""
}

# 深入检查 DNS 解析
deep_check_dns() {
    local domain=$1
    local dns_servers=$(grep -v '^#' /etc/resolv.conf | grep 'nameserver' | awk '{print $2}' | xargs)

    print_header "深入检查: DNS 解析 ($domain) 问题"
    echo "尝试使用系统配置的 DNS 服务器解析 $domain..."
    if [ -n "$dns_servers" ]; then
        for ns in $dns_servers; do
            echo "尝试使用 $ns 解析 $domain..."
            dig "$domain" @$ns +short +time=5
            if [ $? -eq 0 ]; then
                print_success "使用 DNS 服务器 $ns 成功解析 $domain。"
                break
            else
                print_warning "使用 DNS 服务器 $ns 解析 $domain 失败。"
            fi
        done
    else
        print_error "未在 /etc/resolv.conf 中找到 DNS 服务器，无法测试。"
    fi

    echo "尝试使用公共 DNS 服务器 (阿里云DNS: $IPV4_DNS_TARGET) 解析 $domain..."
    dig "$domain" @$IPV4_DNS_TARGET +short +time=5
    if [ $? -eq 0 ]; then
        print_success "使用公共 DNS ($IPV4_DNS_TARGET) 成功解析 $domain。您的本地 DNS 配置可能存在问题。"
        echo "建议: 检查 /etc/resolv.conf 配置，或尝试更换为公共 DNS (如 223.5.5.5, 114.114.114.114)。"
    else
        print_error "使用公共 DNS ($IPV4_DNS_TARGET) 也无法解析 $domain。可能存在更深层次的网络问题（如出站UDP 53端口被防火墙阻止，或上游网络问题）。"
        echo "建议: 检查防火墙是否阻止了 UDP 53 端口的出站流量。"
    fi
    echo ""
}

# 深入检查外部连通性 (Ping)
deep_check_ping_connectivity() {
    local ip_target=$1
    local ip_version_flag=$2 # -4 或 -6
    print_header "深入检查: 外部 IP ($ip_target) Ping 连通性问题"
    echo "尝试使用 traceroute 跟踪到 $ip_target 的路径..."
    if command -v traceroute &> /dev/null; then
        if [ -z "$ip_version_flag" ]; then # For IPv4
             traceroute -n "$ip_target"
        else # For IPv6
            traceroute -n "$ip_version_flag" "$ip_target"
        fi
        if [ $? -ne 0 ]; then
            print_error "traceroute 到 $ip_target 失败。路由可能存在问题或被阻止。"
            echo "建议: 分析 traceroute 输出，查看在哪个跳数中断，这可能指向中间路由器故障或 ISP 路由问题。"
        else
            print_success "traceroute 到 $ip_target 成功完成。"
        fi
    else
        print_warning "traceroute 命令未安装，无法进行路径跟踪。请安装 traceroute 进行更详细检查。"
    fi
    echo ""
}

# 深入检查 HTTP/HTTPS 连通性
deep_check_http_https_connectivity() {
    local domain=$1
    local ip_version_flag=$2 # -4 或 -6
    local protocol=$3 # http 或 https
    local port=$4 # 80 或 443
    print_header "深入检查: $protocol://$domain (端口 $port) 访问问题"

    echo "尝试使用 curl 详细模式访问 $protocol://$domain:$port..."
    if [ "$protocol" == "http" ]; then
        curl $ip_version_flag -v --connect-timeout 10 "$protocol://$domain"
    else
        curl $ip_version_flag -v --connect-timeout 10 "$protocol://$domain"
    fi

    if [ $? -ne 0 ]; then
        print_error "curl 详细模式显示 $protocol://$domain 访问失败。检查输出中的错误信息。"
        echo "常见原因: 防火墙阻止端口 $port，代理问题，TLS/SSL 握手失败 (HTTPS)，服务器无响应。"
        echo "建议: 检查本地防火墙规则是否允许出站到 $port 端口。如果是 HTTPS，检查系统时间是否准确。"
    else
        print_success "$protocol://$domain 详细访问成功，但可能返回了非 200/30x 状态码。请检查 curl 输出。"
    fi
    echo ""
}


# --- 预运行检查 ---
check_command ping
check_command ip
check_command dig
check_command curl
check_command grep
check_command awk

if [[ $EUID -ne 0 ]]; then
   print_warning "脚本未使用 root/sudo 权限运行。防火墙等部分系统策略可能无法完全检查，某些深入检查可能受限。"
fi
echo ""


# ==============================================================================
# 1. 本地网络接口与路由检查
# ==============================================================================
print_header "1. 检查本地网络接口与路由"

# --- 检查网络接口 ---
interfaces=$(ip -o link show | awk -F': ' '{print $2}')
if [ -z "$interfaces" ]; then
    print_error "未找到任何网络接口。请检查硬件连接或虚拟网卡配置。"
else
    print_success "发现网络接口: $interfaces"
    # 检查具有 IP 地址的活动接口
    active_ipv4=$(ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | xargs)
    active_ipv6=$(ip -6 addr show | grep -oP 'inet6 \K[0-9a-f:]+' | grep -v '::1' | xargs)

    if [ -n "$active_ipv4" ]; then
        print_success "检测到活动的 IPv4 地址: $active_ipv4"
    else
        print_warning "未检测到活动的公共 IPv4 地址。这通常是网络不通的原因。"
        issues_found+=("警告: 未检测到活动的公共 IPv4 地址。")
    fi
    if [ -n "$active_ipv6" ]; then
        print_success "检测到活动的 IPv6 地址: $active_ipv6"
    else
        print_warning "未检测到活动的 IPv6 地址。IPv6 功能将受限。"
        issues_found+=("警告: 未检测到活动的 IPv6 地址。")
    fi
fi

# --- 检查默认网关 ---
gateway_ipv4=$(ip -4 route show default | awk '/default/ {print $3}')
gateway_ipv6=$(ip -6 route show default | awk '/default/ {print $3}')

if [ -n "$gateway_ipv4" ]; then
    print_success "IPv4 默认网关: $gateway_ipv4"
    ping -c 1 -W 2 "$gateway_ipv4" &> /dev/null
    if [ $? -eq 0 ]; then
        print_success "IPv4 网关 ($gateway_ipv4) 可访问。"
    else
        print_error "无法访问 IPv4 网关 ($gateway_ipv4)。内部网络可能存在问题。"
        deep_check_gateway "ipv4" "$gateway_ipv4"
    fi
else
    print_error "未找到 IPv4 默认网关。这是导致无法访问外部网络的主要原因。"
    issues_found+=("故障: 未找到 IPv4 默认网关。")
    echo "建议: 检查网络接口配置 (如 DHCP 或静态 IP 设置)。"
fi

if [ -n "$gateway_ipv6" ]; then
    print_success "IPv6 默认网关: $gateway_ipv6"
    ping -6 -c 1 -W 2 "$gateway_ipv6" &> /dev/null
    if [ $? -eq 0 ]; then
        print_success "IPv6 网关 ($gateway_ipv6) 可访问。"
    else
        print_error "无法访问 IPv6 网关 ($gateway_ipv6)。内部网络可能存在问题。"
        deep_check_gateway "ipv6" "$gateway_ipv6"
    fi
else
    print_warning "未找到 IPv6 默认网关。IPv6 网络将无法访问外网。"
    issues_found+=("警告: 未找到 IPv6 默认网关。")
fi
echo ""


# ==============================================================================
# 2. DNS 与 Hosts 文件检查
# ==============================================================================
print_header "2. 检查 DNS 配置与 Hosts 文件"

# --- 检查 /etc/resolv.conf ---
if [ -f /etc/resolv.conf ]; then
    dns_servers=$(grep -v '^#' /etc/resolv.conf | grep 'nameserver' | awk '{print $2}' | xargs)
    if [ -n "$dns_servers" ]; then
        print_success "在 /etc/resolv.conf 中找到 DNS 服务器: $dns_servers"
    else
        print_error "/etc/resolv.conf 文件中未配置有效的 'nameserver'。这会导致无法解析域名。"
        issues_found+=("故障: /etc/resolv.conf 中未配置 DNS 服务器。")
        echo "建议: 编辑 /etc/resolv.conf 添加 'nameserver 223.5.5.5' 等公共 DNS。"
    fi
else
    print_error "DNS 配置文件 /etc/resolv.conf 不存在。系统可能无法进行域名解析。"
    issues_found+=("故障: /etc/resolv.conf 文件不存在。")
    echo "建议: 尝试重新生成此文件，或手动创建并添加 DNS 服务器。"
fi

# --- 检查 DNS 解析 ---
print_success "正在测试域名解析: $DOMAIN_TARGET"
# 测试 A 记录 (IPv4)
if ! dig A "$DOMAIN_TARGET" +short +time=3 | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.' &> /dev/null; then
    print_error "IPv4 DNS 解析 ($DOMAIN_TARGET) 失败。请检查 DNS 服务器设置或网络连接。"
    deep_check_dns "$DOMAIN_TARGET"
fi

# 测试 AAAA 记录 (IPv6)
if ! dig AAAA "$DOMAIN_TARGET" +short +time=3 | grep -E '^[0-9a-fA-F:]+' &> /dev/null; then
    print_warning "IPv6 DNS 解析 ($DOMAIN_TARGET) 失败。可能无 IPv6 DNS 服务器或目标无 IPv6 地址。"
    issues_found+=("警告: IPv6 DNS 解析失败。")
    if [ -n "$gateway_ipv6" ]; then # 只有有 IPv6 网关才深入检查
        deep_check_dns "$DOMAIN_TARGET"
    fi
else
    print_success "IPv6 DNS 解析 ($DOMAIN_TARGET) 成功。"
fi


# --- 检查 /etc/hosts 文件是否存在潜在劫持 ---
if [ -f /etc/hosts ]; then
    hijacked_entries=$(grep "$DOMAIN_TARGET" /etc/hosts | grep -v '^#')
    if [ -n "$hijacked_entries" ]; then
        print_warning "/etc/hosts 文件中发现可能影响网络访问的条目:\n$hijacked_entries"
        issues_found+=("警告: /etc/hosts 存在可疑条目。")
        echo "建议: 检查这些条目是否是您有意为之，否则请删除或注释掉它们。"
    else
        print_success "/etc/hosts 文件检查正常，未发现针对目标的劫持。"
    fi
else
    print_warning "/etc/hosts 文件不存在。这通常不是问题，但若您依赖它进行本地解析，请注意。"
    issues_found+=("警告: /etc/hosts 文件不存在。")
fi
echo ""


# ==============================================================================
# 3. 外部网络连通性检查
# ==============================================================================
print_header "3. 检查外部网络连通性"

# --- Ping 外部 IP ---
print_success "正在 Ping 外部 IPv4 地址: $IPV4_DNS_TARGET"
ping -c "$PING_COUNT" -W 3 "$IPV4_DNS_TARGET" &> /dev/null
if [ $? -ne 0 ]; then
    print_error "Ping 外部 IPv4 地址 ($IPV4_DNS_TARGET) 失败。出站连接可能被阻止或路由不通。"
    deep_check_ping_connectivity "$IPV4_DNS_TARGET" "" # 空字符串表示 IPv4
fi

if [ -n "$gateway_ipv6" ]; then
    print_success "正在 Ping 外部 IPv6 地址: $IPV6_DNS_TARGET"
    ping -6 -c "$PING_COUNT" -W 3 "$IPV6_DNS_TARGET" &> /dev/null
    if [ $? -ne 0 ]; then
        print_error "Ping 外部 IPv6 地址 ($IPV6_DNS_TARGET) 失败。IPv6 出站连接可能被阻止。"
        deep_check_ping_connectivity "$IPV6_DNS_TARGET" "-6"
    fi
else
    print_success "无 IPv6 网关，跳过外部 IPv6 Ping 测试。"
fi

# --- 检查 HTTP/HTTPS 连通性 ---
print_success "正在测试对 $DOMAIN_TARGET 的 HTTP/HTTPS 访问"
# 测试 IPv4
if ! curl -4 --connect-timeout 5 -s -o /dev/null -w "%{http_code}" "http://$DOMAIN_TARGET" | grep -E '200|30[12]' &> /dev/null; then
    print_error "通过 IPv4 访问 HTTP (80端口) 失败。端口可能被防火墙阻止或目标服务不可达。"
    deep_check_http_https_connectivity "$DOMAIN_TARGET" "-4" "http" "80"
fi
if ! curl -4 --connect-timeout 5 -s -o /dev/null -w "%{http_code}" "https://$DOMAIN_TARGET" | grep -E '200|30[12]' &> /dev/null; then
    print_error "通过 IPv4 访问 HTTPS (443端口) 失败。端口可能被防火墙阻止或目标服务不可达。"
    deep_check_http_https_connectivity "$DOMAIN_TARGET" "-4" "https" "443"
fi

# 测试 IPv6
if [ -n "$gateway_ipv6" ]; then
    if ! curl -6 --connect-timeout 5 -s -o /dev/null -w "%{http_code}" "https://$DOMAIN_TARGET" | grep -E '200|30[12]' &> /dev/null; then
        print_warning "通过 IPv6 访问 HTTPS (443端口) 失败。IPv6 流量可能被阻止或目标服务无 IPv6 支持。"
        issues_found+=("警告: IPv6 HTTPS 访问失败。")
        deep_check_http_https_connectivity "$DOMAIN_TARGET" "-6" "https" "443"
    else
        print_success "通过 IPv6 访问 HTTPS (443端口) 成功。"
    fi
else
    print_success "无 IPv6 网关，跳过外部 IPv6 HTTPS 测试。"
fi
echo ""


# ==============================================================================
# 4. 系统策略与配置检查
# ==============================================================================
print_header "4. 检查系统策略与配置"

# --- 检查代理设置 ---
if [ -n "$http_proxy" ] || [ -n "$https_proxy" ] || [ -n "$ftp_proxy" ] || [ -n "$no_proxy" ]; then
    print_warning "检测到系统环境变量中设置了代理:"
    [ -n "$http_proxy" ] && echo "  http_proxy=$http_proxy"
    [ -n "$https_proxy" ] && echo "  https_proxy=$https_proxy"
    [ -n "$ftp_proxy" ] && echo "  ftp_proxy=$ftp_proxy"
    [ -n "$no_proxy" ] && echo "  no_proxy=$no_proxy"
    print_warning "如果代理服务器配置错误、不可用或代理软件未运行，将导致网络访问失败。"
    issues_found+=("警告: 检测到代理设置。")
    echo "建议: 确认代理设置是否正确，代理服务器是否可达。如果不需要代理，请清除这些环境变量。"
else
    print_success "未在环境变量中发现代理设置。"
fi

# --- 检查防火墙 ---
if [[ $EUID -ne 0 ]]; then
    print_warning "无 root 权限，无法执行防火墙检查。请使用 sudo 运行以获得更全面的报告。"
    issues_found+=("警告: 无 root 权限，防火墙检查受限。")
else
    print_success "正在检查防火墙规则 (需要 root 权限)..."
    firewall_checked=false

    # 检查 UFW
    if command -v ufw &> /dev/null; then
        firewall_checked=true
        if ufw status | grep -q "Status: active"; then
            print_success "检测到 UFW 防火墙处于活动状态。"
            ufw_default_outgoing=$(ufw status | grep "Default: outgoing" | awk '{print $NF}')
            if [ "$ufw_default_outgoing" == "deny" ]; then
                print_error "UFW 防火墙默认策略为 '拒绝所有出站流量'。这会阻止大部分网络访问，除非有明确的允许规则。"
                issues_found+=("故障: UFW 默认出站策略为拒绝。")
                echo "建议: 检查 UFW 规则 ('sudo ufw status verbose')，确保允许必要的出站流量（例如 80, 443, 53 端口）。"
            else
                print_success "UFW 出站策略正常 (当前为 '$ufw_default_outgoing')。"
            fi
        else
            print_success "UFW 防火墙未激活。"
        fi
    fi

    # 检查 firewalld
    if command -v firewall-cmd &> /dev/null && ! $firewall_checked; then # 避免重复检查，如果 UFW 没启用再检查 firewalld
        firewall_checked=true
        if systemctl is-active --quiet firewalld; then
            print_success "检测到 firewalld 防火墙处于活动状态。"
            # firewalld 默认是拒绝不匹配规则的流量
            print_warning "firewalld 处于活动状态，其规则可能阻止网络流量。请手动检查 firewalld 规则 ('sudo firewall-cmd --list-all') 以确认没有阻止所需流量。"
            issues_found+=("警告: firewalld 处于活动状态，请手动检查规则。")
        else
            print_success "firewalld 防火墙未激活。"
        fi
    fi

    # 检查 iptables (如果 UFW 和 firewalld 都未检测到或未激活)
    if command -v iptables &> /dev/null && ! $firewall_checked; then
        firewall_checked=true
        print_success "正在检查 iptables 规则..."
        # 检查 IPv4 OUTPUT 链的默认策略
        ipv4_output_policy=$(iptables -L OUTPUT -n | grep "Chain OUTPUT (policy" | awk '{print $4}' | sed 's/[()]//g')
        if [ "$ipv4_output_policy" == "DROP" ] || [ "$ipv4_output_policy" == "REJECT" ]; then
            print_error "iptables 的 IPv4 OUTPUT 链默认策略为 $ipv4_output_policy，这会阻止出站流量。"
            issues_found+=("故障: iptables IPv4 OUTPUT 策略为 $ipv4_output_policy。")
            echo "建议: 检查 iptables 规则 ('sudo iptables -L -n')，确保允许必要的出站流量。"
        else
            print_success "iptables IPv4 OUTPUT 链策略正常 (当前为 $ipv4_output_policy)。"
        fi

        # 检查 IPv6 OUTPUT 链的默认策略
        if command -v ip6tables &> /dev/null; then
            ipv6_output_policy=$(ip6tables -L OUTPUT -n | grep "Chain OUTPUT (policy" | awk '{print $4}' | sed 's/[()]//g')
            if [ "$ipv6_output_policy" == "DROP" ] || [ "$ipv6_output_policy" == "REJECT" ]; then
                print_error "ip6tables 的 IPv6 OUTPUT 链默认策略为 $ipv6_output_policy，这会阻止 IPv6 出站流量。"
                issues_found+=("故障: ip6tables IPv6 OUTPUT 策略为 $ipv6_output_policy。")
                echo "建议: 检查 ip6tables 规则 ('sudo ip6tables -L -n')，确保允许必要的 IPv6 出站流量。"
            else
                print_success "ip6tables IPv6 OUTPUT 链策略正常 (当前为 $ipv6_output_policy)。"
            fi
        fi
    fi

    if ! $firewall_checked; then
        print_success "未检测到主流防火墙 (UFW, firewalld, iptables) 的活动状态。"
    fi
fi
echo ""


# ==============================================================================
# 5. 最终报告
# ==============================================================================
print_header "5. 排查结果摘要"

if [ ${#issues_found[@]} -eq 0 ]; then
    print_success "恭喜！初步检查和深入排查未发现明显的网络配置故障点。"
    echo "如果网络依然存在问题，可能由以下更深层原因导致："
    echo "  - ${COLOR_YELLOW}上游网络设备（路由器、交换机）故障${COLOR_RESET}：尝试重启您的路由器/光猫。"
    echo "  - ${COLOR_YELLOW}ISP (网络服务提供商) 方面的问题${COLOR_RESET}：联系您的网络服务提供商报告故障。"
    echo "  - ${COLOR_YELLOW}特定应用程序的内部网络设置${COLOR_RESET}：检查您所使用的应用是否有自己的代理或网络配置。"
    echo "  - ${COLOR_YELLOW}SELinux/AppArmor 等更强的安全模块限制${COLOR_RESET}：这些模块可能阻止特定进程的网络访问。"
    echo "  - ${COLOR_YELLOW}硬件故障${COLOR_RESET}：网卡本身可能存在问题。"
else
    echo -e "${COLOR_RED}在此次排查中发现了 ${#issues_found[@]} 个潜在问题。请重点关注并根据建议逐一排查和修复：${COLOR_RESET}"
    for (( i=0; i<${#issues_found[@]}; i++ )); do
        echo -e "  $((i+1)). ${issues_found[$i]}"
    done
    echo ""
    echo -e "${COLOR_BLUE}建议您按照上述报告中指出的“故障”和“警告”信息，结合其下方的具体建议进行修复。${COLOR_RESET}"
    echo -e "${COLOR_BLUE}修复后，您可以再次运行此脚本以验证问题是否解决。${COLOR_RESET}"
fi
echo ""
