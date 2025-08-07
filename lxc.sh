#!/bin/bash

# LXC高危配置脚本（PVE root环境专用）

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    echo -e "\033[31m错误：必须使用root用户执行此脚本\033[0m"
    exit 1
fi

# 输入验证
read -p "请输入LXC容器编号: " CT_ID
if ! [[ "$CT_ID" =~ ^[0-9]+$ ]]; then
    echo -e "\033[31m错误：容器编号必须是数字\033[0m"
    exit 1
fi

# 配置文件检查
CONF_FILE="/etc/pve/lxc/${CT_ID}.conf"
if [ ! -f "$CONF_FILE" ]; then
    echo -e "\033[31m错误：容器 ${CT_ID} 配置文件不存在\033[0m"
    exit 1
fi

# 特权模式自动启用
if ! grep -q "unprivileged: 0" "$CONF_FILE"; then
    echo -e "\033[33m[!] 自动启用特权模式..."
    sed -i '/^unprivileged:/d' "$CONF_FILE"
    echo "unprivileged: 0" >> "$CONF_FILE"
fi
sleep 0.5

# 高危操作提示
echo -e "\033[31m▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄"
echo "■                  ■"
echo "■ 正在执行高危操作 ■"
echo "■                  ■"
echo -e "▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀\033[0m"
echo -e "• 禁用AppArmor安全模块"
echo -e "• 允许所有设备访问权限"
echo -e "• 保留全部Linux权能"
sleep 0.5

# 清理历史高危配置
sed -i \
    -e '/lxc\.apparmor\.profile/d' \
    -e '/lxc\.cgroup\.devices\.allow/d' \
    -e '/lxc\.cap\.drop/d' \
    "$CONF_FILE"

# 写入新配置
echo "lxc.apparmor.profile: unconfined" >> "$CONF_FILE"
echo "lxc.cgroup.devices.allow: a" >> "$CONF_FILE"
echo "lxc.cap.drop:" >> "$CONF_FILE"

# 完成提示
echo -e "\033[32m配置已完成，请重启容器生效\033[0m"
