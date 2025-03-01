 
#!/bin/bash
# 系统配置自动化检查与修复脚本
# 支持：Debian/Ubuntu, CentOS/RHEL, Alpine Linux

RED='\033[31m'    # 错误
GREEN='\033[32m'  # 成功
YELLOW='\033[33m' # 警告
BLUE='\033[34m'   # 信息
CYAN='\033[36m'   # 调试
NC='\033[0m'      # 颜色重置

# 镜像源配置信息（新增）
declare -A MIRROR_SOURCES=(
    ["aliyun"]="阿里云"
    ["tencent"]="腾讯云"
    ["huawei"]="华为云"
    ["netease"]="网易云"
    ["ustc"]="中科大"
)

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

# 获取系统版本信息（新增）
get_os_info() {
    case $OS in
        debian)
            if [ -f /etc/debian_version ]; then
                VERSION=$(sed 's/\..*//' /etc/debian_version)
                CODENAME=$(awk -F'[()]' '/VERSION=/ {print $2}' /etc/os-release)
            fi
            ;;
        centos)
            VERSION=$(rpm -E %{rhel})
            ;;
        alpine)
            VERSION=$(awk -F'.' '{print $1"."$2}' /etc/alpine-release)
            ;;
    esac
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

# 镜像源速度测试函数（新增）
test_mirror_speed() {
    local mirror_name=$1
    local mirror_url=$2
    
    # 测试连接时间（单位：毫秒）
    local connect_time=$(curl -o /dev/null -s -w "%{time_connect}\n" --connect-timeout 2 -x "" $mirror_url)
    if [[ $? -ne 0 || -z "$connect_time" ]]; then
        echo -e "${RED}连接失败${NC}"
        return 1
    fi
    
    # 测试下载速度（单位：KB/s）
    local speed=$(curl -s -w "%{speed_download}\n" -o /dev/null --connect-timeout 2 -x "" $mirror_url | awk '{printf "%.2f", $1/1024}')
    
    # 综合评分（连接时间权重40%，下载速度权重60%）
    local score=$(awk -v ct="$connect_time" -v sp="$speed" 'BEGIN {print (1000/(ct*1000)*0.4 + sp*0.6)}')
    
    printf "%-8s | ${CYAN}%-7s${NC} | ${CYAN}%-9s${NC} | ${CYAN}%-8s${NC}\n" \
    "${MIRROR_SOURCES[$mirror_name]}" \
    "$(awk -v ct="$connect_time" 'BEGIN {printf "%.2fms", ct*1000}')" \
    "$(printf "%'.2f KB/s" $speed)" \
    "$(printf "%.2f" $score)"
    
    return 0
}

# 获取镜像源URL（新增）
get_mirror_url() {
    local mirror=$1
    case $OS in
        debian)
            case $mirror in
                aliyun)   echo "https://mirrors.aliyun.com/debian/" ;;
                tencent)  echo "https://mirrors.tencent.com/debian/" ;;
                huawei)   echo "https://mirrors.huaweicloud.com/debian/" ;;
                netease)  echo "https://mirrors.163.com/debian/" ;;
                ustc)     echo "https://mirrors.ustc.edu.cn/debian/" ;;
            esac
            ;;
        ubuntu)
            case $mirror in
                aliyun)   echo "https://mirrors.aliyun.com/ubuntu/" ;;
                tencent)  echo "https://mirrors.tencent.com/ubuntu/" ;;
                huawei)   echo "https://mirrors.huaweicloud.com/ubuntu/" ;;
                netease)  echo "https://mirrors.163.com/ubuntu/" ;;
                ustc)     echo "https://mirrors.ustc.edu.cn/ubuntu/" ;;
            esac
            ;;
        centos)
            case $mirror in
                aliyun)   echo "https://mirrors.aliyun.com/centos/" ;;
                tencent)  echo "https://mirrors.tencent.com/centos/" ;;
                huawei)   echo "https://mirrors.huaweicloud.com/centos/" ;;
                netease)  echo "https://mirrors.163.com/centos/" ;;
                ustc)     echo "https://mirrors.ustc.edu.cn/centos/" ;;
            esac
            ;;
        alpine)
            case $mirror in
                aliyun)   echo "https://mirrors.aliyun.com/alpine/" ;;
                tencent)  echo "https://mirrors.tencent.com/alpine/" ;;
                huawei)   echo "https://mirrors.huaweicloud.com/alpine/" ;;
                netease)  echo "https://mirrors.163.com/alpine/" ;;
                ustc)     echo "https://mirrors.ustc.edu.cn/alpine/" ;;
            esac
            ;;
    esac
}

