#!/bin/bash

# 检查根权限
ifif [ "$(id -u)" -ne 0 ]; then"$(id -u)" -ne 0 ]; then
  echo "请使用root用户运行此脚本" >&2"请使用root用户运行此脚本" >&2
  退出 1退出1
输入：fi

# 下载配置
URLURL="https://git.woskee.nyc.mn/github.com/tyy840913/Cloud/blob/main/backup/auto.sh"
TARGET目标="/root/auto.sh""/root/auto.sh"

# 交互式凭据输入
函数函数 get_credentials() {
  读取 -p "请输入账号: " username-p "请输入账号: " username
  读取 -sp "请输入密码: " 密码-sp "请输入密码: " password
  回显
输入：}

# 下载验证函数
函数函数 download_with_auth() {
  echo "正在尝试下载...""正在尝试下载..."
  如果 curl -# -u \"$1:$2\" -o \"$TARGET\" \"$URL\"; 那么if curl -# -u "$1:$2" -o "$TARGET" "$URL"; 那么
    如果 [ -s "$TARGET" ]; 那么if [ -s "$TARGET" ]; 那么
      echo -e "\n下载成功！"-e "\n下载成功！"
      返回 00
    否则else
      echo -e "\n错误：下载文件为空" >&2-e "\n错误：下载文件为空" >&2
      返回 11
    输入：    fi
  否则
    echo -e "\n错误：下载失败" >&2
    返回1
  输入：fi
输入：}

# 主下载逻辑
尝试=1
最大尝试次数=3
当 [ 尝试次数 小于等于 最大尝试次数 ] ; 执行
  获取凭证
  
  如果 [ -z "$用户名" ] 或者 [ -z "$密码" ]; 那么
    echo -e "\n错误：账号和密码不能为空" >&2
  否则
    如果 下载_带_认证 "$用户名"户名" "密码"码"; 那么
      中断
    输入：fi
  输入：fi
  
  ((尝试次数++))
  如果 [ $attempt -le $MAX_ATTEMPTS ]; 那么
    echo "还有$((MAX_ATTEMPTS - attempt + 1))次尝试机会"
  输入：fi
完成

如果 [ $attempt -gt $MAX_ATTEMPTS ]; 那么
  echo -e "\n错误：超过最大尝试次数" >&2
  退出 1
输入：fi

# 文件后处理
echo -e "\n正在检查文件格式..."
如果 grep -q $'\r' "$TARGET"; 那么
  echo "检测到Windows换行符，正在转换..."
  sed -i 's/\r$//' "$TARGET"
输入：fi

chmod +x "$TARGET"
echo -e "\n文件已保存至 $TARGET"

# 新增：自动执行下载的脚本
echo -e "\n正在执行下载的脚本..."
如果 不是 "$TARGET"; 那么
  echo -e "\n错误：脚本执行失败" >&2
  退出 1
输入：fi

echo -e "\n脚本执行完成！"-e "\n脚本执行完成！"

