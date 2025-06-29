#!/bin/bash

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
  echo "请使用root用户运行此脚本" >&2
  exit 1
fi

# 下载配置
# 更新下载地址，移除账号密码验证
URL="https://backup.woskee.dpdns.org/auto.sh"
TARGET="/root/auto.sh"

# 下载验证函数 (不再需要认证信息)
function download_without_auth() {
  echo "正在尝试下载..."
  # curl 命令的输出和错误重定向到 /dev/null
  if curl -L -# -o "$TARGET" "$URL" &> /dev/null; then
    if [ -s "$TARGET" ]; then
      # 检查文件是否为HTML（简单通过文件头判断），grep 的输出也重定向
      if grep -q "<html" "$TARGET" &> /dev/null; then
        echo -e "\n错误：下载到的是HTML页面，请检查URL" >&2
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

# 主下载逻辑 (不再需要循环尝试和凭据输入)
if download_without_auth; then
  echo "文件下载流程完成。"
else
  echo -e "\n错误：文件下载失败，请检查URL或网络连接。" >&2
  exit 1
fi

# 文件后处理
echo -e "\n正在检查文件格式..."
if grep -q $'\r' "$TARGET"; then
  echo "检测到Windows换行符，正在转换..."
  # sed 命令的输出重定向到 /dev/null
  sed -i 's/\r$//' "$TARGET" &> /dev/null
fi

chmod +x "$TARGET"
echo -e "\n文件已保存至 $TARGET"

### 执行下载的脚本

echo -e "\n正在执行下载的脚本..."
# 执行下载的脚本，其输出和错误也重定向到 /dev/null，只在失败时打印错误信息
if ! bash "$TARGET" &> /dev/null; then
  echo -e "\n错误：脚本执行失败" >&2
  exit 1
fi

echo -e "\n脚本执行完成！"

### 添加定时任务

echo -e "\n正在添加定时任务，使下载的脚本每天凌晨两点自动执行..."

# 检查crontab命令是否存在，command -v 的输出也重定向
if ! command -v crontab &> /dev/null
then
    echo "错误：未找到crontab命令。请手动安装或配置定时任务。" >&2
    exit 1
fi

# 定义cron表达式，每天凌晨2点执行
# 0 2 * * * 表示在每天的2点0分执行
# /usr/bin/bash 是为了确保使用完整的路径，根据你的系统可能需要调整
# CRON_JOB 包含重定向，确保定时任务运行时静默
CRON_JOB="0 2 * * * /usr/bin/bash $TARGET >/dev/null 2>&1" 
CRON_COMMENT="# 每天凌晨2点执行 auto.sh 下载脚本"

# 检查是否已存在相同的定时任务，避免重复添加
# crontab -l 的输出和错误也重定向
(crontab -l 2>/dev/null | grep -Fq "$CRON_JOB")
if [ $? -eq 0 ]; then
    echo "定时任务已存在，无需重复添加。"
else
    # 将新的cron任务添加到crontab
    # 使用 (crontab -l; echo ...) | crontab - 命令来添加
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
