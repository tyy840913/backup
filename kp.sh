#!/bin/bash
# 定时设置：*/10 * * * * /bin/bash /root/kp.sh 每10分钟运行一次
# 如果你已安装了Serv00本地SSH脚本，不要再运行此脚本部署了，这样会造成进程爆满，必须二选一！
# serv00变量添加规则：
# 如使用保活网页，请不要启用cron，以防止cron与网页保活重复运行造成进程爆满
# RES(必填)：n表示每次不重置部署，y表示每次重置部署。REP(必填)：n表示不重置随机端口(三个端口留空)，y表示重置端口(三个端口留空)。SSH_USER(必填)表示serv00账号名。SSH_PASS(必填)表示serv00密码。REALITY表示reality域名(留空表示serv00官方域名：你serv00账号名.serv00.net)。SUUID表示uuid(留空表示随机uuid)。TCP1_PORT表示vless的tcp端口(留空表示随机tcp端口)。TCP2_PORT表示vmess的tcp端口(留空表示随机tcp端口)。UDP_PORT表示hy2的udp端口(留空表示随机udp端口)。HOST(必填)表示登录serv00服务器域名。ARGO_DOMAIN表示argo固定域名(留空表示临时域名)。ARGO_AUTH表示argo固定域名token(留空表示临时域名)。
# 必填变量：RES、REP、SSH_USER、SSH_PASS、HOST
# 注意[]"",:这些符号不要乱删，按规律对齐
# 每行一个{serv00服务器}，一个服务也可，末尾用,间隔，最后一个服务器末尾无需用,间隔
ACCOUNTS='[
{"RES":"n", "REP":"n", "SSH_USER":"woskee", "SSH_PASS":"JKiop84913", "REALITY":"woskee.serv00.net", "SUUID":"aeb8c9cd-5350-4e17-9023-6ac6b7b1e1d0", "TCP1_PORT":"31003", "TCP2_PORT":"31004", "UDP_PORT":"31005", "HOST":"cache9.serv00.com", "ARGO_DOMAIN":"s9.woskee.woskee.ggff.net", "ARGO_AUTH":"eyJhIjoiZGQ5NzY1ZGViZmEwNDBjNmRjZTllZjA5NDAwNjhhOWUiLCJ0IjoiZWNmZTUwNzYtOWJkMC00MTc3LTgzNzgtNTk4ZjU2MWE3YjY0IiwicyI6Ik16aGlOR0UxTVdRdE5HTm1OaTAwWlRVM0xXSTRORE10TXpjNE4yTTRabU13WTJSaSJ9"},
{"RES":"n", "REP":"n", "SSH_USER":"wosker", "SSH_PASS":"JKiop84913", "REALITY":"wosker.serv00.net", "SUUID":"aeb8c9cd-5350-4e17-9023-6ac6b7b1e1d0", "TCP1_PORT":"32003", "TCP2_PORT":"32004", "UDP_PORT":"32005", "HOST":"cache9.serv00.com", "ARGO_DOMAIN":"s9.wosker.woskee.ggff.net", "ARGO_AUTH":"eyJhIjoiZGQ5NzY1ZGViZmEwNDBjNmRjZTllZjA5NDAwNjhhOWUiLCJ0IjoiZjQ2NzQ0N2ItZjMzMS00Yjg1LWEwZTItZjE0OTM3MTQ3ODI4IiwicyI6Ik5XUTVOV00wT1RFdE5XRTBNUzAwWlRsaExUaGlNalF0Tldaa04yRmlOakJpT0dRMiJ9"},
{"RES":"n", "REP":"n", "SSH_USER":"woskeu", "SSH_PASS":"JKiop84913", "REALITY":"woskeu.serv00.net", "SUUID":"aeb8c9cd-5350-4e17-9023-6ac6b7b1e1d0", "TCP1_PORT":"31003", "TCP2_PORT":"31004", "UDP_PORT":"31005", "HOST":"cache13.serv00.com", "ARGO_DOMAIN":"s13.woskeu.woskee.ggff.net", "ARGO_AUTH":"eyJhIjoiZGQ5NzY1ZGViZmEwNDBjNmRjZTllZjA5NDAwNjhhOWUiLCJ0IjoiNmEyMzA1Y2YtOGRiYS00MGMzLThjNjEtYTk2M2NiYTE4NzMyIiwicyI6Ik5UazBOVGhrTVdVdE9UVTVPUzAwWTJObUxUazRNV1F0T0dVNU1XUXlZbUZqTVdabCJ9"},
{"RES":"n", "REP":"n", "SSH_USER":"woskev", "SSH_PASS":"JKiop84913", "REALITY":"woskev.serv00.net", "SUUID":"aeb8c9cd-5350-4e17-9023-6ac6b7b1e1d0", "TCP1_PORT":"31003", "TCP2_PORT":"31004", "UDP_PORT":"31005", "HOST":"cache10.serv00.com", "ARGO_DOMAIN":"s10.woskev.woskee.ggff.net", "ARGO_AUTH":"eyJhIjoiZGQ5NzY1ZGViZmEwNDBjNmRjZTllZjA5NDAwNjhhOWUiLCJ0IjoiYjYzYjJmN2UtNjc2Yy00OWFmLWFhYTktZTM5NzJjM2Y2ZTlmIiwicyI6IlkyTmtPVFUyTmpZdE9HTTFNQzAwT1RSaUxXRmlOREl0TWpabVlXWm1ObUl3WTJJdyJ9"},
{"RES":"n", "REP":"n", "SSH_USER":"woskep", "SSH_PASS":"JKiop84913", "REALITY":"woskep.serv00.net", "SUUID":"aeb8c9cd-5350-4e17-9023-6ac6b7b1e1d0", "TCP1_PORT":"31003", "TCP2_PORT":"31004", "UDP_PORT":"31005", "HOST":"cache11.serv00.com", "ARGO_DOMAIN":"s11.woskep.woskee.ggff.net", "ARGO_AUTH":"eyJhIjoiZGQ5NzY1ZGViZmEwNDBjNmRjZTllZjA5NDAwNjhhOWUiLCJ0IjoiZjY3NTJkNmQtYzg5Mi00OGNmLTgxNTctZDgwYjAyOTQwNDUwIiwicyI6Ill6SmxNekF3WTJRdFpUSmhZeTAwTnpjNUxXSmhNREF0TW1Nd05UTTNZak0zT1RFMiJ9"},
{"RES":"n", "REP":"n", "SSH_USER":"nki2t9df", "SSH_PASS":"JKiop84913", "REALITY":"nki2t9df.serv00.net", "SUUID":"aeb8c9cd-5350-4e17-9023-6ac6b7b1e1d0", "TCP1_PORT":"31003", "TCP2_PORT":"31004", "UDP_PORT":"31005", "HOST":"cache16.serv00.com", "ARGO_DOMAIN":"s16.nki2t9df.woskee.ggff.net", "ARGO_AUTH":"eyJhIjoiZGQ5NzY1ZGViZmEwNDBjNmRjZTllZjA5NDAwNjhhOWUiLCJ0IjoiYmFiZWQyMGEtOGMzZi00NTY1LWIwNzktNDIwMjAyNjc0MmI5IiwicyI6IlpqVXdZV1prTkRRdFptRTBaUzAwTVdVekxXRXpZbVl0WmpFMllqRmpPR0poTm1GbSJ9"},
{"RES":"n", "REP":"n", "SSH_USER":"wosleusrGraham", "SSH_PASS":"JKiop84913", "REALITY":"wosleusrgraham.serv00.net", "SUUID":"aeb8c9cd-5350-4e17-9023-6ac6b7b1e1d0", "TCP1_PORT":"32003", "TCP2_PORT":"32004", "UDP_PORT":"32005", "HOST":"cache15.serv00.com", "ARGO_DOMAIN":"s15.wosleusrgraham.woskee.ggff.net", "ARGO_AUTH":"eyJhIjoiZGQ5NzY1ZGViZmEwNDBjNmRjZTllZjA5NDAwNjhhOWUiLCJ0IjoiMDFkMzg1NDktYmI5Zi00YzkxLThlMTUtZTRmOGE2NmM2MTg0IiwicyI6Ik9HVTNNR1V4WkRjdE1qQm1ZaTAwTjJabUxUa3pZMk10TkdFeE5XRTVZakZqWTJabSJ9"}
]'
run_remote_command() {
local RES=$1
local REP=$2
local SSH_USER=$3
local SSH_PASS=$4
local REALITY=${5}
local SUUID=$6
local TCP1_PORT=$7
local TCP2_PORT=$8
local UDP_PORT=$9
local HOST=${10}
local ARGO_DOMAIN=${11}
local ARGO_AUTH=${12}
  if [ -z "${ARGO_DOMAIN}" ]; then
    echo "Argo域名为空，申请Argo临时域名"
  else
    echo "Argo已设置固定域名：${ARGO_DOMAIN}"
  fi
  remote_command="export reym=$REALITY UUID=$SUUID vless_port=$TCP1_PORT vmess_port=$TCP2_PORT hy2_port=$UDP_PORT reset=$RES resport=$REP ARGO_DOMAIN=${ARGO_DOMAIN} ARGO_AUTH=${ARGO_AUTH} && bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/serv00keep.sh)"
  echo "Executing remote command on $HOST as $SSH_USER with command: $remote_command"
  sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$SSH_USER@$HOST" "$remote_command"
}
if  cat /etc/issue /proc/version /etc/os-release 2>/dev/null | grep -q -E -i "openwrt"; then
opkg update
opkg install sshpass curl jq
else
    if [ -f /etc/debian_version ]; then
        package_manager="apt-get install -y"
        apt-get update >/dev/null 2>&1
    elif [ -f /etc/redhat-release ]; then
        package_manager="yum install -y"
    elif [ -f /etc/fedora-release ]; then
        package_manager="dnf install -y"
    elif [ -f /etc/alpine-release ]; then
        package_manager="apk add"
    fi
    $package_manager sshpass curl jq cron >/dev/null 2>&1 &