# 更换镜像源函数（新增）
change_repository() {
    echo -e "\n${BLUE}=== 开始镜像源速度检测 ===${NC}"
    echo -e "候选镜像源：${CYAN}${!MIRROR_SOURCES[@]}${NC}"
    echo -e "--------------------------------------------"
    printf "%-8s | %-7s | %-9s | %-8s\n" "镜像源" "延迟" "下载速度" "综合评分"
    
    declare -A results
    local test_urls=()
    
    # 生成测试URL列表
    for mirror in "${!MIRROR_SOURCES[@]}"; do
        base_url=$(get_mirror_url $mirror)
        case $OS in
            debian)
                test_url="${base_url}dists/${CODENAME}/Release"
                ;;
            centos)
                test_url="${base_url}${VERSION}/os/x86_64/repodata/repomd.xml"
                ;;
            alpine)
                test_url="${base_url}v${VERSION}/main/x86_64/APKINDEX.tar.gz"
                ;;
        esac
        test_urls+=("$test_url|$mirror")
    done

    # 并行测试
    local tmpfile=$(mktemp)
    for entry in "${test_urls[@]}"; do
        IFS='|' read -r test_url mirror <<< "$entry"
        ( 
            result=$(test_mirror_speed $mirror $test_url)
            if [ $? -eq 0 ]; then
                echo "$mirror|$result" >> $tmpfile
            fi
        ) &
    done
    wait
    
    # 收集结果
    while IFS='|' read -r mirror result; do
        [[ -n "$mirror" ]] && results["$mirror"]="$result"
    done < $tmpfile
    rm -f $tmpfile

    # 显示结果并选择最佳镜像源
    echo -e "--------------------------------------------"
    for mirror in "${!results[@]}"; do
        echo -e "${results[$mirror]}"
    done | sort -t '|' -k4 -nr
    
    local best_mirror=$(for mirror in "${!results[@]}"; do 
        echo "$mirror|${results[$mirror]}"
    done | sort -t '|' -k4 -nr | head -1 | cut -d'|' -f1)
    
    echo -e "\n${GREEN}最佳镜像源：${MIRROR_SOURCES[$best_mirror]}${NC}"

    # 执行镜像源更换
    echo -e "\n${BLUE}=== 开始更换镜像源 ===${NC}"
    case $OS in
        debian)
            sources_file="/etc/apt/sources.list"
            backup_file="/etc/apt/sources.list.bak"
            [ ! -f $backup_file ] && cp $sources_file $backup_file
            new_url=$(get_mirror_url $best_mirror)
            sed -i "s|http.*debian/|$new_url|g" $sources_file
            sed -i "s|https.*debian/|$new_url|g" $sources_file
            echo -e "${GREEN}Debian源已更新为：${new_url}${NC}"
            ;;
        centos)
            sources_dir="/etc/yum.repos.d/"
            backup_dir="/etc/yum.repos.d/backup/"
            mkdir -p $backup_dir && mv $sources_dir/CentOS-*.repo $backup_dir/
            new_url=$(get_mirror_url $best_mirror)
            cat << EOF > $sources_dir/CentOS-Base.repo
[base]
name=CentOS-\$releasever - Base
baseurl=${new_url}\$releasever/os/\$basearch/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-\$releasever
EOF
            echo -e "${GREEN}CentOS源已更新为：${new_url}${NC}"
            ;;
        alpine)
            sources_file="/etc/apk/repositories"
            backup_file="/etc/apk/repositories.bak"
            [ ! -f $backup_file ] && cp $sources_file $backup_file
            new_url=$(get_mirror_url $best_mirror)
            sed -i "s|http.*alpine|$new_url|g" $sources_file
            echo -e "${GREEN}Alpine源已更新为：${new_url}${NC}"
            apk update
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

# 主程序
OS=$(detect_os)
if [ "$OS" == "unknown" ]; then
    echo -e "${RED}不支持的发行版${NC}"
    exit 1
fi

get_os_info  # 新增调用

# 执行所有检查
check_ssh
check_timezone
change_repository  # 新增调用

echo -e "\n${GREEN}所有配置已完成，即将退出脚本！${NC}"
exit 0
