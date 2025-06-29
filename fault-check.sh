#!/bin/bash

# ==============================================================================
# 网络故障排查脚本 (适用于中国大陆 - 深度分析与交互式修复版)
#
# 作者: Gemini
# 版本: 4.3 (颜色修正与输出精简版)
# 描述: 此脚本系统地诊断网络问题，检查 IPv4 和 IPv6 协议栈。
#              它会检查本地配置、DNS、路由、防火墙和外部连接，
#              使用在中国大陆地区可靠的服务进行测试。
#              在发现问题时，会尝试从多个维度和替代方法进行深入分析，
#              并提供交互式自动修复选项，包含修复前备份和修复失败时恢复提示。
#
# 用法: 运行 'bash network_check.sh'。
#        必须使用 sudo 运行 ('sudo bash network_check.sh')，
#        以便获得完整访问权限和执行修复操作。
# ==============================================================================

# --- 配置 ---
# 用于连通性检查的目标，选择在中国大陆地区可靠的服务。
IPV4_DNS_TARGET="223.5.5.5"    # 阿里DNS
IPV6_DNS_TARGET="2400:3200::1" # 阿里DNS IPv6
DOMAIN_TARGET="www.baidu.com"  # 百度，用于 HTTP/HTTPS 检查
PING_COUNT=3                   # 发送的 ping 次数，用于初步测试
PING_DEEP_COUNT=5              # 深入检查时发送的 ping 次数
CURL_TIMEOUT=10                # Curl 连接超时时间 (秒)

# --- 颜色定义 ---
COLOR_GREEN='\e[0;32m'
COLOR_RED='\e[0;31m'
COLOR_YELLOW='\e[0;33m'
COLOR_BLUE='\e[0;34m'
COLOR_RESET='\e[0m'

# --- 存储已识别的“核心”问题和建议 (用于最终报告) ---
# 使用 associative array (map) 来存储唯一的故障，避免重复
declare -A core_issues_map
# 临时文件列表，用于追踪脚本自动创建的备份文件
TEMP_BACKUP_LIST=$(mktemp)

# 全局标志，用于记录 IPv6 HTTPS 访问是否成功
# 注意：在脚本的全局作用域声明，不要使用 local
IPV6_HTTPS_SUCCESS_FLAG=false

# --- 辅助函数 ---
print_header() {
    echo -e "${COLOR_BLUE}======================================================================${COLOR_RESET}"
    echo -e "${COLOR_BLUE} $1 ${COLOR_RESET}"
    echo -e "${COLOR_BLUE}======================================================================${COLOR_RESET}"
}

print_section_header() {
    echo -e "${COLOR_YELLOW}--- $1 ---${COLOR_RESET}"
}

print_success() {
    echo -e "[ ${COLOR_GREEN}正常${COLOR_RESET} ] $1"
}

print_error() {
    local msg=$1
    echo -e "[ ${COLOR_RED}故障${COLOR_RESET} ] $msg"
    # 将故障添加到 map，键为消息，值为“故障”
    core_issues_map["$msg"]="故障"
}

print_warning() {
    local msg=$1
    echo -e "[ ${COLOR_YELLOW}警告${COLOR_RESET} ] $msg"
    # 将警告添加到 map，键为消息，值为“警告”
    core_issues_map["$msg"]="警告"
}

print_info() { # 用于非核心问题或提示
    echo -e "[ ${COLOR_BLUE}信息${COLOR_RESET} ] $1"
}

check_command() {
    local cmd_name=$1
    if ! command -v "$cmd_name" &> /dev/null; then
        echo -e "[ ${COLOR_RED}关键缺失${COLOR_RESET} ] 关键命令 '$cmd_name' 未安装。请先安装后再运行此脚本。例如: sudo apt install $cmd_name 或 sudo yum install $cmd_name"
        exit 1
    fi
}

# 备份文件函数
# 参数: $1 - 文件路径
backup_file() {
    local file_path=$1
    if [ -f "$file_path" ]; then
        local backup_path="${file_path}.$(date +%Y%m%d%H%M%S).bak"
        if cp -p "$file_path" "$backup_path"; then
            print_info "已备份 '$file_path' 到 '$backup_path'。"
            echo "$backup_path" >> "$TEMP_BACKUP_LIST" # 将备份路径添加到临时列表
            return 0
        else
            print_error "无法备份 '$file_path'。请检查权限。"
            return 1
        fi
    else
        print_info "文件 '$file_path' 不存在，无法备份。"
        return 1
    fi
}

# 恢复文件函数 (用于脚本自动创建的备份)
# 参数: $1 - 原始文件路径
#       $2 - 备份文件路径
restore_file() {
    local original_file=$1
    local backup_file=$2
    if [ -f "$backup_file" ]; then
        if cp -p "$backup_file" "$original_file"; then
            print_success "已将 '$original_file' 恢复到备份状态 '$backup_file'。"
            return 0
        else
            print_error "无法恢复 '$original_file' 从 '$backup_file'。请手动检查。"
            return 1
        fi
    else
        print_error "备份文件 '$backup_file' 不存在，无法恢复 '$original_file'。"
        return 1
    fi
}

# 清理脚本创建的临时备份文件
cleanup_backups() {
    print_section_header "清理临时备份文件"
    if [ -f "$TEMP_BACKUP_LIST" ] && [ -s "$TEMP_BACKUP_LIST" ]; then
        print_info "正在删除脚本创建的临时备份文件..."
        while IFS= read -r backup_path; do
            if [ -f "$backup_path" ]; then
                sudo rm -f "$backup_path"
                print_info "已删除: $backup_path"
            fi
        done < "$TEMP_BACKUP_LIST"
    else
        print_info "没有发现脚本创建的临时备份文件，无需清理。"
    fi
    rm -f "$TEMP_BACKUP_LIST"
}

# 建议用户手动备份重要的网络配置文件
suggest_manual_backup_network_configs() {
    print_section_header "重要提示：建议手动备份网络配置"
    echo -e "在尝试自动修复网络问题前，强烈建议您手动备份以下重要的网络配置文件，以防万一："
    echo "  - Debian/Ubuntu: /etc/network/interfaces, /etc/netplan/*.yaml"
    echo "  - CentOS/RHEL: /etc/sysconfig/network-scripts/ifcfg-*"
    echo "  - 通用: /etc/resolv.conf, /etc/hosts, /etc/sysctl.conf"
    echo -e "您可以根据您的系统类型，使用类似 '${COLOR_YELLOW}sudo cp -r /etc/netplan /etc/netplan.bak${COLOR_RESET}' 或 '${COLOR_YELLOW}sudo cp -p /etc/network/interfaces /etc/network/interfaces.bak${COLOR_RESET}' 的命令进行备份。"
    echo -e "请务必执行此操作，这能防止在修复过程中出现不可预知的问题。${COLOR_YELLOW}此脚本的自动修复功能仅针对部分设置进行备份，无法涵盖所有系统配置。${COLOR_RESET}"
    echo ""
}

