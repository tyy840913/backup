#!/bin/bash

# 配置参数
BASE_URL="https://raw.githubusercontent.com/tyy840913/backup/main"
CACT_FILE="cact.txt"
PROXIES=(
    "https://cf-proxy.example.workers.dev/"  # 替换为有效代理
    "$BASE_URL/"  # 原始地址作为最后回退
)

# 颜色配置
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
MAGENTA='\033[1;35m'
CYAN='\033[1;36m'
NC='\033[0m' # 恢复默认

# 增强型内容获取
fetch_content() {
    local url=$1
    local content status_code
    
    for proxy in "${PROXIES[@]}"; do
        local proxy_url="${proxy}${url#$BASE_URL}"
        echo -e "${YELLOW}尝试代理: ${proxy_url//%/%%}${NC}"  # 处理特殊字符
        
        # 获取HTTP状态码和内容
        response=$(curl -fsSLw "\n%{http_code}" --connect-timeout 10 "$proxy_url" 2>/dev/null)
        [[ $? -ne 0 ]] && { echo -e "${RED}连接失败${NC}"; continue; }
        
        content=$(echo "$response" | head -n -1)
        status_code=$(echo "$response" | tail -n 1)
        
        # 验证响应
        if [[ $status_code == 200 ]] && [[ "$content" =~ \.sh ]]; then
            echo -e "${GREEN}获取成功 [HTTP $status_code]${NC}"
            echo "$content"
            return 0
        else
            echo -e "${RED}代理响应异常 [HTTP $status_code]${NC}"
            [[ "$content" =~ Cloudflare ]] && echo -e "${YELLOW}检测到Cloudflare拦截，请检查代理配置${NC}"
        fi
    done
    
    echo -e "${RED}所有代理尝试失败！${NC}"
    return 1
}

# 增强型脚本列表获取
get_scripts_list() {
    echo -e "${CYAN}正在获取脚本列表...${NC}"
    local content=$(fetch_content "$BASE_URL/$CACT_FILE") || {
        echo -e "${RED}错误：无法获取脚本列表${NC}"
        echo "可能原因："
        echo "1. 代理服务器配置错误（当前代理列表：${PROXIES[*]})"
        echo "2. 网络连接问题"
        echo "3. 资源不存在于 $BASE_URL"
        exit 1
    }
    
    # 强过滤机制
    filtered_content=$(echo "$content" | awk '
        BEGIN {count=0}
        {
            gsub(/^[ \t]+|[ \t]+$/, "");  # 移除首尾空白
            if (NF >= 2 && $NF ~ /\.sh$/) {  # 验证格式
                $1 = $1;  # 压缩中间空格
                print;
                count++
            }
        }
        END {
            if (count == 0) exit 1
        }') || {
            echo -e "${RED}错误：获取的列表格式异常${NC}"
            echo "预期格式示例："
            echo "自动备份 auto_backup.sh"
            echo "系统配置 init.sh"
            exit 1
        }
    
    echo "$filtered_content"
}

# 美化菜单显示
show_menu() {
    clear
    echo -e "${MAGENTA}"
    printf "╔══════════════════════════════════════╗\n"
    printf "║%34s║\n" " "
    printf "║   %b脚本管理中心%b   ║\n" "${BLUE}" "${MAGENTA}"
    printf "╠══════════════════════════════════════╣\n"
    
    local count=1
    while IFS= read -r line; do
        name=$(echo "$line" | awk '{for(i=1;i<NF;i++) printf $i " "; print ""}' | sed 's/ *$//')
        script=$(echo "$line" | awk '{print $NF}')
        
        printf "║ %b%-2d.%b %-25s ║\n" "${GREEN}" "$count" "${CYAN}" "$name"
        ((count++))
    done <<< "$SCRIPT_LIST"
    
    printf "╠══════════════════════════════════════╣\n"
    printf "║ %b 0. 退出系统%b                  ║\n" "${RED}" "${MAGENTA}"
    printf "╚══════════════════════════════════════╝\n"
    echo -e "${NC}"
}

# 安全执行子脚本
execute_script() {
    local selected_line=$(echo "$SCRIPT_LIST" | sed -n "${1}p")
    local script_name=$(echo "$selected_line" | awk '{print $NF}')
    local script_url="$BASE_URL/$script_name"
    
    echo -e "${YELLOW}正在下载: $script_name ...${NC}"
    local script_content=$(fetch_content "$script_url") || {
        echo -e "${RED}脚本下载失败${NC}"
        return 1
    }
    
    echo -e "${GREEN}执行中... (可能需要sudo权限)${NC}"
    echo "════════════════════════════════════"
    { 
        echo "#!/bin/bash"
        echo "$script_content"
    } | bash -s --
    local exit_code=$?
    echo "════════════════════════════════════"
    
    if [[ $exit_code -eq 0 ]]; then
        echo -e "${GREEN}执行成功，按回车返回菜单${NC}"
    else
        echo -e "${RED}执行失败，错误码: $exit_code${NC}"
    fi
    read -p ""
}

# 主程序
trap "echo -e '\n${RED}用户终止操作${NC}'; exit 1" SIGINT
SCRIPT_LIST=$(get_scripts_list) || exit 1

while true; do
    show_menu
    max_choice=$(echo "$SCRIPT_LIST" | wc -l)
    read -p "请输入选择 (0-${max_choice}): " choice
    
    # 输入验证
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        if (( choice == 0 )); then
            echo -e "${BLUE}感谢使用，再见！${NC}"
            exit 0
        elif (( choice > 0 && choice <= max_choice )); then
            execute_script $choice
            continue
        fi
    fi
    
    echo -e "${RED}无效输入，请输入0-${max_choice}之间的数字！${NC}"
    sleep 1
done