fi
echo "*****************************************************"
echo "*****************************************************"
echo "甬哥Github项目  ：github.com/yonggekkk"
echo "甬哥Blogger博客 ：ygkkk.blogspot.com"
echo "甬哥YouTube频道 ：www.youtube.com/@ygkkk"
echo "自动远程部署Serv00三合一协议脚本【VPS+软路由】"
echo "版本：V25.3.26"
echo "*****************************************************"
echo "*****************************************************"
              count=0  
           for account in $(echo "${ACCOUNTS}" | jq -c '.[]'); do
              count=$((count+1))
              RES=$(echo $account | jq -r '.RES')
              REP=$(echo $account | jq -r '.REP')              
              SSH_USER=$(echo $account | jq -r '.SSH_USER')
              SSH_PASS=$(echo $account | jq -r '.SSH_PASS')
              REALITY=$(echo $account | jq -r '.REALITY')
              SUUID=$(echo $account | jq -r '.SUUID')
              TCP1_PORT=$(echo $account | jq -r '.TCP1_PORT')
              TCP2_PORT=$(echo $account | jq -r '.TCP2_PORT')
              UDP_PORT=$(echo $account | jq -r '.UDP_PORT')
              HOST=$(echo $account | jq -r '.HOST')
              ARGO_DOMAIN=$(echo $account | jq -r '.ARGO_DOMAIN')
              ARGO_AUTH=$(echo $account | jq -r '.ARGO_AUTH') 
          if sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$SSH_USER@$HOST" -q exit; then
            echo "🎉恭喜！✅第【$count】台服务器连接成功！🚀服务器地址：$HOST ，账户名：$SSH_USER"   
          if [ -z "${ARGO_DOMAIN}" ]; then
           check_process="ps aux | grep '[c]onfig' > /dev/null && ps aux | grep [l]ocalhost:$TCP2_PORT > /dev/null"
            else
           check_process="ps aux | grep '[c]onfig' > /dev/null && ps aux | grep '[t]oken $ARGO_AUTH' > /dev/null"
           fi
          if ! sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$SSH_USER@$HOST" "$check_process" || [[ "$RES" =~ ^[Yy]$ ]]; then
            echo "⚠️检测到主进程或者argo进程未启动，或者执行重置"
             echo "⚠️现在开始修复或重置部署……请稍等"
             output=$(run_remote_command "$RES" "$REP" "$SSH_USER" "$SSH_PASS" "${REALITY}" "$SUUID" "$TCP1_PORT" "$TCP2_PORT" "$UDP_PORT" "$HOST" "${ARGO_DOMAIN}" "${ARGO_AUTH}")
            echo "远程命令执行结果：$output"
          else
            echo "🎉恭喜！✅检测到所有进程正常运行中 "
            SSH_USER_LOWER=$(echo "$SSH_USER" | tr '[:upper:]' '[:lower:]')
            sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no "$SSH_USER@$HOST" "
            echo \"配置显示如下：\"
            cat domains/${SSH_USER_LOWER}.serv00.net/logs/list.txt
            echo \"====================================================\""
            fi
           else
            echo "===================================================="
            echo "💥杯具！❌第【$count】台服务器连接失败！🚀服务器地址：$HOST ，账户名：$SSH_USER"
            echo "⚠️可能账号名、密码、服务器名称输入错误，或者当前服务器在维护中"  
            echo "===================================================="
           fi
            done
