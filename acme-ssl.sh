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
    print_message "$RED" "[✗]" "$1"
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

# ========== 依赖检查 ==========

check_dependencies() {
    print_info "检查系统依赖..."
    
    local missing=()
    local required=("openssl" "crontab" "dig")
    
    for cmd in "${required[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
            print_warning "缺失命令: $cmd"
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        print_warning "发现缺失命令: ${missing[*]}"
        print_info "请手动安装以下命令:"
        for cmd in "${missing[@]}"; do
            echo "  - $cmd"
        done
        echo -e "\n安装示例:"
        echo "  Ubuntu/Debian: sudo apt install openssl cron dnsutils"
        echo "  CentOS/RHEL: sudo yum install openssl crontab bind-utils"
        echo "  Alpine: sudo apk add openssl dcron bind-tools"
        return 1
    fi
    
    print_success "所有依赖已安装"
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

# 获取所有证书 - 改进版本，返回两个数组
get_all_certificates() {
    local certs=()
    local cert_dirs=()
    
    if [ ! -d "$ACME_DIR" ]; then
        # 返回两个空数组
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
    
    # 分别输出两个数组
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

# 获取DNS TXT记录
get_dns_txt_records() {
    local domain="$1"
    
    create_temp_dir
    local log_file="$TEMP_DIR/acme_manual.log"
    
    print_info "获取DNS验证信息..."
    
    # 构建命令 - 只处理单个域名
    local cmd=("$ACME_BIN" "--issue" "--dns" "-d" "$domain")
    
    cmd+=("--server" "letsencrypt" "--yes-I-know-dns-manual-mode-enough-go-ahead-please")
    
    # 执行命令 - 修改这里：实时显示输出
    echo -e "${BLUE}==========================================${NC}"
    echo -e "${YELLOW}[!] 正在执行acme.sh命令...${NC}"
    echo ""
    
    # 实时显示输出并保存到日志文件
    if ! "${cmd[@]}" 2>&1 | tee "$log_file"; then
        echo -e "${BLUE}==========================================${NC}"
        print_error "获取DNS验证信息失败"
        return 1
    fi
    echo ""
    echo -e "${BLUE}==========================================${NC}"
    
    # 从日志文件读取输出用于解析
    local cmd_output=""
    cmd_output=$(cat "$log_file")
    
    # 解析TXT记录
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
        if "${renew_cmd[@]}"; then
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
                local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
                if [ -n "$expiry_date" ]; then
                    echo "$((i+1))) $cert_name - 到期时间: $expiry_date"
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
    echo -e "${RED}[✗] 失败: $fail_count${NC}"
    
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
    echo -e "${RED}[✗] 失败: $fail_count${NC}"
    
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
            local expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
            if [ -n "$expiry_date" ]; then
                echo "$((i+1))) $cert_name - 到期时间: $expiry_date"
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
    
    # 申请证书
    print_info "开始申请证书: $domain"
    if get_dns_txt_records "$domain"; then
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
main_menu() {
    while true; do
        echo -e "\n${BLUE}=== ACME证书管理脚本 ===${NC}"
        echo "1) 申请证书"
        echo "2) 证书续期"
        echo "3) 删除证书"
        echo "4) 列出证书"
        echo "5) 重新安装"
        echo "0) 退出"
        echo ""
        read -p "请选择操作(0-5): " choice
        
        case $choice in
            1) cert_issue_menu ;;
            2) renew_certificate ;;
            3) delete_certificate ;;
            4) list_certificates ;;
            5) reinstall_acme ;;
            0) 
                print_success "再见！"
                exit 0
                ;;
            *)
                print_error "无效的选择，请输入 0-5"
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
    
    if ! check_dependencies; then
        print_error "依赖检查失败"
        wait_for_confirmation
        exit 1
    fi
    
    if ! install_acme; then
        print_error "acme.sh安装失败"
        wait_for_confirmation
        exit 1
    fi
    
    main_menu
}

# 运行主程序
main