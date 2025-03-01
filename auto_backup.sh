#!/bin/sh

# 全局配置参数 ================================================================
TOOLS="curl tar bash grep sed"  # 依赖工具列表
SCRIPT_URL="https://dav.woskee.nyc.mn:88/jianguoyun/backup"  # 脚本地址
SCRIPT_NAME="auto.sh"          # 保存名称

# 包管理器检测函数 ============================================================
detect_pkg_manager() {
  if command -v apk >/dev/null 2>&1; then
    PKG_MANAGER="apk"
    UPDATE_CMD="apk update --no-cache"
    INSTALL_CMD="apk add --no-cache"
  elif command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt-get"
    UPDATE_CMD="apt-get update -qq"
    INSTALL_CMD="apt-get install -y -qq"
  elif command -v yum >/dev/null 2>&1; then
    PKG_MANAGER="yum"
    UPDATE_CMD="yum check-update -q || true"
    INSTALL_CMD="yum install -y -q"
  else
    echo "不支持的包管理器!"
    exit 1
  fi
}

# 工具安装函数 ================================================================
install_tools() {
  detect_pkg_manager

  echo "更新软件仓库..."
  if ! eval "$UPDATE_CMD"; then
    echo "仓库更新失败!"
    exit 1
  fi

  for tool in $TOOLS; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "正在安装 $tool..."
      if ! eval "$INSTALL_CMD $tool" >/dev/null 2>&1; then
        echo "$tool 安装失败!"
        exit 1
      fi
    fi
  done
}

# 脚本下载函数 ================================================================
download_script() {
  echo "下载自动化脚本..."
  if ! curl --user "$USER:$PASS" -O "$SCRIPT_URL" >/dev/null 2>&1; then
    echo "脚本下载失败!"
    exit 1
  fi
  
  [ -f "$SCRIPT_NAME" ] || { echo "文件验证失败!"; exit 1; }
  chmod +x "$SCRIPT_NAME"
}

# 定时任务配置函数 ============================================================
add_cron_job() {
  local cron_job="30 2 * * * $(pwd)/$SCRIPT_NAME >/dev/null 2>&1"
  
  if ! command -v crontab >/dev/null 2>&1; then
    echo "安装cron服务..."
    case $PKG_MANAGER in
      "apk") eval "$INSTALL_CMD cronie" ;;
      *) eval "$INSTALL_CMD cron" ;;
    esac || { echo "Cron安装失败!"; exit 1; }

    if [ -f "/etc/alpine-release" ]; then
      rc-service crond start >/dev/null 2>&1
      rc-update add crond >/dev/null 2>&1
    else
      systemctl enable cron --now >/dev/null 2>&1
    fi
  fi

  if crontab -l 2>/dev/null | grep -Fq "$cron_job"; then
    echo "定时任务已存在，无需重复添加。"
  else
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    echo "已添加定时任务: $cron_job"
  fi
}

# 主执行流程 ==================================================================
main() {
  # 修改后的用户凭证获取
  while [ -z "$USER" ]; do
    read -p "请输入账号（邮箱）: " USER  # 添加邮箱提示
  done
  while [ -z "$PASS" ]; do
    read -s -p "请输入密码: " PASS      # 通用密码提示
    echo
  done

  for tool in $TOOLS; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "检测到缺少工具: $tool，开始安装..."
      install_tools
      break
    fi
  done

  download_script
  add_cron_job

  echo "正在执行自动化脚本..."
  ./"$SCRIPT_NAME" || { echo "脚本执行失败!"; exit 1; }
}

main
