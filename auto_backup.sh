#!/bin/sh

# 配置
LOCAL_DIR="/data"  # 本地指定目录
NUTSTORE_DIR="https://dav.jianguoyun.com/dav/backup/docker_data"  # 坚果云指定目录
NUTSTORE_USER="1036026846@qq.com"  # 坚果云用户名
NUTSTORE_PASS="azpfzhzdtbgzitw2"  # 坚果云密码
TEMP_DIR="/dev/shm"  # 使用内存中的临时目录

# 检查目录是否存在，不存在则创建
ensure_dir_exists() {
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
        echo "目录 $1 不存在，已创建。"
    fi
}

# 压缩目录到内存中的临时文件
compress_dir() {
    local src_dir="$1"
    local dest_file="$2"
    tar -czf "$dest_file" -C "$src_dir" .
    if [ $? -eq 0 ]; then
        echo "压缩成功: $dest_file"
    else
        echo "压缩失败，请检查目录内容或权限。"
        exit 1
    fi
}

# 上传文件
upload_file() {
    local file="$1"
    curl -u "$NUTSTORE_USER:$NUTSTORE_PASS" -T "$file" "$NUTSTORE_DIR/"
    if [ $? -eq 0 ]; then
        echo "上传成功: $NUTSTORE_DIR/$(basename "$file")"
    else
        echo "上传失败，请检查网络或坚果云配置。"
        exit 1
    fi
}

# 下载文件到内存中的临时文件
download_file() {
    local file="$1"
    local dest="$2"
    curl -u "$NUTSTORE_USER:$NUTSTORE_PASS" -o "$dest" "$NUTSTORE_DIR/$file"
    if [ $? -eq 0 ]; then
        echo "下载成功: $dest"
    else
        echo "下载失败，请检查网络或坚果云配置。"
        exit 1
    fi
}

# 解压内存中的临时文件
extract_file() {
    local file="$1"
    local dest_dir="$2"
    tar -xzf "$file" -C "$dest_dir"
    if [ $? -eq 0 ]; then
        echo "解压成功: $dest_dir"
    else
        echo "解压失败，请检查压缩包是否损坏。"
        exit 1
    fi
}

# 获取坚果云最新文件
get_latest_file() {
    local file_list
    file_list=$(curl -u "$NUTSTORE_USER:$NUTSTORE_PASS" -X PROPFIND "$NUTSTORE_DIR/" -s | grep -o '<d:href>[^<]*\.tar\.gz</d:href>' | sed 's/<d:href>//g; s/<\/d:href>//g')
    if [ -z "$file_list" ]; then
        echo "坚果云目录中没有找到压缩文件。"
        exit 1
    fi
    # 将日期格式统一为补零的格式（例如 2025-01-13）
    file_list=$(echo "$file_list" | sed 's/-\([0-9]\)-/-0\1-/g; s/-\([0-9]\)-/-0\1-/g')
    # 按日期排序并获取最新文件
    echo "$file_list" | sort -r | head -n 1
}

# 清理坚果云网盘，保留最近日期的七个文件
cleanup_nutstore() {
    # 获取文件列表并按日期排序
    FILE_LIST=$(curl -u "$NUTSTORE_USER:$NUTSTORE_PASS" -X PROPFIND "$NUTSTORE_DIR" -s | grep -o '<d:href>[^<]*\.tar\.gz</d:href>' | sed 's/<d:href>//g; s/<\/d:href>//g' | sort -r)

    # 保留最近日期的七个文件，删除其余文件
    COUNT=0
    for FILE in $FILE_LIST; do
        COUNT=$((COUNT + 1))
        if [ $COUNT -gt 7 ]; then
            FILE_NAME=$(basename "$FILE")
            curl -u "$NUTSTORE_USER:$NUTSTORE_PASS" -X DELETE "$NUTSTORE_DIR/$FILE_NAME" -s
            echo "清理: $FILE_NAME"
        fi
    done
}

# 主逻辑
ensure_dir_exists "$TEMP_DIR"

if [ -d "$LOCAL_DIR" ]; then
    # 本地目录存在，压缩并上传
    TIMESTAMP=$(date +"%Y-%m-%d")
    ARCHIVE_NAME="docker_$TIMESTAMP.tar.gz"
    ARCHIVE_PATH="$TEMP_DIR/$ARCHIVE_NAME"

    compress_dir "$LOCAL_DIR" "$ARCHIVE_PATH"
    upload_file "$ARCHIVE_PATH"
    rm "$ARCHIVE_PATH"
    echo "已删除内存中的压缩包: $ARCHIVE_PATH"

    # 备份完成后，执行清理操作
    cleanup_nutstore
else
    # 本地目录不存在，下载并解压最新文件
    ensure_dir_exists "$LOCAL_DIR"

    LATEST_FILE=$(get_latest_file)
    if [ -z "$LATEST_FILE" ]; then
        exit 1
    fi

    echo "最新文件: $LATEST_FILE"
    DOWNLOAD_PATH="$TEMP_DIR/$(basename "$LATEST_FILE")"

    download_file "$(basename "$LATEST_FILE")" "$DOWNLOAD_PATH"
    extract_file "$DOWNLOAD_PATH" "$LOCAL_DIR"
    rm "$DOWNLOAD_PATH"
    echo "已删除内存中的压缩包: $DOWNLOAD_PATH"
fi
