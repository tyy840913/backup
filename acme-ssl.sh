#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置文件
ACME_DIR="$HOME/.acme.sh"
ACME_BIN="$ACME_DIR/acme.sh"

# ========== 通用函数 ==========

# 打印消息函数
print_message() {
    local color="$1"
    local prefix="$2"
    local message="$3"
    echo -e "${color}${prefix} ${message}${NC}"
}

print_info() {
    print_message "$BLUE" "[*]" "$1"
}

print_success() {
    print_message "$GREEN" "[✓]" "$1"
}

print_warning() {
    print_message "$YELLOW" "[!]" "$1"
}

print_error() {
    print_message "$RED" "[✗✗✗✗]" "$1"
}

# 等待用户确认
wait_for_confirmation() {
    echo -e "${YELLOW}[!] 按回车键继续...${NC}"
    read -r
}

# 临时文件管理
TEMP_DIR=""
cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        print_info "清理临时目录: $TEMP_DIR"
    fi
}
trap cleanup EXIT INT TERM

create_temp_dir() {
    TEMP_DIR=$(mktemp -d "/tmp/acme_script_XXXXXX")
    print_info "创建临时目录: $TEMP_DIR"
}

# 初始化目录
init_directories() {
    mkdir -p "$ACME_DIR"
}

# ========== 依赖安装函数 ==========

# 安装命令依赖
install_command() {
    local cmd="$1"
    local pkg_name="${2:-$cmd}"
    
    print_info "安装依赖: $cmd"
    
    if command -v apt-get &> /dev/null; then
        # Debian/Ubuntu
        sudo apt-get update && sudo apt-get install -y "$pkg_name"
    elif command -v yum &> /dev/null; then
        # CentOS/RHEL
        sudo yum install -y "$pkg_name"
    elif command -v dnf &> /dev/null; then
        # Fedora
        sudo dnf install -y "$pkg_name"
    elif command -v apk &> /dev/null; then
        # Alpine
        sudo apk add "$pkg_name"
    elif command -v pacman &> /dev/null; then
        # Arch Linux
        sudo pacman -S --noconfirm "$pkg_name"
    else
        print_error "不支持的包管理器，请手动安装: $pkg_name"
        return 1
    fi
}

# 按需检查并安装命令
check_and_install_command() {
    local cmd="$1"
    local pkg_name="${2:-$cmd}"
    
    if command -v "$cmd" &> /dev/null; then
        return 0
    fi
    
    print_warning "命令不存在: $cmd"
    read -p "是否自动安装? (y/n): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        if install_command "$cmd" "$pkg_name"; then
            print_success "安装成功: $cmd"
            return 0
        else
            print_error "安装失败: $cmd"
            return 1
        fi
    else
        print_error "用户取消安装，脚本无法继续"
        return 1
    fi
}

# ========== 基础依赖检查（按需） ==========

# 检查openssl（证书操作需要）
check_openssl() {
    if ! command -v openssl &> /dev/null; then
        print_warning "openssl未安装，证书操作需要openssl"
        if ! check_and_install_command "openssl"; then
            return 1
        fi
    fi
    return 0
}

# 检查crontab（自动续期需要）
check_crontab() {
    if ! command -v crontab &> /dev/null; then
        print_warning "crontab未安装，自动续期需要crontab"
        if ! check_and_install_command "crontab" "cron"; then
            return 1
        fi
    fi
    return 0
}

# 检查curl（acme.sh安装需要）
check_curl() {
    if ! command -v curl &> /dev/null; then
        print_warning "curl未安装，acme.sh安装需要curl"
        if ! check_and_install_command "curl"; then
            return 1
        fi
    fi
    return 0
}

# 检查dig（DNS验证需要）
check_dig() {
    if ! command -v dig &> /dev/null; then
        print_warning "dig未安装，DNS验证需要dig"
        local pkg_name=""
        if command -v apt-get &> /dev/null; then
            pkg_name="dnsutils"
        elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then
            pkg_name="bind-utils"
        elif command -v apk &> /dev/null; then
            pkg_name="bind-tools"
        else
            pkg_name="dnsutils"
        fi
        
        if ! check_and_install_command "dig" "$pkg_name"; then
            return 1
        fi
    fi
    return 0
}

# ========== acme.sh管理 ==========

install_acme() {
    print_info "检查acme.sh安装..."
    
    if [ -f "$ACME_BIN" ]; then
        print_success "acme.sh已安装"
        return 0
    fi
    
    print_warning "acme.sh未安装，开始安装..."
    
    # 检查curl依赖
    if ! check_curl; then
        print_error "curl安装失败，无法安装acme.sh"
        return 1
    fi
    
    if curl -fsSL https://get.acme.sh | sh; then
        print_success "acme.sh安装成功"
        return 0
    fi
    
    print_error "acme.sh安装失败"
    return 1
}

# ========== 证书查找函数 ==========

# 查找证书文件
find_cert_file() {
    local cert_dir="$1"
    local domain="$2"
    
    local candidates=(
        "$cert_dir/$domain.cer"
        "$cert_dir/$domain.crt"
        "$cert_dir/$domain.pem"
        "$cert_dir/fullchain.cer"
        "$cert_dir/fullchain.crt"
        "$cert_dir/fullchain.pem"
        "$cert_dir/cert.pem"
        "$cert_dir/cert.cer"
        "$cert_dir/cert.crt"
    )
    
    for file in "${candidates[@]}"; do
        if [ -f "$file" ]; then
            echo "$file"
            return 0
        fi
    done
    
    return 1
}

# 查找私钥文件
find_key_file() {
    local cert_dir="$1"
    local domain="$2"
    
    local candidates=(
        "$cert_dir/$domain.key"
        "$cert_dir/privkey.pem"
        "$cert_dir/key.pem"
        "$cert_dir/private.key"
    )
    
    for file in "${candidates[@]}"; do
        if [ -f "$file" ]; then
            echo "$file"
            return 0
        fi
    done
    
    return 1
}

# 查找完整链证书文件
find_fullchain_file() {
    local cert_dir="$1"
    
    local candidates=(
        "$cert_dir/fullchain.cer"
        "$cert_dir/fullchain.crt"
        "$cert_dir/fullchain.pem"
    )
    
    for file in "${candidates[@]}"; do
        if [ -f "$file" ]; then
            echo "$file"
            return 0
        fi
    done
    
    return 1
}

# 查找CA证书文件
find_ca_file() {
    local cert_dir="$1"
    
    local candidates=(
        "$cert_dir/ca.cer"
        "$cert_dir/ca.crt"
        "$cert_dir/chain.pem"
        "$cert_dir/ca.pem"
        "$cert_dir/chain.crt"
    )
    
    for file in "${candidates[@]}"; do
        if [ -f "$file" ]; then
            echo "$file"
            return 0
        fi
    done
    
    return 1
}

