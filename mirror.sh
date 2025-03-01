#!/bin/bash
# 系统配置自动化检查与修复脚本
# 支持：Debian/Ubuntu, CentOS/RHEL, Alpine Linux

RED='\033[31m'    # 错误
GREEN='\033[32m'  # 成功
YELLOW='\033[33m' # 警告
BLUE='\033[34m'   # 信息
CYAN='\033[36m'   # 调试
NC='\033[0m'      # 颜色重置

# 镜像源配置信息
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

# 获取系统版本信息
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

# 镜像源速度测试函数
test_mirror_speed() {
    local mirror_name=$1
    local mirror_url=$2
    
    # 测试连接时间（秒）
    local connect_time=$(curl -o /dev/null -s -w "%{time_connect}\n" --connect-timeout 2 $mirror_url)
    if [[ $? -ne 0 || -z "$connect_time" ]]; then
        echo -e "${RED}连接失败${NC}"
        return 1
    fi
    
    # 测试下载速度（KB/s）
    local speed=$(curl -s -w "%{speed_download}\n" -o /dev/null --connect-timeout 2 $mirror_url | awk '{printf "%.2f", $1/1024}')
    
    # 综合评分（连接时间占20%，下载速度占80%）
    local score=$(awk -v ct="$connect_time" -v sp="$speed" 'BEGIN {print (1/(ct+0.1)*0.2 + sp*0.8)}')
    
    printf "%-8s | ${CYAN}%-7s${NC} | ${CYAN}%-9s${NC} | ${CYAN}%-8s${NC}\n" \
    "${MIRROR_SOURCES[$mirror_name]}" \
    "$(printf "%.2fms" $(echo "$connect_time*1000" | bc -l))" \
    "$(printf "%'.2f KB/s" $speed)" \
    "$(printf "%.2f" $score)"
    
    return 0
}

# 获取镜像源URL（修正后）
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

# 更换镜像源函数
change_repository() {
    echo -e "\n${BLUE}=== 镜像源速度检测 ===${NC}"
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
    echo -e "\n${BLUE}=== 更换镜像源 ===${NC}"
    case $OS in
        debian)
            sources_file="/etc/apt/sources.list"
            backup_file="/etc/apt/sources.list.bak"
            [ ! -f $backup_file ] && cp $sources_file $backup_file
            new_url=$(get_mirror_url $best_mirror)
            # 清空原有源并写入新源
            cat > $sources_file << EOF
deb ${new_url} ${CODENAME} main contrib non-free
deb ${new_url} ${CODENAME}-updates main contrib non-free
deb ${new_url}-security ${CODENAME}/updates main contrib non-free
EOF
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
baseurl=${new_url}/\$releasever/os/\$basearch/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial
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

# 主程序
OS=$(detect_os)
if [ "$OS" == "unknown" ]; then
    echo -e "${RED}不支持的发行版${NC}"
    exit 1
fi

get_os_info

change_repository

echo -e "\n${GREEN}所有配置已完成！${NC}"
exit 0
