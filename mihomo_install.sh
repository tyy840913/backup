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

# 运行docker安装脚本
echo "正在运行mihomo-docker脚本..."
bash -c "$(curl -sSL https://route.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/mihomo-proxy/refs/heads/master/mihomo-docker/mihomo-docker.sh)"

# 添加定时任务
echo "正在添加定时任务..."

# 定义两个定时任务
CRON_JOB_1="0 8 * * * /usr/bin/bash /etc/mihomo/mihomo_config.sh && docker restart mihomo >/dev/null 2>&1"
CRON_JOB_2="0 9 * * * tar -czf - -C /etc mihomo | curl -u root:421121 -T - https://backup.woskee.dpdns.org/update/mihomo >/dev/null 2>&1"

# 获取当前crontab内容
CURRENT_CRONTAB=$(crontab -l 2>/dev/null)

# 检查并添加第一个定时任务
if ! echo "${CURRENT_CRONTAB}" | grep -Fq "$CRON_JOB_1"; then
  echo "添加每日更新任务..."
  (echo "${CURRENT_CRONTAB}"; echo "$CRON_JOB_1") | crontab -
else
  echo "每日更新任务已存在。"
fi

# 再次获取crontab内容，以防第一次是空的
CURRENT_CRONTAB=$(crontab -l 2>/dev/null)

# 检查并添加第二个定时任务
if ! echo "${CURRENT_CRONTAB}" | grep -Fq "$CRON_JOB_2"; then
  echo "添加每日备份任务..."
  (echo "${CURRENT_CRONTAB}"; echo "$CRON_JOB_2") | crontab -
else
  echo "每日备份任务已存在。"
fi

echo "定时任务检查和添加完毕。"
echo "所有脚本执行完毕。"
