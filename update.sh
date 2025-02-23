#!/bin/bash

# 检查是否为root用户
if [ "$(id -u)" -ne 0 ]; then
    echo "请使用sudo或以root用户身份运行此脚本"
    exit 1
fi

# 检测系统信息
if [ -f /etc/os-release ]; then
    source /etc/os-release
    OS_ID="${ID}"
    OS_VERSION_CODENAME="${VERSION_CODENAME}"
    OS_VERSION_ID="${VERSION_ID%.*}"
elif [ -f /etc/redhat-release ]; then
    OS_ID="centos"
elif [ -f /etc/alpine-release ]; then
    OS_ID="alpine"
else
    echo "无法检测系统信息"
    exit 1
fi

# 输出系统检测信息
echo "检测到的系统信息："
echo "操作系统ID: $OS_ID"
echo "操作系统版本代号: $OS_VERSION_CODENAME"
echo "操作系统版本ID: $OS_VERSION_ID"
echo ""

# 定义镜像源选项（按名称正序排列）
declare -A MIRRORS=(
    [1]="阿里云"
    [2]="清华大学"
    [3]="中国科学技术大学"
    [4]="华为云"
    [5]="网易"
    [6]="腾讯云"
    [7]="搜狐"
    [8]="兰州大学"
)

# 镜像源基础URL映射
declare -A MIRROR_BASES=(
    [1]="http://mirrors.aliyun.com"
    [2]="https://mirrors.tuna.tsinghua.edu.cn"
    [3]="https://mirrors.ustc.edu.cn"
    [4]="https://repo.huaweicloud.com"
    [5]="http://mirrors.163.com"
    [6]="http://mirrors.cloud.tencent.com"
    [7]="http://mirrors.sohu.com"
    [8]="http://mirror.lzu.edu.cn"
)

# 操作系统路径映射
declare -A OS_PATHS=(
    [ubuntu]="ubuntu"
    [debian]="debian"
    [alpine]="alpine"
    [centos]="centos"
    [rhel]="centos"
    [fedora]="fedora"
    [arch]="archlinux"
    [opensuse]="opensuse"
    [kali]="kali"
    [gentoo]="gentoo"
)

# 显示镜像源菜单
echo "请选择国内镜像源："
for key in $(printf '%s\n' "${!MIRRORS[@]}" | sort -n); do
    echo "$key. ${MIRRORS[$key]}"
done

# 获取用户输入
read -p "请输入选项数字 (默认1): " choice
choice=${choice:-1}

# 验证输入有效性
if [[ ! $choice =~ ^[1-8]$ ]]; then
    echo "无效选项"
    exit 1
fi

# 获取基础镜像URL和操作系统路径
mirror_base="${MIRROR_BASES[$choice]}/${OS_PATHS[$OS_ID]}"

# 公共函数：备份文件
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        cp "$file" "${file}.bak.$(date +%Y%m%d%H%M%S)"
    fi
}

# 公共函数：更新包索引
update_package_manager() {
    case $OS_ID in
        ubuntu|debian|kali)
            apt update -y
            ;;
        alpine)
            apk update
            ;;
        centos|rhel|fedora)
            yum clean all
            yum makecache
            ;;
        arch)
            pacman -Syy
            ;;
        opensuse)
            zypper refresh -f
            ;;
        gentoo)
            emerge --sync
            ;;
    esac
}

# 处理各发行版配置
case $OS_ID in
    ubuntu|debian|kali)
        # 生成APT源配置
        mirror_url="${mirror_base}/"
        sources_file="/etc/apt/sources.list"
        
        backup_file "$sources_file"
        cat > "$sources_file" <<- EOF
deb ${mirror_url} ${OS_VERSION_CODENAME} main restricted universe multiverse
deb ${mirror_url} ${OS_VERSION_CODENAME}-updates main restricted universe multiverse
deb ${mirror_url} ${OS_VERSION_CODENAME}-backports main restricted universe multiverse
deb ${mirror_url} ${OS_VERSION_CODENAME}-security main restricted universe multiverse
deb-src ${mirror_url} ${OS_VERSION_CODENAME} main restricted universe multiverse
deb-src ${mirror_url} ${OS_VERSION_CODENAME}-updates main restricted universe multiverse
deb-src ${mirror_url} ${OS_VERSION_CODENAME}-backports main restricted universe multiverse
deb-src ${mirror_url} ${OS_VERSION_CODENAME}-security main restricted universe multiverse
EOF
        ;;
        
    alpine)
        # 生成Alpine源配置
        repo_file="/etc/apk/repositories"
        backup_file "$repo_file"
        cat > "$repo_file" <<- EOF
${mirror_base}/v${OS_VERSION_ID}/main
${mirror_base}/v${OS_VERSION_ID}/community
# ${mirror_base}/edge/main
# ${mirror_base}/edge/community
EOF
        ;;
        
    centos|rhel)
        # 生成YUM源配置
        repo_file="/etc/yum.repos.d/CentOS-Base.repo"
        backup_file "$repo_file"
        cat > "$repo_file" <<- EOF
[base]
name=CentOS-\$releasever - Base
baseurl=${mirror_base}/\$releasever/os/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-\$releasever

[updates]
name=CentOS-\$releasever - Updates
baseurl=${mirror_base}/\$releasever/updates/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-\$releasever

[extras]
name=CentOS-\$releasever - Extras
baseurl=${mirror_base}/\$releasever/extras/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-\$releasever

[centosplus]
name=CentOS-\$releasever - Plus
baseurl=${mirror_base}/\$releasever/centosplus/\$basearch/
gpgcheck=1
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-\$releasever
EOF
        ;;
        
    fedora)
        # 生成DNF源配置
        repo_file="/etc/yum.repos.d/fedora.repo"
        backup_file "$repo_file"
        cat > "$repo_file" <<- EOF
[fedora]
name=Fedora \$releasever - \$basearch
baseurl=${mirror_base}/releases/\$releasever/Everything/\$basearch/os/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-\$releasever

[updates]
name=Fedora \$releasever - \$basearch - Updates
baseurl=${mirror_base}/updates/\$releasever/Everything/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-\$releasever
EOF
        ;;
        
    arch)
        # 生成Pacman镜像列表
        mirror_file="/etc/pacman.d/mirrorlist"
        backup_file "$mirror_file"
        echo "Server = ${mirror_base}/\$repo/os/\$arch" > "$mirror_file"
        ;;
        
    opensuse)
        # 生成Zypper源配置
        repo_file="/etc/zypp/repos.d/oss.repo"
        backup_file "$repo_file"
        cat > "$repo_file" <<- EOF
[oss]
name=openSUSE-\$releasever-Oss
baseurl=${mirror_base}/distribution/leap/\$releasever/repo/oss/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-openSUSE

[update]
name=openSUSE-\$releasever-Update
baseurl=${mirror_base}/update/leap/\$releasever/oss/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-openSUSE
EOF
        ;;
        
    gentoo)
        # 生成Portage配置
        mirror_file="/etc/portage/make.conf"
        backup_file "$mirror_file"
        echo "GENTOO_MIRRORS=\"${mirror_base}\"" >> "$mirror_file"
        ;;
        
    *)
        echo "不支持的系统类型: $OS_ID"
        exit 1
        ;;
esac

# 更新包索引
update_package_manager
echo "操作完成"