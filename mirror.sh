#!/usr/bin/env bash
#
# 通用 Linux 发行版镜像源更换脚本
# 版本: 2.0 (稳定增强版)
#
# 功能:
# - 支持 Alpine, Debian, Ubuntu, CentOS 7, CentOS 8+ (Stream/Rocky/Alma)
# - 自动检测发行版和版本号，应用最合适的配置。
# - 提供国内主流镜像源选择。
# - 自动备份旧的源文件。
# - 交互式确认是否执行系统升级。

# --- 全局设置 ---
# 设置终端列宽为1，确保`select`菜单单列显示，更美观
COLUMNS=1

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- 核心函数 ---

# 1. 检查并获取Root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${YELLOW}需要root权限来修改系统配置。${NC}"
        # 尝试用sudo重新运行脚本，并传递所有参数
        if command -v sudo >/dev/null 2>&1; then
            echo -e "尝试使用 sudo 提权..."
            exec sudo "$0" "$@"
        else
            echo -e "${RED}错误: 未找到 sudo 命令，请切换到 root 用户后运行此脚本。${NC}"
            exit 1
        fi
    fi
}

# 2. 交互式选择镜像源
select_mirror() {
    echo -e "\n${BLUE}========== 镜像源选择 ==========${NC}"
    PS3='请选择一个镜像源 (输入数字): '
    options=(
        "阿里云"
        "腾讯云"
        "华为云"
        "中科大"
        "清华大学"
    )
    
    # 使用循环确保用户做出有效选择
    while true; do
        select opt in "${options[@]}"; do
            case $REPLY in
                1) MIRROR_KEY="ali" && break ;;
                2) MIRROR_KEY="tencent" && break ;;
                3) MIRROR_KEY="huawei" && break ;;
                4) MIRROR_KEY="ustc" && break ;;
                5) MIRROR_KEY="tsinghua" && break ;;
                *) echo -e "${YELLOW}无效选项 '$REPLY'，请重新选择。${NC}"; break ;;
            esac
        done
        # 如果MIRROR_KEY被赋值，说明选择了有效选项，跳出外层while循环
        if [[ -n "$MIRROR_KEY" ]]; then
            SELECTED_MIRROR_NAME=$opt
            break
        fi
    done
}

# 3. 备份原始仓库文件/目录
backup_repo() {
    local repo_path="$1"
    local backup_path="${repo_path}.bak_$(date +%Y%m%d_%H%M%S)"
    if [[ -e "$repo_path" ]]; then
        echo -e "正在备份原始文件: ${repo_path} -> ${backup_path}"
        mv "$repo_path" "$backup_path"
    else
        echo -e "${YELLOW}警告: 原始文件 ${repo_path} 不存在，无需备份。${NC}"
    fi
}

# 4. 更新软件源并询问是否升级
update_and_upgrade() {
    local pkg_cmd="$1"
    echo -e "\n${BLUE}========== 更新软件源索引 ==========${NC}"
    case $pkg_cmd in
        apk)   apk update ;;
        apt)   apt-get update ;;
        yum|dnf) "$pkg_cmd" clean all && "$pkg_cmd" makecache ;;
    esac

    if [[ $? -ne 0 ]]; then
        echo -e "${RED}软件源索引更新失败！请检查您的网络连接或镜像源配置。${NC}"
        exit 1
    fi
    echo -e "${GREEN}软件源索引更新成功！${NC}"

    read -p "是否要立即执行系统升级 (apt upgrade / yum update)? [y/N]: " choice
    case "$choice" in
        y|Y )
            echo -e "${BLUE}========== 开始系统升级 ==========${NC}"
            case $pkg_cmd in
                apk)   apk upgrade ;;
                apt)   apt-get upgrade -y && apt-get autoremove -y ;;
                yum|dnf) "$pkg_cmd" update -y ;;
            esac
            echo -e "${GREEN}系统升级完成。${NC}"
            ;;
        * )
            echo -e "${YELLOW}已跳过系统升级。${NC}"
            ;;
    esac
}


# --- 主程序 ---
main() {
    check_root "$@"

    # 检测发行版信息
    if [[ ! -f /etc/os-release ]]; then
        echo -e "${RED}错误: /etc/os-release 文件不存在，无法检测系统信息。${NC}"
        exit 1
    fi
    source /etc/os-release
    DISTRO="${ID:-unknown}"
    VERSION_ID="${VERSION_ID:-unknown}"

    # 显示系统信息
    echo -e "\n${BLUE}========== 系统信息 ==========${NC}"
    echo -e "发行版: ${PRETTY_NAME:-$ID}"
    echo -e "版本号: ${VERSION_ID}"

    # 确定包管理器
    local PKG_CMD=""
    case $DISTRO in
        alpine)     PKG_CMD="apk" ;;
        debian|ubuntu) PKG_CMD="apt" ;;
        centos|rhel) PKG_CMD="yum" ;;
        fedora)     PKG_CMD="dnf" ;;
        *) echo -e "${RED}错误: 不支持的发行版 '$DISTRO'。${NC}"; exit 1 ;;
    esac
    echo "包管理器: $PKG_CMD"

    select_mirror

    # 定义镜像主机地址
    declare -A MIRROR_HOSTS=(
        [ali]="mirrors.aliyun.com"
        [tencent]="mirrors.tencent.com"
        [huawei]="repo.huaweicloud.com"
        [ustc]="mirrors.ustc.edu.cn"
        [tsinghua]="mirrors.tuna.tsinghua.edu.cn"
    )
    MIRROR_HOST="${MIRROR_HOSTS[$MIRROR_KEY]}"

    echo -e "\n${BLUE}开始配置 ${DISTRO} 的镜像源...${NC}"

    case $DISTRO in
    alpine)
        local ALPINE_VERSION
        ALPINE_VERSION=$(cut -d. -f1,2 < /etc/alpine-release)
        REPO_FILE="/etc/apk/repositories"
        backup_repo "$REPO_FILE"
        cat > "$REPO_FILE" <<EOF