# Helper function to check IPv6 gateway reachability for repair verification
# 返回 0 表示可达，1 表示不可达
check_ipv6_gateway_reachable() {
    local gateway_ip=$1
    local dev_interface=$2 # 链路本地地址需要接口
    print_info "正在重新检查 IPv6 网关 ($gateway_ip) 可达性..."
    local ping_cmd="ping -6 -c 2 -W 2 \"$gateway_ip\""
    if [[ "$gateway_ip" == fe80:* && -n "$dev_interface" ]]; then
        ping_cmd="ping -6 -c 2 -W 2 \"$gateway_ip%$dev_interface\""
    fi

    if eval "$ping_cmd" &> /dev/null; then
        print_success "IPv6 网关 ($gateway_ip) 已恢复可访问！"
        return 0
    else
        # 即使修复失败，这里的输出也只是描述当前状态，不直接加到 core_issues_map，
        # 因为最终状态会在主流程中判断和添加
        echo -e "[ ${COLOR_RED}故障${COLOR_RESET} ] IPv6 网关 ($gateway_ip) 仍然无法访问。"
        return 1
    fi
}

# --- 深入分析函数 ---

# 深入分析网关可达性
deep_analyze_gateway() {
    local ip_version=$1 # "ipv4" 或 "ipv6"
    local gateway_ip=$2
    local dev_interface=$3 # 仅 IPv6 链路本地需要
    print_header "深入分析: 网关 ($gateway_ip) 可达性问题"

    print_section_header "1. 使用不同包大小和计数再次 Ping"
    print_info "尝试使用更多次数和不同包大小再次 ping 网关..."
    local ping_cmd=""
    if [ "$ip_version" == "ipv4" ]; then
        ping_cmd="ping -c \"$PING_DEEP_COUNT\" -s 64 -W 2 \"$gateway_ip\""
    else
        ping_cmd="ping -6 -c \"$PING_DEEP_COUNT\" -s 64 -W 2 \"$gateway_ip\""
        if [[ "$gateway_ip" == fe80:* && -n "$dev_interface" ]]; then
            ping_cmd="ping -6 -c \"$PING_DEEP_COUNT\" -s 64 -W 2 \"$gateway_ip%$dev_interface\""
        fi
    fi

    if eval "$ping_cmd" &> /dev/null; then
        print_success "网关 ($gateway_ip) 已恢复可达或间歇性问题。"
    else
        print_error "多次尝试后网关 ($gateway_ip) 仍无法访问。这通常指示物理连接或本地网络配置问题。"
    fi

    print_section_header "2. 检查 ARP/邻居表 (仅限 IPv4/IPv6)"
    print_info "检查网关的 MAC 地址是否在 ARP/邻居表中..."
    local arp_check_result=1
    if [ "$ip_version" == "ipv4" ]; then
        if command -v ip &> /dev/null; then
            ip neighbor show "$gateway_ip" | grep -q "$gateway_ip" && arp_check_result=0
        elif command -v arp &> /dev/null; then
            arp -n "$gateway_ip" | grep -q "$gateway_ip" && arp_check_result=0
        else
            print_info "未安装 'ip' 或 'arp' 命令，无法检查 ARP/邻居表。"
        fi

        if [ "$arp_check_result" -eq 0 ]; then
            print_success "IPv4 网关 ($gateway_ip) 的 MAC 地址已解析。"
        else
            print_error "无法解析 IPv4 网关 ($gateway_ip) 的 MAC 地址 (ARP 问题)。这可能意味着网关不在线或本地网络问题。"
            echo "建议: 检查网线连接，确保网卡驱动正常，重启网关或路由器。"
        fi
    else # IPv6
        if command -v ip &> /dev/null; then
            # 对于 IPv6 链路本地地址，确保邻居表检查也指定接口
            if [[ "$gateway_ip" == fe80:* && -n "$dev_interface" ]]; then
                ip -6 neighbor show "$gateway_ip" dev "$dev_interface" | grep -q "$gateway_ip" && arp_check_result=0
            else
                ip -6 neighbor show "$gateway_ip" | grep -q "$gateway_ip" && arp_check_result=0
            fi
        else
            print_info "未安装 'ip' 命令，无法检查 IPv6 邻居表。"
        fi

        if [ "$arp_check_result" -eq 0 ]; then
            print_success "IPv6 网关 ($gateway_ip) 的邻居条目已解析。"
        else
            print_error "无法解析 IPv6 网关 ($gateway_ip) 的邻居条目。这可能意味着网关不在线或本地 IPv6 网络问题。"
            echo "建议: 检查网线连接，确保 IPv6 已正确启用，重启网关或路由器。"
        fi
    fi

    print_section_header "3. 路由表详细检查"
    print_info "显示到网关的详细路由信息..."
    if [ "$ip_version" == "ipv4" ]; then
        ip -4 route get "$gateway_ip"
    else
        ip -6 route get "$gateway_ip"
    fi
    echo "建议: 确保路由表中的下一跳是正确的本地接口。"

    echo -e "${COLOR_YELLOW}总结建议: 检查物理连接 (网线/Wi-Fi)、本地 IP 地址和子网掩码配置，以及路由器/网关设备状态。尝试重启您的路由器。${COLOR_RESET}"
    echo ""
}

