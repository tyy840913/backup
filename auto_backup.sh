#!/bin/sh

# 全局配置参数 ================================================================
# 定义依赖的工具列表，用于后续安装检查
TOOLS="curl tar bash grep sed"
# 要下载的自动化脚本地址和保存名称
SCRIPT_URL="https://dav.woskee.nyc.mn:88/jianguoyun/backup/auto.sh"
SCRIPT_NAME="auto.sh"

# 包管理器检测函数 ============================================================
detect_pkg_manager() {
  # 检测系统使用的包管理器
  if command -v apk >/dev/null 2>&1; then       # Alpine Linux
    PKG_MANAGER="apk"
    UPDATE_CMD="apk update --no-cache"          # 无缓存更新命令
    INSTALL_CMD="apk add --no-cache"            # 无缓存安装命令
  elif command -v apt-get >/dev/null 2>&1; then # Debian/Ubuntu
    PKG_MANAGER="apt-get"
    UPDATE_CMD="apt-get update -qq"             # 静默模式更新
    INSTALL_CMD="apt-get install -y -qq"        # 自动确认+静默安装
  elif command -v yum >/dev/null 2>&1; then     # CentOS/RHEL
    PKG_MANAGER="yum"
    UPDATE_CMD="yum check-update -q || true"    # 忽略错误码
    INSTALL_CMD="yum install -y -q"             # 自动确认+静默安装
  else
    echo "不支持的包管理器!"
    exit 1
  fi
}

# 工具安装函数 ================================================================
install_tools() {
  detect_pkg_manager  # 首先检测包管理器

  echo "更新软件仓库..."
  # 执行仓库更新命令，失败则退出
  if ! eval "$UPDATE_CMD"; then
    echo "仓库更新失败!"
    exit 1
  fi

  # 遍历所有需要的工具
  for tool in $TOOLS; do
    # 检查工具是否已安装
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "正在安装 $tool..."
      # 使用静默模式安装，失败则退出
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
  # 使用curl通过WebDAV下载脚本，使用基础认证
  if ! curl -sL --user "$JIANGUO_USER:$JIANGUO_PASS" -O "$SCRIPT_URL" >/dev/null 2>&1; then
    echo "脚本下载失败!"
    exit 1
  fi
  
  # 验证文件是否下载成功
  [ -f "$SCRIPT_NAME" ] || { echo "文件验证失败!"; exit 1; }
  # 添加可执行权限
  chmod +x "$SCRIPT_NAME"
}

# 定时任务配置函数 ============================================================
add_cron_job() {
  # 定义定时任务（每天凌晨2:30执行）
  local cron_job="30 2 * * * $(pwd)/$SCRIPT_NAME >/dev/null 2>&1"
  
  # 如果cron不存在则安装
  if ! command -v crontab >/dev/null 2>&1; then
    echo "安装cron服务..."
    case $PKG_MANAGER in
      "apk") eval "$INSTALL_CMD cronie" ;;  # Alpine特殊包名
      *) eval "$INSTALL_CMD cron" ;;        # 其他系统
    esac || { echo "Cron安装失败!"; exit 1; }

    # 启动cron服务并设置开机自启
    if [ -f "/etc/alpine-release" ]; then   # Alpine系统
      rc-service crond start >/dev/null 2>&1
      rc-update add crond >/dev/null 2>&1
    else                                    # 其他系统
      systemctl enable cron --now >/dev/null 2>&1
    fi
  fi

  # 检查是否已存在相同的定时任务
  if crontab -l 2>/dev/null | grep -Fq "$cron_job"; then
    echo "定时任务已存在，无需重复添加。"
  else
    # 添加新定时任务（保留原有任务）
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    echo "已添加定时任务: $cron_job"
  fi
}

# 主执行流程 ==================================================================
main() {
  # 交互式输入账号密码
  printf "请输入账号："
  read -r JIANGUO_USER
  printf "请输入密码："
  read -rs JIANGUO_PASS
  echo  # 处理密码输入后的换行
  
  # 验证输入非空
  if [ -z "$JIANGUO_USER" ] || [ -z "$JIANGUO_PASS" ]; then
    echo "错误：账号和密码不能为空！"
    exit 1
  fi

  # 检测并安装缺失工具
  for tool in $TOOLS; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "检测到缺少工具: $tool，开始安装..."
      install_tools
      break
    fi
  done

  # 下载自动化脚本
  download_script

  # 配置定时任务
  add_cron_job

  # 首次执行自动化脚本
  echo "正在执行自动化脚本..."
  ./"$SCRIPT_NAME" || { echo "脚本执行失败!"; exit 1; }
}

# 执行主函数
main
