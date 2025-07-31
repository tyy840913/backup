#!/bin/bash

# 交互式获取用户名和密码
read -p "请输入用户名: " username
read -s -p "请输入密码: " password
echo "" # 换行，因为 -s 不显示输入

echo "正在执行第一个命令：下载并解包文件..."
curl -u "$username":"$password" https://backup.woskee.dpdns.org/xiaoya | tar -xf - -C /etc

# 检查第一个命令的退出状态
if [ $? -eq 0 ]; then
    echo "目录已创建，xiaoya已解压到/etc目录。"

    # 定义定时任务，包含用户名和密码
    CRON_JOB="0 0 */3 * * tar -cf - -C /etc --exclude=xiaoya/data xiaoya | curl -u $username:$password -T - https://backup.woskee.dpdns.org/update/xiaoya >/dev/null 2>&1"
    CRON_JOB="30 2 * * * docker restart xiaoya >/dev/null 2>&1"
    
    # grep -qF "$CRON_JOB" 检查任务是否已经存在，避免重复添加
    if ! crontab -l 2>/dev/null | grep -qF "$CRON_JOB"; then
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
        echo "定时任务已添加：每3天备份xiaoya目录。"
    else
        echo "定时任务已存在，跳过添加。"
    fi

    # exec 会用这个命令替换当前的 shell 进程，所以脚本会立即"退出"
    exec bash -c "$(curl http://docker.xiaoya.pro/update_new.sh)"
    
    # 注意：exec 成功执行后，下面的代码将不会被执行，因为脚本进程已经被替换了。
else
    echo "第一个命令执行失败。请检查错误信息。"
    exit 1 # 如果第一个命令失败，脚本以非零状态退出
fi
