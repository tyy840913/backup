#!/bin/bash
# 系统配置自动化脚本 - 合并优化版
# 功能：1.更换镜像源 2.配置SSH 3.设置时区 4.配置中文环境
# 支持：Debian/Ubuntu, CentOS/RHEL, Alpine Linux

# ==================== 全局配置 ====================
COLUMNS=1
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'
TARGET_ZONE="Asia/Shanghai"
MIRROR_SOURCES=("阿里云" "腾讯云" "华为云" "中科大" "清华大学")

# ==================== 通用函数 ====================
check_root() {
    [[ $EUID -ne 0 ]] && exec sudo "$0" "$@" || {
        echo -e "${RED}需要root权限${NC}"
        exit 1
    }
}

detect_distro() {
    source /etc/os-release 2>/dev/null
    DISTRO="${ID:-unknown}"
    CODENAME="${VERSION_CODENAME}"
    VERSION_ID="${VERSION_ID:-unknown}"
    
    declare -A PKG_MANAGERS=(
        [alpine]="apk" [debian]="apt" [ubuntu]="apt"
        [centos]="yum" [fedora]="dnf" [rhel]="yum"
    )
    PKG_CMD="${PKG_MANAGERS[$DISTRO]}"
    
    echo -e "\n${BLUE}========== 系统信息 ==========${NC}"
    echo "发行版: ${PRETTY_NAME:-$ID}"
    echo "版本号: ${VERSION_ID}"
    echo "包管理器: ${PKG_CMD^^}"
}

backup_file() {
    cp -f "$1" "${1}.bak" && echo -e "${GREEN}已备份: ${1}.bak${NC}"
}

# ==================== 镜像源配置 ====================
configure_mirror() {
    echo -e "\n${BLUE}========== 镜像源选择 ==========${NC}"
    PS3='请选择镜像源 (1-5): '
    select opt in "${MIRROR_SOURCES[@]}"; do
        case $REPLY in
            1) MIRROR="ali";;
            2) MIRROR="tencent";;
            3) MIRROR="huawei";;
            4) MIRROR="ustc";;
            5) MIRROR="tsinghua";;
            *) echo -e "${RED}无效选项${NC}"; return 1;;
        esac
        break
    done

    declare -A MIRROR_MAP=(
        [ali_alpine]="http://mirrors.aliyun.com/alpine/"
        [ali_debian]="http://mirrors.aliyun.com/debian/"
        [ali_ubuntu]="http://mirrors.aliyun.com/ubuntu/"
        [tencent_alpine]="https://mirrors.tencent.com/alpine/"
        [tencent_debian]="http://mirrors.tencentyun.com/debian/"
        [tencent_ubuntu]="http://mirrors.tencentyun.com/ubuntu/"
        [huawei_alpine]="https://repo.huaweicloud.com/alpine/"
        [huawei_debian]="http://repo.huaweicloud.com/debian/"
        [huawei_ubuntu]="http://repo.huaweicloud.com/ubuntu/"
        [ustc_alpine]="http://mirrors.ustc.edu.cn/alpine/"
        [ustc_debian]="http://mirrors.ustc.edu.cn/debian/"
        [ustc_ubuntu]="http://mirrors.ustc.edu.cn/ubuntu/"
        [tsinghua_alpine]="https://mirrors.tuna.tsinghua.edu.cn/alpine/"
        [tsinghua_debian]="https://mirrors.tuna.tsinghua.edu.cn/debian/"
        [tsinghua_ubuntu]="https://mirrors.tuna.tsinghua.edu.cn/ubuntu/"
    )

    case $DISTRO in
        alpine)
            ALPINE_VER=$(cut -d. -f1,2 /etc/alpine-release 2>/dev/null)
            REPO_FILE="/etc/apk/repositories"
            URL="${MIRROR_MAP[${MIRROR}_alpine]}"
            backup_file "$REPO_FILE"
            cat > "$REPO_FILE" <<EOF
${URL}v${ALPINE_VER}/main
${URL}v${ALPINE_VER}/community
${URL}edge/main
${URL}edge/community
${URL}edge/testing
EOF
            ;;
        debian)
            REPO_FILE="/etc/apt/sources.list"
            BASE_URL="${MIRROR_MAP[${MIRROR}_debian]}"
            SECURITY_URL="${MIRROR_MAP[${MIRROR}_debian]}-security/"
            backup_file "$REPO_FILE"
            cat > "$REPO_FILE" <<EOF
deb ${BASE_URL} $CODENAME main contrib non-free
deb ${BASE_URL} $CODENAME-updates main contrib non-free
deb ${BASE_URL} $CODENAME-backports main contrib non-free
deb ${SECURITY_URL} $CODENAME-security main contrib non-free
EOF
            ;;
        ubuntu)
            REPO_FILE="/etc/apt/sources.list"
            BASE_URL="${MIRROR_MAP[${MIRROR}_ubuntu]}"
            backup_file "$REPO_FILE"
            cat > "$REPO_FILE" <<EOF
