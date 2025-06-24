#!/bin/bash

# 目标压缩文件名
OUTPUT_FILE="debian12-rootfs.tar.gz"
# 根文件系统的挂载路径
ROOTFS_MOUNT_DIR="/mnt/rootfs"

# 检查目标文件是否已经存在，若存在则删除
if [ -f "$OUTPUT_FILE" ]; then
    echo "文件 $OUTPUT_FILE 已存在，正在删除..."
    rm -f "$OUTPUT_FILE"
fi

# 执行 tar 命令进行备份
echo "正在备份根文件系统到 $OUTPUT_FILE..."
tar --numeric-owner -czpf "$OUTPUT_FILE" -C "$ROOTFS_MOUNT_DIR" \
    --exclude=dev \
    --exclude=proc \
    --exclude=sys \
    --exclude=run \
    --exclude=tmp \
    --exclude=mnt \
    --exclude=media \
    --exclude=lost+found \
    --exclude=var/log \
    --exclude=var/tmp \
    --exclude=var/cache/apt/archives \
    --exclude=var/lib/apt/lists \
    .

# 检查备份结果
if [ $? -eq 0 ]; then
    echo "备份成功: $OUTPUT_FILE"
else
    echo "备份失败！"
fi
