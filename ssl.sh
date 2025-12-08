#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置文件
CONFIG_DIR="$HOME/.acme_script"
CONFIG_FILE="$CONFIG_DIR/config"
ACME_DIR="$HOME/.acme.sh"
CERT_DIR="$CONFIG_DIR/certs"

# 初始化目录
init_directories() {
    mkdir -p "$CONFIG_DIR" "$CERT_DIR"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "DEFAULT_CA=letsencrypt" > "$CONFIG_FILE"
        echo "DEFAULT_MODE=manual" >> "$CONFIG_FILE"
        echo "DEFAULT_KEY_LENGTH=ec-256" >> "$CONFIG_FILE"
    fi
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
    if git clone https://github.com/acmesh-official/acme.sh.git "$ACME_DIR"; then
        cd "$ACME_DIR" || return 1
        ./acme.sh --install \
            --home "$ACME_DIR" \
            --config-home "$CONFIG_DIR" \
            --cert-home "$CERT_DIR" || {
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
find_all_certificates() {
    local certs=()
    local cert_dirs=()
    local index=1
    
    # 搜索所有可能的证书位置
    echo -e "${BLUE}[*] 搜索证书...${NC}" >&2
    
    # 首先搜索 ACME_DIR 目录
    if [ -d "$ACME_DIR" ]; then
        for cert_dir in "$ACME_DIR"/*; do
            if [ -d "$cert_dir" ]; then
                local dir_name=$(basename "$cert_dir")
                # 检查是否是证书目录
                if [[ "$dir_name" =~ _ecc$ ]] || [[ ! "$dir_name" =~ ^[0-9a-f]{32}$ ]]; then
                    local cert_domain=$(echo "$dir_name" | sed 's/_ecc$//')
                    
                    # 检查证书文件是否存在
                    local cert_file="$cert_dir/$cert_domain.cer"
                    local cert_file2="$cert_dir/$cert_domain.crt"
                    
                    if [ -f "$cert_file" ] && [ -f "$cert_dir/$cert_domain.key" ]; then
                        certs+=("$cert_domain")
                        cert_dirs+=("$cert_dir")
                        echo -e "${GREEN}[✓] 找到证书: $cert_domain (在acme.sh目录)${NC}" >&2
                    elif [ -f "$cert_file2" ] && [ -f "$cert_dir/$cert_domain.key" ]; then
                        certs+=("$cert_domain")
                        cert_dirs+=("$cert_dir")
                        echo -e "${GREEN}[✓] 找到证书: $cert_domain (在acme.sh目录)${NC}" >&2
                    fi
                fi
            fi
        done
    fi
    
    # 然后搜索 CERT_DIR 目录
    if [ -d "$CERT_DIR" ]; then
        for cert in "$CERT_DIR"/*; do
            if [ -d "$cert" ]; then
                local cert_name=$(basename "$cert")
                # 检查是否已经在列表中
                local found=0
                for existing_cert in "${certs[@]}"; do
                    if [ "$existing_cert" = "$cert_name" ]; then
                        found=1
                        break
                    fi
                done
                
                if [ $found -eq 0 ]; then
                    # 检查证书文件是否存在
                    local cert_file="$cert/$cert_name.cer"
                    local cert_file2="$cert/$cert_name.crt"
                    
                    if [ -f "$cert_file" ] || [ -f "$cert_file2" ]; then
                        certs+=("$cert_name")
                        cert_dirs+=("$cert")
                        echo -e "${GREEN}[✓] 找到证书: $cert_name (在certs目录)${NC}" >&2
                    fi
                fi
            fi
        done
    fi
    
    # 返回结果（通过全局变量）
    _CERT_ARRAY=("${certs[@]}")
    _CERT_DIR_ARRAY=("${cert_dirs[@]}")
    
    if [ ${#certs[@]} -eq 0 ]; then
        echo -e "${YELLOW}[!] 未找到任何证书${NC}" >&2
        return 1
    fi
    
    return 0
}

# 检查DNS记录
check_dns_record() {
    local domain="$1"
    local txt_record="$2"
    local max_attempts=36  # 3分钟，每5秒一次
    local attempt=1
    
    echo -e "${BLUE}[*] 开始检查DNS记录传播...${NC}"
    
    while [ $attempt -le $max_attempts ]; do
        echo -ne "${YELLOW}[!] 尝试 $attempt/$max_attempts...\r${NC}"
        
        # 使用多个DNS服务器检查
        local dns_servers=("8.8.8.8" "1.1.1.1" "1.0.0.1" "8.8.4.4")
        local success=0
        
        for dns_server in "${dns_servers[@]}"; do
            # 使用dig查询TXT记录，支持不同格式的输出
            local query_result
            query_result=$(dig +short TXT "_acme-challenge.$domain" @"$dns_server" 2>/dev/null)
            
            # 清理查询结果，移除引号
            local cleaned_result
            cleaned_result=$(echo "$query_result" | sed 's/"//g')
            
            # 检查是否包含TXT记录
            if [[ "$cleaned_result" == *"$txt_record"* ]]; then
                ((success++))
            fi
        done
        
        if [ $success -ge 2 ]; then
            echo -e "\n${GREEN}[✓] DNS记录已在 $success/$# DNS服务器生效${NC}"
            return 0
        fi
        
        sleep 5
        ((attempt++))
    done
    
    echo -e "\n${YELLOW}[!] DNS记录检查超时，可能还未完全传播${NC}"
    
    # 询问是否继续
    read -p "是否继续尝试验证？(y/n): " continue_anyway
    if [[ $continue_anyway =~ ^[Yy]$ ]]; then
        return 0
    else
        echo -e "${YELLOW}[!] 您可以选择稍后手动执行续期命令:${NC}"
        echo "  $ACME_DIR/acme.sh --renew -d $domain --force"
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

# 申请证书 - 优化版本
issue_certificate() {
    local domain="$1"
    local ca="$2"
    local mode="$3"
    local email="$4"
    
    echo -e "${BLUE}[*] 开始申请证书: $domain${NC}"
    
    if [ "$mode" = "manual" ]; then
        echo -e "${YELLOW}[!] 使用手动DNS验证模式${NC}"
        
        # 创建临时日志文件
        local log_file="/tmp/acme_manual_$(date +%s).log"
        
        echo -e "${BLUE}[*] 正在获取DNS验证信息...${NC}"
        echo -e "${YELLOW}[!] 请稍等，正在与证书颁发机构通信...${NC}"
        
        # 构建acme.sh命令
        local get_txt_cmd="$ACME_DIR/acme.sh --issue --dns -d $domain"
        
        if [ -n "$email" ]; then
            get_txt_cmd="$get_txt_cmd -m $email"
        fi
        
        get_txt_cmd="$get_txt_cmd --server $ca --yes-I-know-dns-manual-mode-enough-go-ahead-please --log-level 2"
        
        # 执行命令并保存日志
        echo -e "${BLUE}[*] 执行命令...${NC}"
        eval "$get_txt_cmd" 2>&1 | tee "$log_file"
        
        # 分析执行结果
        local exit_code=${PIPESTATUS[0]}
        
        # 从日志中提取TXT记录（多种可能的格式）
        local txt_record=""
        
        # 尝试多种匹配模式
        txt_record=$(grep -i "txt value:" "$log_file" | tail -1 | sed -n "s/.*TXT value:[[:space:]]*['\"]\?\([^'\"]*\)['\"]\?/\1/p")
        
        if [ -z "$txt_record" ]; then
            txt_record=$(grep -i "txt value:" "$log_file" | tail -1 | sed -n 's/.*TXT value:[[:space:]]*\([^[:space:]]*\).*/\1/p')
        fi
        
        if [ -z "$txt_record" ]; then
            txt_record=$(grep -i "txt record:" "$log_file" | tail -1 | sed -n "s/.*TXT record:[[:space:]]*['\"]\?\([^'\"]*\)['\"]\?/\1/p")
        fi
        
        # 删除日志文件
        rm -f "$log_file"
        
        # 如果无法提取TXT记录
        if [ -z "$txt_record" ]; then
            echo -e "${RED}[✗] 无法获取TXT记录值${NC}"
            echo -e "${YELLOW}[!] 可能的原因:${NC}"
            echo "  1. 域名已存在证书，无需重新验证"
            echo "  2. DNS记录已添加但未生效"
            echo "  3. 网络连接问题"
            echo ""
            
            # 尝试检查是否已有证书
            if [ -d "$ACME_DIR/${domain}_ecc" ] || [ -d "$ACME_DIR/$domain" ]; then
                echo -e "${YELLOW}[!] 检测到该域名可能已有证书${NC}"
                echo -e "${YELLOW}[!] 尝试续期现有证书...${NC}"
                local renew_cmd="$ACME_DIR/acme.sh --renew -d $domain --force"
                if [ "$ca" != "letsencrypt" ]; then
                    renew_cmd="$renew_cmd --server $ca"
                fi
                
                if eval "$renew_cmd"; then
                    echo -e "${GREEN}[✓] 证书续期成功${NC}"
                    return 0
                fi
            fi
            
            read -p "请输入手动获取的TXT记录值: " txt_record
            if [ -z "$txt_record" ]; then
                echo -e "${RED}[✗] 未提供TXT记录，终止申请${NC}"
                return 1
            fi
        fi
        
        # 显示TXT记录给用户
        echo -e "\n${GREEN}[✓] DNS验证信息获取成功${NC}"
        echo -e "${BLUE}==========================================${NC}"
        echo -e "${BLUE}主机名: _acme-challenge.$domain${NC}"
        echo -e "${BLUE}记录类型: TXT${NC}"
        echo -e "${BLUE}记录值: $txt_record${NC}"
        echo -e "${BLUE}==========================================${NC}"
        echo ""
        echo -e "${YELLOW}[!] 请到您的DNS服务商处添加上述TXT记录${NC}"
        echo -e "${YELLOW}[!] 添加完成后，等待1-2分钟让DNS生效${NC}"
        echo -e "${YELLOW}[!] 您可以使用以下命令检查DNS记录:${NC}"
        echo "  dig +short TXT _acme-challenge.$domain @8.8.8.8"
        echo "  nslookup -type=TXT _acme-challenge.$domain"
        echo ""
        
        # 合并等待提示，只询问一次
        read -p "DNS记录添加完成并等待生效后，按回车键继续验证..."
        
        # 检查DNS记录是否已生效
        if ! check_dns_record "$domain" "$txt_record"; then
            return 1
        fi
        
        # 步骤2：完成证书申请
        echo -e "\n${BLUE}[*] DNS验证通过，正在签发证书...${NC}"
        
        local renew_cmd="$ACME_DIR/acme.sh --renew -d $domain --force --yes-I-know-dns-manual-mode-enough-go-ahead-please"
        if [ "$ca" != "letsencrypt" ]; then
            renew_cmd="$renew_cmd --server $ca"
        fi
        
        echo -e "${YELLOW}[!] 执行命令: $renew_cmd${NC}"
        
        if eval "$renew_cmd"; then
            echo -e "${GREEN}[✓] 证书申请成功！${NC}"
            return 0
        else
            echo -e "${RED}[✗] 证书签发失败${NC}"
            return 1
        fi
        
    else
        # Cloudflare API自动验证（保持不变）
        echo -e "${YELLOW}[!] 使用Cloudflare API自动验证${NC}"
        
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
        
        local cmd="$ACME_DIR/acme.sh --issue --dns $dns_api -d $domain"
        cmd="$cmd --server $ca"
        
        if [ -n "$email" ]; then
            cmd="$cmd -m $email"
        fi
        
        echo -e "${BLUE}[*] 正在申请证书...${NC}"
        
        if eval "$cmd"; then
            echo -e "${GREEN}[✓] 证书申请成功${NC}"
            unset CF_Key CF_Email CF_Token 2>/dev/null
            return 0
        else
            echo -e "${RED}[✗] 证书申请失败${NC}"
            unset CF_Key CF_Email CF_Token 2>/dev/null
            return 1
        fi
    fi
}

# 查找证书文件 - 修复版
find_certificate_files() {
    local domain="$1"
    local cert_path="" key_path="" ca_path="" fullchain_path="" cert_dir=""
    
    # 搜索可能的所有证书位置
    local possible_dirs=(
        "$ACME_DIR/${domain}_ecc"
        "$ACME_DIR/$domain"
        "$CERT_DIR/$domain"
    )
    
    for test_dir in "${possible_dirs[@]}"; do
        if [ -d "$test_dir" ]; then
            # 检查标准证书文件
            local test_cert="$test_dir/$domain.cer"
            local test_key="$test_dir/$domain.key"
            
            if [ -f "$test_cert" ] && [ -f "$test_key" ]; then
                cert_path="$test_cert"
                key_path="$test_key"
                cert_dir="$test_dir"
                
                [ -f "$test_dir/ca.cer" ] && ca_path="$test_dir/ca.cer"
                [ -f "$test_dir/fullchain.cer" ] && fullchain_path="$test_dir/fullchain.cer"
                
                break
            fi
            
            # 检查.crt扩展名
            test_cert="$test_dir/$domain.crt"
            if [ -f "$test_cert" ] && [ -f "$test_key" ]; then
                cert_path="$test_cert"
                key_path="$test_key"
                cert_dir="$test_dir"
                
                [ -f "$test_dir/ca.crt" ] && ca_path="$test_dir/ca.crt"
                [ -f "$test_dir/fullchain.crt" ] && fullchain_path="$test_dir/fullchain.crt"
                
                break
            fi
        fi
    done
    
    # 如果没找到，尝试模糊查找
    if [ -z "$cert_path" ]; then
        # 查找所有可能的证书文件
        local cert_files=()
        while IFS= read -r -d '' file; do
            cert_files+=("$file")
        done < <(find "$ACME_DIR" -name "*$domain*.cer" -o -name "*$domain*.crt" 2>/dev/null | head -5)
        
        local key_files=()
        while IFS= read -r -d '' file; do
            key_files+=("$file")
        done < <(find "$ACME_DIR" -name "*$domain*.key" 2>/dev/null | head -5)
        
        if [ ${#cert_files[@]} -gt 0 ] && [ ${#key_files[@]} -gt 0 ]; then
            cert_path="${cert_files[0]}"
            key_path="${key_files[0]}"
            cert_dir=$(dirname "$cert_path")
            
            # 查找其他相关文件
            [ -f "$cert_dir/ca.cer" ] && ca_path="$cert_dir/ca.cer"
            [ -f "$cert_dir/ca.crt" ] && ca_path="$cert_dir/ca.crt"
            [ -f "$cert_dir/fullchain.cer" ] && fullchain_path="$cert_dir/fullchain.cer"
            [ -f "$cert_dir/fullchain.crt" ] && fullchain_path="$cert_dir/fullchain.crt"
        fi
    fi
    
    # 返回找到的路径（通过全局变量）
    _CERT_PATH="$cert_path"
    _KEY_PATH="$key_path"
    _CA_PATH="$ca_path"
    _FULLCHAIN_PATH="$fullchain_path"
    _CERT_DIR="$cert_dir"
}

# 证书申请子菜单（保持不变）
cert_issue_menu() {
    echo -e "\n${BLUE}=== 证书申请 ===${NC}"
    
    read -p "请输入域名: " domain
    if [ -z "$domain" ]; then
        echo -e "${RED}[✗] 域名不能为空${NC}"
        return 1
    fi
    
    echo "选择证书颁发机构："
    echo "1) Let's Encrypt (默认)"
    echo "2) ZeroSSL (需要注册)"
    echo "3) BuyPass"
    read -p "请选择(1-3): " ca_choice
    
    case $ca_choice in
        1|"") ca="letsencrypt" ;;
        2) ca="zerossl" ;;
        3) ca="buypass" ;;
        *) echo -e "${RED}[✗] 无效选择${NC}"; return 1 ;;
    esac
    
    echo "选择验证模式："
    echo "1) 手动DNS验证 (默认)"
    echo "2) DNS API自动验证"
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
    
    # 执行证书申请
    issue_certificate "$domain" "$ca" "$mode" "$email"
    
    if [ $? -eq 0 ]; then
        read -p "证书申请成功，是否立即安装？(y/n): " install_now
        if [[ $install_now =~ ^[Yy]$ ]]; then
            install_certificate_menu "$domain"
        fi
    fi
}

