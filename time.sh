#!/bin/bash

# 权限检查
echo "正在检查运行权限..."
if [ "$(id -u)" -ne 0 ]; then
    echo -e "\033[31m错误：必须使用 root 用户或 sudo 权限运行本脚本\033[0m" >&2
    exit 1
else
    echo -e "\033[32m✓ 权限检查通过\033[0m"
fi

# 系统检测字典 (包名:服务名)
declare -A PKG_MAP=(
    ["apt"]="openssh-server:ssh"
    ["yum"]="openssh-server:sshd"
    ["dnf"]="openssh-server:sshd"
    ["apk"]="openssh:sshd"
)

# 确定包管理器
pkgmgr=""
for cmd in apt yum dnf apk; do
    if command -v $cmd &>/dev/null; then
        pkgmgr=$cmd
        break
    fi
done
[ -z "$pkgmgr" ] && { echo -e "\033[31m错误：不支持的包管理器\033[0m"; exit 1; }

IFS=':' read -ra SSH_INFO <<< "${PKG_MAP[$pkgmgr]}"
pkg_name=${SSH_INFO[0]}
service_name=${SSH_INFO[1]}
echo -e "\033[36m[系统信息]\033[0m 包管理器: \033[33m$pkgmgr\033[0m | 软件包: \033[33m$pkg_name\033[0m | 服务名: \033[33m$service_name\033[0m"

# 安装状态检测函数
is_installed() {
    case $pkgmgr in
        apt) dpkg -s $pkg_name &>/dev/null ;;
        yum|dnf) rpm -q $pkg_name &>/dev/null ;;
        apk) apk info -e $pkg_name &>/dev/null ;;
    esac
}

# SSH 安装流程
if ! is_installed; then
    echo -e "\033[33m! 未检测到 $pkg_name 软件包\033[0m"
    read -p "是否安装并配置SSH服务？[Y/n] " confirm
    confirm=${confirm:-Y}
    
    if [[ $confirm =~ ^[Yy] ]]; then
        echo -e "\033[36m[操作] 正在安装 $pkg_name ...\033[0m"
        
        case $pkgmgr in
            apt) 
                export DEBIAN_FRONTEND=noninteractive
                apt update -y && apt install -y $pkg_name
                ;;
            yum|dnf) $pkgmgr install -y $pkg_name ;;
            apk) apk add $pkg_name --no-cache ;;
        esac
        
        if [ $? -ne 0 ] || ! is_installed; then
            echo -e "\033[31m错误：安装失败，请检查网络或软件源配置\033[0m" >&2
            exit 1
        fi
        echo -e "\033[32m✓ 成功安装 $pkg_name\033[0m"
    else
        echo -e "\033[33m用户取消安装，退出脚本\033[0m"
        exit 0
    fi
else
    echo -e "\033[32m✓ 已安装 $pkg_name\033[0m"
fi

# 服务自启配置
enable_service() {
    echo -n "配置服务自启: "
    case $pkgmgr in
        apk)
            if ! rc-update show default | grep -q $service_name; then
                rc-update add $service_name default && echo -e "\033[32m成功\033[0m" || echo -e "\033[31m失败\033[0m"
            else
                echo -e "\033[36m已配置\033[0m"
            fi
            ;;
        *)
            if systemctl is-enabled $service_name &>/dev/null; then
                echo -e "\033[36m已启用\033[0m"
            else
                systemctl enable $service_name --now 2>/dev/null && echo -e "\033[32m成功\033[0m" || echo -e "\033[31m失败\033[0m"
            fi
            ;;
    esac
}
enable_service

# SSH配置优化
configure_ssh_root_login() {
    echo -e "\033[36m[操作] 正在优化SSH配置...\033[0m"
    local sshd_config="/etc/ssh/sshd_config"
    cp "$sshd_config" "${sshd_config}.bak" 2>/dev/null || echo -e "\033[33m! 未能创建配置文件备份\033[0m"

    sed -i '/PermitRootLogin/d; /PasswordAuthentication/d' "$sshd_config"
    echo "PermitRootLogin yes" >> "$sshd_config"
    echo "PasswordAuthentication yes" >> "$sshd_config"

    case $pkgmgr in
        apt|yum|dnf) systemctl restart $service_name ;;
        apk) rc-service $service_name restart ;;
    esac
    echo -e "\033[32m✓ SSH配置已更新\033[0m"
}
configure_ssh_root_login

# 时区配置
set_timezone() {
    echo -e "\033[36m[操作] 正在校验时区配置...\033[0m"
    current_tz=$(date +%Z)
    [ "$current_tz" = "CST" ] && {
        echo -e "\033[36m当前时区已正确设置 (CST UTC+8)\033[0m"
        return
    }
    
    echo -e "\033[33m! 正在设置时区为 Asia/Shanghai\033[0m"
    timedatectl set-timezone Asia/Shanghai 2>/dev/null || \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    echo -e "\033[32m✓ 时区配置完成\033[0m"
}
set_timezone

echo -e "\n\033[32m所有配置已完成！\033[0m"
