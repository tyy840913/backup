#!/bin/bash
# 捕获Ctrl+C立即强制退出
trap "exit 1" SIGINT

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
RESET="\033[0m"

# 服务器配置
servers=(
    "s9 woskee"
    "s9 wosker"
    "s10 woskev"
    "s11 woskep"
    "s13 woskeu"
    "s16 nki2t9df"
    "s15 wosleusrGraham"
)

password="JKiop84913"
ssh_port=22
install_cmd='UUID=aeb8c9cd-5350-4e17-9023-6ac6b7b1e1d0 bash -c "$(curl -sSL https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/hy2.sh)"'

# 检查sshpass是否安装
if ! command -v sshpass &> /dev/null; then
    echo -e "${RED}错误：未找到 sshpass 工具，请先安装："
    echo -e "Debian/Ubuntu系统: sudo apt-get install sshpass"
    echo -e "CentOS/RHEL系统: sudo yum install sshpass${RESET}"
    exit 1
fi

# 统一用户名大小写转换函数
normalize_username() {
    local username=$1
    echo "${username,,}"  # 统一转换为小写，域名不区分大小写
}

# 检查进程状态函数
check_process() {
    local username=$1
    local subdomain=$2
    local normalized_username=$(normalize_username "$username")
    
    local check_url="http://keep.${normalized_username}.serv00.net/list"
    local response=$(curl -s "$check_url")
    
    if echo "$response" | grep -q "hysteria2"; then
        return 0  # 进程存在
    else
        return 1  # 进程不存在
    fi
}

# 保活函数
keepalive() {
    local username=$1
    local subdomain=$2
    local normalized_username=$(normalize_username "$username")
    
    local primary_url="http://keep.${normalized_username}.serv00.net/${normalized_username}"
    local backup_url="http://keep.${normalized_username}.serv00.net/run"
    
    echo -e "\n${YELLOW}正在执行服务保活...${RESET}"
    
    # 检查主URL返回的JSON
    local response=$(curl -s "$primary_url")
    if [[ -z "$response" ]]; then
        response=$(curl -s "$backup_url")
    fi
    
    # 解析JSON响应
    local status=$(echo "$response" | jq -r '.status' 2>/dev/null)
    local message=$(echo "$response" | jq -r '.message' 2>/dev/null)
    
    # 检查JSON格式是否匹配
    if [[ "$status" == "running" && "$message" == "所有服务都正在运行" ]]; then
        echo -e "${GREEN}服务保活验证中........${RESET}"
        sleep 3
        if check_process "$username" "$subdomain"; then
            echo -e "${GREEN}>>>> 服务已正常运行 ${RESET}"
            return 0
        else
            echo -e "${RED}服务保活执行失败${RESET}"
            return 1
        fi
    else
        echo -e "${RED}服务保活响应不匹配${RESET}"
        return 1
    fi
}

# 检查网络连通性函数
check_connectivity() {
    local subdomain=$1
    local username=$2
    
    # 可能的子域名前缀
    local prefixes=("$subdomain" "cache${subdomain#s}" "web${subdomain#s}")
    local valid_host=""
    
    for prefix in "${prefixes[@]}"; do
        local host="${prefix}.serv00.com"
        if ping -c 1 -W 2 "$host" &> /dev/null; then
            valid_host="$host"
            break
        fi
    done
    
    echo "$valid_host"
}

# 处理每个服务器
for server in "${servers[@]}"; do
    # 解析服务器信息
    read -r subdomain username <<< "$server"
    
    echo -e "\n${YELLOW}**********************************${RESET}"
    
    echo -e "\n${BLUE}正在处理服务器: ${YELLOW}$username@$subdomain.serv00.com${RESET}"

    # 检查进程状态
    if check_process "$username" "$subdomain"; then
        echo -e "\n${GREEN}服务器 $subdomain 上已运行 hysteria2，跳过安装...${RESET}"
        continue
    fi
    
    # 尝试保活
    if keepalive "$username" "$subdomain"; then
        continue
    fi
    
    # 检查网络连通性
    valid_host=$(check_connectivity "$subdomain" "$username")
    if [[ -z "$valid_host" ]]; then
        echo -e "${RED}服务器 $subdomain 无法连通${RESET}"
        continue
    else
        echo -e "${GREEN}使用主机: $valid_host${RESET}"
    fi
    
    # 预先添加主机指纹到known_hosts
    ssh-keyscan -p $ssh_port $valid_host >> ~/.ssh/known_hosts 2>/dev/null

    # 安装hysteria2
        echo -e "${YELLOW}正在下载安装脚本，请稍候...${RESET}"
        sshpass -p "$password" ssh -p "$ssh_port" -o ConnectTimeout=10 -o ServerAliveInterval=60 -o StrictHostKeyChecking=no "$username@$valid_host" "$install_cmd" | \
        while IFS= read -r line; do
            if [[ "$line" == *"hysteria2://"* ]]; then
                echo -e "${GREEN}>>> 成功获取连接配置: \n\n$line${RESET}"
            fi
    done

    # 验证安装结果
    sleep 3  # 等待3秒让进程启动
    
    if check_process "$username" "$subdomain"; then
        echo -e "\n${GREEN}服务器 $valid_host 上的 hysteria2 安装成功${RESET}"
    else
        echo -e "\n${RED}服务器 $valid_host 上的 hysteria2 安装可能失败，请检查${RESET}"
    fi
done

echo -e "\n${BLUE}所有服务器处理完成${RESET}"
echo -e "\n${YELLOW}**********************************${RESET}"
