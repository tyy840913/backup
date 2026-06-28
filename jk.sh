#!/bin/bash

# ================= 配置 =================
CPU_THRESHOLD=70
MEM_THRESHOLD=90

TG_BOT_TOKEN="7030145953:AAEhS_8fCnnn5SmQ2zjOIKS1eH5iSLNx2_E"
TG_CHAT_ID="6302326077"
TG_API_BASE="https://cdn.woskee.nyc.mn/api.telegram.org"

send_telegram() {
    local msg_html="$1"
    curl -s -X POST "${TG_API_BASE}/bot${TG_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${TG_CHAT_ID}" \
        --data-urlencode "text=${msg_html}" \
        --data-urlencode "parse_mode=HTML" \
        --data-urlencode "disable_web_page_preview=true"
}

# ================= 主逻辑 =================

# CPU
CPU_IDLE=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk -F'[, ]+' '{for(i=1;i<=NF;i++) if($(i)=="id") {print $(i-1); exit}}' | tr -d ' ')
CPU_IDLE=${CPU_IDLE:-100.0}
[[ ! "$CPU_IDLE" =~ ^[0-9.]+$ ]] && CPU_IDLE=100.0
CPU_USAGE=$(awk -v idle="$CPU_IDLE" 'BEGIN {printf "%.1f", 100 - idle}')

# 内存
MEM_STATS=$(free -m 2>/dev/null | awk '/Mem:/ {print $2, $3}')
if [ -n "$MEM_STATS" ]; then
    MEM_TOTAL=$(echo "$MEM_STATS" | awk '{print $1}')
    MEM_USED=$(echo "$MEM_STATS" | awk '{print $2}')
    MEM_USAGE=$(awk -v u="$MEM_USED" -v t="$MEM_TOTAL" 'BEGIN {printf "%.1f", (u/t)*100}')
else
    MEM_TOTAL=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    MEM_AVAIL=$(awk '/MemAvailable/ {print $2}' /proc/meminfo)
    MEM_USAGE=$(awk -v t="$MEM_TOTAL" -v a="$MEM_AVAIL" 'BEGIN {printf "%.1f", ((t-a)/t)*100}')
fi

# 判断超限
CPU_ALERT=$(awk -v u="$CPU_USAGE" -v t="$CPU_THRESHOLD" 'BEGIN { if (u > t) print 1; else print 0 }')
MEM_ALERT=$(awk -v u="$MEM_USAGE" -v t="$MEM_THRESHOLD" 'BEGIN { if (u > t) print 1; else print 0 }')

if [ "$CPU_ALERT" != "1" ] && [ "$MEM_ALERT" != "1" ]; then
    exit 0
fi

# 构造告警消息
CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")
HOSTNAME_VAL=$(hostname)
MSG="<b>[系统资源告警]</b>
主机：${HOSTNAME_VAL}
时间：${CURRENT_TIME}

"

if [ "$CPU_ALERT" = "1" ]; then
    MSG+="- <b>CPU 使用率异常</b>: ${CPU_USAGE}% (阈值：${CPU_THRESHOLD}%)
"
fi

if [ "$MEM_ALERT" = "1" ]; then
    MSG+="- <b>内存使用率异常</b>: ${MEM_USAGE}% (阈值：${MEM_THRESHOLD}%)
"
fi

send_telegram "$MSG" > /dev/null 2>&1