# 深入分析 DNS 解析
deep_analyze_dns() {
    local domain=$1
    local dns_servers=$(grep -v '^#' /etc/resolv.conf | grep 'nameserver' | awk '{print $2}' | xargs)

    print_header "深入分析: DNS 解析 ($domain) 问题"

    print_section_header "1. 逐个测试已配置的 DNS 服务器"
    if [ -n "$dns_servers" ]; then
        for ns in $dns_servers; do
            print_info "尝试使用系统配置的 DNS 服务器 ${ns} 解析 ${domain}..."
            if ! dig "$domain" @$ns +short +time=5 | grep -E '^[0-9a-fA-F.:]+$' &> /dev/null; then
                print_error "使用配置的 DNS 服务器 ${ns} 解析 ${domain} 失败。"
                print_info "  -> 尝试 Ping DNS 服务器 ${ns}..."
                if ping -c 1 -W 2 "$ns" &> /dev/null; then
                    print_success "    DNS 服务器 ${ns} 可达。"
                    echo "建议: DNS 服务器可达但解析失败，可能是 DNS 服务器本身故障，或出站 UDP/TCP 53 端口被阻止。"
                else
                    print_error "    DNS 服务器 ${ns} 不可达。请检查到此 DNS 服务器的网络连接或防火墙设置。"
                fi
            else
                print_success "使用 DNS 服务器 ${ns} 成功解析 ${domain}。"
            fi
        done
    else
        print_error "未在 /etc/resolv.conf 中找到 DNS 服务器，无法测试。"
        echo "建议: 编辑 /etc/resolv.conf 添加公共 DNS 服务器，例如 'nameserver 223.5.5.5' 和 'nameserver 114.114.114.114'。"
    fi

    print_section_header "2. 使用公共 DNS 服务器测试 (兼容性测试)"
    print_info "尝试使用公共 DNS 服务器 (阿里云DNS IPv4: $IPV4_DNS_TARGET) 解析 $domain..."
    if ! dig "$domain" @$IPV4_DNS_TARGET +short +time=5 | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.' &> /dev/null; then
        print_error "使用公共 DNS ($IPV4_DNS_TARGET) 也无法解析 $domain。这强烈指示出站 UDP 53 端口可能被防火墙阻止，或存在更深层次的网络问题。"
        echo "建议: 检查防火墙规则是否允许出站 UDP 53 端口。尝试使用 'nc -uz $IPV4_DNS_TARGET 53' (如果已安装 nc) 检查端口连通性。"
    else
        print_success "使用公共 DNS ($IPV4_DNS_TARGET) 成功解析 $domain。您的本地 DNS 配置（/etc/resolv.conf）可能存在问题或本地 DNS 服务器故障。"
        echo "建议: 更改 /etc/resolv.conf 为可靠的公共 DNS 服务器。"
    fi

    # 尝试使用公共 DNS IPv6 (若有IPv6网关且命令可用)
    local gateway_ipv6_check=$(ip -6 route show default | awk '/default/ {print $3}' | head -n 1) # 局部变量，避免与全局冲突
    if [ -n "$gateway_ipv6_check" ]; then
        print_info "尝试使用公共 DNS 服务器 (阿里云DNS IPv6: $IPV6_DNS_TARGET) 解析 $domain..."
        if ! dig AAAA "$domain" @$IPV6_DNS_TARGET +short +time=5 | grep -E '^[0-9a-fA-F:]+' &> /dev/null; then
            print_warning "使用公共 IPv6 DNS ($IPV6_DNS_TARGET) 解析 $domain 失败。可能 IPv6 网络本身有问题或出站 UDP 53 端口被阻止。"
        else
            print_success "使用公共 IPv6 DNS ($IPV6_DNS_TARGET) 成功解析 $domain。"
        fi
    fi

    print_section_header "3. 检查 DNS 客户端服务状态 (Systemd)"
    if command -v systemctl &> /dev/null; then
        print_info "检查 systemd-resolved 服务状态..."
        if systemctl is-active --quiet systemd-resolved; then
            print_success "systemd-resolved 服务正在运行。"
            resolvectl status | grep "Current DNS Server"
            resolvectl status | grep "DNS Servers"
            echo "建议: 确认 systemd-resolved 配置的 DNS 服务器与 /etc/resolv.conf 或网络管理工具一致。"
        else
            print_warning "systemd-resolved 服务未运行或不活跃。如果系统依赖此服务，可能导致 DNS 问题。"
            echo "建议: 尝试 'sudo systemctl start systemd-resolved' 或 'sudo systemctl enable systemd-resolved'。"
        fi
    else
        print_info "systemctl 命令不可用，跳过 DNS 客户端服务状态检查。"
    fi

    echo -e "${COLOR_YELLOW}总结建议: 确认 /etc/resolv.conf 配置正确；检查到 DNS 服务器的连通性；验证防火墙是否阻止 UDP/TCP 53 端口。${COLOR_RESET}"
    echo ""
}

# 深入分析外部连通性 (Ping)
deep_analyze_ping_connectivity() {
    local ip_target=$1
    local ip_version_flag=$2 # -4 或 -6
    print_header "深入分析: 外部 IP ($ip_target) Ping 连通性问题"

    print_section_header "1. Traceroute 路径跟踪 (路由分析)"
    print_info "尝试使用 traceroute 跟踪到 $ip_target 的路径，以定位网络中断的位置..."
    if command -v traceroute &> /dev/null; then
        if [ -z "$ip_version_flag" ]; then # For IPv4
             traceroute -n "$ip_target"
        else # For IPv6
            traceroute -n "$ip_version_flag" "$ip_target"
        fi
        if [ $? -ne 0 ]; then
            print_error "traceroute 到 $ip_target 失败或超时。路由可能存在问题或被中间设备阻止。"
            echo "建议: 分析 traceroute 输出，查看在哪个跳数中断，这可能指向中间路由器故障或 ISP 路由问题。联系您的 ISP。"
        else
            print_success "traceroute 到 $ip_target 成功完成。请检查输出是否有不寻常的延迟或星号。"
        fi
    else
        print_info "traceroute 命令未安装。安装 (如: sudo apt install traceroute) 以获取更详细的路径信息。"
    fi

    print_section_header "2. 链路层检查 (Ping 网关)"
    print_info "确认网关是否可达，以排除局域网问题..."
    local gateway_ip=""
    local dev_interface=""
    if [ -z "$ip_version_flag" ]; then # IPv4
        gateway_ip=$(ip -4 route show default | awk '/default/ {print $3}' | head -n 1)
    else # IPv6
        gateway_ip=$(ip -6 route show default | awk '/default/ {print $3}' | head -n 1)
        dev_interface=$(ip -6 route show default | awk '/default/ {print $5}' | head -n 1)
    fi

    if [ -n "$gateway_ip" ]; then
        local ping_cmd="ping $ip_version_flag -c 2 -W 2 \"$gateway_ip\""
        if [[ "$gateway_ip" == fe80:* && -n "$dev_interface" ]]; then
            ping_cmd="ping $ip_version_flag -c 2 -W 2 \"$gateway_ip%$dev_interface\""
        fi

        if eval "$ping_cmd" &> /dev/null; then
            print_success "网关 ($gateway_ip) 可达。问题可能在网关之外。"
        else
            print_error "网关 ($gateway_ip) 不可达。问题可能出在本地局域网或网关本身。"
            echo "建议: 请参考 '深入分析: 网关可达性问题' 部分进行排查。"
        fi
    else
        print_info "未找到对应 IP 版本的默认网关，无法检查网关连通性。"
    fi

    echo -e "${COLOR_YELLOW}总结建议: 使用 traceroute 定位路由中断点；确认网关可达性；检查防火墙是否阻止 ICMP 协议的出站流量。${COLOR_RESET}"
    echo ""
}

