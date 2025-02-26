#!/bin/bash

# 权限检查
echo "正在检查运行权限..."
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：必须使用 root 用户或 sudo 权限运行本脚本" >&2
    exit 1
else
    echo "✓ 权限检查通过"
fi

# 系统检测字典 (包名: 服务名)
declare -A PKG_MAP=(
    ["apt"]="openssh-server:ssh"
    ["yum"]="openssh-server:sshd"
    ["dnf"]="openssh-server:sshd" 
    ["apk"]="openssh:sshd"
)

# 确定包管理器
detect_pkgmgr() {
    echo -n "正在检测系统包管理器..."
    for cmd in apt yum dnf apk; do
        if command -v $cmd &>/dev/null; then
            echo "检测到使用 $cmd 作为包管理器"
            echo $cmd
            return
        fi
    done
    echo "错误：不支持的包管理器，仅支持 apt/yum/dnf/apk" >&2
    exit 1
}

pkgmgr=$(detect_pkgmgr)
IFS=':' read -ra SSH_INFO <<< "${PKG_MAP[$pkgmgr]}"
pkg_name=${SSH_INFO[0]}
service_name=${SSH_INFO[1]}
echo "将使用以下配置：包名称=$pkg_name, 服务名称=$service_name"

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
    echo "检测到 $pkg_name 未安装"
    read -p "是否安装并配置SSH服务？[Y/n] " confirm
    confirm=${confirm:-Y}
    
    if [[ $confirm =~ ^[Yy] ]]; then
        echo "开始安装 $pkg_name ..."
        
        # 多版本安装命令适配
        case $pkgmgr in
            apt) 
                echo "使用APT安装 $pkg_name ..."
                export DEBIAN_FRONTEND=noninteractive
                apt update -y && apt install -y $pkg_name
                ;;
            yum) 
                echo "使用YUM安装 $pkg_name ..."
                yum install -y $pkg_name 
                ;;
            dnf) 
                echo "使用DNF安装 $pkg_name ..."
                dnf install -y $pkg_name 
                ;;
            apk) 
                echo "使用APK安装 $pkg_name ..."
                apk add $pkg_name --no-cache 
                ;;
        esac
        
        # 安装结果验证
        if [ $? -ne 0 ] || ! is_installed; then
            echo "错误：$pkg_name 安装失败，请检查网络或软件源配置" >&2
            exit 1
        else
            echo "✓ $pkg_name 安装成功"
        fi
    else
        echo "用户取消安装，退出脚本"
        exit 0
    fi
else
    echo "✓ 检测到 $pkg_name 已安装"
fi

# 服务自启配置
enable_service() {
    echo -n "正在配置 $service_name 服务开机自启..."
    case $pkgmgr in
        apk)
            if ! rc-update show default | grep -q $service_name; then
                rc-update add $service_name default
                echo "✓ 已设置 $service_name 开机自启" 
            else
                echo "$service_name 已配置开机启动，无需更改"
            fi
            ;;
        *)
            if ! systemctl is-enabled $service_name &>/dev/null; then
                systemctl enable $service_name --now
                echo "✓ 已设置 $service_name 开机自启" 
            else
                echo "$service_name 已启用，无需操作"
            fi
            ;;
    esac
}

enable_service

# 新增SSH配置：允许root密码登录
configure_ssh_root_login() {
    echo "开始配置SSH允许root登录..."
    local sshd_config="/etc/ssh/sshd_config"
    
    # 备份配置文件
    echo -n "备份配置文件 $sshd_config ..."
    if cp "$sshd_config" "${sshd_config}.bak" 2>/dev/null; then
        echo "备份成功：${sshd_config}.bak"
    else
        echo "警告：无法创建配置文件备份，继续操作可能存在风险" >&2
    fi

    # 检查并修改配置
    local need_restart=0
    echo -n "检查 PermitRootLogin 配置..."
    if ! grep -qE '^PermitRootLogin[[:space:]]+yes' "$sshd_config"; then
        sed -i -E '/^#?PermitRootLogin/c\PermitRootLogin yes' "$sshd_config"
        echo "已允许Root登录"
        need_restart=1
    else
        echo "PermitRootLogin 已配置正确"
    fi

    echo -n "检查 PasswordAuthentication 配置..."
    if ! grep -qE '^PasswordAuthentication[[:space:]]+yes' "$sshd_config"; then
        sed -i -E '/^#?PasswordAuthentication/c\PasswordAuthentication yes' "$sshd_config"
        echo "已启用密码认证"
        need_restart=1
    else
        echo "PasswordAuthentication 已配置正确"
    fi

    # 无需修改时跳过重启
    if [ $need_restart -eq 0 ]; then
        echo "✓ SSH配置无需修改"
        return 0
    fi

    # 重启SSH服务
    echo -n "正在重启SSH服务($service_name)..."
    case $pkgmgr in
        apt|yum|dnf)
            systemctl restart "$service_name"
            ;;
        apk)
            rc-service "$service_name" restart
            ;;
    esac

    # 验证服务状态
    local retries=3
    while [ $retries -gt 0 ]; do
        if (command -v systemctl &>/dev/null && systemctl is-active "$service_name" >/dev/null) || \
           (! command -v systemctl &>/dev/null && rc-service "$service_name" status | grep -q "status: started"); then
            echo "✓ SSH服务重启成功"
            return 0
        fi
        let retries--
        sleep 2
    done

    echo "警告：SSH服务重启失败，请手动检查！" >&2
    return 1
}

configure_ssh_root_login

# 时区修改
set_timezone() {
    local target_tz="Asia/Shanghai"
    echo "开始配置系统时区为 $target_tz ..."
    
    # 检查当前时区
    echo -n "当前时区状态："
    if command -v timedatectl &>/dev/null; then
        timedatectl | grep "Time zone"
    else
        date +"%Z %z"
    fi

    # 安装tzdata（Alpine需要）
    if [ ! -f "/usr/share/zoneinfo/$target_tz" ]; then
        echo "检测到时区文件缺失，安装tzdata..."
        case $pkgmgr in
            apt) apt install -y tzdata ;;
            yum|dnf) $pkgmgr install -y tzdata ;;
            apk) apk add --no-cache tzdata ;;
        esac
    fi

    # 配置时区
    echo -n "设置时区..."
    if command -v timedatectl &>/dev/null; then
        timedatectl set-timezone "$target_tz"
    else
        ln -sf "/usr/share/zoneinfo/$target_tz" /etc/localtime
        echo "$target_tz" > /etc/timezone
    fi

    # 验证结果
    echo -n "验证时区设置..."
    if [ "$(date +%Z)" == "CST" ]; then
        echo "✓ 时区已成功设置为 CST (UTC+8)"
    else
        echo "警告：时区设置可能未生效，当前时间：$(date)"
    fi
}

set_timezone

echo -e "\n所有配置操作已完成！"
echo "请确认以下服务状态："
echo "  - SSH服务状态：$(systemctl is-active $service_name 2>/dev/null || rc-service $service_name status 2>/dev/null)"
echo "  - 当前SSH配置："
echo "    * PermitRootLogin $(grep PermitRootLogin /etc/ssh/sshd_config)"
echo "    * PasswordAuthentication $(grep PasswordAuthentication /etc/ssh/sshd_config)"
echo "  - 系统时区：$(date +%Z%z)"