# 获取所有证书
get_all_certificates() {
    local certs=()
    local cert_dirs=()
    
    if [ ! -d "$ACME_DIR" ]; then
        echo "CERTS:"
        echo "DIRS:"
        return 1
    fi
    
    for cert_dir in "$ACME_DIR"/*; do
        if [ -d "$cert_dir" ]; then
            local dir_name=$(basename "$cert_dir")
            
            # 排除acme.sh自身目录
            if [[ "$dir_name" =~ ^(acme\.sh|\.git|ca)$ ]]; then
                continue
            fi
            
            # 提取域名
            local domain="${dir_name%_ecc}"
            
            # 检查是否有证书文件
            if find_cert_file "$cert_dir" "$domain" > /dev/null; then
                certs+=("$domain")
                cert_dirs+=("$cert_dir")
            fi
        fi
    done
    
    # 使用换行符分隔输出，避免空格问题
    printf '%s\n' "CERTS:" "${certs[@]}"
    printf '%s\n' "DIRS:" "${cert_dirs[@]}"
}

# 解析get_all_certificates的输出
parse_certificates() {
    local output
    output=$(get_all_certificates)
    
    local certs=()
    local cert_dirs=()
    local line
    local section=""
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^CERTS: ]]; then
            section="certs"
        elif [[ "$line" =~ ^DIRS: ]]; then
            section="dirs"
        elif [ -n "$line" ] && [ -n "$section" ]; then
            if [ "$section" = "certs" ]; then
                certs+=("$line")
            elif [ "$section" = "dirs" ]; then
                cert_dirs+=("$line")
            fi
        fi
    done <<< "$output"
    
    printf '%s\n' "${certs[@]}" "${cert_dirs[@]}"
}

# 检查证书是否存在
check_cert_exists() {
    local domain="$1"
    
    local certs_dirs=($(parse_certificates))
    local count=${#certs_dirs[@]}
    local cert_count=$((count / 2))
    
    for ((i=0; i<cert_count; i++)); do
        if [ "${certs_dirs[$i]}" = "$domain" ]; then
            echo "${certs_dirs[$((i + cert_count))]}"
            return 0
        fi
    done
    
    return 1
}

# ========== 证书信息显示 ==========

show_cert_info() {
    local domain="$1"
    local cert_dir="$2"
    
    # 检查openssl依赖
    if ! check_openssl; then
        print_error "无法显示证书信息：openssl未安装"
        return 1
    fi
    
    print_info "证书目录: $cert_dir"
    echo ""
    
    # 查找文件
    local cert_file=$(find_cert_file "$cert_dir" "$domain")
    local key_file=$(find_key_file "$cert_dir" "$domain")
    local ca_file=$(find_ca_file "$cert_dir")
    local fullchain_file=$(find_fullchain_file "$cert_dir")
    
    # 显示文件路径
    if [ -n "$cert_file" ]; then
        echo -e "${YELLOW}证书文件:${NC}"
        echo "  $cert_file"
    fi
    
    if [ -n "$key_file" ]; then
        echo -e "${YELLOW}私钥文件:${NC}"
        echo "  $key_file"
    fi
    
    if [ -n "$ca_file" ]; then
        echo -e "${YELLOW}CA证书:${NC}"
        echo "  $ca_file"
    fi
    
    if [ -n "$fullchain_file" ]; then
        echo -e "${YELLOW}完整证书链:${NC}"
        echo "  $fullchain_file"
    fi
    
    # 显示证书信息
    if [ -n "$cert_file" ]; then
        echo ""
        echo -e "${YELLOW}证书详情:${NC}"
        openssl x509 -in "$cert_file" -noout -subject -issuer -dates 2>/dev/null || echo "  (无法读取证书信息)"
        
        # 计算剩余天数
        local expiry_date
        expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
        if [ -n "$expiry_date" ]; then
            local now_seconds=$(date +%s)
            local expiry_seconds=$(date -d "$expiry_date" +%s 2>/dev/null || date +%s)
            if [ "$expiry_seconds" -gt "$now_seconds" ]; then
                local days_left=$(( (expiry_seconds - now_seconds) / 86400 ))
                echo "  剩余天数: $days_left 天"
            else
                echo "  证书已过期"
            fi
        fi
    fi
    
    echo ""
}

# ========== DNS检查 ==========

check_dns_record() {
    local domain="$1"
    local txt_record="$2"
    
    # 检查dig依赖
    if ! check_dig; then
        print_error "DNS检查失败：dig未安装"
        return 1
    fi
    
    local check_domain="_acme-challenge.$domain"
    if [[ "$domain" == *"*"* ]]; then
        check_domain="_acme-challenge.${domain#\*}"
    fi
    
    print_info "检查DNS记录: $check_domain"
    
    local dns_servers=("8.8.8.8" "1.1.1.1" "8.8.4.4")
    local check_count=0
    
    while [ $check_count -lt 10 ]; do
        ((check_count++))
        
        for dns_server in "${dns_servers[@]}"; do
            echo -ne "${YELLOW}[!] 尝试 $check_count 次，DNS服务器: $dns_server\r${NC}"
            
            local query_result
            query_result=$(dig +short TXT "$check_domain" @"$dns_server" 2>/dev/null | sed 's/"//g')
            
            if [[ "$query_result" == *"$txt_record"* ]]; then
                echo -e "\n${GREEN}[✓] DNS记录验证成功！${NC}"
                return 0
            fi
            
            sleep 2
        done
    done
    
    print_error "DNS记录验证失败"
    return 1
}

# ========== 证书操作函数 ==========

# Webroot模式申请证书
webroot_issue_cert() {
    local domain="$1"
    
    print_info "Webroot模式申请证书: $domain"
    
    # 检查是否包含通配符
    if [[ "$domain" == *"*"* ]]; then
        print_error "Webroot模式不支持通配符证书 (*.domain)"
        return 1
    fi
    
    read -p "请输入网站根目录路径 (例如: /var/www/html): " webroot_path
    
    if [ -z "$webroot_path" ]; then
        print_error "网站根目录不能为空"
        return 1
    fi
    
    if [ ! -d "$webroot_path" ]; then
        print_warning "指定的目录 $webroot_path 不存在或不是一个有效的目录"
        read -p "是否继续执行? (y/n): " confirm
        if [ "$confirm" != "y" ]; then
            return 1
        fi
    fi
    
    # 执行申请命令
    print_info "正在申请证书..."
    local cmd=("$ACME_BIN" "--issue" "-d" "$domain" "-w" "$webroot_path")
    
    echo -e "${BLUE}==========================================${NC}"
    if "${cmd[@]}"; then
        echo -e "${BLUE}==========================================${NC}"
        print_success "证书申请成功！"
        return 0
    else
        echo -e "${BLUE}==========================================${NC}"
        print_error "证书申请失败"
        return 1
    fi
}

# DNS API模式申请证书
dns_api_issue_cert() {
    local domain="$1"
    
    print_info "DNS API模式申请证书: $domain"
    
    echo "请选择DNS服务商:"
    echo "1) Cloudflare"
    echo "2) 阿里云"
    echo "3) 腾讯云"
    echo "4) 其他"
    read -p "请选择(1-4): " dns_provider
    
    case $dns_provider in
        1)
            local api_key_name="CF_Key"
            local api_email_name="CF_Email"
            local dns_type="dns_cf"
            ;;
        2)
            local api_key_name="Ali_Key"
            local api_secret_name="Ali_Secret"
            local dns_type="dns_ali"
            ;;
        3)
            local api_key_name="DP_Id"
            local api_secret_name="DP_Key"
            local dns_type="dns_dp"
            ;;
        4)
            print_info "请参考acme.sh文档配置其他DNS服务商"
            return 1
            ;;
        *)
            print_error "无效的选择"
            return 1
            ;;
    esac
    
    # 获取API密钥
    if [ "$dns_provider" -eq 1 ]; then
        read -p "请输入Cloudflare Global API Key ($api_key_name): " api_key
        read -p "请输入Cloudflare邮箱 ($api_email_name): " api_email
        
        if [ -z "$api_key" ] || [ -z "$api_email" ]; then
            print_error "API密钥和邮箱不能为空"
            return 1
        fi
        
        # 设置环境变量并执行
        export CF_Key="$api_key"
        export CF_Email="$api_email"
    else
        read -p "请输入API Key ($api_key_name): " api_key
        read -p "请输入API Secret ($api_secret_name): " api_secret
        
        if [ -z "$api_key" ] || [ -z "$api_secret" ]; then
            print_error "API密钥和Secret不能为空"
            return 1
        fi
        
        # 根据服务商设置环境变量
        case $dns_provider in
            2)
                export Ali_Key="$api_key"
                export Ali_Secret="$api_secret"
                ;;
            3)
                export DP_Id="$api_key"
                export DP_Key="$api_secret"
                ;;
        esac
    fi
    
    # 执行申请命令
    print_info "正在申请证书..."
    local cmd=("$ACME_BIN" "--issue" "-d" "$domain" "--dns" "$dns_type")
    
    echo -e "${BLUE}==========================================${NC}"
    if "${cmd[@]}"; then
        echo -e "${BLUE}==========================================${NC}"
        print_success "证书申请成功！"
        
        # 提示自动续期配置
        print_info "证书申请成功后，acme.sh会自动记住您的API密钥用于自动续期"
        return 0
    else
        echo -e "${BLUE}==========================================${NC}"
        print_error "证书申请失败"
        return 1
    fi
}

# DNS手动模式申请证书
dns_manual_issue_cert() {
    local domain="$1"
    
    print_info "DNS手动模式申请证书: $domain"
    
    # 检查DNS依赖
    if ! check_dig; then
        print_error "DNS模式依赖检查失败"
        return 1
    fi
    
    create_temp_dir
    local log_file="$TEMP_DIR/acme_manual.log"
    
    print_info "获取DNS验证信息..."
    
    # 构建命令
    local cmd=("$ACME_BIN" "--issue" "--dns" "-d" "$domain")
    cmd+=("--server" "letsencrypt" "--yes-I-know-dns-manual-mode-enough-go-ahead-please")
    
    # 执行命令
    echo -e "${BLUE}==========================================${NC}"
    if ! "${cmd[@]}" 2>&1 | tee "$log_file"; then
        echo -e "${BLUE}==========================================${NC}"
        print_error "获取DNS验证信息失败"
        return 1
    fi
    echo -e "${BLUE}==========================================${NC}"
    
    # 解析TXT记录
    local cmd_output=""
    cmd_output=$(cat "$log_file")
    local txt_record=""
    txt_record=$(echo "$cmd_output" | grep -A 2 "Domain: '_acme-challenge.$domain'" | grep "TXT value:" | sed -n "s/.*TXT value: '\([^']*\)'.*/\1/p")
    
    if [ -z "$txt_record" ]; then
        txt_record=$(echo "$cmd_output" | grep -i "TXT value:" | sed -n "s/.*TXT value: '\([^']*\)'.*/\1/p")
    fi
    
    if [ -z "$txt_record" ]; then
        print_warning "无法自动获取TXT记录"
        echo "请从上面的输出中手动查找TXT记录值"
        read -p "请输入 _acme-challenge.$domain 的TXT记录值: " txt_record
    fi
    
    if [ -z "$txt_record" ]; then
        print_error "未获取到TXT记录"
        return 1
    fi
    
    # 显示TXT记录
    echo ""
    print_success "DNS验证信息获取成功"
    echo -e "${BLUE}==========================================${NC}"
    echo ""
    echo -e "${YELLOW}域名:     $domain${NC}"
    echo -e "${YELLOW}类型:     TXT${NC}"
    echo -e "${YELLOW}主机名:   _acme-challenge.$domain${NC}"
    echo -e "${YELLOW}记录值:   $txt_record${NC}"
    echo ""
    echo -e "${BLUE}==========================================${NC}"
    echo ""
    
    # 等待用户添加DNS记录
    print_info "请添加上述TXT记录到DNS解析"
    print_info "添加完成后，等待1-2分钟让DNS生效"
    echo -e "${YELLOW}验证命令:${NC}"
    echo "  dig +short TXT _acme-challenge.$domain @8.8.8.8"
    echo ""
    read -p "DNS记录添加完成并等待生效后，按回车键继续验证..."
    
    # 验证DNS记录
    print_info "检查DNS记录传播..."
    if ! check_dns_record "$domain" "$txt_record"; then
        print_error "DNS验证失败"
        return 1
    fi
    
    # 签发证书
    print_info "DNS验证通过，正在签发证书..."
    
    local renew_cmd=("$ACME_BIN" "--renew" "-d" "$domain" "--force" "--yes-I-know-dns-manual-mode-enough-go-ahead-please")
    
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        echo -e "${BLUE}==========================================${NC}"
        if "${renew_cmd[@]}"; then
            echo -e "${BLUE}==========================================${NC}"
            print_success "证书申请成功！"
            return 0
        else
            ((retry_count++))
            if [ $retry_count -lt $max_retries ]; then
                print_warning "证书签发失败，第 $retry_count 次重试..."
                sleep 5
            else
                print_error "证书签发失败，已重试 $max_retries 次"
                return 1
            fi
        fi
    done
}

