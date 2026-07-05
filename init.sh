#!/bin/bash

# ============================================================
#  系统初始化脚本
#  功能：时区设置 | 中文环境 | 换源 | SSH 配置 | 系统清理
#  支持：Ubuntu / Debian / CentOS / RHEL / Fedora / Alpine
# ============================================================

# --- 颜色 ---
R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'
B='\033[1;34m'; C='\033[1;36m'; N='\033[0m'

# --- 权限检查 ---
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${R}错误：需要 root 权限。请使用 sudo 或切换到 root 用户。${N}"
        exit 1
    fi
}

# --- 发行版检测 ---
detect_distro() {
    source /etc/os-release
    DISTRO="${ID,,}"
    CODENAME="${VERSION_CODENAME,,}"
    VER_MAJOR=$(echo "$VERSION_ID" | cut -d. -f1)
    case "$DISTRO" in
        ubuntu|debian) PKG="apt" ;;
        centos|rhel|almalinux|rocky) PKG="yum" ;;
        fedora) PKG="dnf" ;;
        alpine) PKG="apk" ;;
        *) echo -e "${R}不支持的发行版：$DISTRO${N}"; exit 1 ;;
    esac
    echo -e "${C}系统：${PRETTY_NAME:-$DISTRO}${N}"
}

# --- 1. 设置时区 ---
set_timezone() {
    echo -e "\n${B}--- 设置时区为 Asia/Shanghai ---${N}"
    if [[ "$(readlink /etc/localtime 2>/dev/null)" = *Asia/Shanghai ]] || \
       timedatectl show 2>/dev/null | grep -q 'Timezone=Asia/Shanghai'; then
        echo -e "${G}当前时区已是 Asia/Shanghai，跳过。${N}"
        return 0
    fi
    if command -v timedatectl &>/dev/null; then
        timedatectl set-timezone Asia/Shanghai && echo -e "${G}时区设置成功${N}" || \
            echo -e "${R}timedatectl 设置失败${N}"
    else
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
            echo -e "${G}时区设置成功${N}" || \
            echo -e "${R}链接失败，请检查 /usr/share/zoneinfo/Asia/Shanghai 是否存在${N}"
    fi
    echo "当前时间：$(date)"
}

# --- 2. 中文环境 ---
setup_chinese() {
    echo -e "\n${B}--- 配置中文环境 ---${N}"

    # 安装中文字体
    echo -e "${Y}检查中文字体...${N}"
    if dpkg -s fonts-wqy-zenhi &>/dev/null 2>&1; then
        echo -e "${G}文泉驿字体已安装${N}"
    else
        echo "安装文泉驿字体..."
        $PKG install -y fonts-wqy-zenhi >/dev/null 2>&1 && \
            echo -e "${G}字体安装成功${N}" || \
            echo -e "${R}字体安装失败${N}"
    fi

    # 配置 locale
    local LC_FILE="/etc/default/locale"
    if grep -q 'LANG=zh_CN.UTF-8' "$LC_FILE" 2>/dev/null; then
        echo -e "${G}中文 locale 已配置${N}"
        return 0
    fi

    if [[ "$DISTRO" = ubuntu ]]; then
        $PKG install -y language-pack-zh-hans >/dev/null 2>&1 && \
            echo -e "${G}中文语言包安装成功${N}" || \
            echo -e "${Y}中文语言包安装失败，尝试用 locale-gen 方式...${N}"
    fi

    if command -v locale-gen &>/dev/null; then
        sed -i '/^# *zh_CN.UTF-8/s/^# *//' /etc/locale.gen 2>/dev/null
        locale-gen zh_CN.UTF-8 >/dev/null 2>&1
    fi

    echo 'LANG=zh_CN.UTF-8' >> "$LC_FILE"
    export LANG=zh_CN.UTF-8
    echo -e "${G}中文环境配置完成（部分更改需要重新登录生效）${N}"
}

# --- 3. 换源 ---
select_mirror_and_apply() {
    echo -e "\n${B}--- 更换镜像源 ---${N}"
    echo "1) 阿里云    2) 腾讯云    3) 华为云"
    echo "4) 中科大    5) 清华大学  0) 跳过"
    read -p "$(echo -e "${C}请选择镜像源：${N}")" m_choice

    case "$m_choice" in
        1) HOST="mirrors.aliyun.com";   NAME="阿里云" ;;
        2) HOST="mirrors.tencent.com";  NAME="腾讯云" ;;
        3) HOST="repo.huaweicloud.com"; NAME="华为云" ;;
        4) HOST="mirrors.ustc.edu.cn";  NAME="中科大" ;;
        5) HOST="mirrors.tuna.tsinghua.edu.cn"; NAME="清华大学" ;;
        0) return 0 ;;
        *) echo -e "${R}无效选项${N}"; return 1 ;;
    esac
    echo -e "选择：${C}$NAME${N} ($HOST)"

    case "$PKG" in
        apt) apply_apt_mirror ;;
        apk) apply_alpine_mirror ;;
        yum|dnf) apply_rpm_mirror ;;
    esac
}