# 深入分析 HTTP/HTTPS 连通性
deep_analyze_http_https_connectivity() {
    local domain=$1
    local ip_version_flag=$2 # -4 或 -6
    local protocol=$3 # http 或 https
    local port=$4 # 80 或 443
    print_header "深入分析: $protocol://$domain (端口 $port) 访问问题"

    print_section_header "1. Curl 详细模式诊断"
    print_info "尝试使用 curl 详细模式 ($protocol://$domain:$port) 诊断连接过程..."
    local resolved_ip=""
    if [ -z "$ip_version_flag" ]; then # IPv4
        resolved_ip=$(dig A "$domain" +short +time=3 | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.' | head -n 1)
    else # IPv6
        resolved_ip=$(dig AAAA "$domain" +short +time=3 | grep -E '^[0-9a-fA-F:]+' | head -n 1)
    fi

    local curl_cmd="curl $ip_version_flag -v --connect-timeout $CURL_TIMEOUT"
    if [ -n "$resolved_ip" ]; then
        print_info "尝试强制解析到 IP: $resolved_ip"
        curl_cmd+=" --resolve $domain:$port:$resolved_ip"
    fi
    curl_cmd+=" $protocol://$domain"

    local CURL_OUTPUT=$(mktemp)
    if eval "$curl_cmd" -o /dev/null &> "$CURL_OUTPUT"; then
        print_success "Curl 命令执行成功，请查看以下详细输出以分析问题（如 HTTP 状态码、TLS 握手信息等）。"
        cat "$CURL_OUTPUT"
    else
        print_error "Curl 命令执行失败。请查看以下详细输出中的错误信息。"
        cat "$CURL_OUTPUT"
        local CURL_EXIT_CODE=$?
        case $CURL_EXIT_CODE in
            6) print_error "无法解析主机名 ($domain)。请检查 DNS 配置或主机名拼写。" ;;
            7) print_error "无法连接到服务器 ($domain:$port)。连接被拒绝或超时。可能防火墙阻止或服务器不在线。" ;;
            22) print_error "HTTP 返回错误代码（非 2xx/3xx）。服务器响应异常，但连接建立成功。" ;;
            28) print_error "操作超时。连接或数据传输超时。网络延迟高或服务器响应慢。" ;;
            35) print_error "SSL/TLS 握手失败。可能证书问题、不兼容的加密套件或系统时间不准确。" ;;
            *) print_error "Curl 返回未知错误码: $CURL_EXIT_CODE。请查阅 curl 错误码文档。" ;;
        esac
    fi
    rm "$CURL_OUTPUT"

    print_section_header "2. 端口扫描 (兼容性测试)"
    print_info "尝试使用 'nc' 或 'telnet' 检查目标端口 ($port) 是否开放..."
    if command -v nc &> /dev/null; then
        print_info "使用 nc 检查端口..."
        if nc -z -w 3 "$domain" "$port" &> /dev/null; then
            print_success "目标 $domain 的 $port 端口开放。"
        else
            print_error "目标 $domain 的 $port 端口未开放或无法连接。可能被防火墙阻止或服务未运行。"
            echo "建议: 检查本地防火墙 (OUTPUT 链) 和远程服务器防火墙 (INPUT 链)。"
        fi
    elif command -v telnet &> /dev/null; then
        print_info "使用 telnet 检查端口 (telnet 命令可能会挂起，需要手动中断)..."
        if telnet "$domain" "$port" &> /dev/null; then
            print_success "目标 $domain 的 $port 端口开放 (请手动 Ctrl+C 退出 telnet)。"
        else
            print_error "目标 $domain 的 $port 端口未开放或无法连接。可能被防火墙阻止或服务未运行。"
            echo "建议: 检查本地防火墙 (OUTPUT 链) 和远程服务器防火墙 (INPUT 链)。"
        fi
    else
        print_info "未安装 nc 或 telnet，无法进行端口连通性检查。请安装其中一个工具以获得更详细检查。"
    fi

    echo -e "${COLOR_YELLOW}总结建议: 分析 Curl 详细输出中的错误信息；检查本地防火墙是否阻止出站到 $port 端口；确认目标服务器的 $port 端口是否开放且服务正常运行。${COLOR_RESET}"
    echo ""
}

# --- 自动修复函数 ---

