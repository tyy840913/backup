#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置文件
ACME_DIR="$HOME/.acme.sh"

# 初始化目录
init_directories() {
    mkdir -p "$ACME_DIR"
}

# 检查并安装依赖
check_dependencies() {
    local dependencies=("curl" "socat" "openssl" "crontab" "idn")
    local missing=()
    
    echo -e "${BLUE}[*] 检查系统依赖...${NC}"
    
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -eq 0 ]; then
        echo -e "${GREEN}[✓] 所有依赖已安装${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}[!] 发现缺失依赖: ${missing[*]}${NC}"
    echo -e "${BLUE}[*] 尝试安装缺失依赖...${NC}"
    
    if command -v apt-get &> /dev/null; then
        apt-get update
        apt-get install -y "${missing[@]}" || {
            echo -e "${RED}[✗] 依赖安装失败${NC}"
            return 1
        }
    elif command -v yum &> /dev/null; then
        yum install -y "${missing[@]}" || {
            echo -e "${RED}[✗] 依赖安装失败${NC}"
            return 1
        }
    elif command -v dnf &> /dev/null; then
        dnf install -y "${missing[@]}" || {
            echo -e "${RED}[✗] 依赖安装失败${NC}"
            return 1
        }
    else
        echo -e "${RED}[✗] 无法确定包管理器，请手动安装: ${missing[*]}${NC}"
        return 1
    fi
    
    echo -e "${GREEN}[✓] 依赖安装完成${NC}"
    return 0
}

# 安装acme.sh
install_acme() {
    echo -e "${BLUE}[*] 检查acme.sh安装...${NC}"
    
    if [ -f "$ACME_DIR/acme.sh" ]; then
        echo -e "${GREEN}[✓] acme.sh已安装${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}[!] acme.sh未安装，开始安装...${NC}"
    
    # 尝试官方安装
    echo -e "${BLUE}[*] 尝试官方安装...${NC}"
    if curl https://get.acme.sh | sh; then
        echo -e "${GREEN}[✓] acme.sh安装成功${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}[!] 官方安装失败，尝试GitHub安装...${NC}"
    
    # 尝试GitHub安装
    if git clone https://gitclone.com/acmesh-official/acme.sh.git "$ACME_DIR"; then
        cd "$ACME_DIR" || return 1
        ./acme.sh --install \
            --home "$ACME_DIR" || {
            echo -e "${RED}[✗] GitHub安装失败${NC}"
            return 1
        }
        echo -e "${GREEN}[✓] acme.sh安装成功${NC}"
        return 0
    fi
    
    echo -e "${RED}[✗] acme.sh安装失败${NC}"
    return 1
}