apply_apt_mirror() {
    local BACKUP_DIR="/etc/apt/backup_$(date +%s)"
    mkdir -p "$BACKUP_DIR"

    # 检测是否使用 DEB822 格式（Ubuntu 24.04+）
    local USE_DEB822=false
    if ls /etc/apt/sources.list.d/*.sources &>/dev/null 2>&1; then
        USE_DEB822=true
    fi

    if $USE_DEB822; then
        echo -e "${Y}检测到 DEB822 格式，使用新格式配置...${N}"
        # 备份并删除旧的 sources 文件
        cp /etc/apt/sources.list.d/*.sources "$BACKUP_DIR/" 2>/dev/null
        cp /etc/apt/sources.list "$BACKUP_DIR/" 2>/dev/null
        rm -f /etc/apt/sources.list.d/*.sources 2>/dev/null
        : > /etc/apt/sources.list

        if [[ "$DISTRO" = ubuntu ]]; then
            local KEYRING="/usr/share/keyrings/ubuntu-archive-keyring.gpg"
            cat > /etc/apt/sources.list.d/ubuntu.sources <<EOF
Types: deb
URIs: https://$HOST/ubuntu/
Suites: $CODENAME $CODENAME-updates $CODENAME-backports $CODENAME-security
Components: main restricted universe multiverse
Signed-By: $KEYRING
EOF
        elif [[ "$DISTRO" = debian ]]; then
            local KEYRING="/usr/share/keyrings/debian-archive-keyring.gpg"
            cat > /etc/apt/sources.list.d/debian.sources <<EOF
Types: deb
URIs: https://$HOST/debian/
Suites: $CODENAME $CODENAME-updates $CODENAME-backports
Components: main contrib non-free
Signed-By: $KEYRING

Types: deb
URIs: https://$HOST/debian-security/
Suites: $CODENAME-security
Components: main contrib non-free
Signed-By: $KEYRING
EOF
        fi
    else
        # 传统格式
        cp /etc/apt/sources.list "$BACKUP_DIR/" 2>/dev/null
        if [[ "$DISTRO" = ubuntu ]]; then
            cat > /etc/apt/sources.list <<EOF
deb https://$HOST/ubuntu/ $CODENAME main restricted universe multiverse
deb https://$HOST/ubuntu/ $CODENAME-updates main restricted universe multiverse
deb https://$HOST/ubuntu/ $CODENAME-backports main restricted universe multiverse
deb https://$HOST/ubuntu/ $CODENAME-security main restricted universe multiverse
EOF
        elif [[ "$DISTRO" = debian ]]; then
            local FW=""
            [[ $VER_MAJOR -ge 12 ]] && FW="non-free-firmware"
            cat > /etc/apt/sources.list <<EOF
deb https://$HOST/debian/ $CODENAME main contrib non-free $FW
deb https://$HOST/debian/ $CODENAME-updates main contrib non-free $FW
deb https://$HOST/debian/ $CODENAME-backports main contrib non-free $FW
deb https://$HOST/debian-security/ $CODENAME-security main contrib non-free $FW
EOF
        fi
    fi

    echo "备份目录：$BACKUP_DIR"
    echo "更新软件源..."
    apt-get update && echo -e "${G}换源成功${N}" || {
        echo -e "${R}更新失败，正在恢复备份...${N}"
        cp -r "$BACKUP_DIR"/* /etc/apt/ 2>/dev/null
        apt-get update
    }
}

apply_alpine_mirror() {
    local VER=$(cut -d. -f1,2 < /etc/alpine-release)
    cp /etc/apk/repositories /etc/apk/repositories.bak
    cat > /etc/apk/repositories <<EOF
https://$HOST/alpine/v$VER/main
https://$HOST/alpine/v$VER/community
EOF
    apk update && echo -e "${G}换源成功${N}"
}

apply_rpm_mirror() {
    local REPO_DIR="/etc/yum.repos.d"
    local BAK="${REPO_DIR}.bak_$(date +%s)"
    [[ -d "$REPO_DIR" ]] && cp -r "$REPO_DIR" "$BAK"

    mkdir -p "$REPO_DIR"
    if [[ $VER_MAJOR -le 7 ]]; then
        cat > "${REPO_DIR}/custom.repo" <<EOF
[base]
name=CentOS-\$releasever - Base
baseurl=https://$HOST/centos/\$releasever/os/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[updates]
name=CentOS-\$releasever - Updates
baseurl=https://$HOST/centos/\$releasever/updates/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
EOF
    else
        cat > "${REPO_DIR}/custom.repo" <<EOF
[BaseOS]
name=CentOS Stream \$releasever - BaseOS
baseurl=https://$HOST/centos-stream/\$releasever/BaseOS/\$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial

[AppStream]
name=CentOS Stream \$releasever - AppStream
baseurl=https://$HOST/centos-stream/\$releasever/AppStream/\$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial
EOF
    fi
    $PKG clean all && $PKG makecache && echo -e "${G}换源成功${N}"
}

# --- 4. SSH 配置 ---
configure_ssh() {
    echo -e "\n${B}--- SSH 远程登录配置 ---${N}"
    echo -e "${R}!!! 开启 root/密码登录会增加安全风险 !!!${N}"
    read -p "确认开启？(y/N): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && echo "已取消" && return 0

    local CFG="/etc/ssh/sshd_config"
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' "$CFG"
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$CFG"

    if systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null; then
        echo -e "${G}SSH 服务已重启${N}"
    else
        echo -e "${Y}请手动重启 SSH 服务：systemctl restart ssh${N}"
    fi
}

# --- 5. 系统清理 ---
clean_system() {
    echo -e "\n${B}--- 系统清理 ---${N}"

    # 清理临时文件
    echo -n "清理临时文件..."
    for d in /tmp /var/tmp; do
        [[ -d "$d" ]] && find "$d" -mindepth 1 -mtime +1 -exec rm -rf {} + 2>/dev/null
    done
    echo -e " ${G}完成${N}"

    # 清理旧日志（保留7天）
    echo -n "清理旧日志..."
    find /var/log -name "*.log" -o -name "*.gz" -o -name "syslog" -o -name "messages" \
        -o -name "kern.log" -o -name "auth.log" -o -name "daemon.log" | \
        xargs -I{} find {} -type f -mtime +7 -delete 2>/dev/null
    echo -e " ${G}完成${N}"

    # 清理缓存（保留30天）
    echo -n "清理缓存..."
    for d in /root/.cache /root/.thumbnails; do
        [[ -d "$d" ]] && find "$d" -mindepth 1 -mtime +30 -exec rm -rf {} + 2>/dev/null
    done
    echo -e " ${G}完成${N}"

    # apt 清理
    if command -v apt-get &>/dev/null; then
        echo -n "APT 自动清理..."
        apt-get autoremove -y >/dev/null 2>&1 && apt-get clean >/dev/null 2>&1
        echo -e " ${G}完成${N}"
    fi

    # updatedb
    if command -v updatedb &>/dev/null; then
        echo -n "更新数据库索引..."
        updatedb >/dev/null 2>&1
        echo -e " ${G}完成${N}"
    fi

    sync
    echo -e "${G}清理完毕${N}"
}

# --- 主菜单 ---
main_menu() {
    while true; do
        clear
        echo -e "${C}==============================================${N}"
        echo -e "${C}           系统初始化工具                      ${N}"
        echo -e "${C}==============================================${N}"
        echo " 1) 设置时区 (Asia/Shanghai)"
        echo " 2) 配置中文环境 (字体 + locale)"
        echo " 3) 更换镜像源"
        echo " 4) 开启 SSH root/密码登录"
        echo " 5) 系统清理"
        echo " 6) 全部执行 (1→2→3→4→5)"
        echo " 0) 退出"
        echo -e "${C}==============================================${N}"
        read -p "$(echo -e "${Y}请输入选项：${N}")" choice

        case "$choice" in
            1) set_timezone ;;
            2) setup_chinese ;;
            3) select_mirror_and_apply ;;
            4) configure_ssh ;;
            5) clean_system ;;
            6)
                set_timezone
                setup_chinese
                select_mirror_and_apply
                configure_ssh
                clean_system
                echo -e "\n${G}全部任务执行完毕${N}"
                ;;
            0) echo "退出"; exit 0 ;;
            *) echo -e "${R}无效选项${N}" ;;
        esac
        read -p "按回车键继续..."
    done
}

# --- 入口 ---
check_root
detect_distro
main_menu