# 修复 IPv6 网关无法访问的问题
# 参数: $1 - IPv6 网关 IP
repair_ipv6_gateway_unreachable() {
    local gateway_ip=$1
    local interface=""
    local sysctl_backup_path=""

    print_header "尝试自动修复: IPv6 网关无法访问 ($gateway_ip)"
    suggest_manual_backup_network_configs # 再次强调手动备份

    echo -e "将尝试以下自动修复步骤，每个步骤后会重新检查。如果修复成功，将停止并退出修复流程。"

    # 1. 检查并启用 IPv6 (sysctl)
    print_section_header "步骤 1/4: 检查并启用 IPv6 (sysctl)"
    local current_disable_ipv6_all=$(sysctl -n net.ipv6.conf.all.disable_ipv6 2>/dev/null)
    local current_disable_ipv6_default=$(sysctl -n net.ipv6.conf.default.disable_ipv6 2>/dev/null)

    if [[ "$current_disable_ipv6_all" == "1" || "$current_disable_ipv6_default" == "1" ]]; then
        print_warning "检测到 IPv6 可能被 sysctl 禁用。尝试启用..."
        if backup_file "/etc/sysctl.conf"; then # 备份 sysctl.conf
            sysctl_backup_path=$(tail -n 1 "$TEMP_BACKUP_LIST") # 获取刚刚备份的路径
            echo "net.ipv6.conf.all.disable_ipv6 = 0" | sudo tee -a /etc/sysctl.conf > /dev/null
            echo "net.ipv6.conf.default.disable_ipv6 = 0" | sudo tee -a /etc/sysctl.conf > /dev/null
            sudo sysctl -p > /dev/null # 立即应用 sysctl 配置
            sleep 2 # 等待配置生效
            if [[ "$(sysctl -n net.ipv6.conf.all.disable_ipv6)" == "0" && "$(sysctl -n net.ipv6.conf.default.disable_ipv6)" == "0" ]]; then
                print_success "IPv6 已通过 sysctl 启用。正在重新检查网关。"
                # 尝试找到接口，用于 Ping 链路本地地址
                local repair_interface=$(ip -6 route show default | awk '/default/ {print $5}' | head -n 1)
                if check_ipv6_gateway_reachable "$gateway_ip" "$repair_interface"; then return 0; fi # 如果修复成功，返回
                print_info "启用 sysctl 后 IPv6 网关仍无法访问。"
            else
                print_error "未能通过 sysctl 启用 IPv6。尝试恢复 sysctl.conf。"
                restore_file "/etc/sysctl.conf" "$sysctl_backup_path"
            fi
        else
            print_error "无法备份 sysctl.conf，跳过 sysctl 修复。"
        fi
    else
        print_info "sysctl 未禁用 IPv6。"
    fi

    # 尝试找到与网关关联的接口
    interface=$(ip -6 route show default | awk '/default/ {print $5}' | head -n 1)
    if [ -z "$interface" ]; then
        # 如果直接路由没有找到，尝试从地址中查找
        interface=$(ip -6 addr show | grep "$gateway_ip" | awk '{print $NF}' | head -n 1)
    fi

    if [ -z "$interface" ]; then
        print_warning "未能确定与 IPv6 网关相关的网络接口。部分修复步骤可能无法执行。"
    fi

    # 2. 重启网络接口 (如果接口已确定)
    if [ -n "$interface" ]; then
        print_section_header "步骤 2/4: 重启网络接口 ($interface)"
        print_info "尝试关闭并重新开启接口..."
        # 注意: 这可能短暂中断所有网络连接
        if sudo ip link set dev "$interface" down && sudo ip link set dev "$interface" up; then
            print_success "接口 $interface 重启命令执行成功。"
            sleep 5 # 等待接口重新获取地址
            if check_ipv6_gateway_reachable "$gateway_ip" "$interface"; then return 0; fi
            print_info "重启接口 ($interface) 未能解决问题。"
        else
            print_error "重启接口 ($interface) 失败。请检查接口名称或权限。"
        fi
    else
        print_info "无法确定网络接口，跳过接口重启。"
    fi


    # 3. 重启网络管理服务 (NetworkManager/systemd-networkd)
    print_section_header "步骤 3/4: 重启网络管理服务"
    if command -v systemctl &> /dev/null; then
        if systemctl is-active --quiet NetworkManager; then
            print_info "尝试重启 NetworkManager 服务..."
            if sudo systemctl restart NetworkManager; then
                print_success "NetworkManager 服务重启命令执行成功。"
                sleep 5
                local repair_interface=$(ip -6 route show default | awk '/default/ {print $5}' | head -n 1) # 重新获取接口
                if check_ipv6_gateway_reachable "$gateway_ip" "$repair_interface"; then return 0; fi
                print_info "重启 NetworkManager 未能解决问题。"
            else
                print_error "重启 NetworkManager 服务失败。"
            fi
        elif systemctl is-active --quiet systemd-networkd; then
            print_info "尝试重启 systemd-networkd 服务..."
            if sudo systemctl restart systemd-networkd; then
                print_success "systemd-networkd 服务重启命令执行成功。"
                sleep 5
                local repair_interface=$(ip -6 route show default | awk '/default/ {print $5}' | head -n 1) # 重新获取接口
                if check_ipv6_gateway_reachable "$gateway_ip" "$repair_interface"; then return 0; fi
                print_info "重启 systemd-networkd 未能解决问题。"
            else
                print_error "重启 systemd-networkd 服务失败。"
            fi
        else
            print_info "未检测到 NetworkManager 或 systemd-networkd 活跃，跳过服务重启。"
        fi
    else
        print_info "systemctl 命令不可用，无法重启网络管理服务。"
    fi

    # 4. 检查并重启 DHCPv6 客户端 (如果适用)
    print_section_header "步骤 4/4: 检查并重启 DHCPv6 客户端"
    if [ -n "$interface" ]; then
        if command -v dhclient &> /dev/null; then
            print_info "尝试重启 dhclient IPv6 客户端..."
            # 停止现有 dhclient -6 进程，然后重新启动
            sudo killall dhclient -q -w -SIGTERM 2>/dev/null
            if sudo dhclient -6 -v "$interface" &> /dev/null; then # 后台运行，静默输出
                print_success "dhclient IPv6 客户端启动命令执行成功。"
                sleep 5
                local repair_interface=$(ip -6 route show default | awk '/default/ {print $5}' | head -n 1) # 重新获取接口
                if check_ipv6_gateway_reachable "$gateway_ip" "$repair_interface"; then return 0; fi
                print_info "重启 dhclient -6 未能解决问题。"
            else
                print_error "启动 dhclient -6 失败。请检查日志或配置。"
            fi
        elif command -v dhcpcd &> /dev/null; then
            print_info "尝试重启 dhcpcd IPv6 客户端..."
            sudo killall dhcpcd -q -w -SIGTERM 2>/dev/null
            if sudo dhcpcd -6 -v "$interface" &> /dev/null; then # 后台运行
                print_success "dhcpcd IPv6 客户端启动命令执行成功。"
                sleep 5
                local repair_interface=$(ip -6 route show default | awk '/default/ {print $5}' | head -n 1) # 重新获取接口
                if check_ipv6_gateway_reachable "$gateway_ip" "$repair_interface"; then return 0; fi
                print_info "重启 dhcpcd -6 未能解决问题。"
            else
                print_error "启动 dhcpcd -6 失败。请检查日志或配置。"
            fi
        else
            print_info "未检测到 dhclient 或 dhcpcd 客户端，无法检查或重启 DHCPv6 客户端。"
        fi
    else
        print_info "无法确定网络接口，跳过 DHCPv6 客户端检查和重启。"
    fi


    # 如果所有自动修复尝试都失败
    echo -e "${COLOR_RED}自动修复尝试已完成，但 IPv6 网关 ($gateway_ip) 仍然无法访问。${COLOR_RESET}"
    echo "这可能需要手动检查以下更复杂的问题："
    echo "  - ${COLOR_YELLOW}路由器/光猫的 IPv6 配置${COLOR_RESET}：确保路由器正确分配 IPv6 地址和网关。"
    echo "  - ${COLOR_YELLOW}ISP 的 IPv6 支持${COLOR_RESET}：确认您的网络服务提供商已为您启用 IPv6。"
    echo "  - ${COLOR_YELLOW}系统日志${COLOR_RESET}：查看 /var/log/syslog 或 journalctl -xe 了解更多网络相关的错误信息。"
    echo "  - ${COLOR_YELLOW}网络硬件问题${COLOR_RESET}：网卡驱动或硬件故障。"
    echo ""

    # 如果有通过脚本创建的备份，询问是否恢复
    if [ -f "$TEMP_BACKUP_LIST" ] && [ -s "$TEMP_BACKUP_LIST" ]; then
        read -p "自动修复未能解决问题。是否恢复本次脚本自动进行的配置更改? (y/N): " restore_choice
        if [[ "$restore_choice" =~ ^[Yy]$ ]]; then
            print_info "正在恢复脚本自动创建的备份..."
            # 倒序读取备份文件列表进行恢复，以正确的顺序撤销更改
            tac "$TEMP_BACKUP_LIST" | while IFS= read -r backup_path; do
                local original_file=$(echo "$backup_path" | sed 's/\.[0-9]\{14\}\.bak//')
                restore_file "$original_file" "$backup_path"
            done
            print_success "已尝试恢复所有脚本自动创建的备份。请重新检查网络。"
        else
            print_info "跳过自动恢复备份。请自行解决问题或手动恢复配置。"
        fi
    else
        print_info "没有发现脚本自动创建的备份，无需恢复。"
    fi
    return 1 # 表示修复失败
}


# --- 预运行检查 ---
# 确保脚本以 root 权限运行
if [[ $EUID -ne 0 ]]; then
   echo -e "${COLOR_RED}此脚本需要 root/sudo 权限才能运行，尤其是执行修复操作和完整的防火墙检查。${COLOR_RESET}"
   echo "请使用: ${COLOR_YELLOW}sudo bash $(basename "$0")${COLOR_RESET} 运行。"
   exit 1
fi

print_header "依赖命令检查"
check_command ping
check_command ip
check_command dig
check_command curl
check_command grep
check_command awk
check_command mktemp # 用于创建临时文件
check_command tee    # 用于写入文件
check_command sed    # 用于字符串处理
check_command tail   # 用于读取文件尾部
check_command tac    # 用于倒序读取文件

# 可选命令检查，如果缺失不会退出，但在需要时会给出警告
if ! command -v traceroute &> /dev/null; then
    print_info "traceroute 命令未安装。部分路由分析功能将受限。"
fi
if ! command -v nc &> /dev/null && ! command -v telnet &> /dev/null; then
    print_info "nc 或 telnet 命令均未安装。部分端口连通性检查将受限。"