deb ${BASE_URL} $CODENAME main restricted universe multiverse
deb ${BASE_URL} $CODENAME-updates main restricted universe multiverse
deb ${BASE_URL} $CODENAME-backports main restricted universe multiverse
deb ${BASE_URL} $CODENAME-security main restricted universe multiverse
EOF
            ;;
        centos|fedora|rhel)
            CENTOS_REPO="/etc/yum.repos.d/CentOS-Base.repo"
            BASE_URL="${MIRROR_MAP[${MIRROR}_centos]}"
            backup_file "$CENTOS_REPO"
            sed -i -e "s|^mirrorlist=|#mirrorlist=|g" \
                   -e "s|^#baseurl=|baseurl=|g" \
                   -e "s|baseurl=.*|baseurl=${BASE_URL}|g" "$CENTOS_REPO"
            ;;
        *)
            echo -e "${RED}不支持的发行版${NC}"
            exit 1
            ;;
    esac
    
    # 更新软件源
    case $PKG_CMD in
        apk)   $PKG_CMD update ;;
        apt)   $PKG_CMD update -y ;;
        yum|dnf) $PKG_CMD clean all && $PKG_CMD makecache ;;
    esac
}

# ==================== SSH配置 ====================
configure_ssh() {
    echo -e "\n${BLUE}=== SSH服务配置 ===${NC}"
    case $DISTRO in
        alpine) PKG="openssh" SERVICE="sshd" ;;
        *)      PKG="openssh-server" SERVICE="sshd" ;;
    esac

    # 安装SSH服务
    if ! command -v sshd &>/dev/null; then
        echo -e "${YELLOW}正在安装 $PKG..."
        case $PKG_CMD in
            apk)   $PKG_CMD add $PKG ;;
            apt)   $PKG_CMD install -y $PKG ;;
            yum|dnf) $PKG_CMD install -y $PKG ;;
        esac
    fi

    # 启用服务
    case $DISTRO in
        alpine)
            rc-update add $SERVICE 2>/dev/null
            rc-service $SERVICE restart
            ;;
        *)
            systemctl enable --now $SERVICE
            systemctl restart $SERVICE
            ;;
    esac

    # 配置优化
    SSH_CONFIG="/etc/ssh/sshd_config"
    backup_file "$SSH_CONFIG"
    sed -i 's/^#*\(PermitRootLogin\).*/\1 yes/' $SSH_CONFIG
    sed -i 's/^#*\(PasswordAuthentication\).*/\1 yes/' $SSH_CONFIG
}

# ==================== 时区配置 ====================
configure_timezone() {
    echo -e "\n${BLUE}=== 时区配置 ===${NC}"
    ZONE_FILE="/usr/share/zoneinfo/$TARGET_ZONE"
    
    # 安装时区数据
    [[ ! -f $ZONE_FILE ]] && {
        echo -e "${YELLOW}安装时区数据..."
        case $PKG_CMD in
            apk)   $PKG_CMD add tzdata ;;
            apt)   $PKG_CMD install -y tzdata ;;
            yum|dnf) $PKG_CMD install -y tzdata ;;
        esac
    }

    # 配置时区
    ln -sf "$ZONE_FILE" /etc/localtime 2>/dev/null || \
    cp -f "$ZONE_FILE" /etc/localtime
    [[ $DISTRO == "alpine" ]] && echo "$TARGET_ZONE" > /etc/timezone
    
    # 验证配置
    date +"%Z %z" | grep -qE "CST|\+0800" && \
    echo -e "${GREEN}时区已设置为东八区${NC}" || \
    echo -e "${RED}时区配置失败${NC}"
}


# ==================== 中文环境 ====================
configure_locale() {
    echo -e "\n${BLUE}=== 中文环境配置 ===${NC}"
    case $DISTRO in
        alpine)
            $PKG_CMD add musl-locales musl-locales-lang
            echo "LANG=zh_CN.UTF-8" > /etc/profile.d/locale.sh
            ;;
        debian|ubuntu)
            $PKG_CMD install -y locales language-pack-zh-hans
            sed -i 's/^# *$zh_CN.UTF-8$/\1/' /etc/locale.gen
            locale-gen zh_CN.UTF-8
            update-locale LANG=zh_CN.UTF-8
            ;;
        centos|rhel|fedora)
            $PKG_CMD install -y glibc-langpack-zh
            localectl set-locale LANG=zh_CN.UTF-8
            ;;
    esac
    echo -e "${GREEN}中文环境已配置，请重新登录生效${NC}"
}

# ==================== 主流程 ====================
main() {
    check_root "$@"
    detect_distro
    configure_mirror
    configure_ssh
    configure_timezone
    configure_locale
    echo -e "\n${GREEN}====== 所有配置已完成 ======${NC}"
}

main "$@"
