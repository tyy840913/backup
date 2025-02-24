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
    [2]="北京外国语大学"
    [3]="重庆大学"
    [4]="中国科学技术大学"
    [5]="华为云"
    [6]="兰州大学"
    [7]="南京大学"
    [8]="网易"
    [9]="清华大学"
    [10]="上海交通大学"
    [11]="腾讯云"
    [12]="搜狐"
    [13]="浙江大学"
    [14]="中科院软件所"
    [15]="OPENTHOS"
)

# 镜像源基础URL映射
declare -A MIRROR_BASES=(
    [1]="http://mirrors.aliyun.com"                     # 阿里云
    [2]="https://mirrors.bfsu.edu.cn"                   # 北京外国语大学
    [3]="https://mirrors.cqu.edu.cn"                    # 重庆大学
    [4]="https://mirrors.ustc.edu.cn"                   # 中国科学技术大学
    [5]="https://repo.huaweicloud.com"                   # 华为云
    [6]="http://mirror.lzu.edu.cn"                       # 兰州大学
    [7]="https://mirrors.nju.edu.cn"                    # 南京大学
    [8]="http://mirrors.163.com"                         # 网易
    [9]="https://mirrors.tuna.tsinghua.edu.cn"          # 清华大学
    [10]="https://mirror.sjtu.edu.cn"                   # 上海交通大学
    [11]="http://mirrors.cloud.tencent.com"              # 腾讯云
    [12]="http://mirrors.sohu.com"                       # 搜狐
    [13]="http://mirrors.zju.edu.cn"                     # 浙江大学
    [14]="http://mirror.iscas.ac.cn"                     # 中科院软件所
    [15]="http://mirrors.openthos.com"                   # OPENTHOS
)

# 操作系统路径映射
declare -A OS_PATHS=(
    [almalinux]="almalinux"
    [alpine]="alpine"
    [arch]="archlinux"
    [centos]="centos"
    [clearlinux]="clearlinux"
    [debian]="debian"
    [fedora]="fedora"
    [gentoo]="gentoo"
    [kali]="kali"
    [opensuse]="opensuse"
    [raspbian]="raspbian"
    [rocky]="rocky"
    [rhel]="rhel"
    [slackware]="slackware"
    [solus]="solus"
    [ubuntu]="ubuntu"
    [void]="voidlinux"
)

# 显示镜像源菜单
echo "请选择镜像源（国内）："
for key in $(printf '%s\n' "${!MIRRORS[@]}" | sort -n); do
    echo "$key. ${MIRRORS[$key]}"
done

# 获取用户输入
read -p "请输入选项数字 (默认1): " choice
choice=${choice:-1}

# 验证输入有效性
if [[ ! $choice =~ ^([1-9]|1[0-5])$ ]]; then
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
        ubuntu|debian|kali|raspbian)
            apt update -y
            ;;
        alpine)
            apk update
            ;;
        centos|rhel|fedora|rocky|almalinux)
            yum clean all
            yum makecache
            ;;
        arch|manjaro)
            pacman -Syy
            ;;
        opensuse|sled)
            zypper refresh -f
            ;;
        gentoo)
            emerge --sync
            ;;
        void)
            xbps-install -S
            ;;
        solus)
            eopkg update-repo
            ;;
        clearlinux)
            swupd update
            ;;
        slackware)
            slackpkg update
            ;;
    esac
}

# 处理各发行版配置
case $OS_ID in
    ubuntu|debian|kali|raspbian)
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
        repo_file="/etc/apk/repositories"
        backup_file "$repo_file"
        cat > "$repo_file" <<- EOF
${mirror_base}/v${OS_VERSION_ID}/main
${mirror_base}/v${OS_VERSION_ID}/community
EOF
        ;;
        
    centos|rhel|rocky|almalinux)
        repo_file="/etc/yum.repos.d/${OS_ID}-Base.repo"
        backup_file "$repo_file"
        cat > "$repo_file" <<- EOF
[base]
name=${OS_ID}-\$releasever - Base
baseurl=${mirror_base}/\$releasever/BaseOS/\$basearch/os/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-${OS_ID^^}

[updates]
name=${OS_ID}-\$releasever - Updates
baseurl=${mirror_base}/\$releasever/Updates/\$basearch/os/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-${OS_ID^^}

[extras]
name=${OS_ID}-\$releasever - Extras
baseurl=${mirror_base}/\$releasever/Extras/\$basearch/os/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-${OS_ID^^}
EOF
        ;;
        
    fedora)
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
        
    arch|manjaro)
        mirror_file="/etc/pacman.d/mirrorlist"
        backup_file "$mirror_file"
        echo "Server = ${mirror_base}/\$repo/os/\$arch" > "$mirror_file"
        ;;
        
    opensuse|sled)
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
        mirror_file="/etc/portage/make.conf"
        backup_file "$mirror_file"
        echo "GENTOO_MIRRORS=\"${mirror_base}\"" >> "$mirror_file"
        ;;
        
    void)
        repo_file="/etc/xbps.d/mirror.conf"
        backup_file "$repo_file"
        echo "repository=${mirror_base}/current" > "$repo_file"
        ;;
        
    solus)
        repo_file="/etc/eopkg/repo.conf"
        backup_file "$repo_file"
        sed -i "s|^uri=.*|uri=${mirror_base}|" "$repo_file"
        ;;
        
    clearlinux)
        mirror_file="/etc/clear/mirror"
        backup_file "$mirror_file"
        echo "${mirror_base}" > "$mirror_file"
        ;;
        
    slackware)
        mirror_file="/etc/slackpkg/mirrors"
        backup_file "$mirror_file"
        echo "${mirror_base}/" > "$mirror_file"
        ;;
        
    *)
        echo "不支持的系统类型: $OS_ID"
        exit 1
        ;;
esac

# 更新包索引
update_package_manager
echo "操作完成"