fi
if ! command -v systemctl &> /dev/null; then
    print_info "systemctl 命令未安装。DNS 客户端服务状态检查将受限。"
fi
if ! command -v arp &> /dev/null; then
    print_info "arp 命令未安装。部分 IPv4 ARP 检查将使用 'ip neighbor' 替代。"
fi
if ! command -v dhclient &> /dev/null && ! command -v dhcpcd &> /dev/null; then
    print_info "dhclient 或 dhcpcd 命令均未安装。DHCPv6 客户端检查和重启将受限。"
fi

echo ""


# ==============================================================================
# 1. 本地网络接口与路由检查
# ==============================================================================
print_header "1. 检查本地网络接口与路由"

# --- 检查网络接口 ---
interfaces=$(ip -o link show | awk -F': ' '{print $2}' | xargs) # xargs 确保多行变单行
if [ -z "$interfaces" ]; then
    print_error "未找到任何网络接口。请检查硬件连接或虚拟网卡配置。"
else
    print_success "发现网络接口: $interfaces"
    local active_ipv4=$(ip -4 addr show | grep -oP 'inet \K[\d.]+' | grep -v '127.0.0.1' | xargs)
    local active_ipv6=$(ip -6 addr show | grep -oP 'inet6 \K[0-9a-f:]+' | grep -v '::1' | xargs)

    if [ -n "$active_ipv4" ]; then
        print_success "检测到活动的 IPv4 地址: $active_ipv4"
    else
        print_warning "未检测到活动的公共 IPv4 地址。这通常是网络不通的原因。"
        echo "建议: 检查网络接口配置 (如 DHCP 或静态 IP 设置)。"
    fi
    if [ -n "$active_ipv6" ]; then
        print_success "检测到活动的 IPv6 地址: $active_ipv6"
    else
        print_warning "未检测到活动的 IPv6 地址。IPv6 功能将受限。"
        echo "建议: 检查网络接口的 IPv6 配置或路由器是否分配 IPv6 地址。"
    fi
fi

# --- 检查默认网关 ---
local gateway_ipv4=$(ip -4 route show default | awk '/default/ {print $3}' | head -n 1)
# 获取 IPv6 默认网关和其对应的接口，用于链路本地地址 Ping
local gateway_ipv6=$(ip -6 route show default | awk '/default/ {print $3}' | head -n 1)
local gateway_ipv6_dev=$(ip -6 route show default | awk '/default/ {print $5}' | head -n 1)


if [ -n "$gateway_ipv4" ]; then
    print_success "IPv4 默认网关: $gateway_ipv4"
    if ! ping -c 1 -W 2 "$gateway_ipv4" &> /dev/null; then
        print_error "无法访问 IPv4 网关 ($gateway_ipv4)。内部网络可能存在问题。"
        deep_analyze_gateway "ipv4" "$gateway_ipv4" ""
    fi
else
    print_error "未找到 IPv4 默认网关。这是导致无法访问外部网络的主要原因。"
    echo "建议: 检查网络接口配置 (如 DHCP 或静态 IP 设置)。"
fi

if [ -n "$gateway_ipv6" ]; then
    print_success "IPv6 默认网关: $gateway_ipv6"
    local initial_ipv6_gateway_reachable=false
    local ping_ipv6_gw_cmd="ping -6 -c 1 -W 2 \"$gateway_ipv6\""
    if [[ "$gateway_ipv6" == fe80:* && -n "$gateway_ipv6_dev" ]]; then
        ping_ipv6_gw_cmd="ping -6 -c 1 -W 2 \"$gateway_ipv6%$gateway_ipv6_dev\""
    fi

    if eval "$ping_ipv6_gw_cmd" &> /dev/null; then
        print_success "IPv6 默认网关 ($gateway_ipv6) 可访问。"
        initial_ipv6_gateway_reachable=true
    else
        print_error "无法访问 IPv6 网关 ($gateway_ipv6)。内部网络可能存在问题。"
        deep_analyze_gateway "ipv6" "$gateway_ipv6" "$gateway_ipv6_dev" # 先进行深入分析

        # 在深度分析后，再次检查 IPv6 网关是否可达。如果仍不可达，则提供修复选项。
        if ! check_ipv6_gateway_reachable "$gateway_ipv6" "$gateway_ipv6_dev"; then
            read -p "是否尝试自动修复 IPv6 网关问题? (y/N): " choice
            if [[ "$choice" =~ ^[Yy]$ ]]; then
                if repair_ipv6_gateway_unreachable "$gateway_ipv6"; then
                    print_success "IPv6 网关问题已修复！"
                    cleanup_backups # 修复成功，清理临时备份
                else
                    print_error "IPv6 网关自动修复失败。"
                    # repair_ipv6_gateway_unreachable 函数内部已处理了修复失败时的备份恢复提示
                fi
            else
                print_info "跳过自动修复。"
            fi
        fi
    fi
else
    print_warning "未找到 IPv6 默认网关。IPv6 网络将无法访问外网。"
fi
echo ""


# ==============================================================================
# 2. DNS 与 Hosts 文件检查
# ==============================================================================
print_header "2. 检查 DNS 配置与 Hosts 文件"

# --- 检查 /etc/resolv.conf ---
if [ -f /etc/resolv.conf ]; then
    local dns_servers=$(grep -v '^#' /etc/resolv.conf | grep 'nameserver' | awk '{print $2}' | xargs)
    if [ -n "$dns_servers" ]; then
        print_success "在 /etc/resolv.conf 中找到 DNS 服务器: $dns_servers"
    else
        print_error "/etc/resolv.conf 文件中未配置有效的 'nameserver'。这会导致无法解析域名。"
        echo "建议: 编辑 /etc/resolv.conf 添加 'nameserver 223.5.5.5' 等公共 DNS。"
    fi
else
    print_error "DNS 配置文件 /etc/resolv.conf 不存在。系统可能无法进行域名解析。"
    echo "建议: 尝试重新生成此文件，或手动创建并添加 DNS 服务器。"
fi