# 安装证书到Web服务 - 优化版
install_certificate_menu() {
    local domain="$1"
    
    if [ -z "$domain" ]; then
        echo -e "\n${BLUE}=== 安装证书 ===${NC}"
        
        # 使用统一的证书查找函数
        find_all_certificates
        
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
        find_certificate_files "$domain"
        cert_dir="$_CERT_DIR"
        
        # 获取到期时间
        local cert_file="$_CERT_PATH"
        expiry_date=""
        if [ -f "$cert_file" ]; then
            expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
        fi
    fi
    
    if [ -z "$cert_dir" ]; then
        find_certificate_files "$domain"
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
    
    echo "选择Web服务："
    echo "1) Nginx"
    echo "2) X-UI"
    echo "3) 自定义路径"
    read -p "请选择(1-3): " service_choice

    case $service_choice in
        1) # Nginx
            local nginx_conf="/etc/nginx/conf.d/$domain.conf"
            if [ ! -f "$nginx_conf" ]; then
                nginx_conf="/etc/nginx/sites-available/$domain"
            fi
            
            if [ ! -f "$nginx_conf" ]; then
                read -p "请输入Nginx配置文件路径: " nginx_conf
            fi
            
            if [ -f "$nginx_conf" ]; then
                cp "$nginx_conf" "$nginx_conf.bak"
                local cert_to_use="$cert_path"
                if [ -n "$fullchain_path" ]; then
                    cert_to_use="$fullchain_path"
                    echo -e "${GREEN}[✓] 使用完整链证书 (推荐)${NC}"
                fi
                
                sed -i "s|ssl_certificate .*|ssl_certificate $cert_to_use;|" "$nginx_conf"
                sed -i "s|ssl_certificate_key .*|ssl_certificate_key $key_path;|" "$nginx_conf"
                
                echo -e "${GREEN}[✓] Nginx配置已更新${NC}"
                echo -e "${YELLOW}[!] 请执行: nginx -t && systemctl reload nginx${NC}"
            else
                echo -e "${YELLOW}[!] Nginx配置文件不存在，证书文件位置:${NC}"
                echo "证书: $cert_path"
                [ -n "$fullchain_path" ] && echo "完整链证书: $fullchain_path"
                echo "私钥: $key_path"
            fi
            ;;
            
        2) # X-UI
            local xui_config="/etc/x-ui/config.json"
            if [ ! -f "$xui_config" ]; then
                xui_config="/usr/local/x-ui/config.json"
            fi
            
            if [ ! -f "$xui_config" ]; then
                read -p "请输入X-UI配置文件路径: " xui_config
            fi
            
            if [ -f "$xui_config" ]; then
                echo -e "${GREEN}[✓] 请手动更新X-UI配置:${NC}"
                echo "证书路径: $cert_path"
                [ -n "$fullchain_path" ] && echo "完整链证书: $fullchain_path"
                echo "私钥路径: $key_path"
                echo ""
                echo "在X-UI面板中："
                echo "1. 进入入站列表"
                echo "2. 编辑相关入站"
                echo "3. 在TLS设置中更新证书路径"
            else
                echo -e "${YELLOW}[!] X-UI配置文件不存在，证书文件位置:${NC}"
                echo "证书: $cert_path"
                [ -n "$fullchain_path" ] && echo "完整链证书: $fullchain_path"
                echo "私钥: $key_path"
            fi
            ;;
            
        3) # 自定义路径
            echo -e "${GREEN}[✓] 证书文件位置:${NC}"
            echo "证书: $cert_path"
            [ -n "$fullchain_path" ] && echo "完整链证书: $fullchain_path (推荐)"
            echo "私钥: $key_path"
            [ -f "$ca_path" ] && echo "CA证书: $ca_path"
            
            read -p "请输入目标证书路径: " target_cert
            read -p "请输入目标私钥路径: " target_key
            
            if [ -n "$target_cert" ]; then
                mkdir -p "$(dirname "$target_cert")"
                local source_cert="$cert_path"
                [ -n "$fullchain_path" ] && source_cert="$fullchain_path"
                cp "$source_cert" "$target_cert"
                chmod 644 "$target_cert"
                echo -e "${GREEN}[✓] 证书复制到: $target_cert${NC}"
            fi
            
            if [ -n "$target_key" ]; then
                mkdir -p "$(dirname "$target_key")"
                cp "$key_path" "$target_key"
                chmod 600 "$target_key"
                echo -e "${GREEN}[✓] 私钥复制到: $target_key${NC}"
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
    find_all_certificates
    
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
    find_all_certificates
    
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
    rm -rf "$CERT_DIR/$domain" 2>/dev/null
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
    find_all_certificates
    
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

