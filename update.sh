#!/bin/bash
# 国内镜像源一键切换脚本
# 支持系统：Alpine/CentOS/Debian/Ubuntu/Fedora/OpenSUSE
# 作者：Shell助手 最后更新：2025-02-25

# 函数：以红色显示错误信息并退出
error_exit() {
    echo -e "\033[31m[错误] $1\033[0m" >&2
    exit 1
}

# 检查root权限
if [ "$(id -u)" -ne 0 ]; then
    error_exit "请使用sudo或以root用户运行此脚本"
fi

# 系统检测函数
detect_os() {
    if [ -f /etc/os-release ]; then
        source /etc/os-release
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
    echo -e "\n\033[34m[系统检测]\033[0m"
    echo "操作系统ID: $OS_ID"
    echo "版本代号: $OS_VERSION_CODENAME"
    echo "版本号: $OS_VERSION_ID"
}

# 备份文件函数
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        cp -v "$file" "${file}.bak.$(date +%Y%m%d%H%M%S)"
    fi
}

# 定义镜像源选项（按字母顺序排列）
declare -A MIRRORS=(
    [1]="阿里云"            # 国内最大云服务商[3,7](@ref)
    [2]="华为云"            # 企业级支持[3,5](@ref)
    [3]="南京大学"          # 教育网优选[7](@ref)
    [4]="清华大学"          # 更新及时[7,9](@ref)
    [5]="腾讯云"            # 云服务集成[5](@ref)
    [6]="网易"             # 老牌服务商[3](@ref)
    [7]="中国科学技术大学"   # 科研场景优选[7,9](@ref)
)

# 镜像源基础URL映射
declare -A MIRROR_BASES=(
    [1]="http://mirrors.aliyun.com"
    [2]="https://repo.huaweicloud.com"
    [3]="https://mirrors.nju.edu.cn"
    [4]="https://mirrors.tuna.tsinghua.edu.cn"
    [5]="http://mirrors.cloud.tencent.com"
    [6]="http://mirrors.163.com"
    [7]="https://mirrors.ustc.edu.cn"
)

# 操作系统路径映射（精简后）
declare -A OS_PATHS=(
    [alpine]="alpine"       # 特别保留[1,2](@ref)
    [centos]="centos"
    [debian]="debian"
    [ubuntu]="ubuntu"
    [fedora]="fedora"
    [opensuse]="opensuse"
)

# 主流程开始
detect_os

# 显示镜像源菜单
echo -e "\n\033[34m[镜像源选择]\033[0m"
for key in $(printf '%s\n' "${!MIRRORS[@]}" | sort -n); do
    echo "$key. ${MIRRORS[$key]}"
done

# 获取用户输入
read -p "请输入选项数字 (默认1): " choice
choice=${choice:-1}

# 验证输入有效性
if [[ ! $choice =~ ^[1-7]$ ]]; then
    error_exit "无效选项，请输入1-7之间的数字"
fi

# 获取基础镜像URL和操作系统路径
mirror_base="${MIRROR_BASES[$choice]}/${OS_PATHS[$OS_ID]}"

# 配置处理函数
configure_sources() {
    case $OS_ID in
        ubuntu|debian)
            # Debian系配置[1,2](@ref)
            sources_file="/etc/apt/sources.list"
            backup_file "$sources_file"
            
            echo -e "\033[32m[配置APT源]\033[0m 使用镜像：${MIRRORS[$choice]}"
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
            # Alpine配置[1,2](@ref)
            repo_file="/etc/apk/repositories"
            backup_file "$repo_file"
            
            echo -e "\033[32m[配置APK源]\033[0m 使用镜像：${MIRRORS[$choice]}"
            cat > "$repo_file" <<- EOF
${mirror_base}/v${OS_VERSION_ID}/main
${mirror_base}/v${OS_VERSION_ID}/community
# 边缘测试仓库
# ${mirror_base}/edge/main
EOF
            ;;

        centos|rocky|almalinux)
            # RHEL系配置[1,5](@ref)
            repo_file="/etc/yum.repos.d/${OS_ID}-Base.repo"
            backup_file "$repo_file"
            
            echo -e "\033[32m[配置YUM源]\033[0m 使用镜像：${MIRRORS[$choice]}"
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
EOF
            ;;

        fedora)
            # Fedora配置[5](@ref)
            repo_file="/etc/yum.repos.d/fedora.repo"
            backup_file "$repo_file"
            
            echo -e "\033[32m[配置DNF源]\033[0m 使用镜像：${MIRRORS[$choice]}"
            cat > "$repo_file" <<- EOF
[fedora]
name=Fedora \$releasever - \$basearch
baseurl=${mirror_base}/releases/\$releasever/Everything/\$basearch/os/
gpgcheck=1
EOF
            ;;

        opensuse)
            # OpenSUSE配置[5](@ref)
            repo_file="/etc/zypp/repos.d/oss.repo"
            backup_file "$repo_file"
            
            echo -e "\033[32m[配置ZYpp源]\033[0m 使用镜像：${MIRRORS[$choice]}"
            cat > "$repo_file" <<- EOF
[oss]
name=openSUSE-\$releasever-Oss
baseurl=${mirror_base}/distribution/leap/\$releasever/repo/oss/
gpgcheck=1
EOF
            ;;

        *)
            error_exit "不支持的发行版：$OS_ID"
            ;;
    esac
}

# 执行配置
configure_sources

# 更新包索引
echo -e "\n\033[34m[更新软件源]\033[0m"
case $OS_ID in
    ubuntu|debian) apt update -y ;;
    alpine) apk update ;;
    centos|fedora|rocky|almalinux) yum clean all && yum makecache ;;
    opensuse) zypper refresh -f ;;
esac

echo -e "\n\033[32m[完成] 镜像源已切换至 ${MIRRORS[$choice]}\033[0m"
