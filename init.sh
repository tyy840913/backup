#!/bin/bash

# --- 权限检查 ---
if [[ $EUID -ne 0 ]]; then
   echo "错误：此脚本必须以 root 权限运行。"
   echo "请尝试使用: sudo bash $0"
   exit 1
fi

# --- 主循环 ---
while true; do
    # 清屏，显示菜单
    clear
    echo "================================================"
    echo "          Debian && Ubuntu服务器设置脚本          "
    echo "================================================"
    echo "请选择要执行的功能："
    echo
    echo "1. 设置时区为 Asia/Shanghai"
    echo "2. 更换 APT 源为清华大学镜像"
    echo "3. 开启 SSH 远程 root/密码登录 (有风险!)"
    echo
    echo "0. 退出脚本"
    echo "================================================"
    read -p "请输入选项 [1-4]: " choice

    case $choice in
        1)
            echo
            echo "--- 1. 设置时区 ---"
            echo
            
            # 策略1：优先使用现代系统的 timedatectl 命令
            echo "[策略1] 正在尝试使用推荐命令 'timedatectl'..."
            if command -v timedatectl &> /dev/null; then
                # 命令存在，执行它
                if timedatectl set-timezone Asia/Shanghai; then
                    echo "成功！时区已通过 timedatectl 设置。"
                else
                    echo "错误：timedatectl 命令执行失败！"
                fi
            else
                # 命令不存在，进入备用方案
                echo "'timedatectl' 命令不存在。启动备用方案..."
                echo
                echo "[策略2] 正在尝试使用传统的符号链接方法..."
                
                # 检查时区文件是否存在
                if [ -f /usr/share/zoneinfo/Asia/Shanghai ]; then
                    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
                    if [ $? -eq 0 ]; then
                        echo "成功！时区已通过符号链接设置。"
                        echo "注意：在某些老系统上，可能需要重启服务(如cron)或系统才能完全生效。"
                    else
                        echo "错误：创建符号链接失败！"
                    fi
                else
                    echo "错误：备用方案也失败了，因为时区文件 /usr/share/zoneinfo/Asia/Shanghai 不存在。"
                fi
            fi

            echo "------------------------------------------------"
            echo "检查最终结果：当前系统时间为 $(date)"
            echo
            read -p "按 Enter 键返回主菜单..."
            ;;

        2)
            echo
            echo "--- 2. 更换 APT 源 ---"
            read -p "按 Enter 键开始..."

            echo "[步骤 1/4] 正在获取系统代号..."
            CODENAME=$(lsb_release -cs)
            
            # 检查是否成功获取代号
            if [ -z "$CODENAME" ]; then
                echo "错误：无法获取系统代号。请先确保 'lsb-release' 包已安装 (sudo apt install lsb-release)。"
            else
                echo "系统代号: $CODENAME"
                
                BACKUP_FILE="/etc/apt/sources.list.bak.$(date +%s)"
                echo "[步骤 2/4] 正在备份原始文件到 $BACKUP_FILE ..."
                cp /etc/apt/sources.list "$BACKUP_FILE"
                
                echo "[步骤 3/4] 正在写入新的清华大学镜像源..."
                # 根据系统ID选择不同的镜像源地址
                if grep -q "ubuntu" /etc/os-release; then
                    MIRROR_URL="https://mirrors.tuna.tsinghua.edu.cn/ubuntu/"
                else
                    MIRROR_URL="https://mirrors.tuna.tsinghua.edu.cn/debian/"
                fi
                
                cat << EOF > /etc/apt/sources.list
deb ${MIRROR_URL} ${CODENAME} main restricted universe multiverse
# deb-src ${MIRROR_URL} ${CODENAME} main restricted universe multiverse
deb ${MIRROR_URL} ${CODENAME}-updates main restricted universe multiverse
# deb-src ${MIRROR_URL} ${CODENAME}-updates main restricted universe multiverse
deb ${MIRROR_URL} ${CODENAME}-backports main restricted universe multiverse
# deb-src ${MIRROR_URL} ${CODENAME}-backports main restricted universe multiverse
deb ${MIRROR_URL} ${CODENAME}-security main restricted universe multiverse
# deb-src ${MIRROR_URL} ${CODENAME}-security main restricted universe multiverse
EOF

                echo "[步骤 4/4] 正在执行 'apt-get update'..."
                # 检查 apt-get update 是否成功
                if apt-get update; then
                    echo "成功！APT 源已更新。"
                else
                    echo "错误：'apt-get update' 执行失败！"
                    echo "正在从备份 $BACKUP_FILE 自动恢复原始配置..."
                    mv "$BACKUP_FILE" /etc/apt/sources.list
                    echo "已恢复原始 sources.list 文件。请手动检查网络或源地址问题。"
                fi
            fi
            
            echo "------------------------------------------------"
            echo "所有步骤执行完毕！"
            echo
            read -p "按 Enter 键返回主菜单..."
            ;;

        3)
            echo
            echo "--- 3. 开启 SSH 远程 root/密码登录 ---"
            echo "!!!!!! 安全警告 !!!!!!"
            echo "此操作会极大增加服务器被攻击的风险，请仅在受信任的环境中使用。"
            echo "!!!!!!!!!!!!!!!!!!!!"
            read -p "您是否理解风险并确认要继续？(y/n): " confirm_ssh
            
            if [[ "$confirm_ssh" =~ ^[Yy]$ ]]; then
                echo "正在修改 SSH 配置文件..."
                sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
                sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
                
                echo "正在重启 SSH 服务..."
                # 检查重启是否成功
                if systemctl restart ssh; then
                    echo "成功！SSH 服务已重启。"
                    # 最终确认服务是否在运行
                    if systemctl is-active --quiet ssh; then
                        echo "检查通过：SSH 服务当前正在运行。"
                    else
                        echo "警告：SSH 服务重启后并未处于活动状态！请立即检查！"
                    fi
                else
                    echo "!!!!!! 严重错误：SSH服务重启失败! !!!!!! "
                    echo "为防止您被锁定，请不要关闭当前的终端连接！"
                    echo "请立即手动执行 'systemctl status ssh' 和 'journalctl -xeu ssh' 来排查问题。"
                fi
            else
                echo "操作已取消。"
            fi
            
            echo "------------------------------------------------"
            echo
            read -p "按 Enter 键返回主菜单..."
            ;;

        0)
            echo "正在退出脚本..."
            exit 0
            ;;

        *)
            echo "无效选项，请输入 1-4 之间的数字。"
            read -p "按 Enter 键重试..."
            ;;
    esac
done
