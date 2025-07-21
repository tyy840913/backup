#!/bin/sh

# 检测当前 IPv4 默认网关，检查网络连通性。

GW=$(ip -4 route | awk '$1=="default"{print $3; exit}')

if [ -n "$GW" ] && ping -c 3 -i 1 "$GW" >/dev/null 2>&1; then
    echo "OK >> $GW"
else
    echo "Network DOWN - rebooting"
    reboot
fi
