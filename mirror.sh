#!/bin/bash

# 检查是否为root，否则尝试用sudo重新运行
if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "$@" || {
        echo "需要root权限，请使用sudo运行或切换至root用户"
        exit 1
    }
fi

# 检测发行版信息
source /etc/os-release 2>/dev/null
DISTRO="${ID:-unknown}"
CODENAME="${VERSION_CODENAME}"
VERSION_ID="${VERSION_ID:-unknown}"

# 显示系统信息
echo -e "\n========== 系统信息 =========="
echo "发行版: ${PRETTY_NAME:-$ID}"
echo "版本号: ${VERSION_ID}"

# 确定包管理器
declare -A PKG_MANAGERS=(
    [alpine]="apk"
    [debian]="apt"
    [ubuntu]="apt"
    [centos]="yum"
    [fedora]="dnf"
    [rhel]="yum"
)

PKG_CMD="${PKG_MANAGERS[$DISTRO]}"
case $PKG_CMD in
    apk)   echo "包管理器: Alpine APK" ;;
    apt)   echo "包管理器: Debian/Ubuntu APT" ;;
    yum|dnf) echo "包管理器: RedHat/YUM" ;;
    *)     echo "未知包管理器"; exit 1 ;;
esac

# 镜像源选择菜单
echo -e "\n========== 镜像源选择 =========="
PS3='请选择镜像源 (1-5): '
options=(
    "阿里云"
    "腾讯云" 
    "华为云"
    "中科大"
    "清华大学"
)
select opt in "${options[@]}"; do
    case $REPLY in
        1) MIRROR="ali" ;;
        2) MIRROR="tencent" ;;
        3) MIRROR="huawei" ;;
        4) MIRROR="ustc" ;;
        5) MIRROR="tsinghua" ;;
        *) echo "无效选项"; exit 1 ;;
    esac
    break
done

# 获取发行版特定信息
case $DISTRO in
    alpine)
        ALPINE_VERSION=$(cut -d. -f1,2 /etc/alpine-release 2>/dev/null)
        REPO_FILE="/etc/apk/repositories"
        ;;
    debian|ubuntu)
        CODENAME=${CODENAME:-$(lsb_release -cs 2>/dev/null || echo "unknown")}
        REPO_FILE="/etc/apt/sources.list"
        ;;
    centos|fedora|rhel)
        REPO_DIR="/etc/yum.repos.d/"
        MAJOR_VERSION=$(echo "$VERSION_ID" | cut -d. -f1)
        ;;
esac

# 备份原始文件
backup_file() {
    local file=$1
    cp "$file" "${file}.bak" && echo "已备份: ${file}.bak"
}

# 处理不同发行版的镜像源
case $DISTRO in
alpine)
    case $MIRROR in
        ali)      URL="http://mirrors.aliyun.com/alpine/" ;;
        tencent)  URL="https://mirrors.tencent.com/alpine/" ;;
        huawei)   URL="https://repo.huaweicloud.com/alpine/" ;;
        ustc)     URL="http://mirrors.ustc.edu.cn/alpine/" ;;
        tsinghua) URL="https://mirrors.tuna.tsinghua.edu.cn/alpine/" ;;
    esac

    backup_file "$REPO_FILE"
    cat > "$REPO_FILE" <<EOF
${URL}v${ALPINE_VERSION}/main
${URL}v${ALPINE_VERSION}/community
${URL}edge/main
${URL}edge/community
${URL}edge/testing
EOF
    ;;

debian)
    declare -A MIRROR_URLS=(
        [ali]="http://mirrors.aliyun.com/debian/"
        [tencent]="http://mirrors.tencentyun.com/debian/"
        [huawei]="http://repo.huaweicloud.com/debian/"
        [ustc]="http://mirrors.ustc.edu.cn/debian/"
        [tsinghua]="https://mirrors.tuna.tsinghua.edu.cn/debian/"
    )
    declare -A SECURITY_URLS=(
        [ali]="http://mirrors.aliyun.com/debian-security/"
        [tencent]="http://mirrors.tencentyun.com/debian-security/"
        [huawei]="http://repo.huaweicloud.com/debian-security/"
        [ustc]="http://mirrors.ustc.edu.cn/debian-security/"
        [tsinghua]="https://mirrors.tuna.tsinghua.edu.cn/debian-security/"
    )

    backup_file "$REPO_FILE"
    cat > "$REPO_FILE" <<EOF
deb ${MIRROR_URLS[$MIRROR]} $CODENAME main contrib non-free
deb ${MIRROR_URLS[$MIRROR]} $CODENAME-updates main contrib non-free
deb ${MIRROR_URLS[$MIRROR]} $CODENAME-backports main contrib non-free
deb ${SECURITY_URLS[$MIRROR]} $CODENAME-security main contrib non-free
EOF
    ;;

ubuntu)
    declare -A MIRROR_URLS=(
        [ali]="http://mirrors.aliyun.com/ubuntu/"
        [tencent]="http://mirrors.tencentyun.com/ubuntu/"
        [huawei]="http://repo.huaweicloud.com/ubuntu/"
        [ustc]="http://mirrors.ustc.edu.cn/ubuntu/"
        [tsinghua]="https://mirrors.tuna.tsinghua.edu.cn/ubuntu/"
    )

    backup_file "$REPO_FILE"
    cat > "$REPO_FILE" <<EOF
deb ${MIRROR_URLS[$MIRROR]} $CODENAME main restricted universe multiverse
deb ${MIRROR_URLS[$MIRROR]} $CODENAME-updates main restricted universe multiverse
deb ${MIRROR_URLS[$MIRROR]} $CODENAME-backports main restricted universe multiverse
deb ${MIRROR_URLS[$MIRROR]} $CODENAME-security main restricted universe multiverse
EOF
    ;;

centos|fedora|rhel)
    CENTOS_REPO="${REPO_DIR}/CentOS-Base.repo"
    backup_file "$CENTOS_REPO"

    declare -A BASE_URLS=(
        [ali]="http://mirrors.aliyun.com/centos/\$releasever/os/\$basearch/"
        [tencent]="http://mirrors.tencentyun.com/centos/\$releasever/os/\$basearch/"
        [huawei]="https://repo.huaweicloud.com/centos/\$releasever/os/\$basearch/"
        [ustc]="http://mirrors.ustc.edu.cn/centos/\$releasever/os/\$basearch/"
        [tsinghua]="https://mirrors.tuna.tsinghua.edu.cn/centos/\$releasever/os/\$basearch/"
    )

    sed -i -e "s|^mirrorlist=|#mirrorlist=|g" \
           -e "s|^#baseurl=|baseurl=|g" \
           -e "s|baseurl=.*|baseurl=${BASE_URLS[$MIRROR]}|g" \
           "$CENTOS_REPO"
    ;;

*)
    echo "不支持的发行版"
    exit 1
    ;;
esac

# 更新软件索引
echo -e "\n========== 更新软件源 =========="
case $PKG_CMD in
    apk)
        apk update 
        ;;
    apt)
        apt update -y
        ;;
    yum|dnf)
        $PKG_CMD clean all
        $PKG_CMD makecache
        ;;
esac

echo -e "\n[完成] 镜像源已成功更换为 $opt"
