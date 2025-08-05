#!/bin/bash

# --- 系统检测 ---
if ! grep -qiE 'debian|ubuntu' /etc/os-release; then
    echo "错误：不支持的系统。"
    echo "本脚本仅支持 Debian 和 Ubuntu 系统。"
    exit 1
fi

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
    read -p "请输入选项 [0-3]: " choice

    case $choice in
        1)
            echo
            echo "--- 1. 设置时区 ---"
            
            # (优化) 执行前检查：检查当前时区是否已经是目标时区
            is_already_set=false
            if command -v timedatectl &> /dev/null; then
                if timedatectl | grep -q "Asia/Shanghai"; then
                    is_already_set=true
                fi
            elif [[ "$(readlink /etc/localtime)" == *"/Asia/Shanghai" ]]; then
                is_already_set=true
            fi

            if [ "$is_already_set" = true ]; then
                echo "检测到当前时区已经是 Asia/Shanghai，无需修改。"
            else
                echo "当前时区不是 Asia/Shanghai，开始设置..."
                # 策略1：优先使用现代系统的 timedatectl 命令
                echo "[策略1] 正在尝试使用推荐命令 'timedatectl'..."
                if command -v timedatectl &> /dev/null; then
                    if timedatectl set-timezone Asia/Shanghai; then
                        echo "成功！时区已通过 timedatectl 设置。"
                    else
                        echo "错误：timedatectl 命令执行失败！"
                    fi
                else
                    echo "'timedatectl' 命令不存在。启动备用方案..."
                    echo "[策略2] 正在尝试使用传统的符号链接方法..."
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
            fi

            echo "------------------------------------------------"
            echo "检查最终结果：当前系统时间为 $(date)"
            echo
            read -p "按 Enter 键返回主菜单..."
            ;;

        2)
            echo
            echo "--- 2. 更换 APT 源 ---"
            
            if grep -q "tuna.tsinghua.edu.cn" /etc/apt/sources.list; then
                read -p "检测到源文件已包含清华镜像地址，是否仍要强制覆盖？(y/n): " confirm_overwrite
                if [[ ! "$confirm_overwrite" =~ ^[Yy]$ ]]; then
                    echo "操作已取消。"
                    read -p "按 Enter 键返回主菜单..."
                    continue
                fi
            fi

            echo "[步骤 1/4] 正在获取系统代号..."
            if ! command -v lsb_release &> /dev/null; then
                echo "正在安装 'lsb-release' 以获取系统信息..."
                apt-get update && apt-get install -y lsb-release
            fi

            CODENAME=$(lsb_release -cs)
            if [ -z "$CODENAME" ]; then
                echo "错误：无法获取系统代号。请手动检查并修复 'lsb-release' 工具。"
            else
                echo "系统代号: $CODENAME"
                
                BACKUP_FILE="/etc/apt/sources.list.bak.$(date +%s)"
                echo "[步骤 2/4] 正在备份原始文件到 $BACKUP_FILE ..."
                cp /etc/apt/sources.list "$BACKUP_FILE"
                
                echo "[步骤 3/4] 正在根据系统类型写入新的清华大学镜像源..."
                if grep -q "Ubuntu" /etc/os-release; then
                    echo "检测到系统为 Ubuntu。"
                    MIRROR_URL="https://mirrors.tuna.tsinghua.edu.cn/ubuntu/"
                    cat << EOF > /etc/apt/sources.list
deb ${MIRROR_URL} ${CODENAME} main restricted universe multiverse
deb ${MIRROR_URL} ${CODENAME}-updates main restricted universe multiverse
deb ${MIRROR_URL} ${CODENAME}-backports main restricted universe multiverse
deb ${MIRROR_URL} ${CODENAME}-security main restricted universe multiverse
EOF
                else
                    echo "检测到系统为 Debian。"
                    MIRROR_URL="https://mirrors.tuna.tsinghua.edu.cn/debian/"
                    # (重要修正) Debian 的安全源有独立地址，且组件不同
                    cat << EOF > /etc/apt/sources.list
deb ${MIRROR_URL} ${CODENAME} main contrib non-free
deb ${MIRROR_URL} ${CODENAME}-updates main contrib non-free
deb ${MIRROR_URL} ${CODENAME}-backports main
deb https://security.debian.org/debian-security ${CODENAME}-security main contrib non-free
EOF
                fi

                echo "[步骤 4/4] 正在执行 'apt-get update'..."
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
            
            # (优化) 检查是否已配置
            if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config && grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config; then
                echo "检测到 SSH 已配置为允许 root 和密码登录，无需修改。"
                if systemctl is-active --quiet ssh; then
                    echo "服务状态：SSH 服务当前正在运行。"
                else
                    echo "警告：SSH 服务当前未运行！请使用 'systemctl start ssh' 启动它。"
                fi
            else
                echo "!!!!!! 安全警告 !!!!!!"
                echo "此操作会极大增加服务器被攻击的风险，请仅在受信任的环境中使用。"
                echo "!!!!!!!!!!!!!!!!!!!!"
                read -p "您是否理解风险并确认要继续？(y/n): " confirm_ssh
                
                if [[ "$confirm_ssh" =~ ^[Yy]$ ]]; then
                    echo "正在修改 SSH 配置文件..."
                    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
                    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
                    
                    echo "正在重启 SSH 服务..."
                    if systemctl restart ssh; then
                        echo "成功！SSH 服务已重启。"
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
            echo "无效选项，请输入 0-3 之间的数字。"
            read -p "按 Enter 键重试..."
            ;;
    esac
done
