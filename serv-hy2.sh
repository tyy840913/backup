#!/bin/bash


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

# 处理每个服务器
for server in "${servers[@]}"; do
    # 解析服务器信息
    read -r subdomain username <<< "$server"
    host="$subdomain.serv00.com"
    
    echo -e "\n${YELLOW}##################################################${RESET}"
    echo -e "\n${BLUE}正在处理服务器: ${YELLOW}$username@$host${RESET}"
    
    # 检查hysteria2进程是否存在
    if sshpass -p "$password" ssh -p "$ssh_port" -o StrictHostKeyChecking=no "$username@$host" \
       "pgrep -x hysteria2 || ps aux | grep -i hysteria2 | grep -v grep" &>/dev/null; then
        echo -e "${YELLOW}服务器 $host 上已运行 hysteria2，跳过安装...${RESET}"
        continue
    fi
    
    echo -e "${GREEN}正在 $host 上安装 hysteria2...${RESET}"
    
    # 执行安装命令并过滤输出
    echo -e "${YELLOW}正在下载安装脚本，请稍候...${RESET}"
    sshpass -p "$password" ssh -p "$ssh_port" -o StrictHostKeyChecking=no "$username@$host" "$install_cmd" | \
    while IFS= read -r line; do
        if [[ "$line" == *"hysteria2://"* ]]; then
            echo -e "${GREEN}>>> 成功获取连接配置: \n$line${RESET}"
        fi
    done
    
    # 验证安装结果
    if sshpass -p "$password" ssh -p "$ssh_port" -o StrictHostKeyChecking=no "$username@$host" \
       "pgrep -x hysteria2" &>/dev/null; then
        echo -e "\n${GREEN}服务器 $host 上的 hysteria2 安装成功${RESET}"
    else
        echo -e "\n${RED}服务器 $host 上的 hysteria2 安装可能失败，请检查${RESET}"
    fi
done


echo -e "\n${BLUE}所有服务器处理完成${RESET}"