# 统一的证书查找函数
find_certificates() {
    local target_domain="$1"  # 可选：如果指定域名，只查找该域名的文件
    
    # 清空所有全局变量
    _CERT_ARRAY=()
    _CERT_DIR_ARRAY=()
    _CERT_PATH=""
    _KEY_PATH=""
    _CA_PATH=""
    _FULLCHAIN_PATH=""
    _CERT_DIR=""
    
    # 搜索的目录顺序（按优先级）
    local search_roots=("$ACME_DIR")
    
    # 遍历所有搜索根目录
    for root_dir in "${search_roots[@]}"; do
        if [ ! -d "$root_dir" ]; then
            continue
        fi
        
        # 遍历根目录下的所有子目录
        for cert_dir in "$root_dir"/*; do
            if [ ! -d "$cert_dir" ]; then
                continue
            fi
            
            # 获取目录名并提取域名
            local dir_name=$(basename "$cert_dir")
            local domain=""
            
            # 简单的域名提取规则
            if [[ "$dir_name" =~ _ecc$ ]]; then
                domain="${dir_name%_ecc}"  # 去掉 _ecc 后缀
            else
                domain="$dir_name"  # 直接使用目录名
            fi
            
            # 检查是否有证书文件
            local cert_file=""
            if [ -f "$cert_dir/$domain.cer" ]; then
                cert_file="$cert_dir/$domain.cer"
            elif [ -f "$cert_dir/$domain.crt" ]; then
                cert_file="$cert_dir/$domain.crt"
            elif [ -f "$cert_dir/fullchain.cer" ]; then
                cert_file="$cert_dir/fullchain.cer"
            elif [ -f "$cert_dir/fullchain.crt" ]; then
                cert_file="$cert_dir/fullchain.crt"
            fi
            
            # 如果有证书文件
            if [ -n "$cert_file" ]; then
                # 如果指定了目标域名
                if [ -n "$target_domain" ]; then
                    if [ "$domain" = "$target_domain" ]; then
                        # 找到目标域名的证书
                        _CERT_DIR="$cert_dir"
                        _CERT_PATH="$cert_file"
                        
                        # 查找私钥
                        if [ -f "$cert_dir/$domain.key" ]; then
                            _KEY_PATH="$cert_dir/$domain.key"
                        fi
                        
                        # 查找CA证书
                        if [ -f "$cert_dir/ca.cer" ]; then
                            _CA_PATH="$cert_dir/ca.cer"
                        elif [ -f "$cert_dir/ca.crt" ]; then
                            _CA_PATH="$cert_dir/ca.crt"
                        fi
                        
                        # 查找完整链证书
                        if [ -f "$cert_dir/fullchain.cer" ]; then
                            _FULLCHAIN_PATH="$cert_dir/fullchain.cer"
                        elif [ -f "$cert_dir/fullchain.crt" ]; then
                            _FULLCHAIN_PATH="$cert_dir/fullchain.crt"
                        fi
                        
                        return 0  # 找到目标，直接返回
                    fi
                else
                    # 添加到证书列表
                    _CERT_ARRAY+=("$domain")
                    _CERT_DIR_ARRAY+=("$cert_dir")
                fi
            fi
        done
    done
    
    # 根据调用类型返回结果
    if [ -n "$target_domain" ]; then
        # 查找特定域名但没找到
        echo -e "${YELLOW}[!] 未找到域名 $target_domain 的证书${NC}" >&2
        return 1
    else
        # 查找所有证书
        if [ ${#_CERT_ARRAY[@]} -eq 0 ]; then
            echo -e "${YELLOW}[!] 未找到任何证书${NC}" >&2
            return 1
        fi
        return 0
    fi
}

# 检查DNS记录 - 支持通配符域名
check_dns_record() {
    local domain="$1"
    local txt_record="$2"
    local max_attempts=36
    local attempt=1
    
    echo -e "${BLUE}[*] 检查DNS记录: _acme-challenge.$domain${NC}"
    
    # 处理通配符域名
    local check_domain="_acme-challenge.$domain"
    if [[ "$domain" == **\** ]]; then
        # 如果是通配符域名，需要检查通配符记录
        check_domain="_acme-challenge.${domain#\*}"
        echo -e "${YELLOW}[!] 通配符域名检测: 实际检查 $check_domain${NC}"
    fi
    
    while [ $attempt -le $max_attempts ]; do
        echo -ne "${YELLOW}[!] 尝试 $attempt/$max_attempts...\r${NC}"
        
        local dns_servers=("8.8.8.8" "1.1.1.1" "1.0.0.1" "8.8.4.4")
        local success=0
        
        for dns_server in "${dns_servers[@]}"; do
            local query_result
            query_result=$(dig +short TXT "$check_domain" @"$dns_server" 2>/dev/null)
            
            local cleaned_result
            cleaned_result=$(echo "$query_result" | sed 's/"//g')
            
            if [[ "$cleaned_result" == *"$txt_record"* ]]; then
                ((success++))
            fi
        done
        
        if [ $success -ge 2 ]; then
            echo -e "\n${GREEN}[✓] DNS记录已在 $success/${#dns_servers[@]} 个DNS服务器生效${NC}"
            return 0
        fi
        
        sleep 5
        ((attempt++))
    done
    
    echo -e "\n${YELLOW}[!] DNS记录检查超时: $check_domain${NC}"
    
    read -p "是否继续尝试验证？(y/n): " continue_anyway
    if [[ $continue_anyway =~ ^[Yy]$ ]]; then
        return 0
    else
        echo -e "${YELLOW}[!] 您可以稍后手动执行续期:${NC}"
        echo "  $ACME_DIR/acme.sh --renew $domain_params --force"
        return 1
    fi
}

# 注册证书颁发机构
register_ca() {
    local ca="$1"
    local email="$2"
    
    case "$ca" in
        "letsencrypt")
            "$ACME_DIR/acme.sh" --register-account -m "$email" \
                --server letsencrypt || return 1
            ;;
        "zerossl")
            echo -e "${YELLOW}[!] ZeroSSL需要EAB凭证${NC}"
            read -p "请输入EAB Key ID: " eab_kid
            read -p "请输入EAB HMAC Key: " eab_hmac
            
            "$ACME_DIR/acme.sh" --register-account -m "$email" \
                --server zerossl \
                --eab-kid "$eab_kid" \
                --eab-hmac-key "$eab_hmac" || return 1
            ;;
        "buypass")
            "$ACME_DIR/acme.sh" --register-account -m "$email" \
                --server buypass || return 1
            ;;
        *)
            echo -e "${RED}[✗] 不支持的CA: $ca${NC}"
            return 1
            ;;
    esac
    
    echo -e "${GREEN}[✓] $ca 注册成功${NC}"
    return 0
}

# 申请证书 - 支持多域名版本
issue_certificate() {
    # 参数处理：最后一个参数是邮箱，倒数第二个是模式，倒数第三个是CA，其余都是域名
    local args=("$@")
    local total=${#args[@]}
    
    # 提取参数
    local email="${args[$((total-1))]}"
    local mode="${args[$((total-2))]}"
    local ca="${args[$((total-3))]}"
    
    # 提取所有域名
    local domains=()
    for ((i=0; i<$((total-3)); i++)); do
        domains+=("${args[$i]}")
    done
    
    # 获取主域名（第一个域名，用于显示和目录）
    local primary_domain="${domains[0]}"
    
    echo -e "${BLUE}[*] 开始申请证书${NC}"
    echo -e "${GREEN}[✓] 域名列表: ${NC}"
    for ((i=0; i<${#domains[@]}; i++)); do
        echo "  $((i+1)). ${domains[$i]}"
    done
    echo ""
    
    # 构建域名参数字符串
    local domain_params=""
    for domain in "${domains[@]}"; do
        domain_params="$domain_params -d $domain"
    done
    
    if [ "$mode" = "manual" ]; then
        echo -e "${YELLOW}[!] 使用手动DNS验证模式${NC}"
        echo -e "${YELLOW}[!] 注意：每个域名都需要单独添加DNS TXT记录${NC}"
        
        # 创建临时日志文件
        local log_file="/tmp/acme_manual_$(date +%s).log"
        
        echo -e "${BLUE}[*] 正在获取DNS验证信息...${NC}"
        
        # 构建acme.sh命令 - 包含所有域名
        local get_txt_cmd="$ACME_DIR/acme.sh --issue --dns $domain_params"
        
        if [ -n "$email" ]; then
            get_txt_cmd="$get_txt_cmd -m $email"
        fi
        
        get_txt_cmd="$get_txt_cmd --server $ca --yes-I-know-dns-manual-mode-enough-go-ahead-please --log-level 2"
        
        echo -e "${BLUE}[*] 执行命令...${NC}"
        eval "$get_txt_cmd" 2>&1 | tee "$log_file"
        
        local exit_code=${PIPESTATUS[0]}
        
        # 解析日志，获取每个域名的TXT记录
        declare -A domain_txt_records
        
        for domain in "${domains[@]}"; do
            # 从日志中提取该域名的TXT记录
            local txt_record=""
            
            # 尝试多种匹配模式
            txt_record=$(grep -i "domain: $domain" "$log_file" -A 5 | grep -i "txt value:" | head -1 | sed -n "s/.*TXT value:[[:space:]]*['\"]\?\([^'\"]*\)['\"]\?/\1/p")
            
            if [ -z "$txt_record" ]; then
                txt_record=$(grep -i "_acme-challenge.$domain" "$log_file" -A 3 | grep -i "txt value:" | head -1 | sed 's/.*TXT value:[[:space:]]*//' | tr -d '\"' | tr -d "'")
            fi
            
            if [ -z "$txt_record" ]; then
                echo -e "${YELLOW}[!] 无法自动获取域名 $domain 的TXT记录${NC}"
                read -p "请手动输入 _acme-challenge.$domain 的TXT记录值: " txt_record
            fi
            
            if [ -n "$txt_record" ]; then
                domain_txt_records["$domain"]="$txt_record"
            fi
        done
        
        rm -f "$log_file"
        
        # 显示所有域名的DNS验证信息
        echo -e "\n${GREEN}[✓] DNS验证信息获取成功${NC}"
        echo -e "${BLUE}==========================================${NC}"
        
        for domain in "${domains[@]}"; do
            local txt_record="${domain_txt_records[$domain]}"
            if [ -n "$txt_record" ]; then
                echo -e "${YELLOW}域名: $domain${NC}"
                echo -e "${YELLOW}记录类型: TXT${NC}"
                echo -e "${YELLOW}主机名:   _acme-challenge.$domain${NC}"
                echo -e "${YELLOW}记录值:   $txt_record${NC}"
                echo -e "${BLUE}------------------------------------------${NC}"
            fi
        done
        
        echo -e "${BLUE}==========================================${NC}"
        echo ""
        echo -e "${YELLOW}[!] 请为每个域名添加上述TXT记录${NC}"
        echo -e "${YELLOW}[!] 添加完成后，等待1-2分钟让DNS生效${NC}"
        echo ""
        
        read -p "DNS记录添加完成并等待生效后，按回车键继续验证..."
        
        # 检查所有域名的DNS记录
        for domain in "${domains[@]}"; do
            local txt_record="${domain_txt_records[$domain]}"
            if [ -n "$txt_record" ]; then
                echo -e "${BLUE}[*] 检查域名 $domain 的DNS记录...${NC}"
                if ! check_dns_record "$domain" "$txt_record"; then
                    echo -e "${RED}[✗] 域名 $domain 的DNS验证失败${NC}"
                    return 1
                fi
            fi
        done
        
        # 步骤2：完成证书申请
        echo -e "\n${BLUE}[*] 所有域名DNS验证通过，正在签发证书...${NC}"
        
        local renew_cmd="$ACME_DIR/acme.sh --renew $domain_params --force --yes-I-know-dns-manual-mode-enough-go-ahead-please"
        if [ "$ca" != "letsencrypt" ]; then
            renew_cmd="$renew_cmd --server $ca"
        fi
        
        echo -e "${YELLOW}[!] 执行命令: $renew_cmd${NC}"
        
        if eval "$renew_cmd"; then
            echo -e "${GREEN}[✓] 证书申请成功！${NC}"
            
            # 显示证书信息
            local clean_domain="${primary_domain//\*/_}"
            if find_certificates "$clean_domain"; then
                echo -e "${GREEN}[✓] 证书已保存到: ${NC}"
                echo "证书文件: $_CERT_PATH"
                [ -n "$_KEY_PATH" ] && echo "私钥文件: $_KEY_PATH"
                [ -n "$_FULLCHAIN_PATH" ] && echo "完整链证书: $_FULLCHAIN_PATH"
            fi
            
            return 0
        else
            echo -e "${RED}[✗] 证书签发失败${NC}"
            return 1
        fi
        
    else
        # Cloudflare API自动验证
        echo -e "${YELLOW}[!] 使用Cloudflare API自动验证${NC}"
        echo -e "${BLUE}[!] 提示：本脚本默认使用Cloudflare API${NC}"
        echo -e "${BLUE}[!] 如需使用其他DNS服务商，可以手动执行以下命令：${NC}"
        echo "  1. 查看支持的服务商列表："
        echo "     ls ~/.acme.sh/dnsapi/dns_*.sh"
        echo "  2. 设置对应API环境变量，可以参考dnsapi目录域名服务商脚本中的环境变量名设置，例如："
        echo "     # Cloudflare:"
        echo "     export CF_Token=\"your-token\"  # 或 CF_Key + CF_Email"
        echo "     # 阿里云:"
        echo "     export Ali_Key=\"your-key\""
        echo "     export Ali_Secret=\"your-secret\""
        echo "     # 腾讯云DNSPod:"
        echo "     export DP_Id=\"your-id\""
        echo "     export DP_Key=\"your-key\""
        echo "     # 华为云:"
        echo "     export HUAWEICLOUD_Username=\"username\""
        echo "     export HUAWEICLOUD_Password=\"password\""
        echo "     export HUAWEICLOUD_DomainName=\"domain\""
        echo "  3. 执行申请命令：<服务商为dnsapi中脚本的服务商名称，去除 ".sh">"
        echo "     ~/.acme.sh/acme.sh --issue --dns <服务商> -d example.com"
        echo "     # 例如："
        echo "     ~/.acme.sh/acme.sh --issue --dns dns_ali -d example.com"
        echo "     ~/.acme.sh/acme.sh --issue --dns dns_dp -d example.com"
  
        # Cloudflare API凭证输入
        read -p "请输入Cloudflare API Token: " cf_token
        
        if [ -z "$cf_token" ]; then
            echo -e "${YELLOW}[!] 尝试使用传统API Key...${NC}"
            read -p "请输入Cloudflare邮箱: " cf_email
            read -p "请输入Cloudflare Global API Key: " cf_key
            
            if [ -z "$cf_email" ] || [ -z "$cf_key" ]; then
                echo -e "${RED}[✗] Cloudflare API凭证不能为空${NC}"
                return 1
            fi
            
            export CF_Key="$cf_key"
            export CF_Email="$cf_email"
            dns_api="dns_cf"
        else
            export CF_Token="$cf_token"
            dns_api="dns_cf"
        fi
        
        # 构建包含所有域名的命令
        local cmd="$ACME_DIR/acme.sh --issue --dns $dns_api $domain_params"
        cmd="$cmd --server $ca"
        
        if [ -n "$email" ]; then
            cmd="$cmd -m $email"
        fi
        
        echo -e "${BLUE}[*] 正在申请证书...${NC}"
        echo -e "${YELLOW}[!] 命令: $cmd${NC}"
        
        if eval "$cmd"; then
            echo -e "${GREEN}[✓] 证书申请成功${NC}"
            unset CF_Key CF_Email CF_Token 2>/dev/null
            
            # 显示证书信息
            local clean_domain="${primary_domain//\*/_}"
            if find_certificates "$clean_domain"; then
                echo -e "${GREEN}[✓] 证书已保存到: ${NC}"
                echo "证书文件: $_CERT_PATH"
                [ -n "$_KEY_PATH" ] && echo "私钥文件: $_KEY_PATH"
                [ -n "$_FULLCHAIN_PATH" ] && echo "完整链证书: $_FULLCHAIN_PATH"
            fi
            
            return 0
        else
            echo -e "${RED}[✗] 证书申请失败${NC}"
            unset CF_Key CF_Email CF_Token 2>/dev/null
            return 1
        fi
    fi
}