# 获取DNS TXT记录（原有函数，保持兼容）
get_dns_txt_records() {
    dns_manual_issue_cert "$1"
}

# 证书续期
renew_certificate() {
    local domains=()
    
    if [ $# -gt 0 ]; then
        domains=("$@")
        echo -e "\n${BLUE}=== 续期证书 ===${NC}"
        print_success "检测到以下域名已有证书:"
        for domain in "${domains[@]}"; do
            echo "  - $domain"
        done
    else
        echo -e "\n${BLUE}=== 证书续期 ===${NC}"
        
        local certs_dirs=($(parse_certificates))
        local count=${#certs_dirs[@]}
        
        if [ $count -eq 0 ]; then
            print_warning "没有找到证书"
            wait_for_confirmation
            return 1
        fi
        
        local cert_count=$((count / 2))
        local certs=("${certs_dirs[@]:0:$cert_count}")
        local cert_dirs=("${certs_dirs[@]:$cert_count}")
        
        print_success "找到 $cert_count 个证书:"
        for i in "${!certs[@]}"; do
            local cert_name="${certs[$i]}"
            local cert_dir="${cert_dirs[$i]}"
            local cert_file=$(find_cert_file "$cert_dir" "$cert_name")
            
            if [ -n "$cert_file" ]; then
                # 检查openssl依赖
                if check_openssl; then
                    local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
                    if [ -n "$expiry_date" ]; then
                        echo "$((i+1))) $cert_name - 到期时间: $expiry_date"
                    else
                        echo "$((i+1))) $cert_name"
                    fi
                else
                    echo "$((i+1))) $cert_name"
                fi
            else
                echo "$((i+1))) $cert_name"
            fi
        done
        echo ""
        
        read -p "请选择要续期的证书序号 (留空返回): " cert_index
        if [ -z "$cert_index" ]; then
            print_info "返回主菜单"
            return 0
        fi
        
        if ! [[ "$cert_index" =~ ^[0-9]+$ ]] || [ "$cert_index" -lt 1 ] || [ "$cert_index" -gt ${#certs[@]} ]; then
            print_error "无效的序号"
            return 1
        fi
        
        local domain="${certs[$((cert_index-1))]}"
        domains=("$domain")
    fi
    
    # 执行续期
    local success_count=0
    local fail_count=0
    
    for domain in "${domains[@]}"; do
        print_info "续期: $domain"
        
        if "$ACME_BIN" --renew --domain "$domain" --force; then
            print_success "证书 $domain 续期成功"
            ((success_count++))
        else
            print_error "证书 $domain 续期失败"
            ((fail_count++))
        fi
    done
    
    echo -e "\n${BLUE}=== 续期结果 ===${NC}"
    echo -e "${GREEN}[✓] 成功: $success_count${NC}"
    echo -e "${RED}[✗✗✗✗] 失败: $fail_count${NC}"
    
    wait_for_confirmation
    return $((fail_count > 0 ? 1 : 0))
}

# 删除证书
delete_certificate() {
    local domains=()
    
    if [ $# -gt 0 ]; then
        domains=("$@")
        echo -e "\n${BLUE}=== 删除证书 ===${NC}"
        print_warning "检测到以下域名已有证书:"
        for domain in "${domains[@]}"; do
            echo "  - $domain"
        done
    else
        echo -e "\n${BLUE}=== 删除证书 ===${NC}"
        
        local certs_dirs=($(parse_certificates))
        local count=${#certs_dirs[@]}
        
        if [ $count -eq 0 ]; then
            print_warning "没有找到证书"
            wait_for_confirmation
            return 1
        fi
        
        local cert_count=$((count / 2))
        local certs=("${certs_dirs[@]:0:$cert_count}")
        
        print_success "找到 $cert_count 个证书:"
        for i in "${!certs[@]}"; do
            echo "$((i+1))) ${certs[$i]}"
        done
        echo ""
        
        read -p "请选择要删除的证书序号 (留空返回): " cert_index
        if [ -z "$cert_index" ]; then
            print_info "返回主菜单"
            return 0
        fi
        
        if ! [[ "$cert_index" =~ ^[0-9]+$ ]] || [ "$cert_index" -lt 1 ] || [ "$cert_index" -gt ${#certs[@]} ]; then
            print_error "无效的序号"
            return 1
        fi
        
        local domain="${certs[$((cert_index-1))]}"
        domains=("$domain")
    fi
    
    # 确认删除
    echo ""
    print_warning "警告：此操作不可恢复！"
    read -p "确定要删除吗？(y/n): " confirm
    
    if ! [[ $confirm =~ ^[Yy]$ ]]; then
        print_info "取消删除"
        return 0
    fi
    
    # 执行删除
    local success_count=0
    local fail_count=0
    
    for domain in "${domains[@]}"; do
        print_info "删除: $domain"
        
        # 删除acme.sh中的证书
        if "$ACME_BIN" --remove --domain "$domain" 2>/dev/null; then
            print_success "证书 $domain 从acme.sh中移除"
        fi
        
        # 删除证书目录
        rm -rf "$ACME_DIR/${domain}_ecc" 2>/dev/null
        rm -rf "$ACME_DIR/$domain" 2>/dev/null
        
        # 检查是否删除成功
        if check_cert_exists "$domain" > /dev/null; then
            print_error "证书 $domain 删除失败"
            ((fail_count++))
        else
            print_success "证书 $domain 删除成功"
            ((success_count++))
        fi
    done
    
    echo -e "\n${BLUE}=== 删除结果 ===${NC}"
    echo -e "${GREEN}[✓] 成功: $success_count${NC}"
    echo -e "${RED}[✗✗✗✗] 失败: $fail_count${NC}"
    
    wait_for_confirmation
    return $((fail_count > 0 ? 1 : 0))
}

# 列出证书
list_certificates() {
    echo -e "\n${BLUE}=== 证书列表 ===${NC}"
    
    local certs_dirs=($(parse_certificates))
    local count=${#certs_dirs[@]}
    
    if [ $count -eq 0 ]; then
        print_warning "没有找到证书"
        wait_for_confirmation
        return 1
    fi
    
    local cert_count=$((count / 2))
    local certs=("${certs_dirs[@]:0:$cert_count}")
    local cert_dirs=("${certs_dirs[@]:$cert_count}")
    
    print_success "找到 $cert_count 个证书:"
    for i in "${!certs[@]}"; do
        local cert_name="${certs[$i]}"
        local cert_dir="${cert_dirs[$i]}"
        local cert_file=$(find_cert_file "$cert_dir" "$cert_name")
        
        if [ -n "$cert_file" ]; then
            # 检查openssl依赖
            if check_openssl; then
                local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
                if [ -n "$expiry_date" ]; then
                    echo "$((i+1))) $cert_name - 到期时间: $expiry_date"
                else
                    echo "$((i+1))) $cert_name"
                fi
            else
                echo "$((i+1))) $cert_name"
            fi
        else
            echo "$((i+1))) $cert_name"
        fi
    done
    echo ""
    
    read -p "请输入证书序号查看详情 (留空返回): " cert_index
    if [ -z "$cert_index" ]; then
        return 0
    fi
    
    if ! [[ "$cert_index" =~ ^[0-9]+$ ]] || [ "$cert_index" -lt 1 ] || [ "$cert_index" -gt ${#certs[@]} ]; then
        print_error "无效的序号"
        return 1
    fi
    
    local domain="${certs[$((cert_index-1))]}"
    local cert_dir="${cert_dirs[$((cert_index-1))]}"
    
    echo ""
    show_cert_info "$domain" "$cert_dir"
    wait_for_confirmation
}

# ========== 菜单函数 ==========

# 申请证书
cert_issue_menu() {
    echo -e "\n${BLUE}=== 证书申请 ===${NC}"
    
    echo "请选择验证方式："
    echo "1) Webroot (HTTP验证) - 适用于普通网站，不支持通配符"
    echo "2) DNS API - 适用于通配符证书，需要API密钥"
    echo "3) DNS手动模式 - 适用于通配符，需要手动操作TXT记录"
    echo ""
    read -p "请选择验证方式(1-3): " verify_choice
    
    case $verify_choice in
        1|2|3)
            ;;
        *)
            print_error "无效的选择"
            return 1
            ;;
    esac
    
    echo ""
    echo "请输入域名："
    echo "示例："
    echo "  example.com                 # 单域名"
    echo "  *.example.com               # 通配符域名"
    echo ""
    read -p "请输入域名: " domain
    
    if [ -z "$domain" ]; then
        print_info "返回主菜单"
        return 0
    fi
    
    # 检查是否已存在
    local cert_dir=$(check_cert_exists "$domain")
    if [ -n "$cert_dir" ]; then
        print_warning "检测到该域名已有证书"
        
        echo -e "\n${BLUE}请选择操作:${NC}"
        echo "1) 续期现有证书"
        echo "2) 删除重新申请"
        echo "3) 取消申请操作"
        echo ""
        
        read -p "请选择(1-3): " choice
        
        case $choice in
            1)
                renew_certificate "$domain"
                return $?
                ;;
            2)
                delete_certificate "$domain"
                # 继续申请流程
                ;;
            3)
                print_info "取消操作"
                return 0
                ;;
            *)
                print_error "无效的选择"
                return 1
                ;;
        esac
    fi
    
    # 根据选择的验证方式申请证书
    print_info "开始申请证书: $domain"
    
    local result=1
    case $verify_choice in
        1)
            if webroot_issue_cert "$domain"; then
                result=0
            fi
            ;;
        2)
            if dns_api_issue_cert "$domain"; then
                result=0
            fi
            ;;
        3)
            if dns_manual_issue_cert "$domain"; then
                result=0
            fi
            ;;
    esac
    
    if [ $result -eq 0 ]; then
        # 显示证书信息
        echo -e "\n${BLUE}=== 证书申请成功 ===${NC}"
        
        local cert_dir=$(check_cert_exists "$domain")
        if [ -n "$cert_dir" ]; then
            show_cert_info "$domain" "$cert_dir"
        fi
        
        wait_for_confirmation
        return 0
    else
        print_error "证书申请失败"
        wait_for_confirmation
        return 1
    fi
}

# 重新安装
reinstall_acme() {
    echo -e "\n${BLUE}=== 重新安装acme.sh ===${NC}"
    
    read -p "确定要重新安装acme.sh吗？(y/n): " confirm
    if ! [[ $confirm =~ ^[Yy]$ ]]; then
        print_info "取消操作"
        return 0
    fi
    
    # 备份证书
    create_temp_dir
    local backup_dir="$TEMP_DIR/acme_backup"
    mkdir -p "$backup_dir"
    
    print_info "备份证书..."
    
    local certs_dirs=($(parse_certificates))
    local count=${#certs_dirs[@]}
    local cert_count=$((count / 2))
    
    if [ $cert_count -gt 0 ]; then
        local certs=("${certs_dirs[@]:0:$cert_count}")
        local cert_dirs=("${certs_dirs[@]:$cert_count}")
        
        for i in "${!certs[@]}"; do
            local domain="${certs[$i]}"
            local cert_dir="${cert_dirs[$i]}"
            
            if [ -d "$cert_dir" ]; then
                cp -r "$cert_dir" "$backup_dir/" 2>/dev/null
                print_info "备份证书: $domain"
            fi
        done
    fi
    
    # 卸载
    print_info "卸载acme.sh..."
    if [ -f "$ACME_BIN" ]; then
        "$ACME_BIN" --uninstall 2>/dev/null || true
    fi
    
    rm -rf "$ACME_DIR"
    
    # 重新安装
    print_info "重新安装acme.sh..."
    if install_acme; then
        # 恢复证书
        print_info "恢复证书..."
        for backup_cert in "$backup_dir"/*; do
            if [ -d "$backup_cert" ]; then
                local dir_name=$(basename "$backup_cert")
                cp -r "$backup_cert" "$ACME_DIR/" 2>/dev/null
                print_info "恢复证书: $dir_name"
            fi
        done
        
        print_success "重新安装完成"
    else
        print_error "重新安装失败"
    fi
    
    wait_for_confirmation
}

# 主菜单
# 主菜单
main_menu() {
    while true; do
        echo -e "\n${BLUE}=== ACME证书管理脚本 ===${NC}"
        echo "1) 申请证书"
        echo "2) 证书续期"
        echo "3) 安装证书"
        echo "4) 删除证书"
        echo "5) 列出证书"
        echo "6) 重新安装"
        echo "0) 退出脚本"
        echo ""
        read -p "请选择操作(0-6): " choice
        
        case $choice in
            1) 
                cert_issue_menu 
                ;;
            2) 
                renew_certificate 
                ;;
            3) 
                # 调用外部安装脚本
                print_info "正在下载并运行证书安装脚本..."
                if bash <(curl -sL https://raw.githubusercontent.com/tyy840913/backup/refs/heads/main/webconf.sh); then
                    print_success "证书安装脚本执行完成"
                else
                    print_error "证书安装脚本执行失败"
                fi
                wait_for_confirmation
                ;;
            4) 
                delete_certificate 
                ;;
            5) 
                list_certificates 
                ;;
            6) 
                reinstall_acme 
                ;;
            0) 
                print_success "再见！"
                exit 0
                ;;
            *)
                print_error "无效的选择，请输入 0-6"
                wait_for_confirmation
                ;;
        esac
    done
}

# 主程序
main() {
    if [ "$EUID" -eq 0 ]; then
        print_success "以ROOT权限运行"
    else
        print_warning "以普通用户运行，建议使用sudo运行"
        echo ""
    fi
    
    init_directories
    
    # 只检查acme.sh依赖
    if ! install_acme; then
        print_error "acme.sh安装失败"
        wait_for_confirmation
        exit 1
    fi
    
    main_menu
}

# 运行主程序
main
            return 0
        else
            print_error "安装失败: $cmd"
            return 1
        fi
    else
        print_error "用户取消安装，脚本无法继续"
        return 1
    fi
}

# ========== 基础依赖检查（按需） ==========

# 检查openssl（证书操作需要）
check_openssl() {
    if ! command -v openssl &> /dev/null; then
        print_warning "openssl未安装，证书操作需要openssl"
        if ! check_and_install_command "openssl"; then
            return 1
        fi
    fi
    return 0
}

# 检查crontab（自动续期需要）
check_crontab() {
    if ! command -v crontab &> /dev/null; then
        print_warning "crontab未安装，自动续期需要crontab"
        if ! check_and_install_command "crontab" "cron"; then
            return 1
        fi
    fi
    return 0
}

# 检查curl（acme.sh安装需要）
check_curl() {
    if ! command -v curl &> /dev/null; then
        print_warning "curl未安装，acme.sh安装需要curl"
        if ! check_and_install_command "curl"; then
            return 1
        fi
    fi
    return 0
}

# 检查dig（DNS验证需要）
check_dig() {
    if ! command -v dig &> /dev/null; then
        print_warning "dig未安装，DNS验证需要dig"
        local pkg_name=""
        if command -v apt-get &> /dev/null; then
            pkg_name="dnsutils"
        elif command -v yum &> /dev/null || command -v dnf &> /dev/null; then
            pkg_name="bind-utils"
        elif command -v apk &> /dev/null; then
            pkg_name="bind-tools"
        else
            pkg_name="dnsutils"
        fi
        
        if ! check_and_install_command "dig" "$pkg_name"; then
            return 1
        fi
    fi
    return 0
}

# ========== acme.sh管理 ==========

install_acme() {
    print_info "检查acme.sh安装..."
    
    if [ -f "$ACME_BIN" ]; then
        print_success "acme.sh已安装"
        return 0
    fi
    
    print_warning "acme.sh未安装，开始安装..."
    
    # 检查curl依赖
    if ! check_curl; then
        print_error "curl安装失败，无法安装acme.sh"
        return 1
    fi
    
    if curl -fsSL https://get.acme.sh | sh; then
        print_success "acme.sh安装成功"
        return 0
    fi
    
    print_error "acme.sh安装失败"
    return 1
}

# ========== 证书查找函数 ==========

# 查找证书文件
find_cert_file() {
    local cert_dir="$1"
    local domain="$2"
    
    local candidates=(
        "$cert_dir/$domain.cer"
        "$cert_dir/$domain.crt"
        "$cert_dir/$domain.pem"
        "$cert_dir/fullchain.cer"
        "$cert_dir/fullchain.crt"
        "$cert_dir/fullchain.pem"
        "$cert_dir/cert.pem"
        "$cert_dir/cert.cer"
        "$cert_dir/cert.crt"
    )
    
    for file in "${candidates[@]}"; do
        if [ -f "$file" ]; then
            echo "$file"
            return 0
        fi
    done
    
    return 1
}

# 查找私钥文件
find_key_file() {
    local cert_dir="$1"
    local domain="$2"
    
    local candidates=(
        "$cert_dir/$domain.key"
        "$cert_dir/privkey.pem"
        "$cert_dir/key.pem"
        "$cert_dir/private.key"
    )
    
    for file in "${candidates[@]}"; do
        if [ -f "$file" ]; then
            echo "$file"
            return 0
        fi
    done
    
    return 1
}

# 查找完整链证书文件
find_fullchain_file() {
    local cert_dir="$1"
    
    local candidates=(
        "$cert_dir/fullchain.cer"
        "$cert_dir/fullchain.crt"
        "$cert_dir/fullchain.pem"
    )
    
    for file in "${candidates[@]}"; do
        if [ -f "$file" ]; then
            echo "$file"
            return 0
        fi
    done
    
    return 1
}

# 查找CA证书文件
find_ca_file() {
    local cert_dir="$1"
    
    local candidates=(
        "$cert_dir/ca.cer"
        "$cert_dir/ca.crt"
        "$cert_dir/chain.pem"
        "$cert_dir/ca.pem"
        "$cert_dir/chain.crt"
    )
    
    for file in "${candidates[@]}"; do
        if [ -f "$file" ]; then
            echo "$file"
            return 0
        fi
    done
    
    return 1
}

# 获取所有证书
get_all_certificates() {
    local certs=()
    local cert_dirs=()
    
    if [ ! -d "$ACME_DIR" ]; then
        echo "CERTS:"
        echo "DIRS:"
        return 1
    fi
    
    for cert_dir in "$ACME_DIR"/*; do
        if [ -d "$cert_dir" ]; then
            local dir_name=$(basename "$cert_dir")
            
            # 排除acme.sh自身目录
            if [[ "$dir_name" =~ ^(acme\.sh|\.git|ca)$ ]]; then
                continue
            fi
            
            # 提取域名
            local domain="${dir_name%_ecc}"
            
            # 检查是否有证书文件
            if find_cert_file "$cert_dir" "$domain" > /dev/null; then
                certs+=("$domain")
                cert_dirs+=("$cert_dir")
            fi
        fi
    done
    
    echo "CERTS: ${certs[@]}"
    echo "DIRS: ${cert_dirs[@]}"
}

# 解析get_all_certificates的输出
parse_certificates() {
    local output
    output=$(get_all_certificates)
    
    local certs=()
    local cert_dirs=()
    local line
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^CERTS:\ (.*)$ ]]; then
            read -ra certs <<< "${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^DIRS:\ (.*)$ ]]; then
            read -ra cert_dirs <<< "${BASH_REMATCH[1]}"
        fi
    done <<< "$output"
    
    echo "${certs[@]}" "${cert_dirs[@]}"
}

# 检查证书是否存在
check_cert_exists() {
    local domain="$1"
    
    local certs_dirs=($(parse_certificates))
    local count=${#certs_dirs[@]}
    local cert_count=$((count / 2))
    
    for ((i=0; i<cert_count; i++)); do
        if [ "${certs_dirs[$i]}" = "$domain" ]; then
            echo "${certs_dirs[$((i + cert_count))]}"
            return 0
        fi
    done
    
    return 1
}

# ========== 证书信息显示 ==========

show_cert_info() {
    local domain="$1"
    local cert_dir="$2"
    
    # 检查openssl依赖
    if ! check_openssl; then
        print_error "无法显示证书信息：openssl未安装"
        return 1
    fi
    
    print_info "证书目录: $cert_dir"
    echo ""
    
    # 查找文件
    local cert_file=$(find_cert_file "$cert_dir" "$domain")
    local key_file=$(find_key_file "$cert_dir" "$domain")
    local ca_file=$(find_ca_file "$cert_dir")
    local fullchain_file=$(find_fullchain_file "$cert_dir")
    
    # 显示文件路径
    if [ -n "$cert_file" ]; then
        echo -e "${YELLOW}证书文件:${NC}"
        echo "  $cert_file"
    fi
    
    if [ -n "$key_file" ]; then
        echo -e "${YELLOW}私钥文件:${NC}"
        echo "  $key_file"
    fi
    
    if [ -n "$ca_file" ]; then
        echo -e "${YELLOW}CA证书:${NC}"
        echo "  $ca_file"
    fi
    
    if [ -n "$fullchain_file" ]; then
        echo -e "${YELLOW}完整证书链:${NC}"
        echo "  $fullchain_file"
    fi
    
    # 显示证书信息
    if [ -n "$cert_file" ]; then
        echo ""
        echo -e "${YELLOW}证书详情:${NC}"
        openssl x509 -in "$cert_file" -noout -subject -issuer -dates 2>/dev/null || echo "  (无法读取证书信息)"
        
        # 计算剩余天数
        local expiry_date
        expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
        if [ -n "$expiry_date" ]; then
            local now_seconds=$(date +%s)
            local expiry_seconds=$(date -d "$expiry_date" +%s 2>/dev/null || date +%s)
            if [ "$expiry_seconds" -gt "$now_seconds" ]; then
                local days_left=$(( (expiry_seconds - now_seconds) / 86400 ))
                echo "  剩余天数: $days_left 天"
            else
                echo "  证书已过期"
            fi
        fi
    fi
    
    echo ""
}

# ========== DNS检查 ==========

check_dns_record() {
    local domain="$1"
    local txt_record="$2"
    
    # 检查dig依赖
    if ! check_dig; then
        print_error "DNS检查失败：dig未安装"
        return 1
    fi
    
    local check_domain="_acme-challenge.$domain"
    if [[ "$domain" == **\** ]]; then
        check_domain="_acme-challenge.${domain#\*}"
    fi
    
    print_info "检查DNS记录: $check_domain"
    
    local dns_servers=("8.8.8.8" "1.1.1.1" "8.8.4.4")
    local check_count=0
    
    while [ $check_count -lt 10 ]; do
        ((check_count++))
        
        for dns_server in "${dns_servers[@]}"; do
            echo -ne "${YELLOW}[!] 尝试 $check_count 次，DNS服务器: $dns_server\r${NC}"
            
            local query_result
            query_result=$(dig +short TXT "$check_domain" @"$dns_server" 2>/dev/null | sed 's/"//g')
            
            if [[ "$query_result" == *"$txt_record"* ]]; then
                echo -e "\n${GREEN}[✓] DNS记录验证成功！${NC}"
                return 0
            fi
            
            sleep 2
        done
    done
    
    print_error "DNS记录验证失败"
    return 1
}

# ========== 证书操作函数 ==========

# Webroot模式申请证书
webroot_issue_cert() {
    local domain="$1"
    
    print_info "Webroot模式申请证书: $domain"
    
    # 检查是否包含通配符
    if [[ "$domain" == *"*"* ]]; then
        print_error "Webroot模式不支持通配符证书 (*.domain)"
        return 1
    fi
    
    read -p "请输入网站根目录路径 (例如: /var/www/html): " webroot_path
    
    if [ -z "$webroot_path" ]; then
        print_error "网站根目录不能为空"
        return 1
    fi
    
    if [ ! -d "$webroot_path" ]; then
        print_warning "指定的目录 $webroot_path 不存在或不是一个有效的目录"
        read -p "是否继续执行? (y/n): " confirm
        if [ "$confirm" != "y" ]; then
            return 1
        fi
    fi
    
    # 执行申请命令
    print_info "正在申请证书..."
    local cmd=("$ACME_BIN" "--issue" "-d" "$domain" "-w" "$webroot_path")
    
    echo -e "${BLUE}==========================================${NC}"
    if "${cmd[@]}"; then
        echo -e "${BLUE}==========================================${NC}"
        print_success "证书申请成功！"
        return 0
    else
        echo -e "${BLUE}==========================================${NC}"
        print_error "证书申请失败"
        return 1
    fi
}

# DNS API模式申请证书
dns_api_issue_cert() {
    local domain="$1"
    
    print_info "DNS API模式申请证书: $domain"
    
    echo "请选择DNS服务商:"
    echo "1) Cloudflare"
    echo "2) 阿里云"
    echo "3) 腾讯云"
    echo "4) 其他"
    read -p "请选择(1-4): " dns_provider
    
    case $dns_provider in
        1)
            local api_key_name="CF_Key"
            local api_email_name="CF_Email"
            local dns_type="dns_cf"
            ;;
        2)
            local api_key_name="Ali_Key"
            local api_secret_name="Ali_Secret"
            local dns_type="dns_ali"
            ;;
        3)
            local api_key_name="DP_Id"
            local api_secret_name="DP_Key"
            local dns_type="dns_dp"
            ;;
        4)
            print_info "请参考acme.sh文档配置其他DNS服务商"
            return 1
            ;;
        *)
            print_error "无效的选择"
            return 1
            ;;
    esac
    
    # 获取API密钥
    if [ "$dns_provider" -eq 1 ]; then
        read -p "请输入Cloudflare Global API Key ($api_key_name): " api_key
        read -p "请输入Cloudflare邮箱 ($api_email_name): " api_email
        
        if [ -z "$api_key" ] || [ -z "$api_email" ]; then
            print_error "API密钥和邮箱不能为空"
            return 1
        fi
        
        # 设置环境变量并执行
        export CF_Key="$api_key"
        export CF_Email="$api_email"
    else
        read -p "请输入API Key ($api_key_name): " api_key
        read -p "请输入API Secret ($api_secret_name): " api_secret
        
        if [ -z "$api_key" ] || [ -z "$api_secret" ]; then
            print_error "API密钥和Secret不能为空"
            return 1
        fi
        
        # 根据服务商设置环境变量
        case $dns_provider in
            2)
                export Ali_Key="$api_key"
                export Ali_Secret="$api_secret"
                ;;
            3)
                export DP_Id="$api_key"
                export DP_Key="$api_secret"
                ;;
        esac
    fi
    
    # 执行申请命令
    print_info "正在申请证书..."
    local cmd=("$ACME_BIN" "--issue" "-d" "$domain" "--dns" "$dns_type")
    
    echo -e "${BLUE}==========================================${NC}"
    if "${cmd[@]}"; then
        echo -e "${BLUE}==========================================${NC}"
        print_success "证书申请成功！"
        
        # 提示自动续期配置
        print_info "证书申请成功后，acme.sh会自动记住您的API密钥用于自动续期"
        return 0
    else
        echo -e "${BLUE}==========================================${NC}"
        print_error "证书申请失败"
        return 1
    fi
}

# DNS手动模式申请证书
dns_manual_issue_cert() {
    local domain="$1"
    
    print_info "DNS手动模式申请证书: $domain"
    
    # 检查DNS依赖
    if ! check_dig; then
        print_error "DNS模式依赖检查失败"
        return 1
    fi
    
    create_temp_dir
    local log_file="$TEMP_DIR/acme_manual.log"
    
    print_info "获取DNS验证信息..."
    
    # 构建命令
    local cmd=("$ACME_BIN" "--issue" "--dns" "-d" "$domain")
    cmd+=("--server" "letsencrypt" "--yes-I-know-dns-manual-mode-enough-go-ahead-please")
    
    # 执行命令
    echo -e "${BLUE}==========================================${NC}"
    if ! "${cmd[@]}" 2>&1 | tee "$log_file"; then
        echo -e "${BLUE}==========================================${NC}"
        print_error "获取DNS验证信息失败"
        return 1
    fi
    echo -e "${BLUE}==========================================${NC}"
    
    # 解析TXT记录
    local cmd_output=""
    cmd_output=$(cat "$log_file")
    local txt_record=""
    txt_record=$(echo "$cmd_output" | grep -A 2 "Domain: '_acme-challenge.$domain'" | grep "TXT value:" | sed -n "s/.*TXT value: '\([^']*\)'.*/\1/p")
    
    if [ -z "$txt_record" ]; then
        txt_record=$(echo "$cmd_output" | grep -i "TXT value:" | sed -n "s/.*TXT value: '\([^']*\)'.*/\1/p")
    fi
    
    if [ -z "$txt_record" ]; then
        print_warning "无法自动获取TXT记录"
        echo "请从上面的输出中手动查找TXT记录值"
        read -p "请输入 _acme-challenge.$domain 的TXT记录值: " txt_record
    fi
    
    if [ -z "$txt_record" ]; then
        print_error "未获取到TXT记录"
        return 1
    fi
    
    # 显示TXT记录
    echo ""
    print_success "DNS验证信息获取成功"
    echo -e "${BLUE}==========================================${NC}"
    echo ""
    echo -e "${YELLOW}域名:     $domain${NC}"
    echo -e "${YELLOW}类型:     TXT${NC}"
    echo -e "${YELLOW}主机名:   _acme-challenge.$domain${NC}"
    echo -e "${YELLOW}记录值:   $txt_record${NC}"
    echo ""
    echo -e "${BLUE}==========================================${NC}"
    echo ""
    
    # 等待用户添加DNS记录
    print_info "请添加上述TXT记录到DNS解析"
    print_info "添加完成后，等待1-2分钟让DNS生效"
    echo -e "${YELLOW}验证命令:${NC}"
    echo "  dig +short TXT _acme-challenge.$domain @8.8.8.8"
    echo ""
    read -p "DNS记录添加完成并等待生效后，按回车键继续验证..."
    
    # 验证DNS记录
    print_info "检查DNS记录传播..."
    if ! check_dns_record "$domain" "$txt_record"; then
        print_error "DNS验证失败"
        return 1
    fi
    
    # 签发证书
    print_info "DNS验证通过，正在签发证书..."
    
    local renew_cmd=("$ACME_BIN" "--renew" "-d" "$domain" "--force" "--yes-I-know-dns-manual-mode-enough-go-ahead-please")
    
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        echo -e "${BLUE}==========================================${NC}"
        if "${renew_cmd[@]}"; then
            echo -e "${BLUE}==========================================${NC}"
            print_success "证书申请成功！"
            return 0
        else
            ((retry_count++))
            if [ $retry_count -lt $max_retries ]; then
                print_warning "证书签发失败，第 $retry_count 次重试..."
                sleep 5
            else
                print_error "证书签发失败，已重试 $max_retries 次"
                return 1
            fi
        fi
    done
}

# 获取DNS TXT记录（原有函数，保持兼容）
get_dns_txt_records() {
    dns_manual_issue_cert "$1"
}

# 证书续期
renew_certificate() {
    local domains=()
    
    if [ $# -gt 0 ]; then
        domains=("$@")
        echo -e "\n${BLUE}=== 续期证书 ===${NC}"
        print_success "检测到以下域名已有证书:"
        for domain in "${domains[@]}"; do
            echo "  - $domain"
        done
    else
        echo -e "\n${BLUE}=== 证书续期 ===${NC}"
        
        local certs_dirs=($(parse_certificates))
        local count=${#certs_dirs[@]}
        
        if [ $count -eq 0 ]; then
            print_warning "没有找到证书"
            wait_for_confirmation
            return 1
        fi
        
        local cert_count=$((count / 2))
        local certs=("${certs_dirs[@]:0:$cert_count}")
        local cert_dirs=("${certs_dirs[@]:$cert_count}")
        
        print_success "找到 $cert_count 个证书:"
        for i in "${!certs[@]}"; do
            local cert_name="${certs[$i]}"
            local cert_dir="${cert_dirs[$i]}"
            local cert_file=$(find_cert_file "$cert_dir" "$cert_name")
            
            if [ -n "$cert_file" ]; then
                # 检查openssl依赖
                if check_openssl; then
                    local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
                    if [ -n "$expiry_date" ]; then
                        echo "$((i+1))) $cert_name - 到期时间: $expiry_date"
                    else
                        echo "$((i+1))) $cert_name"
                    fi
                else
                    echo "$((i+1))) $cert_name"
                fi
            else
                echo "$((i+1))) $cert_name"
            fi
        done
        echo ""
        
        read -p "请选择要续期的证书序号 (留空返回): " cert_index
        if [ -z "$cert_index" ]; then
            print_info "返回主菜单"
            return 0
        fi
        
        if ! [[ "$cert_index" =~ ^[0-9]+$ ]] || [ "$cert_index" -lt 1 ] || [ "$cert_index" -gt ${#certs[@]} ]; then
            print_error "无效的序号"
            return 1
        fi
        
        local domain="${certs[$((cert_index-1))]}"
        domains=("$domain")
    fi
    
    # 执行续期
    local success_count=0
    local fail_count=0
    
    for domain in "${domains[@]}"; do
        print_info "续期: $domain"
        
        if "$ACME_BIN" --renew --domain "$domain" --force; then
            print_success "证书 $domain 续期成功"
            ((success_count++))
        else
            print_error "证书 $domain 续期失败"
            ((fail_count++))
        fi
    done
    
    echo -e "\n${BLUE}=== 续期结果 ===${NC}"
    echo -e "${GREEN}[✓] 成功: $success_count${NC}"
    echo -e "${RED}[✗✗✗✗] 失败: $fail_count${NC}"
    
    wait_for_confirmation
    return $((fail_count > 0 ? 1 : 0))
}

# 删除证书
delete_certificate() {
    local domains=()
    
    if [ $# -gt 0 ]; then
        domains=("$@")
        echo -e "\n${BLUE}=== 删除证书 ===${NC}"
        print_warning "检测到以下域名已有证书:"
        for domain in "${domains[@]}"; do
            echo "  - $domain"
        done
    else
        echo -e "\n${BLUE}=== 删除证书 ===${NC}"
        
        local certs_dirs=($(parse_certificates))
        local count=${#certs_dirs[@]}
        
        if [ $count -eq 0 ]; then
            print_warning "没有找到证书"
            wait_for_confirmation
            return 1
        fi
        
        local cert_count=$((count / 2))
        local certs=("${certs_dirs[@]:0:$cert_count}")
        
        print_success "找到 $cert_count 个证书:"
        for i in "${!certs[@]}"; do
            echo "$((i+1))) ${certs[$i]}"
        done
        echo ""
        
        read -p "请选择要删除的证书序号 (留空返回): " cert_index
        if [ -z "$cert_index" ]; then
            print_info "返回主菜单"
            return 0
        fi
        
        if ! [[ "$cert_index" =~ ^[0-9]+$ ]] || [ "$cert_index" -lt 1 ] || [ "$cert_index" -gt ${#certs[@]} ]; then
            print_error "无效的序号"
            return 1
        fi
        
        local domain="${certs[$((cert_index-1))]}"
        domains=("$domain")
    fi
    
    # 确认删除
    echo ""
    print_warning "警告：此操作不可恢复！"
    read -p "确定要删除吗？(y/n): " confirm
    
    if ! [[ $confirm =~ ^[Yy]$ ]]; then
        print_info "取消删除"
        return 0
    fi
    
    # 执行删除
    local success_count=0
    local fail_count=0
    
    for domain in "${domains[@]}"; do
        print_info "删除: $domain"
        
        # 删除acme.sh中的证书
        if "$ACME_BIN" --remove --domain "$domain" 2>/dev/null; then
            print_success "证书 $domain 从acme.sh中移除"
        fi
        
        # 删除证书目录
        rm -rf "$ACME_DIR/${domain}_ecc" 2>/dev/null
        rm -rf "$ACME_DIR/$domain" 2>/dev/null
        
        # 检查是否删除成功
        if check_cert_exists "$domain" > /dev/null; then
            print_error "证书 $domain 删除失败"
            ((fail_count++))
        else
            print_success "证书 $domain 删除成功"
            ((success_count++))
        fi
    done
    
    echo -e "\n${BLUE}=== 删除结果 ===${NC}"
    echo -e "${GREEN}[✓] 成功: $success_count${NC}"
    echo -e "${RED}[✗✗✗✗] 失败: $fail_count${NC}"
    
    wait_for_confirmation
    return $((fail_count > 0 ? 1 : 0))
}

# 列出证书
list_certificates() {
    echo -e "\n${BLUE}=== 证书列表 ===${NC}"
    
    local certs_dirs=($(parse_certificates))
    local count=${#certs_dirs[@]}
    
    if [ $count -eq 0 ]; then
        print_warning "没有找到证书"
        wait_for_confirmation
        return 1
    fi
    
    local cert_count=$((count / 2))
    local certs=("${certs_dirs[@]:0:$cert_count}")
    local cert_dirs=("${certs_dirs[@]:$cert_count}")
    
    print_success "找到 $cert_count 个证书:"
    for i in "${!certs[@]}"; do
        local cert_name="${certs[$i]}"
        local cert_dir="${cert_dirs[$i]}"
        local cert_file=$(find_cert_file "$cert_dir" "$cert_name")
        
        if [ -n "$cert_file" ]; then
            # 检查openssl依赖
            if check_openssl; then
                local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
                if [ -n "$expiry_date" ]; then
                    echo "$((i+1))) $cert_name - 到期时间: $expiry_date"
                else
                    echo "$((i+1))) $cert_name"
                fi
            else
                echo "$((i+1))) $cert_name"
            fi
        else
            echo "$((i+1))) $cert_name"
        fi
    done
    echo ""
    
    read -p "请输入证书序号查看详情 (留空返回): " cert_index
    if [ -z "$cert_index" ]; then
        return 0
    fi
    
    if ! [[ "$cert_index" =~ ^[0-9]+$ ]] || [ "$cert_index" -lt 1 ] || [ "$cert_index" -gt ${#certs[@]} ]; then
        print_error "无效的序号"
        return 1
    fi
    
    local domain="${certs[$((cert_index-1))]}"
    local cert_dir="${cert_dirs[$((cert_index-1))]}"
    
    echo ""
    show_cert_info "$domain" "$cert_dir"
    wait_for_confirmation
}

# ========== 菜单函数 ==========

# 申请证书
cert_issue_menu() {
    echo -e "\n${BLUE}=== 证书申请 ===${NC}"
    
    echo "请选择验证方式："
    echo "1) Webroot (HTTP验证) - 适用于普通网站，不支持通配符"
    echo "2) DNS API - 适用于通配符证书，需要API密钥"
    echo "3) DNS手动模式 - 适用于通配符，需要手动操作TXT记录"
    echo ""
    read -p "请选择验证方式(1-3): " verify_choice
    
    case $verify_choice in
        1|2|3)
            ;;
        *)
            print_error "无效的选择"
            return 1
            ;;
    esac
    
    echo ""
    echo "请输入域名："
    echo "示例："
    echo "  example.com                 # 单域名"
    echo "  *.example.com               # 通配符域名"
    echo ""
    read -p "请输入域名: " domain
    
    if [ -z "$domain" ]; then
        print_info "返回主菜单"
        return 0
    fi
    
    # 检查是否已存在
    local cert_dir=$(check_cert_exists "$domain")
    if [ -n "$cert_dir" ]; then
        print_warning "检测到该域名已有证书"
        
        echo -e "\n${BLUE}请选择操作:${NC}"
        echo "1) 续期现有证书"
        echo "2) 删除重新申请"
        echo "3) 取消申请操作"
        echo ""
        
        read -p "请选择(1-3): " choice
        
        case $choice in
            1)
                renew_certificate "$domain"
                return $?
                ;;
            2)
                delete_certificate "$domain"
                # 继续申请流程
                ;;
            3)
                print_info "取消操作"
                return 0
                ;;
            *)
                print_error "无效的选择"
                return 1
                ;;
        esac
    fi
    
    # 根据选择的验证方式申请证书
    print_info "开始申请证书: $domain"
    
    local result=1
    case $verify_choice in
        1)
            if webroot_issue_cert "$domain"; then
                result=0
            fi
            ;;
        2)
            if dns_api_issue_cert "$domain"; then
                result=0
            fi
            ;;
        3)
            if dns_manual_issue_cert "$domain"; then
                result=0
            fi
            ;;
    esac
    
    if [ $result -eq 0 ]; then
        # 显示证书信息
        echo -e "\n${BLUE}=== 证书申请成功 ===${NC}"
        
        local cert_dir=$(check_cert_exists "$domain")
        if [ -n "$cert_dir" ]; then
            show_cert_info "$domain" "$cert_dir"
        fi
        
        wait_for_confirmation
        return 0
    else
        print_error "证书申请失败"
        wait_for_confirmation
        return 1
    fi
}

# 重新安装
reinstall_acme() {
    echo -e "\n${BLUE}=== 重新安装acme.sh ===${NC}"
    
    read -p "确定要重新安装acme.sh吗？(y/n): " confirm
    if ! [[ $confirm =~ ^[Yy]$ ]]; then
        print_info "取消操作"
        return 0
    fi
    
    # 备份证书
    create_temp_dir
    local backup_dir="$TEMP_DIR/acme_backup"
    mkdir -p "$backup_dir"
    
    print_info "备份证书..."
    
    local certs_dirs=($(parse_certificates))
    local count=${#certs_dirs[@]}
    local cert_count=$((count / 2))
    
    if [ $cert_count -gt 0 ]; then
        local certs=("${certs_dirs[@]:0:$cert_count}")
        local cert_dirs=("${certs_dirs[@]:$cert_count}")
        
        for i in "${!certs[@]}"; do
            local domain="${certs[$i]}"
            local cert_dir="${cert_dirs[$i]}"
            
            if [ -d "$cert_dir" ]; then
                cp -r "$cert_dir" "$backup_dir/" 2>/dev/null
                print_info "备份证书: $domain"
            fi
        done
    fi
    
    # 卸载
    print_info "卸载acme.sh..."
    if [ -f "$ACME_BIN" ]; then
        "$ACME_BIN" --uninstall 2>/dev/null || true
    fi
    
    rm -rf "$ACME_DIR"
    
    # 重新安装
    print_info "重新安装acme.sh..."
    if install_acme; then
        # 恢复证书
        print_info "恢复证书..."
        for backup_cert in "$backup_dir"/*; do
            if [ -d "$backup_cert" ]; then
                local dir_name=$(basename "$backup_cert")
                cp -r "$backup_cert" "$ACME_DIR/" 2>/dev/null
                print_info "恢复证书: $dir_name"
            fi
        done
        
        print_success "重新安装完成"
    else
        print_error "重新安装失败"
    fi
    
    wait_for_confirmation
}

# 主菜单
# 主菜单
main_menu() {
    while true; do
        echo -e "\n${BLUE}=== ACME证书管理脚本 ===${NC}"
        echo "1) 申请证书"
        echo "2) 证书续期"
        echo "3) 安装证书"
        echo "4) 删除证书"
        echo "5) 列出证书"
        echo "6) 重新安装"
        echo "0) 退出脚本"
        echo ""
        read -p "请选择操作(0-6): " choice
        
        case $choice in
            1) 
                cert_issue_menu 
                ;;
            2) 
                renew_certificate 
                ;;
            3) 
                # 调用外部安装脚本
                print_info "正在下载并运行证书安装脚本..."
                if bash <(curl -sL https://raw.githubusercontent.com/tyy840913/backup/refs/heads/main/webconf.sh); then
                    print_success "证书安装脚本执行完成"
                else
                    print_error "证书安装脚本执行失败"
                fi
                wait_for_confirmation
                ;;
            4) 
                delete_certificate 
                ;;
            5) 
                list_certificates 
                ;;
            6) 
                reinstall_acme 
                ;;
            0) 
                print_success "再见！"
                exit 0
                ;;
            *)
                print_error "无效的选择，请输入 0-6"
                wait_for_confirmation
                ;;
        esac
    done
}

# 主程序
main() {
    if [ "$EUID" -eq 0 ]; then
        print_success "以ROOT权限运行"
    else
        print_warning "以普通用户运行，建议使用sudo运行"
        echo ""
    fi
    
    init_directories
    
    # 只检查acme.sh依赖
    if ! install_acme; then
        print_error "acme.sh安装失败"
        wait_for_confirmation
        exit 1
    fi
    
    main_menu
}

# 运行主程序
main
