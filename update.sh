#!/bin/ash
# 国内镜像源一键切换脚本（Ash兼容版）
# 支持系统：Alpine/CentOS/Debian/Ubuntu/Fedora/OpenSUSE
# 作者：Shell助手 最后更新：2025-02-25

# 函数：以红色显示错误信息并退出
error_exit() {
    printf "\033[31m[错误] %s\033[0m\n" "$1" >&2
    exit 1
}

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    error_exit "请使用sudo或以root用户运行此脚本"
fi

# 系统检测函数
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID}"
        OS_VERSION_CODENAME="${VERSION_CODENAME}"
        OS_VERSION_ID="${VERSION_ID%.*}"
    elif [ -f /etc/centos-release ]; then
        OS_ID="centos"
    elif [ -f /etc/alpine-release ]; then
        OS_ID="alpine"
    else
        error_exit "系统检测失败，请手动配置"
    fi

    # 显示检测结果
    printf "\n\033[34m[系统检测]\033[0m\n"
    echo "操作系统ID: $OS_ID"
    echo "版本代号: $OS_VERSION_CODENAME"
    echo "版本号: $OS_VERSION_ID"
}

# 备份文件函数
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        cp "$file" "${file}.bak.$(date +%Y%m%d%H%M%S)"
        echo "备份文件: ${file}.bak.$(date +%Y%m%d%H%M%S)"
    fi
}

# 定义镜像源选项
MIRROR1_NAME="阿里云"
MIRROR1_URL="https://mirrors.aliyun.com"
MIRROR2_NAME="华为云"
MIRROR2_URL="https://repo.huaweicloud.com"
MIRROR3_NAME="南京大学"
MIRROR3_URL="https://mirrors.nju.edu.cn"
MIRROR4_NAME="清华大学"
MIRROR4_URL="https://mirrors.tuna.tsinghua.edu.cn"
MIRROR5_NAME="腾讯云"
MIRROR5_URL="http://mirrors.cloud.tencent.com"
MIRROR6_NAME="网易"
MIRROR6_URL="http://mirrors.163.com"
MIRROR7_NAME="中国科学技术大学"
MIRROR7_URL="https://mirrors.ustc.edu.cn"

# 主流程开始
detect_os

# 显示镜像源菜单
printf "\n\033[34m[镜像源选择]\033[0m\n"
i=1
while [ $i -le 7 ]; do
    eval "mirror_name=\$MIRROR${i}_NAME"
    echo "$i. $mirror_name"
    i=$((i + 1))
done

# 获取用户输入
printf "请输入选项数字 (默认1): "
read choice
choice=${choice:-1}

# 验证输入有效性
case "$choice" in
    [1-7]) ;;
    *) error_exit "无效选项，请输入1-7之间的数字" ;;
esac

# 获取镜像名称和URL
eval "mirror_name=\$MIRROR${choice}_NAME"
eval "mirror_url=\$MIRROR${choice}_URL"

# 确定系统路径
case "$OS_ID" in
    alpine) os_path="alpine" ;;
    centos) os_path="centos" ;;
    debian) os_path="debian" ;;
    ubuntu) os_path="ubuntu" ;;
    fedora) os_path="fedora" ;;
    opensuse) os_path="opensuse" ;;
    *) error_exit "不支持的发行版：$OS_ID" ;;
esac

mirror_base="${mirror_url}/${os_path}"

# 配置处理函数
configure_sources() {
    case $OS_ID in
        ubuntu|debian)
            sources_file="/etc/apt/sources.list"
            backup_file "$sources_file"
            
            printf "\033[32m[配置APT源]\033[0m 使用镜像：%s\n" "$mirror_name"
            cat > "$sources_file" <<- EOF
# 主仓库
deb ${mirror_base}/ ${OS_VERSION_CODENAME} main restricted universe multiverse
# 安全更新
deb ${mirror_base}/ ${OS_VERSION_CODENAME}-security main restricted universe multiverse
# 软件更新
deb ${mirror_base}/ ${OS_VERSION_CODENAME}-updates main restricted universe multiverse
EOF
            ;;

        alpine)
            repo_file="/etc/apk/repositories"
            backup_file "$repo_file"
            
            printf "\033[32m[配置APK源]\033[0m 使用镜像：%s\n" "$mirror_name"
            cat > "$repo_file" <<- EOF
${mirror_base}/v${OS_VERSION_ID}/main
${mirror_base}/v${OS_VERSION_ID}/community
EOF
            ;;

        centos|rocky|almalinux)
            repo_file="/etc/yum.repos.d/${OS_ID}-Base.repo"
            backup_file "$repo_file"
            
            os_id_upper=$(echo "$OS_ID" | tr '[:lower:]' '[:upper:]')
            printf "\033[32m[配置YUM源]\033[0m 使用镜像：%s\n" "$mirror_name"
            cat > "$repo_file" <<- EOF
[base]
name=${OS_ID}-\$releasever - Base
baseurl=${mirror_base}/\$releasever/BaseOS/\$basearch/os/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-${os_id_upper}

[updates]
name=${OS_ID}-\$releasever - Updates
baseurl=${mirror_base}/\$releasever/Updates/\$basearch/os/
gpgcheck=1
EOF
            ;;

        fedora)
            repo_file="/etc/yum.repos.d/fedora.repo"
            backup_file "$repo_file"
            
            printf "\033[32m[配置DNF源]\033[0m 使用镜像：%s\n" "$mirror_name"
            cat > "$repo_file" <<- EOF
[fedora]
name=Fedora \$releasever - \$basearch
baseurl=${mirror_base}/releases/\$releasever/Everything/\$basearch/os/
gpgcheck=1
EOF
            ;;

        opensuse)
            repo_file="/etc/zypp/repos.d/oss.repo"
            backup_file "$repo_file"
            
            printf "\033[32m[配置ZYpp源]\033[0m 使用镜像：%s\n" "$mirror_name"
            cat > "$repo_file" <<- EOF
[oss]
name=openSUSE-\$releasever-Oss
baseurl=${mirror_base}/distribution/leap/\$releasever/repo/oss/
gpgcheck=1
EOF
            ;;

        *) error_exit "不支持的发行版：$OS_ID" ;;
    esac
}

# 执行配置
configure_sources

# 更新包索引
printf "\n\033[34m[更新软件源]\033[0m\n"
case $OS_ID in
    ubuntu|debian) apt update -y ;;
    alpine) apk update ;;
    centos|fedora|rocky|almalinux) yum clean all && yum makecache ;;
    opensuse) zypper refresh -f ;;
esac

printf "\n\033[32m[完成] 镜像源已切换至 %s\033[0m\n" "$mirror_name"
