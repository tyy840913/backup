#!/bin/bash

# 脚本将从 https://backup.woskee.dpdns.org/mihomo 下载文件，
# 然后解压到 /etc/mihomo，最后运行 /etc/mihomo/mihomo_config.sh。

URL="https://backup.woskee.dpdns.org/mihomo"
DEST_DIR="/etc/mihomo"

# 交互式输入用户名和密码
read -p "请输入用户名: " USERNAME
read -sp "请输入密码: " PASSWORD
echo

# 创建目标目录
mkdir -p "${DEST_DIR}"

# 使用curl下载并通过管道直接解压
echo "正在下载并解压文件..."
curl -u "${USERNAME}:${PASSWORD}" -L "${URL}" | tar -xzf - -C "${DEST_DIR}"

# 检查上一个命令是否成功
if [ ${PIPESTATUS[0]} -ne 0 ]; then
  echo "下载失败，请检查您的用户名和密码。"
  exit 1
fi

if [ ${PIPESTATUS[1]} -ne 0 ]; then
  echo "解压失败。"
  exit 1
fi

# 运行配置脚本
echo "正在运行配置脚本..."
bash "${DEST_DIR}/mihomo_config.sh"

# 运行mihomo-docker.sh安装脚本
echo "正在运行mihomo-docker脚本..."
bash -c "$(curl -sSL https://route.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/mihomo-proxy/refs/heads/master/mihomo-docker/mihomo-docker.sh)"

echo "所有脚本执行完毕。"
