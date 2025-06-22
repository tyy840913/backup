#!/bin/bash

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
  echo "请使用root用户运行此脚本" >&2
  exit 1
fi

# 下载配置
URL="https://dav.jianguoyun.com/dav/backup/auto.sh"
TARGET="/root/auto.sh"

# 交互式凭据输入
function get_credentials() {
  read -p "请输入账号: " username
  read -sp "请输入密码: " password
  echo
}

# 下载验证函数
function download_with_auth() {
  echo "正在尝试下载..."
  if curl -L -# -u "$1:$2" -o "$TARGET" "$URL"; then
    if [ -s "$TARGET" ]; then
      # 检查文件是否为HTML（简单通过文件头判断）
      if grep -q "<html" "$TARGET"; then
        echo -e "\n错误：下载到的是HTML页面，请检查URL或认证信息" >&2
        return 1
      else
        echo -e "\n下载成功！"
        return 0
      fi
    else
      echo -e "\n错误：下载文件为空" >&2
      return 1
    fi
  else
    echo -e "\n错误：下载失败" >&2
    return 1
  fi
}

# 主下载逻辑
attempt=1
MAX_ATTEMPTS=3
while [ $attempt -le $MAX_ATTEMPTS ]; do
  get_credentials
  
  if [ -z "$username" ] || [ -z "$password" ]; then
    echo -e "\n错误：账号和密码不能为空" >&2
  else
    if download_with_auth "$username" "$password"; then
      break
    fi
  fi
  
  ((attempt++))
  if [ $attempt -le $MAX_ATTEMPTS ]; then
    echo "还有$((MAX_ATTEMPTS - attempt + 1))次尝试机会"
  fi
done

if [ $attempt -gt $MAX_ATTEMPTS ]; then
  echo -e "\n错误：超过最大尝试次数" >&2
  exit 1
fi

# 文件后处理
echo -e "\n正在检查文件格式..."
if grep -q $'\r' "$TARGET"; then
  echo "检测到Windows换行符，正在转换..."
  sed -i 's/\r$//' "$TARGET"
fi

chmod +x "$TARGET"
echo -e "\n文件已保存至 $TARGET"

# 新增：自动执行下载的脚本
echo -e "\n正在执行下载的脚本..."
if ! bash "$TARGET"; then
  echo -e "\n错误：脚本执行失败" >&2
  exit 1
fi

echo -e "\n脚本执行完成！"
