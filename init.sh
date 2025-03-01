#!/bin/bash
# 系统配置自动化检查与修复脚本
# 支持：Debian/Ubuntu, CentOS/RHEL, Alpine Linux

RED='\033[31m'    # 错误
GREEN='\033[32m'  # 成功
YELLOW='\033[33m' # 警告
BLUE='\033[34m'   # 信息
NC='\033[0m'      # 颜色重置

# 精准检测系统发行版
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case $ID in
            debian|ubuntu) echo "debian" ;;
            centos|rhel)   echo "centos" ;;
            alpine)        echo "alpine" ;;
            *)             echo "unknown" ;;
        esac
    else
        echo "unknown"
    fi
}

# 服务管理抽象层
manage_service() {
    case $OS in
        debian|centos)
            systemctl $2 $1
            ;;
        alpine)
            rc-service $1 $2
            ;;
    esac
}

# SSH服务检查与配置（增强版）
check_ssh() {
    echo -e "\n${BLUE}=== SSH服务检查 ===${NC}"
    
    case $OS in
        debian)
            PKG="openssh-server"
            SERVICE="ssh"
            ;;
        centos)
            PKG="openssh-server"
            SERVICE="sshd"
            ;;
        alpine)
            PKG="openssh"
            SERVICE="sshd"
            ;;
    esac

    # 安装状态检查
    if ! command -v sshd &>/dev/null; then
        echo -e "${YELLOW}[SSH] 服务未安装，正在安装...${NC}"
        case $OS in
            debian) apt update && apt install -y $PKG ;;
            centos) yum install -y $PKG ;;
            alpine) apk add $PKG ;;
        esac || {
            echo -e "${RED}SSH安装失败，请检查网络连接${NC}"
            exit 1
        }
    fi

    # 自启动配置
    case $OS in
        debian|centos)
            if ! systemctl is-enabled $SERVICE &>/dev/null; then
                systemctl enable $SERVICE
            fi
            ;;
        alpine)
            if ! rc-update show | grep -q $SERVICE; then
                rc-update add $SERVICE
            fi
            ;;
    esac

    # 配置文件优化
    SSH_CONFIG="/etc/ssh/sshd_config"
    sed -i 's/#*PermitRootLogin.*/PermitRootLogin yes/' $SSH_CONFIG
    sed -i 's/#*PasswordAuthentication.*/PasswordAuthentication yes/' $SSH_CONFIG
    
    # 服务重启
    if ! manage_service $SERVICE restart; then
        echo -e "${RED}SSH服务重启失败${NC}"
        exit 1
    fi
    echo -e "${GREEN}[SSH] 服务已配置完成${NC}"
}

# 时区配置检查（增强版）
check_timezone() {
    echo -e "\n${BLUE}=== 时区检查 ===${NC}"
    TARGET_ZONE="Asia/Shanghai"
    ZONE_FILE="/usr/share/zoneinfo/${TARGET_ZONE}"
    
    # 检查时区文件是否存在
    if [ ! -f "$ZONE_FILE" ]; then
        echo -e "${RED}错误：时区文件 $ZONE_FILE 不存在${NC}"
        return 1
    fi

    # 优先尝试符号链接方式
    if [ -w /etc/localtime ]; then
        CURRENT_ZONE=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||')
        if [ "$CURRENT_ZONE" != "$TARGET_ZONE" ]; then
            echo -e "${YELLOW}当前时区: ${CURRENT_ZONE}, 正在配置为东八区...${NC}"
            ln -sf "$ZONE_FILE" /etc/localtime
        fi
    else
        echo -e "${YELLOW}无法创建符号链接，改用专用配置...${NC}"
        case $OS in
            debian|centos)
                timedatectl set-timezone $TARGET_ZONE
                ;;
            alpine)
                apk add --no-cache tzdata
                cp "$ZONE_FILE" /etc/localtime
                echo $TARGET_ZONE > /etc/timezone
                apk del tzdata
                ;;
        esac
    fi

    # 最终验证
    if [ "$(date +%Z)" == "CST" ]; then
        echo -e "${GREEN}时区已正确设置为东八区${NC}"
    else
        echo -e "${RED}时区配置异常，当前时区：$(date +%Z)${NC}"
        return 1
    fi
}

# 新增镜像测速功能
ping_mirror() {
    local domain=$1
    local timeout=2
    
    # 使用curl测试HTTP连接时间（兼容容器环境）
    if command -v curl &>/dev/null; then
        local start=$(date +%s%3N)
        if curl -sI --connect-timeout $timeout "${domain}" &>/dev/null; then
            local end=$(date +%s%3N)
            echo $((end - start))
        else
            echo 9999
        fi
    # 使用ping作为备选方案
    elif command -v ping &>/dev/null; then
        local result=$(ping -c 2 -W $timeout "$domain" 2>&1 | awk -F '/' 'END {print $5}')
        if [[ "$result" =~ ^[0-9.]+$ ]]; then
            echo "${result%.*}" 
        else
            echo 9999
        fi
    else
        echo 9999
    fi
}

