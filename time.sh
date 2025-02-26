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

# 新增SSH配置：允许root密码登录
configure_ssh_root_login() {
    echo "正在配置SSH允许root用户密码登录..."
    local sshd_config="/etc/ssh/sshd_config"
    
    # 备份配置文件
    cp "$sshd_config" "${sshd_config}.bak" 2>/dev/null || {
        echo "无法备份SSH配置文件" >&2
        return 1
    }

    # 修改关键参数（兼容不同注释格式）
    sed -i -E '/^#?PermitRootLogin/c\PermitRootLogin yes' "$sshd_config"
    sed -i -E '/^#?PasswordAuthentication/c\PasswordAuthentication yes' "$sshd_config"

    # 重启SSH服务（适配不同系统）
    case $pkgmgr in
        apt|yum|dnf)
            systemctl restart "$service_name"
            ;;
        apk)
            rc-service "$service_name" restart
            ;;
    esac

    # 验证服务状态
    if ! systemctl is-active "$service_name" >/dev/null 2>&1; then
        echo "SSH服务重启失败，请检查日志：journalctl -u $service_name" >&2
        return 1
    fi
    echo "SSH配置更新成功 √"
}
configure_ssh_root_login

# 时区修改
set_timezone() {
    local target_tz="Asia/Shanghai"
    local tzfile="/usr/share/zoneinfo/$target_tz"
    local localtime="/etc/localtime"
    local timezone="/etc/timezone"

    # 先检查当前是否已经是东八区 
    if command -v timedatectl &>/dev/null; then
        if timedatectl | grep -q "$target_tz"; then
            echo "时区已正确配置为 $target_tz"
            return 0
        fi
    elif [ -f "$localtime" ]; then
        # 通过符号链接或文件内容判断 
        if [ -L "$localtime" ] && [ "$(readlink -f "$localtime")" = "$tzfile" ]; then
            echo "时区已正确配置为 $target_tz"
            return 0
        elif cmp -s "$localtime" "$tzfile"; then
            echo "时区已正确配置为 $target_tz"
            return 0
        fi
    fi

    # 检查符号链接可行性 
    local can_use_symlink=true
    if [ ! -f "$tzfile" ]; then
        echo "错误：时区文件 $tzfile 不存在，尝试安装 tzdata..."
        case $pkgmgr in
            apt) apt install -y tzdata ;;
            yum|dnf) $pkgmgr install -y tzdata ;;
            apk) apk add --no-cache tzdata ;;
        esac
        [ -f "$tzfile" ] || { echo "时区文件安装失败"; return 1; }
    fi

    # 测试创建临时符号链接检测可行性
    local temp_link="$(mktemp -u)"
    if ! ln -sf "$tzfile" "$temp_link" 2>/dev/null; then
        can_use_symlink=false
    else
        rm -f "$temp_link"
    fi

    # 优先使用符号链接方案 
    if $can_use_symlink; then
        echo "尝试符号链接方式配置时区..."
        # 备份原有配置
        [ -e "$localtime" ] && cp -a "$localtime" "$localtime.bak"
        [ -e "$timezone" ] && cp -a "$timezone" "$timezone.bak"
        
        # 删除旧配置（兼容实体文件和符号链接）
        rm -f "$localtime"
        # 创建符号链接
        if ln -sf "$tzfile" "$localtime"; then
            echo "$target_tz" > "$timezone"
            # 特殊系统适配
            [ -f /etc/sysconfig/clock ] && sed -i "s/^ZONE=.*/ZONE=\"$target_tz\"/" /etc/sysconfig/clock
            [ -f /etc/conf.d/clock ] && sed -i "s/^TIMEZONE=.*/TIMEZONE=\"$target_tz\"/" /etc/conf.d/clock
        else
            can_use_symlink=false
        fi
    fi

    # 符号链接失败时使用替代方案 
    if ! $can_use_symlink; then
        echo "符号链接不可用，尝试复制文件方式..."
        if [ -f "$tzfile" ]; then
            cp -f "$tzfile" "$localtime"
            echo "$target_tz" > "$timezone"
        else
            echo "时区文件缺失，无法配置" >&2
            return 1
        fi
    fi

    # 验证配置结果
    if { [ -L "$localtime" ] && [ "$(readlink -f "$localtime")" = "$tzfile" ]; } || 
       { [ -f "$localtime" ] && cmp -s "$localtime" "$tzfile"; }; then
        echo "时区成功设置为 $target_tz (UTC+8)"
        # 更新系统时间
        hwclock --hctosys 2>/dev/null || true
    else
        # 终极回退方案：使用 timedatectl
        if command -v timedatectl &>/dev/null; then
            timedatectl set-timezone "$target_tz"
        else
            echo "时区配置失败，请手动检查" >&2
            return 1
        fi
    fi
}

echo "所有配置已完成"
