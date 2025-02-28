#!/bin/sh
# 主脚本 - 域名IP监控主程序

# 依赖检查与安装函数
check_dependencies() {
    # 识别系统类型
    if grep -qi 'alpine' /etc/os-release 2>/dev/null; then
        PKG_MGR='apk add'
        DIG_PKG='bind-tools'
    elif grep -qi 'ubuntu\|debian' /etc/os-release 2>/dev/null; then
        PKG_MGR='apt-get install -y'
        DIG_PKG='dnsutils'
    elif grep -qi 'centos\|redhat' /etc/os-release 2>/dev/null; then
        PKG_MGR='yum install -y'
        DIG_PKG='bind-utils'
    else
        echo "不支持的发行版"
        exit 1
    fi

    # 检查dig命令是否存在
    if ! command -v dig >/dev/null 2>&1; then
        echo "缺少依赖：$DIG_PKG"
        printf "是否自动安装？[Y/n] "
        read -r answer
        case $answer in
            [Nn]*) exit 1 ;;
            *) $PKG_MGR $DIG_PKG || exit 1 ;;
        esac
    fi
}

# 缓存文件检查
check_cache() {
    CACHE_FILE="/dev/shm/domain_ip_cache"
    if [ ! -f "$CACHE_FILE" ]; then
        echo "缓存文件不存在，已创建缓存文件"
        touch "$CACHE_FILE"
    else
        echo "缓存文件已存在"
    fi
}

# 监控子脚本设置
setup_monitor() {
    SCRIPT_NAME="ip.sh"
    CRON_JOB="0 * * * * $(pwd)/$SCRIPT_NAME"

    # 创建子脚本
    if [ ! -f "$SCRIPT_NAME" ]; then
        cat > "$SCRIPT_NAME" <<'EOF'
#!/bin/sh
# 子脚本 - IP监控核心逻辑

# DNS服务器列表（3个国外+2个国内）
DNS_SERVERS="8.8.8.8 1.1.1.1 208.67.222.222 114.114.114.114 223.5.5.5"

# 域名列表（按用户提供的分组顺序）
DOMAINS="
woskee.dynv6.net
luxxk.dynv6.net
woskee.dns.navy
woskee.dns.army
kexin.dns.army
woskee.us.kg
wosken.us.kg
luxxk.us.kg
woskee.freemyip.com
wosleusr.freemyip.com
kexin.freemyip.com
bin.ydns.eu
kexin.ydns.eu
woskee.ydns.eu
woskee.cloudns.be
woskee.cloudns.ch
wosken.cloudns.be
wosken.cloudns.ch
woskee.ddns-ip.net
woskee.work.gd
woskee.line.pm
woskee.linkpc.net
woskee.xyz
a.woskee.nyc.mn
"

# 核心检查函数
check_domain() {
    domain=$1
    for dns in $DNS_SERVERS; do
        ipv4=$(dig @$dns $domain A +short 2>/dev/null | head -n1)
        ipv6=$(dig @$dns $domain AAAA +short 2>/dev/null | head -n1)
        [ -n "$ipv4" ] && break
    done
    echo "$domain $ipv4 $ipv6"
}

# 主检查流程
main_check() {
    CACHE_FILE="/dev/shm/domain_ip_cache"
    UPDATES=""
    ERRORS=""

    while read -r domain old_ipv4 old_ipv6; do
        # 获取最新记录
        read -r _ new_ipv4 new_ipv6 <<< $(check_domain $domain)
        
        # IPv4异常检测
        if [ -z "$new_ipv4" ]; then
            ERRORS="$ERRORS$domain%0A"
            continue
        fi

        # 更新检测
        if [ "$old_ipv4" != "$new_ipv4" ] || [ "$old_ipv6" != "$new_ipv6" ]; then
            UPDATES="${UPDATES}%0A${domain}%0AIPV4：${new_ipv4}%0AIPV6：${new_ipv6}%0A"
        fi

        # 更新缓存
        sed -i "/^$domain /c\\$domain $new_ipv4 $new_ipv6" "$CACHE_FILE" 2>/dev/null
    done < "$CACHE_FILE"

    # 发送通知
    if [ -n "$UPDATES" ]; then
        send_notice "您的域名IP记录已更新：$UPDATES"
    fi
    if [ -n "$ERRORS" ]; then
        send_notice "域名监控报告，以下域名更新异常%0A$ERRORS"
    fi
}

# 通知发送函数
send_notice() {
    msg=$1
    curl -sS "https://api.telegram.org/bot7030145953:AAEhS_8fCnnn5SmQ2zjOIKS1eH5iSLNx2_E/sendMessage?chat_id=6302326077&text=$msg"
}

# 初始化缓存文件
init_cache() {
    CACHE_FILE="/dev/shm/domain_ip_cache"
    [ -f "$CACHE_FILE" ] || touch "$CACHE_FILE"
    
    for domain in $DOMAINS; do
        if ! grep -q "^$domain " "$CACHE_FILE"; then
            check_domain $domain >> "$CACHE_FILE"
        fi
    done
}

# 主执行流程
init_cache
main_check

echo "域名检查已运行，相关通知可能会延迟送达，注意接收"
EOF

        chmod +x "$SCRIPT_NAME"
        echo "监控子脚本已创建"
    fi

    # 配置定时任务
    if ! crontab -l | grep -q "$SCRIPT_NAME"; then
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
        echo "定时任务已配置"
    else
        echo "定时任务已存在"
    fi
}

# 主执行流程
check_dependencies
check_cache
setup_monitor

# 首次执行子脚本
echo "正在执行首次检查..."
./ip.sh