https://${MIRROR_HOST}/alpine/v${ALPINE_VERSION}/main
https://${MIRROR_HOST}/alpine/v${ALPINE_VERSION}/community
EOF
        ;;

    debian)
        local CODENAME="${VERSION_CODENAME}"
        if [[ -z "$CODENAME" ]]; then
            echo -e "${RED}无法从 /etc/os-release 获取 Debian 的版本代号(CODENAME)。${NC}"
            exit 1
        fi
        local REPO_FILE="/etc/apt/sources.list"
        backup_repo "$REPO_FILE"
        
        # Debian 12+ (Bookworm) 包含 non-free-firmware
        local FIRMWARE_PART="non-free-firmware"
        if [[ $(echo "$VERSION_ID" | cut -d. -f1) -lt 12 ]]; then
            FIRMWARE_PART=""
        fi
        
        cat > "$REPO_FILE" <<EOF
deb https://${MIRROR_HOST}/debian/ ${CODENAME} main contrib non-free ${FIRMWARE_PART}
deb https://${MIRROR_HOST}/debian/ ${CODENAME}-updates main contrib non-free ${FIRMWARE_PART}
deb https://${MIRROR_HOST}/debian/ ${CODENAME}-backports main contrib non-free ${FIRMWARE_PART}
deb https://${MIRROR_HOST}/debian-security/ ${CODENAME}-security main contrib non-free ${FIRMWARE_PART}
EOF
        ;;

    ubuntu)
        local CODENAME="${VERSION_CODENAME}"
        if [[ -z "$CODENAME" ]]; then
            echo -e "${RED}无法从 /etc/os-release 获取 Ubuntu 的版本代号(CODENAME)。${NC}"
            exit 1
        fi
        local REPO_FILE="/etc/apt/sources.list"
        backup_repo "$REPO_FILE"
        cat > "$REPO_FILE" <<EOF
deb https://${MIRROR_HOST}/ubuntu/ ${CODENAME} main restricted universe multiverse
deb https://${MIRROR_HOST}/ubuntu/ ${CODENAME}-updates main restricted universe multiverse
deb https://${MIRROR_HOST}/ubuntu/ ${CODENAME}-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu/ ${CODENAME}-security main restricted universe multiverse
EOF
        ;;

    centos|rhel|fedora)
        REPO_DIR="/etc/yum.repos.d"
        backup_repo "$REPO_DIR" # 备份整个目录
        mkdir -p "$REPO_DIR"   # 确保目录存在
        
        local MAJOR_VERSION
        MAJOR_VERSION=$(echo "$VERSION_ID" | cut -d. -f1)
        
        if [[ "$MAJOR_VERSION" -le 7 ]]; then
            # CentOS 7 / RHEL 7
            cat > "${REPO_DIR}/CentOS-Base-custom.repo" <<EOF
[base]
name=CentOS-\$releasever - Base - ${MIRROR_HOST}
baseurl=https://${MIRROR_HOST}/centos/\$releasever/os/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[updates]
name=CentOS-\$releasever - Updates - ${MIRROR_HOST}
baseurl=https://${MIRROR_HOST}/centos/\$releasever/updates/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

[extras]
name=CentOS-\$releasever - Extras - ${MIRROR_HOST}
baseurl=https://${MIRROR_HOST}/centos/\$releasever/extras/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
EOF
        else
            # CentOS 8+, RHEL 8+, Fedora
            # 这些系统使用 BaseOS 和 AppStream
            cat > "${REPO_DIR}/CentOS-Base-custom.repo" <<EOF
[BaseOS]
name=CentOS Stream \$releasever - BaseOS - ${MIRROR_HOST}
baseurl=https://${MIRROR_HOST}/centos-stream/\$releasever/BaseOS/\$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial

[AppStream]
name=CentOS Stream \$releasever - AppStream - ${MIRROR_HOST}
baseurl=https://${MIRROR_HOST}/centos-stream/\$releasever/AppStream/\$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial
EOF
        fi
        ;;
    esac

    update_and_upgrade "$PKG_CMD"

    echo -e "\n${GREEN}[完成] 镜像源已成功更换为 ${SELECTED_MIRROR_NAME}。${NC}"
}

# --- 脚本执行入口 ---
main "$@"
