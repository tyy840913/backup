#!/bin/bash

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
  echo "请使用root用户运行此脚本" >&2
  exit 1
fi

# 下载配置
URL="https://backup.woskee.dpdns.org/auto.sh"
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
  # curl 命令的输出和错误重定向到 /dev/null
  if curl -L -# -u "$1:$2" -o "$TARGET" "$URL" &> /dev/null; then
    if [ -s "$TARGET" ]; then
      # 检查文件是否为HTML（简单通过文件头判断），grep 的输出也重定向
      if grep -q "<html" "$TARGET" &> /dev/null; then
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
  sed -i 's/\r$//' "$TARGET" &> /dev/null
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

# 添加定时任务
echo -e "\n正在添加定时任务，使下载的脚本每天凌晨两点自动执行..."

if ! command -v crontab &> /dev/null
then
    echo "错误：未找到crontab命令。请手动安装或配置定时任务。" >&2
    exit 1
fi

CRON_JOB="0 0 * * * /bin/bash $TARGET >/dev/null 2>&1" 
CRON_COMMENT="# 每天凌晨0点执行 auto.sh 下载脚本"

(crontab -l 2>/dev/null | grep -Fq "$CRON_JOB")
if [ $? -eq 0 ]; then
    echo "定时任务已存在，无需重复添加。"
else
    (crontab -l 2>/dev/null; echo "$CRON_JOB $CRON_COMMENT") | crontab -
    if [ $? -eq 0 ]; then
        echo "定时任务添加成功！'$CRON_JOB' 已添加到 crontab。"
        echo "你可以通过运行 'crontab -l' 查看已添加的任务。"
    else
        echo "错误：定时任务添加失败。" >&2
        exit 1
    fi
fi

echo -e "\n所有操作完成！"
