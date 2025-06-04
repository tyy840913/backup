#!/bin/bash

# 配置坚果云WebDAV参数
NUTSTORE_URL="https://dav.jianguoyun.com/dav/backup/auto.sh"
NUTSTORE_USER="1036026846@qq.com"
NUTSTORE_PASS="azpfzhzdtbgzitw2"
LOCAL_SCRIPT_PATH="/root/auto.sh"

# 使用curl下载脚本（带认证）
download_script() {
    echo "正在从坚果云下载auto.sh..."
    curl -u "$NUTSTORE_USER:$NUTSTORE_PASS" -o "$LOCAL_SCRIPT_PATH" "$NUTSTORE_URL"
    
    if [ $? -eq 0 ]; then
        echo "下载成功，保存到: $LOCAL_SCRIPT_PATH"
        return 0
    else
        echo "下载失败，请检查："
        echo "1. 网络连接"
        echo "2. WebDAV地址是否正确"
        echo "3. 用户名密码是否正确"
        exit 1
    fi
}

# 验证并执行脚本
execute_script() {
    if [ -f "$LOCAL_SCRIPT_PATH" ]; then
        echo "验证脚本权限..."
        chmod +x "$LOCAL_SCRIPT_PATH"
        
        echo "执行下载的脚本..."
        bash "$LOCAL_SCRIPT_PATH"
        
        # 可选：执行后删除脚本
        # rm -f "$LOCAL_SCRIPT_PATH"
    else
        echo "错误：脚本文件不存在"
        exit 1
    fi
}

# 主流程
download_script
execute_script