# --- 检查 DNS 解析 ---
print_info "正在测试域名解析: $DOMAIN_TARGET"
# 检查 IPv4 和 IPv6 DNS 解析，如果任一失败，则进行深度分析
local ipv4_dns_ok=$(dig A "$DOMAIN_TARGET" +short +time=3 | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.' &> /dev/null; echo $?)
local ipv6_dns_ok=$(dig AAAA "$DOMAIN_TARGET" +short +time=3 | grep -E '^[0-9a-fA-F:]+' &> /dev/null; echo $?)

if [ "$ipv4_dns_ok" -ne 0 ] || [ "$ipv6_dns_ok" -ne 0 ]; then
    print_error "DNS 解析 ($DOMAIN_TARGET) 失败（IPv4 或 IPv6）。"
    deep_analyze_dns "$DOMAIN_TARGET"
else
    print_success "IPv4/IPv6 DNS 解析 ($DOMAIN_TARGET) 成功。"
fi


# --- 检查 /etc/hosts 文件是否存在潜在劫持 ---
if [ -f /etc/hosts ]; then
    local hijacked_entries=$(grep "$DOMAIN_TARGET" /etc/hosts | grep -v '^#')
    if [ -n "$hijacked_entries" ]; then
        print_warning "/etc/hosts 文件中发现可能影响网络访问的条目:\n$hijacked_entries"
        echo "建议: 检查这些条目是否是您有意为之，否则请删除或注释掉它们。"
    else
        print_success "/etc/hosts 文件检查正常，未发现针对目标的劫持。"
    fi
else
    print_info "/etc/hosts 文件不存在。这通常不是问题，但若您依赖它进行本地解析，请注意。"
fi
echo ""


# ==============================================================================
# 3. 外部网络连通性检查
# ==============================================================================
print_header "3. 检查外部网络连通性"

# --- Ping 外部 IP ---
print_info "正在 Ping 外部 IPv4 地址: $IPV4_DNS_TARGET"
if ! ping -c "$PING_COUNT" -W 3 "$IPV4_DNS_TARGET" &> /dev/null; then
    print_error "Ping 外部 IPv4 地址 ($IPV4_DNS_TARGET) 失败。出站连接可能被阻止或路由不通。"
    deep_analyze_ping_connectivity "$IPV4_DNS_TARGET" "" # 空字符串表示 IPv4
fi

if [ -n "$gateway_ipv6" ]; then
    print_info "正在 Ping 外部 IPv6 地址: $IPV6_DNS_TARGET"
    local ping_external_ipv6_cmd="ping -6 -c \"$PING_COUNT\" -W 3 \"$IPV6_DNS_TARGET\""
    if [[ "$gateway_ipv6" == fe80:* && -n "$gateway_ipv6_dev" ]]; then
        ping_external_ipv6_cmd="ping -6 -c \"$PING_COUNT\" -W 3 \"$IPV6_DNS_TARGET%$gateway_ipv6_dev\"" # 尝试指定接口
    fi

    if ! eval "$ping_external_ipv6_cmd" &> /dev/null; then
        print_error "Ping 外部 IPv6 地址 ($IPV6_DNS_TARGET) 失败。IPv6 出站连接可能被阻止。"
        deep_analyze_ping_connectivity "$IPV6_DNS_TARGET" "-6"
    fi
else
    print_info "无 IPv6 网关，跳过外部 IPv6 Ping 测试。"
fi

# --- 检查 HTTP/HTTPS 连通性 ---
print_info "正在测试对 $DOMAIN_TARGET 的 HTTP/HTTPS 访问"
# 测试 IPv4 HTTP
if ! curl -4 --connect-timeout $CURL_TIMEOUT -s -o /dev/null -w "%{http_code}" "http://$DOMAIN_TARGET" | grep -E '200|30[12]' &> /dev/null; then
    print_error "通过 IPv4 访问 HTTP (80端口) 失败。端口可能被防火墙阻止或目标服务不可达。"
    deep_analyze_http_https_connectivity "$DOMAIN_TARGET" "-4" "http" "80"
fi
# 测试 IPv4 HTTPS
if ! curl -4 --connect-timeout $CURL_TIMEOUT -s -o /dev/null -w "%{http_code}" "https://$DOMAIN_TARGET" | grep -E '200|30[12]' &> /dev/null; then
    print_error "通过 IPv4 访问 HTTPS (443端口) 失败。端口可能被防火墙阻止或目标服务不可达。"
    deep_analyze_http_https_connectivity "$DOMAIN_TARGET" "-4" "https" "443"
fi

# 测试 IPv6 HTTPS
if [ -n "$gateway_ipv6" ]; then
    local curl_ipv6_cmd="curl -6 --connect-timeout $CURL_TIMEOUT -s -o /dev/null -w \"%{http_code}\" \"https://$DOMAIN_TARGET\""
    if [[ "$gateway_ipv6" == fe80:* && -n "$gateway_ipv6_dev" ]]; then
        print_info "IPv6 网关为链路本地地址，curl 将尝试通过默认路由表连接。"
    fi

    # 捕获 curl 的输出，以便判断是否成功
    local curl_status_code=$(eval "$curl_ipv6_cmd")
    if echo "$curl_status_code" | grep -E '200|30[12]' &> /dev/null; then
        print_success "通过 IPv6 访问 HTTPS (443端口) 成功。"
        IPV6_HTTPS_SUCCESS_FLAG=true # 设置全局标志
    else
        print_warning "通过 IPv6 访问 HTTPS (443端口) 失败。IPv6 流量可能被阻止或目标服务无 IPv6 支持。"
        deep_analyze_http_https_connectivity "$DOMAIN_TARGET" "-6" "https" "443"
    fi
else
    print_info "无 IPv6 网关，跳过外部 IPv6 HTTPS 测试。"
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
    echo "建议: 如果代理服务器配置错误、不可用或代理软件未运行，将导致网络访问失败。确认代理设置是否正确，代理服务器是否可达。如果不需要代理，请清除这些环境变量。"
else
    print_success "未在环境变量中发现代理设置。"
fi

# --- 检查防火墙 ---
# 由于脚本已强制要求 sudo 运行，此处不再进行权限警告，而是直接执行检查。
print_info "正在检查防火墙规则 (需要 root 权限)..."
local firewall_checked=false

# 检查 UFW
if command -v ufw &> /dev/null; then
    firewall_checked=true
    if ufw status | grep -q "Status: active"; then
        print_success "检测到 UFW 防火墙处于活动状态。"
        local ufw_default_outgoing=$(ufw status | grep "Default: outgoing" | awk '{print $NF}')
        if [ "$ufw_default_outgoing" == "deny" ]; then
            print_error "UFW 防火墙默认策略为 '拒绝所有出站流量'。这会阻止大部分网络访问，除非有明确的允许规则。"
            echo "建议: 检查 UFW 规则 ('sudo ufw status verbose')，确保允许必要的出站流量（例如 80, 443, 53 端口）。"
        else
            print_success "UFW 出站策略正常 (当前为 '$ufw_default_outgoing')。"
        fi
    else
        print_success "UFW 防火墙未激活。"
    fi
fi

# 检查 firewalld
if command -v firewall-cmd &> /dev/null && ! $firewall_checked; then
    firewall_checked=true
    if systemctl is-active --quiet firewalld; then
        print_success "检测到 firewalld 防火墙处于活动状态。"
        print_warning "firewalld 处于活动状态，其规则可能阻止网络流量。请手动检查 firewalld 规则 ('sudo firewall-cmd --list-all') 以确认没有阻止所需流量。"
    else
        print_success "firewalld 防火墙未激活。"
    fi
fi

# 检查 iptables (如果 UFW 和 firewalld 都未检测到或未激活)
if command -v iptables &> /dev/null && ! $firewall_checked; then
    firewall_checked=true
    print_info "正在检查 iptables 规则..."
    local ipv4_output_policy=$(iptables -L OUTPUT -n | grep "Chain OUTPUT (policy" | awk '{print $4}' | sed 's/[()]//g')
    if [ "$ipv4_output_policy" == "DROP" ] || [ "$ipv4_output_policy" == "REJECT" ]; then
        print_error "iptables 的 IPv4 OUTPUT 链默认策略为 $ipv4_output_policy，这会阻止出站流量。"
        echo "建议: 检查 iptables 规则 ('sudo iptables -L -n')，确保允许必要的出站流量。"
    else
        print_success "iptables IPv4 OUTPUT 链策略正常 (当前为 $ipv4_output_policy)。"
    fi

    if command -v ip6tables &> /dev/null; then
        local ipv6_output_policy=$(ip6tables -L OUTPUT -n | grep "Chain OUTPUT (policy" | awk '{print $4}' | sed 's/[()]//g')
        if [ "$ipv6_output_policy" == "DROP" ] || [ "$ipv6_output_policy" == "REJECT" ]; then
            print_error "ip6tables 的 IPv6 OUTPUT 链默认策略为 $ipv6_output_policy，这会阻止 IPv6 出站流量。"
            echo "建议: 检查 ip6tables 规则 ('sudo ip6tables -L -n')，确保允许必要的 IPv6 出站流量。"
        else
            print_success "ip6tables IPv6 OUTPUT 链策略正常 (当前为 $ipv6_output_policy)。"
        fi
    fi
fi

if ! $firewall_checked; then
    print_info "未检测到主流防火墙 (UFW, firewalld, iptables) 的活动状态。"
fi
echo ""


# ==============================================================================
# 5. 最终报告
# ==============================================================================
print_header "5. 排查结果摘要"

# 将 core_issues_map 转换为最终用于报告的列表，并进行特殊处理
declare -a final_summary_issues
for msg in "${!core_issues_map[@]}"; do
    local severity=${core_issues_map["$msg"]}
    local processed_msg=""

    # 特殊处理 IPv6 连通性矛盾：如果外部 HTTPS 访问成功，则降级相关故障为警告
    if [[ "$IPV6_HTTPS_SUCCESS_FLAG" == true ]]; then
        if [[ "$msg" =~ "无法访问 IPv6 网关" || "$msg" =~ "多次尝试后网关" ]]; then
            # 检查是否是 fe80:: 开头的链路本地地址
            local gw_ip_in_msg=$(echo "$msg" | grep -oP '\((fe80::[0-9a-fA-F:]+)\)' | head -n 1 | sed 's/[()]//g')
            if [[ "$gw_ip_in_msg" == fe80:* ]]; then
                processed_msg="警告: IPv6 链路本地网关 ($gw_ip_in_msg) 无法 Ping 通，但外部 IPv6 HTTPS 访问正常。这可能由于网关限制 ICMPv6 或存在其他出站路由。"
            else
                processed_msg="警告: IPv6 默认网关 ($gw_ip_in_msg) 无法 Ping 通，但外部 IPv6 HTTPS 访问正常。这可能由于网关限制 ICMPv6 或存在其他出站路由。"
            fi
            severity="警告" # 强制设为警告
        elif [[ "$msg" =~ "Ping 外部 IPv6 地址" ]]; then
            processed_msg="警告: 外部 IPv6 地址 ($IPV6_DNS_TARGET) Ping 失败，但外部 IPv6 HTTPS 访问正常。这可能由于目标服务器限制 ICMPv6 或网络路由偏好 HTTP/HTTPS 流量。"
            severity="警告" # 强制设为警告
        elif [[ "$msg" =~ "通过 IPv6 访问 HTTPS .*失败" ]]; then
            # 如果 HTTPS 最终是成功的，那么之前的失败警告不应出现在最终摘要中
            continue # 跳过此项，因为它最终被解决了
        elif [[ "$msg" =~ "IPv6 网关自动修复失败" ]]; then
            processed_msg="警告: IPv6 网关自动修复失败，但外部 IPv6 HTTPS 访问正常。"
            severity="警告" # 强制设为警告
        fi
    fi

    # 如果没有特殊处理，则使用原始消息
    if [ -z "$processed_msg" ]; then
        processed_msg="$msg"
    fi
    
    final_summary_issues+=("$severity: $processed_msg")
done

# 对最终的摘要列表进行去重处理
declare -A temp_unique_summary
declare -a deduped_summary_issues
for item in "${final_summary_issues[@]}"; do
    if [[ -z "${temp_unique_summary["$item"]}" ]]; then
        temp_unique_summary["$item"]=1
        deduped_summary_issues+=("$item")
    fi
done

if [ ${#deduped_summary_issues[@]} -eq 0 ]; then
    print_success "恭喜！初步检查和深度分析均未发现明显的网络配置故障点。"
    echo "如果网络依然存在问题，可能由以下更深层原因导致："
    echo "  - ${COLOR_YELLOW}上游网络设备（路由器、交换机）故障${COLOR_RESET}：尝试重启您的路由器/光猫。"
    echo "  - ${COLOR_YELLOW}ISP (网络服务提供商) 方面的问题${COLOR_RESET}：联系您的网络服务提供商报告故障。"
    echo "  - ${COLOR_YELLOW}特定应用程序的内部网络设置${COLOR_RESET}：检查您所使用的应用是否有自己的代理或网络配置。"
    echo "  - ${COLOR_YELLOW}SELinux/AppArmor 等更强的安全模块限制${COLOR_RESET}：这些模块可能阻止特定进程的网络访问。"
    echo "  - ${COLOR_YELLOW}硬件故障${COLOR_RESET}：网卡本身可能存在问题。"
else
    echo -e "${COLOR_RED}在此次排查中发现了 ${#deduped_summary_issues[@]} 个潜在问题。请重点关注并根据建议逐一排查和修复：${COLOR_RESET}"
    for (( i=0; i<${#deduped_summary_issues[@]}; i++ )); do
        local issue_line="${deduped_summary_issues[$i]}"
        if [[ "$issue_line" =~ ^故障: ]]; then
            echo -e "  $((i+1)). ${COLOR_RED}${issue_line}${COLOR_RESET}"
        elif [[ "$issue_line" =~ ^警告: ]]; then
            echo -e "  $((i+1)). ${COLOR_YELLOW}${issue_line}${COLOR_RESET}"
        else
            echo -e "  $((i+1)). ${issue_line}" # Fallback, should not happen with current logic
        fi
    done
    echo ""
    echo -e "${COLOR_BLUE}建议您按照上述报告中指出的“故障”和“警告”信息，结合其下方的具体建议进行修复。${COLOR_RESET}"
    echo -e "${COLOR_BLUE}修复后，您可以再次运行此脚本以验证问题是否解决。${COLOR_RESET}"
fi
echo ""

# 确保在脚本退出前清理临时备份列表文件
# 如果在修复成功时，已经执行了 cleanup_backups，这个文件可能已经被删除
# 即使没有被删除，这里确保它被清理
rm -f "$TEMP_BACKUP_LIST"

echo -e "\n${COLOR_BLUE}======================================================================${COLOR_RESET}"
echo -e "${COLOR_BLUE} ═══════════════ 操作完成 ═══════════════${COLOR_RESET}"
echo -e "${COLOR_BLUE}======================================================================${COLOR_RESET}\n"