# 证书申请子菜单 - 支持多域名
cert_issue_menu() {
    echo -e "\n${BLUE}=== 证书申请 ===${NC}"
    
    echo "请输入域名（支持多个域名，用空格分隔）："
    echo "示例："
    echo "  example.com                   # 单域名"
    echo "  example.com www.example.com   # 多个域名"
    echo "  *.example.com                 # 通配符域名"
    echo "  example.com api.example.com *.example.com  # 混合"
    echo ""
    read -p "请输入域名: " domain_input
    
    if [ -z "$domain_input" ]; then
        echo -e "${RED}[✗] 域名不能为空${NC}"
        return 1
    fi
    
    # 将输入转换为数组
    local domains=()
    for d in $domain_input; do
        domains+=("$d")
    done
    
    # 显示用户输入的域名
    echo -e "${GREEN}[✓] 您输入的域名: ${NC}"
    for ((i=0; i<${#domains[@]}; i++)); do
        echo "  $((i+1)). ${domains[$i]}"
    done
    echo ""
    
    # 选择CA（保持不变）
    echo "选择证书颁发机构："
    echo "1) Let's Encrypt (默认)"
    echo "2) ZeroSSL (需要注册)"
    echo "3) BuyPass"
    echo ""
    read -p "请选择(1-3): " ca_choice
    
    case $ca_choice in
        1|"") ca="letsencrypt" ;;
        2) ca="zerossl" ;;
        3) ca="buypass" ;;
        *) echo -e "${RED}[✗] 无效选择${NC}"; return 1 ;;
    esac
    
    # 选择验证模式（保持不变）
    echo "选择验证模式："
    echo "1) 手动DNS验证 (默认)"
    echo "2) DNS API自动验证"
    echo ""
    read -p "请选择(1-2): " mode_choice
    
    case $mode_choice in
        1|"") mode="manual" ;;
        2) mode="api" ;;
        *) echo -e "${RED}[✗] 无效选择${NC}"; return 1 ;;
    esac
    
    local email=""
    if [ "$ca" != "letsencrypt" ]; then
        read -p "请输入邮箱地址: " email
        if [ -z "$email" ]; then
            echo -e "${RED}[✗] $ca 需要邮箱地址${NC}"
            return 1
        fi
    else
        read -p "请输入邮箱地址 (可选，建议填写): " email
    fi
    
    # 执行证书申请（传入域名数组）
    issue_certificate "${domains[@]}" "$ca" "$mode" "$email"
    
    if [ $? -eq 0 ]; then
        # 使用主域名（第一个域名）进行后续操作
        local primary_domain="${domains[0]}"
        # 清理通配符符号用于查找目录
        local clean_domain="${primary_domain//\*/_}"
        
        read -p "证书申请成功，是否立即安装？(y/n): " install_now
        if [[ $install_now =~ ^[Yy]$ ]]; then
            install_certificate_menu "$clean_domain"
        fi
    fi
}

