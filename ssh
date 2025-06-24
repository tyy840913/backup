#!/bin/bash

# SSH配置修改脚本
# 功能：允许root远程登录和密码认证
# 警告：此操作会降低系统安全性，请谨慎使用

# 检查是否为root用户
if [ "$(id -u)" != "0" ]; then
   echo "错误：此脚本必须以root用户身份运行" 1>&2
   exit 1
fi

# 修改SSH配置
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config

# 重启SSH服务
if systemctl is-active sshd >/dev/null 2>&1; then
    # 使用systemctl的系统
    systemctl restart sshd
    echo "已使用systemctl重启SSH服务"
elif service ssh status >/dev/null 2>&1; then
    # 使用service的系统
    service ssh restart
    echo "已使用service重启SSH服务"
else
    echo "警告：无法确定如何重启SSH服务，请手动重启"
fi

echo "配置已完成修改，SSH现在允许root登录和密码认证"
