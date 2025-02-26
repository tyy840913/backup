#!/bin/bash

# 带延时的输出函数
log() {
    echo -e "$@"
    sleep 0.5
}

logn() {
    echo -en "$@"
    sleep 0.5
}

# 权限检查
log "正在检查运行权限..."
if [ "$(id -u)" -ne 0 ]; then
    log "\033[31m错误：必须使用 root 用户或 sudo 权限运行本脚本\033[0m" >&2
    exit 1
else
    log "\033[32m✓ 权限检查通过\033[0m"
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
[ -z "$pkgmgr" ] && { log "\033[31m错误：不支持的包管理器\033[0m"; exit 1; }

IFS=':' read -ra SSH_INFO <<< "${PKG_MAP[$pkgmgr]}"
pkg_name=${SSH_INFO[0]}
service_name=${SSH_INFO[1]}
log "\033[36m[系统信息]\033[0m 包管理器: \033[33m$pkgmgr\033[0m | 软件包: \033[33m$pkg_name\033[0m | 服务名: \033[33m$service_name\033[0m"

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
    log "\033[33m! 未检测到 $pkg_name 软件包\033[0m"
    read -p "是否安装并配置SSH服务？[Y/n] " confirm
    confirm=${confirm:-Y}
    
    if [[ $confirm =~ ^[Yy] ]]; then
        log "\033[36m[操作] 正在安装 $pkg_name ...\033[0m"
        
        case $pkgmgr in
            apt) 
                export DEBIAN_FRONTEND=noninteractive
                apt update -y && apt install -y $pkg_name
                ;;
            yum|dnf) $pkgmgr install -y $pkg_name ;;
            apk) apk add $pkg_name --no-cache ;;
        esac
        
        if [ $? -ne 0 ] || ! is_installed; then
            log "\033[31m错误：安装失败，请检查网络或软件源配置\033[0m" >&2
            exit 1
        fi
        log "\033[32m✓ 成功安装 $pkg_name\033[0m"
    else
        log "\033[33m用户取消安装，退出脚本\033[0m"
        exit 0
    fi
else
    log "\033[32m✓ 已安装 $pkg_name\033[0m"
fi

# 服务自启配置
enable_service() {
    logn "配置服务自启: "
    case $pkgmgr in
        apk)
            if ! rc-update show default | grep -q $service_name; then
                rc-update add $service_name default && log "\033[32m成功\033[0m" || log "\033[31m失败\033[0m"
            else
                log "\033[36m已配置\033[0m"
            fi
            ;;
        *)
            if systemctl is-enabled $service_name &>/dev/null; then
                log "\033[36m已启用\033[0m"
            else
                systemctl enable $service_name --now 2>/dev/null && log "\033[32m成功\033[0m" || log "\033[31m失败\033[0m"
            fi
            ;;
    esac
}
enable_service

# SSH配置优化
configure_ssh_root_login() {
    log "\033[36m[操作] 正在检查SSH配置...\033[0m"
    local sshd_config="/etc/ssh/sshd_config"
    
    # 创建备份
    if ! cp "$sshd_config" "${sshd_config}.bak" 2>/dev/null; then
        log "\033[33m! 警告：未能创建配置文件备份\033[0m"
    fi

    # 配置检查函数
    is_configured() {
        grep -qE '^[[:space:]]*PermitRootLogin[[:space:]]+yes' "$sshd_config" && \
        grep -qE '^[[:space:]]*PasswordAuthentication[[:space:]]+yes' "$sshd_config"
    }

    # 如果配置已正确则跳过
    if is_configured; then
        log "\033[32m✓ 配置已符合要求（允许root登录和密码认证）\033[0m"
        return 0
    fi

    # 执行配置修改
    log "\033[33m! 检测到需要修改SSH配置\033[0m"
    sed -i '/PermitRootLogin\|PasswordAuthentication/d' "$sshd_config"
    echo "PermitRootLogin yes" >> "$sshd_config"
    echo "PasswordAuthentication yes" >> "$sshd_config"

    # 重启服务并验证
    local need_restart=1
    case $pkgmgr in
        apt|yum|dnf)
            if systemctl restart "$service_name"; then
                log "\033[32m✓ SSH服务重启成功\033[0m"
                need_restart=0
            fi
            ;;
        apk)
            if rc-service "$service_name" restart; then
                log "\033[32m✓ SSH服务重启成功\033[0m"
                need_restart=0
            fi
            ;;
    esac

    # 处理重启失败的情况
    if [ $need_restart -eq 1 ]; then
        log "\033[31m错误：SSH服务重启失败，请手动检查！\033[0m"
        return 1
    fi

    log "\033[32m✓ 配置更新完成（修改后已生效）\033[0m"
}
configure_ssh_root_login

# 时区配置
set_timezone() {
    log "\033[36m[操作] 正在校验时区配置...\033[0m"
    current_tz=$(date +%Z)
    [ "$current_tz" = "CST" ] && {
        log "\033[36m当前时区已正确设置 (Asia/Shanghai CST+8)\033[0m"
        return
    }
    
    log "\033[33m! 正在设置时区为 Asia/Shanghai\033[0m"
    timedatectl set-timezone Asia/Shanghai 2>/dev/null || \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    log "\033[32m✓ 时区配置完成\033[0m"
}
set_timezone

log "\n\033[32m所有配置已完成！\033[0m"