# 安装证书到Web服务 - 智能Nginx配置版
install_certificate_menu() {
    local domain="$1"
    
    if [ -z "$domain" ]; then
        echo -e "\n${BLUE}=== 安装证书 ===${NC}"
        
        # 使用统一的证书查找函数
        find_certificates
        
        if [ ${#_CERT_ARRAY[@]} -eq 0 ]; then
            echo -e "${YELLOW}[!] 没有找到证书${NC}"
            echo -e "${YELLOW}[!] 请先申请证书或检查acme.sh安装${NC}"
            return 1
        fi
        
        local certs=("${_CERT_ARRAY[@]}")
        local cert_dirs=("${_CERT_DIR_ARRAY[@]}")
        
        # 显示证书列表供选择
        for i in "${!certs[@]}"; do
            local cert_name="${certs[$i]}"
            local cert_dir="${cert_dirs[$i]}"
            local cert_file="$cert_dir/$cert_name.cer"
            if [ ! -f "$cert_file" ]; then
                cert_file="$cert_dir/$cert_name.crt"
            fi
            
            local expiry_date=""
            if [ -f "$cert_file" ]; then
                expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
            fi
            
            if [ -n "$expiry_date" ]; then
                echo "$((i+1))) $cert_name - 到期时间: $expiry_date"
            else
                echo "$((i+1))) $cert_name"
            fi
        done
        
        echo ""
        read -p "请选择要安装的证书序号: " selected_index
        if ! [[ "$selected_index" =~ ^[0-9]+$ ]] || [ "$selected_index" -lt 1 ] || [ "$selected_index" -gt ${#certs[@]} ]; then
            echo -e "${RED}[✗] 无效的序号${NC}"
            return 1
        fi
        
        domain="${certs[$((selected_index-1))]}"
        cert_dir="${cert_dirs[$((selected_index-1))]}"
        
        # 获取到期时间
        local cert_file="$cert_dir/$domain.cer"
        if [ ! -f "$cert_file" ]; then
            cert_file="$cert_dir/$domain.crt"
        fi
        
        expiry_date=""
        if [ -f "$cert_file" ]; then
            expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
        fi
    else
        # 查找指定域名的证书文件
        find_certificates "$domain"
        cert_dir="$_CERT_DIR"
        
        # 获取到期时间
        local cert_file="$_CERT_PATH"
        expiry_date=""
        if [ -f "$cert_file" ]; then
            expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
        fi
    fi
    
    if [ -z "$cert_dir" ]; then
        find_certificates "$domain"
        cert_dir="$_CERT_DIR"
    fi
    
    if [ -z "$cert_dir" ]; then
        echo -e "${RED}[✗] 无法找到证书: $domain${NC}"
        return 1
    fi
    
    cert_path="$_CERT_PATH"
    key_path="$_KEY_PATH"
    ca_path="$_CA_PATH"
    fullchain_path="$_FULLCHAIN_PATH"
    
    echo -e "\n${BLUE}安装证书: $domain${NC}"
    
    # 只显示到期时间（如果获取到的话）
    if [ -n "$expiry_date" ]; then
        echo -e "${GREEN}[✓] 证书到期时间: $expiry_date${NC}"
    fi
    
    # 显示证书文件信息
    echo -e "${BLUE}证书文件位置:${NC}"
    echo -e "  ${GREEN}证书:${NC} $cert_path"
    if [ -n "$fullchain_path" ]; then
        echo -e "  ${GREEN}完整链证书:${NC} $fullchain_path (推荐使用)"
    fi
    echo -e "  ${GREEN}私钥:${NC} $key_path"
    if [ -f "$ca_path" ]; then
        echo -e "  ${GREEN}CA证书:${NC} $ca_path"
    fi
    echo ""
    
    echo "选择安装方式："
    echo "1) Nginx (智能进程检测)"
    echo "2) 自定义路径 (仅输出证书路径)"
    read -p "请选择(1-2): " service_choice
    
    case $service_choice in
        1) # Nginx - 完全基于进程检测
            echo -e "${BLUE}[*] Nginx智能安装模式${NC}"
            
            # 获取所有Nginx进程
            echo -e "${BLUE}[*] 扫描Nginx进程...${NC}"
            
            # 获取详细的Nginx进程信息
            local nginx_processes
            nginx_processes=$(ps aux | grep -E "nginx: (master|worker)" | grep -v grep | sort -k2 -n)
            
            if [ -z "$nginx_processes" ]; then
                echo -e "${RED}[✗] 未找到运行的Nginx进程${NC}"
                echo -e "${YELLOW}[!] 请先启动Nginx或手动指定配置文件路径${NC}"
                read -p "是否手动指定Nginx配置文件路径？(y/n): " manual_path
                if [[ $manual_path =~ ^[Yy]$ ]]; then
                    read -p "请输入Nginx配置文件路径: " nginx_conf
                    if [ ! -f "$nginx_conf" ]; then
                        echo -e "${RED}[✗] 配置文件不存在: $nginx_conf${NC}"
                        return 1
                    fi
                else
                    return 1
                fi
            else
                # 提取master进程
                local master_processes=()
                local master_pids=()
                
                while IFS= read -r line; do
                    if [[ "$line" =~ nginx:\ master ]]; then
                        master_processes+=("$line")
                        local pid=$(echo "$line" | awk '{print $2}')
                        master_pids+=("$pid")
                    fi
                done <<< "$nginx_processes"
                
                echo -e "${GREEN}[✓] 找到 ${#master_processes[@]} 个Nginx主进程${NC}"
                
                # 如果只有一个master进程
                if [ ${#master_processes[@]} -eq 1 ]; then
                    local pid="${master_pids[0]}"
                    echo -e "${GREEN}[✓] 使用Nginx进程PID: $pid${NC}"
                    
                    # 从进程获取配置文件路径
                    local nginx_conf=""
                    if [ -f "/proc/$pid/cmdline" ]; then
                        local cmdline
                        cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ')
                        
                        # 提取-c参数指定的配置文件
                        if [[ "$cmdline" =~ -c[[:space:]]+([^[:space:]]+) ]]; then
                            nginx_conf="${BASH_REMATCH[1]}"
                            echo -e "${GREEN}[✓] 从进程获取配置文件: $nginx_conf${NC}"
                        else
                            # 如果没有-c参数，可能是默认配置
                            echo -e "${YELLOW}[!] 进程未指定配置文件，使用内置配置${NC}"
                            echo -e "${YELLOW}[!] 需要手动修改nginx.conf中的include配置${NC}"
                            
                            # 查找nginx二进制路径
                            local nginx_bin=""
                            if [[ "$cmdline" =~ ^([^[:space:]]*nginx[^[:space:]]*) ]]; then
                                nginx_bin="${BASH_REMATCH[1]}"
                            fi
                            
                            if [ -n "$nginx_bin" ] && [ -x "$nginx_bin" ]; then
                                # 使用nginx -t获取配置路径
                                local test_output
                                test_output=$("$nginx_bin" -t 2>&1)
                                if echo "$test_output" | grep -q "test is successful"; then
                                    nginx_conf=$(echo "$test_output" | grep -o "file .*" | sed 's/file //')
                                    if [ -n "$nginx_conf" ]; then
                                        echo -e "${GREEN}[✓] 从nginx -t获取配置文件: $nginx_conf${NC}"
                                    fi
                                fi
                            fi
                            
                            if [ -z "$nginx_conf" ]; then
                                # 让用户输入
                                read -p "请输入Nginx主配置文件路径: " nginx_conf
                            fi
                        fi
                    fi
                    
                else
                    # 多个master进程，让用户选择
                    echo -e "${BLUE}请选择要操作的Nginx实例:${NC}"
                    echo ""
                    
                    for i in "${!master_processes[@]}"; do
                        local pid="${master_pids[$i]}"
                        local process_info="${master_processes[$i]}"
                        local user=$(echo "$process_info" | awk '{print $1}')
                        local cmd=$(echo "$process_info" | cut -d' ' -f11- | cut -c1-80)
                        
                        # 获取配置文件路径
                        local config_path="(未指定)"
                        if [ -f "/proc/$pid/cmdline" ]; then
                            local cmdline
                            cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ')
                            if [[ "$cmdline" =~ -c[[:space:]]+([^[:space:]]+) ]]; then
                                config_path="${BASH_REMATCH[1]}"
                            fi
                        fi
                        
                        printf "  %2d) PID: %-6s 用户: %-8s 配置: %s\n" $((i+1)) "$pid" "$user" "$config_path"
                        echo "      命令行: $cmd"
                        echo ""
                    done
                    
                    read -p "请选择Nginx实例(1-${#master_processes[@]}): " selected_idx
                    
                    if ! [[ "$selected_idx" =~ ^[0-9]+$ ]] || [ "$selected_idx" -lt 1 ] || [ "$selected_idx" -gt ${#master_processes[@]} ]; then
                        echo -e "${RED}[✗] 无效的选择${NC}"
                        return 1
                    fi
                    
                    local selected_pid="${master_pids[$((selected_idx-1))]}"
                    echo -e "${GREEN}[✓] 选择PID: $selected_pid${NC}"
                    
                    # 获取配置文件
                    local nginx_conf=""
                    if [ -f "/proc/$selected_pid/cmdline" ]; then
                        local cmdline
                        cmdline=$(cat "/proc/$selected_pid/cmdline" 2>/dev/null | tr '\0' ' ')
                        if [[ "$cmdline" =~ -c[[:space:]]+([^[:space:]]+) ]]; then
                            nginx_conf="${BASH_REMATCH[1]}"
                            echo -e "${GREEN}[✓] 配置文件: $nginx_conf${NC}"
                        fi
                    fi
                    
                    if [ -z "$nginx_conf" ]; then
                        read -p "请输入该Nginx实例的配置文件路径: " nginx_conf
                    fi
                fi
            fi
            
            # 验证配置文件
            if [ ! -f "$nginx_conf" ]; then
                echo -e "${RED}[✗] 配置文件不存在: $nginx_conf${NC}"
                return 1
            fi
            
            echo -e "${GREEN}[✓] 确定使用配置文件: $nginx_conf${NC}"
            
            # 备份配置文件
            local backup_file="$nginx_conf.bak.$(date +%Y%m%d_%H%M%S)"
            cp "$nginx_conf" "$backup_file"
            echo -e "${GREEN}[✓] 配置文件已备份到: $backup_file${NC}"
            
            # 确定要使用的证书路径（优先使用完整链证书）
            local cert_to_use="$cert_path"
            if [ -n "$fullchain_path" ]; then
                cert_to_use="$fullchain_path"
                echo -e "${GREEN}[✓] 使用完整链证书 (推荐)${NC}"
            fi
            
            # 更新Nginx配置文件
            echo -e "${BLUE}[*] 更新Nginx配置文件...${NC}"
            
            # 处理通配符域名的目录名
            local clean_domain="${domain//\*/_}"
            
            # 使用更智能的方法更新配置文件
            local updated=0
            local temp_file="/tmp/nginx_update_$(date +%s).conf"
            
            # 读取并处理配置文件
            local in_server=0
            local server_block=""
            local server_start_line=0
            local output_content=""
            local line_num=0
            
            # 生成SSL配置块
            local ssl_config_block="\n    # SSL证书配置 - 由acme-ssl优化脚本自动添加 $(date '+%Y-%m-%d %H:%M:%S')\n"
            ssl_config_block+="    ssl_certificate $cert_to_use;\n"
            ssl_config_block+="    ssl_certificate_key $key_path;\n"
            ssl_config_block+="    ssl_protocols TLSv1.2 TLSv1.3;\n"
            ssl_config_block+="    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;\n"
            ssl_config_block+="    ssl_prefer_server_ciphers off;\n"
            ssl_config_block+="    ssl_session_cache shared:SSL:10m;\n"
            ssl_config_block+="    ssl_session_timeout 10m;\n"
            
            while IFS= read -r line || [ -n "$line" ]; do
                ((line_num++))
                
                # 检测server块开始
                if [[ "$line" =~ ^[[:space:]]*server[[:space:]]*\{ ]]; then
                    in_server=1
                    server_start_line=$line_num
                    server_block="$line"
                    output_content+="$line"$'\n'
                    continue
                fi
                
                # 如果在server块内
                if [ $in_server -eq 1 ]; then
                    server_block+="\n$line"
                    
                    # 检测server块结束
                    if [[ "$line" =~ ^[[:space:]]*\} ]]; then
                        in_server=0
                        
                        # 检查这个server块是否包含目标域名
                        if echo "$server_block" | grep -q -E "server_name.*[[:space:]]$domain[[:space:];]|server_name.*[[:space:]]$clean_domain[[:space:];]" ; then
                            echo -e "${GREEN}[✓] 在第 $server_start_line 行找到包含域名 $domain 的server块${NC}"
                            
                            # 处理server块中的SSL配置
                            local processed_block=""
                            local has_ssl_cert=0
                            local has_ssl_key=0
                            local has_ssl_block=0
                            
                            # 逐行处理server块
                            while IFS= read -r srv_line || [ -n "$srv_line" ]; do
                                # 检查是否已有SSL证书配置（包括被注释的）
                                if [[ "$srv_line" =~ ^[[:space:]]*#?[[:space:]]*ssl_certificate[[:space:]]+ ]]; then
                                    # 更新证书路径（取消注释）
                                    processed_block+="    ssl_certificate $cert_to_use;"$'\n'
                                    has_ssl_cert=1
                                elif [[ "$srv_line" =~ ^[[:space:]]*#?[[:space:]]*ssl_certificate_key[[:space:]]+ ]]; then
                                    # 更新私钥路径（取消注释）
                                    processed_block+="    ssl_certificate_key $key_path;"$'\n'
                                    has_ssl_key=1
                                elif [[ "$srv_line" =~ ^[[:space:]]*#?[[:space:]]*ssl_protocols[[:space:]]+ ]]; then
                                    # 更新SSL协议
                                    processed_block+="    ssl_protocols TLSv1.2 TLSv1.3;"$'\n'
                                    has_ssl_block=1
                                elif [[ "$srv_line" =~ ^[[:space:]]*\} ]]; then
                                    # server块结束，检查是否需要添加SSL配置
                                    if [ $has_ssl_cert -eq 0 ] || [ $has_ssl_key -eq 0 ]; then
                                        processed_block+="$ssl_config_block"
                                    fi
                                    processed_block+="$srv_line"$'\n'
                                else
                                    # 其他行原样保留
                                    processed_block+="$srv_line"$'\n'
                                fi
                            done < <(echo -e "$server_block")
                            
                            output_content+="$processed_block"
                            updated=1
                        else
                            # 不包含目标域名，原样输出
                            output_content+="$server_block"$'\n'
                        fi
                        
                        server_block=""
                        continue
                    fi
                else
                    # 不在server块中的行
                    output_content+="$line"$'\n'
                fi
            done < "$nginx_conf"
            
            # 将更新后的内容写入临时文件
            echo -e "$output_content" > "$temp_file"
            
            if [ $updated -eq 1 ]; then
                # 验证配置语法
                echo -e "${BLUE}[*] 验证配置语法...${NC}"
                if nginx -t -c "$temp_file" 2>/dev/null; then
                    # 替换原配置文件
                    mv "$temp_file" "$nginx_conf"
                    echo -e "${GREEN}[✓] Nginx配置文件更新成功${NC}"
                    
                    # 显示更新的配置部分
                    echo -e "${BLUE}[*] 更新的SSL配置:${NC}"
                    grep -n -A8 -B2 "ssl_certificate.*$(basename "$cert_to_use")\|由acme-ssl优化脚本" "$nginx_conf" | head -30
                    
                    # 重载Nginx（使用进程ID）
                    echo -e "\n${BLUE}[*] 重载Nginx服务...${NC}"
                    
                    local reload_success=0
                    local reloaded_pid=""
                    
                    # 尝试向所有匹配的Nginx进程发送HUP信号
                    if [ -n "$selected_pid" ]; then
                        # 如果有选中的进程ID
                        if kill -HUP "$selected_pid" 2>/dev/null; then
                            echo -e "${GREEN}[✓] Nginx重载成功 (向PID $selected_pid 发送HUP信号)${NC}"
                            reload_success=1
                            reloaded_pid="$selected_pid"
                        fi
                    else
                        # 尝试向所有master进程发送HUP信号
                        for pid in "${master_pids[@]}"; do
                            if kill -HUP "$pid" 2>/dev/null; then
                                echo -e "${GREEN}[✓] Nginx重载成功 (向PID $pid 发送HUP信号)${NC}"
                                reload_success=1
                                reloaded_pid="$pid"
                                break
                            fi
                        done
                    fi
                    
                    # 如果发送信号失败，尝试其他方式
                    if [ $reload_success -eq 0 ]; then
                        # 查找使用该配置文件的nginx二进制
                        local nginx_bin=""
                        if [ -n "$reloaded_pid" ] && [ -f "/proc/$reloaded_pid/exe" ]; then
                            nginx_bin=$(readlink -f "/proc/$reloaded_pid/exe")
                        fi
                        
                        if [ -n "$nginx_bin" ] && [ -x "$nginx_bin" ]; then
                            if "$nginx_bin" -s reload 2>/dev/null; then
                                echo -e "${GREEN}[✓] Nginx重载成功 (nginx -s reload)${NC}"
                                reload_success=1
                            fi
                        fi
                    fi
                    
                    if [ $reload_success -eq 0 ]; then
                        echo -e "${YELLOW}[!] 无法自动重载Nginx${NC}"
                        echo -e "${YELLOW}[!] 请手动执行重载命令:${NC}"
                        echo -e "    kill -HUP <nginx_master_pid>"
                        echo -e "    或 nginx -s reload"
                    fi
                    
                    echo -e "${GREEN}[✓] 证书安装完成！${NC}"
                    echo -e "${BLUE}[*] 证书文件已应用到Nginx配置${NC}"
                    echo -e "${BLUE}[*] 原始配置文件备份在: $backup_file${NC}"
                else
                    echo -e "${RED}[✗] 配置语法验证失败${NC}"
                    echo -e "${YELLOW}[!] 详细错误信息:${NC}"
                    nginx -t -c "$temp_file" 2>&1
                    echo -e "\n${YELLOW}[!] 配置文件未修改，备份在: $backup_file${NC}"
                    rm -f "$temp_file"
                    return 1
                fi
            else
                echo -e "${YELLOW}[!] 未找到包含域名 $domain 的server块${NC}"
                echo -e "${YELLOW}[!] 证书路径信息:${NC}"
                echo -e "  证书文件: $cert_to_use"
                echo -e "  私钥文件: $key_path"
                echo -e "${YELLOW}[!] 请手动修改Nginx配置${NC}"
                rm -f "$temp_file"
            fi
            ;;
            
        2) # 自定义路径（仅输出路径）
            echo -e "\n${BLUE}=== 证书路径信息 ===${NC}"
            echo -e "${GREEN}证书文件位置:${NC}"
            echo -e "  ${YELLOW}证书文件:${NC} $cert_path"
            
            if [ -n "$fullchain_path" ]; then
                echo -e "  ${YELLOW}完整链证书:${NC} $fullchain_path"
                echo -e "  ${GREEN}(推荐使用完整链证书，包含中间证书)${NC}"
            fi
            
            echo -e "  ${YELLOW}私钥文件:${NC} $key_path"
            
            if [ -f "$ca_path" ]; then
                echo -e "  ${YELLOW}CA证书:${NC} $ca_path"
            fi
            
            echo ""
            echo -e "${BLUE}使用示例:${NC}"
            echo "在Nginx配置中添加:"
            echo "  ssl_certificate $(basename "$cert_path");"
            echo "  ssl_certificate_key $(basename "$key_path");"
            
            if [ -n "$fullchain_path" ]; then
                echo ""
                echo -e "${GREEN}或使用完整链证书:${NC}"
                echo "  ssl_certificate $(basename "$fullchain_path");"
                echo "  ssl_certificate_key $(basename "$key_path");"
            fi
            ;;
            
        *)
            echo -e "${RED}[✗] 无效的选择${NC}"
            return 1
            ;;
    esac
    
    return 0
}

# 证书续期
renew_certificate() {
    echo -e "\n${BLUE}=== 证书续期 ===${NC}"
    
    # 使用统一的证书查找函数
    find_certificates
    
    if [ ${#_CERT_ARRAY[@]} -eq 0 ]; then
        echo -e "${YELLOW}[!] 没有找到证书${NC}"
        return 1
    fi
    
    local certs=("${_CERT_ARRAY[@]}")
    local cert_dirs=("${_CERT_DIR_ARRAY[@]}")
    
    # 显示证书列表（带到期时间）
    for i in "${!certs[@]}"; do
        local cert_name="${certs[$i]}"
        local cert_dir="${cert_dirs[$i]}"
        local cert_file="$cert_dir/$cert_name.cer"
        if [ ! -f "$cert_file" ]; then
            cert_file="$cert_dir/$cert_name.crt"
        fi
        
        local expiry_date=""
        if [ -f "$cert_file" ]; then
            expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
        fi
        
        if [ -n "$expiry_date" ]; then
            echo "$((i+1))) $cert_name - 到期时间: $expiry_date"
        else
            echo "$((i+1))) $cert_name"
        fi
    done
    
    echo ""
    read -p "请选择要续期的证书序号: " cert_index
    
    # 验证输入
    if [ -z "$cert_index" ] || ! [[ "$cert_index" =~ ^[0-9]+$ ]] || [ "$cert_index" -lt 1 ] || [ "$cert_index" -gt ${#certs[@]} ]; then
        echo -e "${RED}[✗] 无效的序号${NC}"
        return 1
    fi
    
    local domain="${certs[$((cert_index-1))]}"
    
    echo -e "${BLUE}[*] 续期证书: $domain${NC}"
    
    # 显示证书详情
    local cert_dir="${cert_dirs[$((cert_index-1))]}"
    local cert_file="$cert_dir/$domain.cer"
    if [ ! -f "$cert_file" ]; then
        cert_file="$cert_dir/$domain.crt"
    fi
    
    if [ -f "$cert_file" ]; then
        local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
        local start_date=$(openssl x509 -startdate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
        
        echo -e "${GREEN}[✓] 证书详情:${NC}"
        echo "域名: $domain"
        echo "开始时间: $start_date"
        echo "到期时间: $expiry_date"
        echo "证书位置: $cert_dir"
        echo ""
    fi
    
    echo -e "${YELLOW}[!] 即将开始证书续期...${NC}"
    read -p "是否继续？(y/n): " confirm
    if ! [[ $confirm =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}[!] 取消续期${NC}"
        return 0
    fi
    
    echo -e "${BLUE}[*] 正在续期证书...${NC}"
    
    # 执行续期
    if "$ACME_DIR/acme.sh" --renew --domain "$domain" --force; then
        echo -e "${GREEN}[✓] 证书续期成功${NC}"
        
        # 显示续期后的到期时间
        if [ -f "$cert_file" ]; then
            local new_expiry=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
            echo -e "${GREEN}[✓] 新到期时间: $new_expiry${NC}"
        fi
        
        return 0
    else
        echo -e "${RED}[✗] 证书续期失败${NC}"
        
        # 提供手动续期建议
        echo -e "${YELLOW}[!] 您可以尝试手动续期:${NC}"
        echo "  $ACME_DIR/acme.sh --renew -d $domain --force --debug"
        
        return 1
    fi
}

# 删除证书
delete_certificate() {
    echo -e "\n${BLUE}=== 删除证书 ===${NC}"
    
    # 使用统一的证书查找函数
    find_certificates
    
    if [ ${#_CERT_ARRAY[@]} -eq 0 ]; then
        echo -e "${YELLOW}[!] 没有找到证书${NC}"
        return 1
    fi
    
    local certs=("${_CERT_ARRAY[@]}")
    local cert_dirs=("${_CERT_DIR_ARRAY[@]}")
    local index=1
    
    # 显示证书列表
    for i in "${!certs[@]}"; do
        local cert_name="${certs[$i]}"
        local cert_dir="${cert_dirs[$i]}"
        local cert_file="$cert_dir/$cert_name.cer"
        if [ ! -f "$cert_file" ]; then
            cert_file="$cert_dir/$cert_name.crt"
        fi
        
        if [ -f "$cert_file" ]; then
            local expiry_date
            expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
            if [ -n "$expiry_date" ]; then
                echo "$index) $cert_name - 到期时间: $expiry_date - 位置: $(basename "$(dirname "$cert_dir")")/$(basename "$cert_dir")"
            else
                echo "$index) $cert_name - 位置: $(basename "$(dirname "$cert_dir")")/$(basename "$cert_dir")"
            fi
        else
            echo "$index) $cert_name - 位置: $(basename "$(dirname "$cert_dir")")/$(basename "$cert_dir")"
        fi
        ((index++))
    done
    
    echo ""
    read -p "请选择要删除的证书序号: " cert_index
    if ! [[ "$cert_index" =~ ^[0-9]+$ ]] || [ "$cert_index" -lt 1 ] || [ "$cert_index" -gt ${#certs[@]} ]; then
        echo -e "${RED}[✗] 无效的序号${NC}"
        return 1
    fi
    
    local domain="${certs[$((cert_index-1))]}"
    local cert_dir="${cert_dirs[$((cert_index-1))]}"
    
    read -p "确定要删除证书 $domain 吗？(y/n): " confirm
    if ! [[ $confirm =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}[!] 取消删除${NC}"
        return 0
    fi
    
    # 删除证书
    echo -e "${BLUE}[*] 删除证书: $domain${NC}"
    
    # 尝试使用acme.sh删除
    if "$ACME_DIR/acme.sh" --remove --domain "$domain" 2>/dev/null; then
        echo -e "${GREEN}[✓] 证书从acme.sh中移除${NC}"
    else
        echo -e "${YELLOW}[!] 无法通过acme.sh移除证书，尝试手动删除文件${NC}"
    fi
    
    # 清理所有可能的位置
    echo -e "${BLUE}[*] 清理证书文件...${NC}"
    rm -rf "$ACME_DIR/${domain}_ecc" 2>/dev/null
    rm -rf "$ACME_DIR/$domain" 2>/dev/null
    rm -rf "$cert_dir" 2>/dev/null
    
    echo -e "${GREEN}[✓] 证书删除成功${NC}"
    return 0
}

# 列出证书
list_certificates() {
    echo -e "\n${BLUE}=== 证书列表 ===${NC}"
    
    # 使用统一的证书查找函数
    find_certificates
    
    if [ ${#_CERT_ARRAY[@]} -eq 0 ]; then
        echo -e "${YELLOW}[!] 没有找到证书${NC}"
        return 1
    fi
    
    local certs=("${_CERT_ARRAY[@]}")
    local cert_dirs=("${_CERT_DIR_ARRAY[@]}")
    
    for i in "${!certs[@]}"; do
        local cert_name="${certs[$i]}"
        local cert_dir="${cert_dirs[$i]}"
        
        # 查找证书文件
        local cert_file="$cert_dir/$cert_name.cer"
        if [ ! -f "$cert_file" ]; then
            cert_file="$cert_dir/$cert_name.crt"
        fi
        
        if [ -f "$cert_file" ]; then
            local expiry_date
            expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
            
            local file_type="证书"
            if [[ "$cert_dir" == *"_ecc" ]]; then
                file_type="ECC证书"
            elif [ -f "$cert_dir/fullchain.cer" ] || [ -f "$cert_dir/fullchain.crt" ]; then
                file_type="完整链证书"
            fi
            
            if [ -n "$expiry_date" ]; then
                echo "$((i+1))) $cert_name - $file_type"
                echo "    到期时间: $expiry_date"
                echo "    位置: $(basename "$(dirname "$cert_dir")")/$(basename "$cert_dir")"
            else
                echo "$((i+1))) $cert_name - $file_type"
                echo "    位置: $(basename "$(dirname "$cert_dir")")/$(basename "$cert_dir")"
            fi
        else
            echo "$((i+1))) $cert_name"
            echo "    位置: $(basename "$(dirname "$cert_dir")")/$(basename "$cert_dir")"
        fi
        echo ""
    done
    
    return 0
}

# 重新安装acme.sh - 路径修复版
reinstall_acme() {
    echo -e "\n${BLUE}=== 重新安装acme.sh ===${NC}"
    
    read -p "确定要重新安装acme.sh吗？(y/n): " confirm
    if ! [[ $confirm =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}[!] 取消重新安装${NC}"
        return 0
    fi
    
    local backup_dir="/tmp/acme_backup_$(date +%s)"
    echo -e "${BLUE}[*] 创建备份目录: $backup_dir${NC}"
    mkdir -p "$backup_dir"
    
    echo -e "${BLUE}[*] 备份证书和配置...${NC}"
    
    # 备份 ~/.acme.sh/ 中的证书
    if [ -d "$ACME_DIR" ]; then
        echo -e "${BLUE}[*] 扫描acme.sh目录中的证书...${NC}"
        mkdir -p "$backup_dir/acme_certs_backup"
        
        # 查找所有可能的证书目录
        local cert_count=0
        for cert_dir in "$ACME_DIR"/*; do
            if [ -d "$cert_dir" ]; then
                local dir_name=$(basename "$cert_dir")
                # 排除acme.sh自身的目录
                if [[ ! "$dir_name" =~ ^(acme\.sh|\.git|ca)$ ]]; then
                    # 检查是否是证书目录（有.cer或.crt文件）
                    if ls "$cert_dir"/*.cer 1>/dev/null 2>&1 || ls "$cert_dir"/*.crt 1>/dev/null 2>&1; then
                        local domain_name=""
                        if [[ "$dir_name" =~ _ecc$ ]]; then
                            domain_name="${dir_name%_ecc}"
                        else
                            domain_name="$dir_name"
                        fi
                        
                        echo -e "${BLUE}  - 备份证书: $domain_name${NC}"
                        cp -r "$cert_dir" "$backup_dir/acme_certs_backup/" 2>/dev/null
                        ((cert_count++))
                    fi
                fi
            fi
        done
        
        if [ $cert_count -gt 0 ]; then
            echo -e "${GREEN}[✓] acme.sh证书备份成功 ($cert_count 个证书)${NC}"
        fi
    fi
    
    # 备份账户配置
    if [ -d "$ACME_DIR" ]; then
        echo -e "${BLUE}[*] 备份账户信息...${NC}"
        
        # 备份账户配置文件
        if [ -f "$ACME_DIR/account.conf" ]; then
            cp "$ACME_DIR/account.conf" "$backup_dir/" 2>/dev/null
            echo -e "${GREEN}[✓] 账户配置备份成功${NC}"
        fi
        
        # 备份ca目录
        if [ -d "$ACME_DIR/ca" ]; then
            cp -r "$ACME_DIR/ca" "$backup_dir/" 2>/dev/null
            echo -e "${GREEN}[✓] CA证书备份成功${NC}"
        fi
        
        # 备份httpd目录（如果有）
        if [ -d "$ACME_DIR/httpd" ]; then
            cp -r "$ACME_DIR/httpd" "$backup_dir/" 2>/dev/null
        fi
    fi
    
    echo -e "${BLUE}[*] 卸载旧版本...${NC}"
    if [ -f "$ACME_DIR/acme.sh" ]; then
        "$ACME_DIR/acme.sh" --uninstall 2>/dev/null || true
    fi
    
    # 删除acme.sh主目录，但保留证书目录
    echo -e "${BLUE}[*] 清理旧文件...${NC}"
    rm -rf "$ACME_DIR"
    echo -e "${GREEN}[✓] 清理完成${NC}"
    
    echo -e "${BLUE}[*] 重新安装acme.sh...${NC}"
    if install_acme; then
        echo -e "${GREEN}[✓] acme.sh安装成功${NC}"
        
        echo -e "${BLUE}[*] 恢复证书和配置...${NC}"
        
        # 恢复证书到 ~/.acme.sh/
        if [ -d "$backup_dir/acme_certs_backup" ] && [ -n "$(ls -A "$backup_dir/acme_certs_backup" 2>/dev/null)" ]; then
            echo -e "${BLUE}[*] 恢复证书到 $ACME_DIR...${NC}"
            mkdir -p "$ACME_DIR"
            
            for cert_dir in "$backup_dir/acme_certs_backup"/*; do
                if [ -d "$cert_dir" ]; then
                    local dir_name=$(basename "$cert_dir")
                    echo -e "${BLUE}  - 恢复: $dir_name${NC}"
                    
                    # 直接复制整个目录到acme.sh
                    cp -r "$cert_dir" "$ACME_DIR/" 2>/dev/null
                fi
            done
            echo -e "${GREEN}[✓] acme.sh证书恢复完成${NC}"
        fi
        
        # 恢复账户配置
        if [ -f "$backup_dir/account.conf" ]; then
            echo -e "${BLUE}[*] 恢复账户配置...${NC}"
            cp "$backup_dir/account.conf" "$ACME_DIR/" 2>/dev/null
            echo -e "${GREEN}[✓] 账户配置恢复完成${NC}"
        fi
        
        if [ -d "$backup_dir/ca" ]; then
            echo -e "${BLUE}[*] 恢复CA证书...${NC}"
            cp -r "$backup_dir/ca" "$ACME_DIR/" 2>/dev/null
            echo -e "${GREEN}[✓] CA证书恢复完成${NC}"
        fi
        
        # 清理备份
        rm -rf "$backup_dir"
        echo -e "${GREEN}[✓] 清理备份文件完成${NC}"
        
        # 验证恢复结果
        echo -e "${BLUE}[*] 验证证书恢复...${NC}"
        find_certificates
        
        if [ ${#_CERT_ARRAY[@]} -gt 0 ]; then
            echo -e "${GREEN}[✓] 证书恢复成功！找到 ${#_CERT_ARRAY[@]} 个证书${NC}"
            for cert in "${_CERT_ARRAY[@]}"; do
                echo -e "  - $cert"
            done
        else
            echo -e "${YELLOW}[!] 未找到证书，可能需要重新申请${NC}"
        fi
        
        echo -e "${GREEN}[✓] acme.sh重新安装完成${NC}"
        return 0
    else
        echo -e "${RED}[✗] 重新安装失败${NC}"
        echo -e "${YELLOW}[!] 备份文件保存在: $backup_dir${NC}"
        echo -e "${YELLOW}[!] 您可以手动恢复:${NC}"
        echo "  1. 检查备份: ls -la $backup_dir/"
        echo "  2. 重新运行脚本"
        return 1
    fi
}

# 主菜单
main_menu() {
    while true; do
        echo -e "\n${BLUE}=== ACME证书管理脚本 ===${NC}"
        echo "1) 申请证书"
        echo "2) 证书续期"
        echo "3) 删除证书"
        echo "4) 列出证书"
        echo "5) 安装证书到Web服务"
        echo "6) 重新安装acme.sh"
        echo "0) 退出"
        echo ""
        read -p "请选择操作(0-6): " choice
        
        case $choice in
            1) cert_issue_menu ;;
            2) renew_certificate ;;
            3) delete_certificate ;;
            4) list_certificates ;;
            5) install_certificate_menu ;;
            6) reinstall_acme ;;
            0) 
                echo -e "${GREEN}再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}[✗] 无效的选择${NC}"
                ;;
        esac
        
        echo -e "\n${YELLOW}按回车键继续...${NC}"
        read -r
    done
}

# 主程序
main() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${YELLOW}[!] 请使用sudo重新运行脚本${NC}"
        exit 1
    fi
    
    init_directories
    
    if ! check_dependencies; then
        echo -e "${RED}[✗] 依赖检查失败，请手动安装缺失的依赖${NC}"
        exit 1
    fi
    
    if ! install_acme; then
        echo -e "${RED}[✗] acme.sh安装失败${NC}"
        exit 1
    fi
    
    alias acme.sh="$ACME_DIR/acme.sh"
    
    main_menu
}

# 运行主程序
main
