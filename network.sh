#!/bin/sh
DNS_IP_LIST="223.5.5.5 119.29.29.29 114.114.114.114 180.76.76.76"

check_network() {
    for ip in $DNS_IP_LIST; do
        if ping -c 1 -w 1 "$ip" >/dev/null 2>&1; then
            echo "Network OK >> $ip"
            return 0
        fi
    done
    return 1
}

if ! check_network; then
    echo "Network DOWN - rebooting"
    reboot
fi