# 镜像源列表与测速
select_fast_mirror() {
    declare -A mirrors
    local os_type=$1
    
    case $os_type in
        debian|ubuntu)
            mirrors=(
                [aliyun]="mirrors.aliyun.com"
                [tencent]="mirrors.cloud.tencent.com"
                [huawei]="repo.huaweicloud.com"
                [tsinghua]="mirrors.tuna.tsinghua.edu.cn"
                [ustc]="mirrors.ustc.edu.cn"
                [163]="mirrors.163.com"
                [njuitc]="mirrors.nju.edu.cn"
            ) ;;
        centos)
            mirrors=(
                [aliyun]="mirrors.aliyun.com"
                [tencent]="mirrors.cloud.tencent.com" 
                [huawei]="mirrors.huaweicloud.com"
                [tsinghua]="mirrors.tuna.tsinghua.edu.cn"
                [ustc]="mirrors.ustc.edu.cn"
                [163]="mirrors.163.com"
            ) ;;
        alpine)
            mirrors=(
                [aliyun]="mirrors.aliyun.com"
                [tencent]="mirrors.cloud.tencent.com"
                [huawei]="repo.huaweicloud.com"
                [tsinghua]="mirrors.tuna.tsinghua.edu.cn"
                [ustc]="mirrors.ustc.edu.cn"
                [bfsu]="mirrors.bfsu.edu.cn"
            ) ;;
    esac

    echo -e "${BLUE}正在测试镜像源响应速度...${NC}"
    declare -A speeds
    for name in "${!mirrors[@]}"; do
        local domain="${mirrors[$name]}"
        echo -n "测试 ${name} (${domain}) ... "
        local latency=$(ping_mirror "$domain")
        speeds["$name"]=$latency
        if [ $latency -eq 9999 ]; then
            echo -e "${RED}超时${NC}"
        else
            echo -e "${GREEN}${latency}ms${NC}"
        fi
    done

    # 按延迟排序并选择最快源
    local fastest="aliyun" # 默认值
    local min_latency=9999
    for name in "${!speeds[@]}"; do
        if [ ${speeds[$name]} -lt $min_latency ]; then
            min_latency=${speeds[$name]}
            fastest=$name
        fi
    done

    echo -e "\n${GREEN}最快镜像源: ${fastest} (${min_latency}ms)${NC}"
    echo "$fastest"
}

# 修改后的镜像源配置入口
replace_mirror_source() {
    echo -e "\n${BLUE}=== 镜像源更换 ===${NC}"
    local user_mirror=${1:-"auto"}  # 默认自动选择
    
    # 获取系统版本信息
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        CODENAME=$VERSION_CODENAME
        CENTOS_VER=$(rpm --eval %{rhel} 2>/dev/null || echo "unknown")
    fi

    # 自动测速逻辑
    if [ "$user_mirror" == "auto" ]; then
        local selected_mirror=$(select_fast_mirror $OS)
    else
        local selected_mirror=$user_mirror
    fi

    case $OS in
        debian|ubuntu)
            replace_debian_mirror "$selected_mirror" ;;
        centos)
            replace_centos_mirror "$selected_mirror" ;;
        alpine)
            replace_alpine_mirror "$selected_mirror" ;;
    esac || {
        echo -e "${RED}镜像源更换失败，已恢复备份${NC}"
        return 1
    }
}

# 修正后的Debian/Ubuntu镜像处理
replace_debian_mirror() {
    local mirror=$1
    local backup_file="/etc/apt/sources.list.bak"
    local security_path="debian-security"
    
    # 扩展镜像源选项
    declare -A mirror_urls=(
        [aliyun]="mirrors.aliyun.com"
        [tencent]="mirrors.cloud.tencent.com"
        [huawei]="repo.huaweicloud.com"
        [tsinghua]="mirrors.tuna.tsinghua.edu.cn"
        [ustc]="mirrors.ustc.edu.cn"
        [163]="mirrors.163.com"
        [njuitc]="mirrors.nju.edu.cn"
    )

    # 安全更新路径特殊处理
    declare -A security_urls=(
        [aliyun]="mirrors.aliyun.com/debian-security"
        [tencent]="mirrors.cloud.tencent.com/debian-security"
        [huawei]="repo.huaweicloud.com/debian-security"
        [tsinghua]="mirrors.tuna.tsinghua.edu.cn/debian-security"
        [ustc]="mirrors.ustc.edu.cn/debian-security"
        [163]="mirrors.163.com/debian-security"
        [njuitc]="mirrors.nju.edu.cn/debian-security"
    )

    # 参数检查
    if [ -z "${mirror_urls[$mirror]}" ]; then
        echo -e "${RED}不支持的Debian镜像源: $mirror${NC}"
        return 1
    fi

    local url=${mirror_urls[$mirror]}
    local security_url=${security_urls[$mirror]}

    # 生成源配置
    if [ "$ID" = "debian" ]; then
        cat <<EOF | sudo tee /etc/apt/sources.list >/dev/null
deb https://$url/debian/ $CODENAME main contrib non-free
deb-src https://$url/debian/ $CODENAME main contrib non-free

deb https://$url/debian/ $CODENAME-updates main contrib non-free
deb-src https://$url/debian/ $CODENAME-updates main contrib non-free

deb https://$url/debian/ $CODENAME-backports main contrib non-free
deb-src https://$url/debian/ $CODENAME-backports main contrib non-free

deb https://$security_url/ $CODENAME-security main contrib non-free
deb-src https://$security_url/ $CODENAME-security main contrib non-free
EOF
    else  # Ubuntu
        security_path="ubuntu-security"
        cat <<EOF | sudo tee /etc/apt/sources.list >/dev/null
deb https://$url/ubuntu/ $CODENAME main restricted universe multiverse
deb-src https://$url/ubuntu/ $CODENAME main restricted universe multiverse

deb https://$url/ubuntu/ $CODENAME-updates main restricted universe multiverse
deb-src https://$url/ubuntu/ $CODENAME-updates main restricted universe multiverse

deb https://$url/ubuntu/ $CODENAME-backports main restricted universe multiverse
deb-src https://$url/ubuntu/ $CODENAME-backports main restricted universe multiverse

deb https://$url/ubuntu/ $CODENAME-security main restricted universe multiverse
deb-src https://$url/ubuntu/ $CODENAME-security main restricted universe multiverse
EOF
    fi

    # 更新测试
    if ! sudo apt update; then
        sudo cp "$backup_file" /etc/apt/sources.list
        return 1
    fi
    echo -e "${GREEN}[APT] 已更换为 ${mirror} 镜像源${NC}"
}

