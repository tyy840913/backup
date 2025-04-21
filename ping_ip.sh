#!/bin/bash

# 配置参数
TIMEOUT=1              # Ping超时时间（秒）
THREADS=20             # 并发线程数
ARP_CACHE="/proc/net/arp"  # ARP缓存文件路径

# 自动获取本地IP和网络段
get_local_network() {
    # 获取第一个非lo网卡的IP地址
    local ip=$(ip route get 1 | awk '{print $7}' | head -1)
    if [ -z "$ip" ]; then
        ip=$(hostname -I | awk '{print $1}')
    fi
    
    # 提取网络段 (如192.168.1)
    echo "$ip" | awk -F. '{print $1"."$2"."$3}'
}

# 扫描函数（获取详细信息）
scan_ip() {
    local ip="$1"
    if ping -c 1 -W "$TIMEOUT" "$ip" &>/dev/null; then
        # 从ARP缓存获取MAC地址
        local mac=$(awk -v ip="$ip" '$1==ip {print $4}' "$ARP_CACHE" 2>/dev/null)
        
        # 获取主机名
        local hostname=$(nslookup "$ip" 2>/dev/null | awk -F'= ' '/name =/{print $2}' | sed 's/\.$//')
        [ -z "$hostname" ] && hostname="未知"
        
        # 输出结果（固定宽度格式）
        if [ -n "$mac" ] && [ "$mac" != "00:00:00:00:00:00" ]; then
            printf "✅ 在线: %-15s | MAC: %-17s | 主机名: %-20s\n" \
                   "$ip" "$mac" "$hostname"
        else
            printf "✅ 在线: %-15s | MAC: %-17s | 主机名: %-20s\n" \
                   "$ip" "未知" "$hostname"
        fi
    fi
}

# 主程序
NETWORK=$(get_local_network)
if [ -z "$NETWORK" ]; then
    echo "❌ 无法自动获取本地网络地址，请手动设置NETWORK变量"
    exit 1
fi

echo "🔄 扫描局域网 $NETWORK.0/24 ..."

total_ips=254
current_ip=0

# 创建临时文件存储结果
result_file=$(mktemp)

for i in {1..254}; do
    ip="$NETWORK.$i"
    (scan_ip "$ip") >> "$result_file" &
    current_ip=$((current_ip + 1))
    
    # 进度条
    printf "\r扫描进度: %d/%d" "$current_ip" "$total_ips"
    
    # 控制并发线程数
    if [[ $(jobs -r | wc -l) -ge "$THREADS" ]]; then
        wait -n
    fi
done

# 等待所有后台任务完成
wait

# 显示结果
echo -e "\n\n🔍 扫描结果:"
sort -n -t. -k4 "$result_file" | uniq
rm "$result_file"

echo -e "\n🎉 扫描完成！"
