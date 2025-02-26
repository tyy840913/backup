#!/bin/bash

# 权限检查
if [ "$(id -u)" -ne 0 ]; then
    echo "必须使用 root 用户或 sudo 权限运行" >&2
    exit 1
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
    for cmd in apt yum dnf apk; do
        if command -v $cmd &>/dev/null; then
            echo $cmd
            return
        fi
    done
    echo "不支持的包管理器" >&2
    exit 1
}

pkgmgr=$(detect_pkgmgr)
IFS=':' read -ra SSH_INFO <<< "${PKG_MAP[$pkgmgr]}"
pkg_name=${SSH_INFO[0]}
service_name=${SSH_INFO[1]}

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
    echo "未检测到 $pkg_name 软件包"
    read -p "是否安装并配置SSH服务？[Y/n] " confirm
    confirm=${confirm:-Y}
    
    if [[ $confirm =~ ^[Yy] ]]; then
        echo "正在安装 $pkg_name ..."
        
        # 多版本安装命令适配
        case $pkgmgr in
            apt) 
                export DEBIAN_FRONTEND=noninteractive
                apt update -y && apt install -y $pkg_name
                ;;
            yum) yum install -y $pkg_name ;;
            dnf) dnf install -y $pkg_name ;;
            apk) apk add $pkg_name --no-cache ;;
        esac
        
        # 安装结果验证
        if [ $? -ne 0 ] || ! is_installed; then
            echo "安装失败，请检查网络或软件源配置" >&2
            exit 1
        fi
    else
        echo "用户取消安装"
        exit 0
    fi
fi

# 服务自启配置
enable_service() {
    case $pkgmgr in
        apk)
            if ! rc-update show default | grep -q $service_name; then
                rc-update add $service_name default
                echo "已设置 $service_name 开机自启" 
            fi
            ;;
        *)
            if ! systemctl is-enabled $service_name &>/dev/null; then
                systemctl enable $service_name --now
                echo "已设置 $service_name 开机自启" 
            fi
            ;;
    esac
}

enable_service

# 时区配置 (符号链接优先)
set_timezone() {
    local target_tz="Asia/Shanghai"
    local tzfile="/usr/share/zoneinfo/$target_tz"
    local localtime="/etc/localtime"
    local timezone="/etc/timezone"

    # 验证时区文件存在性
    if [ ! -f "$tzfile" ]; then
        echo "错误：时区文件 $tzfile 不存在" >&2
        return 1
    fi

    # 检查现有符号链接有效性
    if [ -L "$localtime" ]; then
        if [ "$(readlink -f "$localtime")" = "$tzfile" ]; then
            echo "时区已正确配置为 $target_tz"
            return 0
        else
            echo "检测到无效的时区符号链接，重新配置..."
            rm -f "$localtime"
        fi
    elif [ -f "$localtime" ]; then
        echo "发现时区实体文件，转换为符号链接..."
        mv "$localtime" "$localtime.bak"
    fi

    # 优先创建符号链接
    echo "正在设置符号链接时区..."
    if ln -sf "$tzfile" "$localtime"; then
        # 更新辅助配置文件
        echo "$target_tz" > "$timezone"
        [ -f /etc/sysconfig/clock ] && sed -i "s/^ZONE=.*/ZONE=\"$target_tz\"/" /etc/sysconfig/clock
        
        # 针对Debian系更新配置
        if [ -f /etc/localtime ] && command -v dpkg-reconfigure &>/dev/null; then
            dpkg-reconfigure -f noninteractive tzdata &> /dev/null
        fi
    else
        # 符号链接失败时回退到timedatectl
        echo "符号链接创建失败，尝试其他方式..."
        if command -v timedatectl &>/dev/null; then
            timedatectl set-timezone "$target_tz"
        else
            # 最终回退方案
            cp "$tzfile" "$localtime"
            echo "$target_tz" > "$timezone"
        fi
    fi

    # 最终验证
    if check_tz_config "$target_tz"; then
        echo "时区已成功设置为 $target_tz (UTC+8)"
    else
        echo "时区配置失败，请手动检查" >&2
        return 1
    fi
}

# 时区验证函数
check_tz_config() {
    local expect_tz="$1"
    # 检查当前系统时区
    if date | grep -q "CST"; then
        return 0
    fi
    # 检查符号链接
    [ -L "/etc/localtime" ] && [ "$(readlink -f /etc/localtime)" = "/usr/share/zoneinfo/$expect_tz" ]
}

set_timezone

echo "所有配置已完成"
