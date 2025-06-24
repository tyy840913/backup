#!/bin/bash
# 清理 Debian rootfs 的无用缓存、日志等内容，准备打包

# 清理 apt 缓存
echo "清理 apt 缓存..."
rm -rf /mnt/rootfs/var/cache/apt/archives/*
rm -rf /mnt/rootfs/var/lib/apt/lists/*

# 清理日志文件
echo "清理日志文件..."
rm -rf /mnt/rootfs/var/log/*

# 清理临时文件
echo "清理临时文件..."
rm -rf /mnt/rootfs/var/tmp/*
rm -rf /mnt/rootfs/tmp/*

# 清理系统存储的丢失文件
echo "清理丢失文件目录..."
rm -rf /mnt/rootfs/lost+found/*

# 清理不必要的网络文件
echo "清理网络文件..."
rm -rf /mnt/rootfs/etc/udev/rules.d/70-persistent-net.rules
rm -rf /mnt/rootfs/etc/network/interfaces.d/*

# 清理内存交换文件（如果有）
echo "清理交换文件..."
rm -f /mnt/rootfs/swapfile