# 修正后的CentOS镜像处理
replace_centos_mirror() {
    local mirror=$1
    local repo_file="/etc/yum.repos.d/CentOS-Base.repo"
    local backup_file="$repo_file.bak"
    
    declare -A mirror_urls=(
        [aliyun]="mirrors.aliyun.com/centos"
        [tencent]="mirrors.cloud.tencent.com/centos" 
        [huawei]="mirrors.huaweicloud.com/centos"
        [tsinghua]="mirrors.tuna.tsinghua.edu.cn/centos"
        [ustc]="mirrors.ustc.edu.cn/centos"
        [163]="mirrors.163.com/centos"
    )

    # 参数验证
    if [ -z "${mirror_urls[$mirror]}" ]; then
        echo -e "${RED}不支持的CentOS镜像源: $mirror${NC}"
        return 1
    fi

    local base_url="https://${mirror_urls[$mirror]}/\$releasever"
    
    # 备份源文件
    [ ! -f "$backup_file" ] && sudo cp "$repo_file" "$backup_file"

    # 生成新配置
    sudo sed -i -e "s|^mirrorlist=|#mirrorlist=|g" \
                -e "s|^#baseurl=http://mirror.centos.org|baseurl=$base_url|g" \
                "$repo_file"
    
    # 更新测试
    if ! sudo yum clean all || ! sudo yum makecache; then
        sudo mv "$backup_file" "$repo_file"
        return 1
    fi
    echo -e "${GREEN}[YUM] 已更换为 ${mirror} 镜像源${NC}"
}

# 增强的Alpine镜像处理
replace_alpine_mirror() {
    local mirror=$1
    local repo_file="/etc/apk/repositories"
    local backup_file="$repo_file.bak"
    
    declare -A mirror_urls=(
        [aliyun]="mirrors.aliyun.com/alpine"
        [tencent]="mirrors.cloud.tencent.com/alpine"
        [huawei]="repo.huaweicloud.com/alpine"
        [tsinghua]="mirrors.tuna.tsinghua.edu.cn/alpine"
        [ustc]="mirrors.ustc.edu.cn/alpine"
        [bfsu]="mirrors.bfsu.edu.cn/alpine"
    )

    # 参数检查
    if [ -z "${mirror_urls[$mirror]}" ]; then
        echo -e "${RED}不支持的Alpine镜像源: $mirror${NC}"
        return 1
    fi

    local new_url="https://${mirror_urls[$mirror]}"
    
    # 备份源文件
    [ ! -f "$backup_file" ] && sudo cp "$repo_file" "$backup_file"

    # 替换源
    sudo sed -i "s#https\?://dl-cdn.alpinelinux.org#$new_url#g" "$repo_file"
    
    # 更新测试
    if ! sudo apk update; then
        sudo mv "$backup_file" "$repo_file"
        return 1
    fi
    echo -e "${GREEN}[APK] 已更换为 ${mirror} 镜像源${NC}"
}

# 主程序
OS=$(detect_os)
if [ "$OS" == "unknown" ]; then
    echo -e "${RED}不支持的发行版${NC}"
    exit 1
fi

# 参数处理
while getopts "m:" opt; do
    case $opt in
        m) MIRROR=$OPTARG ;;
        *) ;;
    esac
done

replace_mirror_source "${MIRROR:-auto}"  # 默认自动选择最快源
check_ssh
check_timezone

echo -e "\n${GREEN}所有配置已完成，即将退出脚本！${NC}"
exit 0