# 重新安装acme.sh
reinstall_acme() {
    echo -e "\n${BLUE}=== 重新安装acme.sh ===${NC}"
    
    read -p "确定要重新安装acme.sh吗？(y/n): " confirm
    if ! [[ $confirm =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}[!] 取消重新安装${NC}"
        return 0
    fi
    
    local backup_dir="/tmp/acme_backup_$(date +%s)"
    mkdir -p "$backup_dir"
    cp -r "$CERT_DIR" "$backup_dir/certs"
    cp -r "$CONFIG_DIR" "$backup_dir/config"
    
    echo -e "${BLUE}[*] 卸载旧版本...${NC}"
    if [ -f "$ACME_DIR/acme.sh" ]; then
        "$ACME_DIR/acme.sh" --uninstall || true
    fi
    rm -rf "$ACME_DIR"
    
    echo -e "${BLUE}[*] 重新安装...${NC}"
    if install_acme; then
        echo -e "${BLUE}[*] 恢复证书...${NC}"
        cp -r "$backup_dir/certs"/* "$CERT_DIR/" 2>/dev/null || true
        cp -r "$backup_dir/config"/* "$CONFIG_DIR/" 2>/dev/null || true
        
        echo -e "${GREEN}[✓] acme.sh重新安装完成${NC}"
        rm -rf "$backup_dir"
        return 0
    else
        echo -e "${RED}[✗] 重新安装失败${NC}"
        echo -e "${YELLOW}[!] 备份文件保存在: $backup_dir${NC}"
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
