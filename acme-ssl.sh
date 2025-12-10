#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置文件
ACME_DIR="$HOME/.acme.sh"
ACME_BIN="$ACME_DIR/acme.sh"  # 使用变量替代 alias

# 临时文件管理
TEMP_DIR=""
cleanup() {
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        echo -e "${BLUE}[*] 清理临时目录: $TEMP_DIR${NC}"
    fi
}
trap cleanup EXIT INT TERM

# 创建安全临时目录
create_temp_dir() {
    TEMP_DIR=$(mktemp -d "/tmp/acme_script_XXXXXX")
    echo -e "${BLUE}[*] 创建临时目录: $TEMP_DIR${NC}"
}

# 初始化目录
init_directories() {
    mkdir -p "$ACME_DIR"
}

# 检查并安装依赖 - 完全修正版
check_dependencies() {
    echo -e "${BLUE}[*] 检查系统依赖...${NC}"
    
    # 1. 首先检查核心依赖（必须）
    local core_missing=()
    
    # 注意：curl 不需要检查，因为脚本是用 curl 运行的
    # openssl 必须（证书操作）
    if ! command -v openssl &> /dev/null; then
        core_missing+=("openssl")
        echo -e "${YELLOW}[!] 缺失核心命令: openssl${NC}"
    fi
    
    # crontab 必须（自动续期）
    if ! command -v crontab &> /dev/null; then
        core_missing+=("crontab")
        echo -e "${YELLOW}[!] 缺失核心命令: crontab${NC}"
    fi
    
    # 2. 如果有缺失的核心依赖，尝试安装
    if [ ${#core_missing[@]} -gt 0 ]; then
        echo -e "${YELLOW}[!] 发现缺失核心命令: ${core_missing[*]}${NC}"
        echo -e "${BLUE}[*] 尝试安装核心依赖...${NC}"
        
        if ! install_packages "${core_missing[@]}"; then
            echo -e "${RED}[✗] 核心依赖安装失败，脚本无法继续${NC}"
            return 1
        fi
    else
        echo -e "${GREEN}[✓] 所有核心依赖已安装${NC}"
    fi
    
    # 3. 检查可选依赖（仅提示，不强制安装）
    echo -e "\n${BLUE}[*] 检查可选依赖...${NC}"
    
    # socat: 用于HTTP验证模式
    if ! command -v socat &> /dev/null; then
        echo -e "${YELLOW}[!] 可选依赖缺失: socat${NC}"
        echo -e "${BLUE}[!] 如需使用HTTP验证模式（Standalone），请手动安装:${NC}"
        echo -e "  Debian/Ubuntu: sudo apt-get install socat"
        echo -e "  CentOS/RHEL:   sudo yum install socat"
        echo -e "  Alpine Linux:  sudo apk add socat"
        echo -e "  或使用 DNS 验证模式（推荐）"
    fi
    
    # dig: 用于手动DNS验证的检查（比 nslookup 更好）
    if ! command -v dig &> /dev/null; then
        echo -e "${YELLOW}[!] 可选依赖缺失: dig${NC}"
        echo -e "${BLUE}[!] 如需更准确的DNS记录检查，请手动安装:${NC}"
        echo -e "  Debian/Ubuntu: sudo apt-get install dnsutils"
        echo -e "  CentOS/RHEL:   sudo yum install bind-utils"
        echo -e "  Alpine Linux:  sudo apk add bind-tools"
        echo -e "  可使用 nslookup 作为替代方案"
    fi
    
    # git: 用于GitHub安装方式（备选方案）
    if ! command -v git &> /dev/null; then
        echo -e "${YELLOW}[!] 可选依赖缺失: git${NC}"
        echo -e "${BLUE}[!] 仅当官方curl安装失败时才需要:${NC}"
        echo -e "  Debian/Ubuntu: sudo apt-get install git"
        echo -e "  CentOS/RHEL:   sudo yum install git"
        echo -e "  Alpine Linux:  sudo apk add git"
    fi
    
    # idn: 用于国际化域名（罕见需求）
    if ! command -v idn &> /dev/null; then
        echo -e "${YELLOW}[!] 可选依赖缺失: idn${NC}"
        echo -e "${BLUE}[!] 仅处理国际化域名（如中文域名）时需要:${NC}"
        echo -e "  Debian/Ubuntu: sudo apt-get install idn"
        echo -e "  CentOS/RHEL:   sudo yum install libidn"
        echo -e "  Alpine Linux:  sudo apk add libidn"
    fi
    
    echo -e "${GREEN}[✓] 依赖检查完成${NC}"
    return 0
}

# 安装包的辅助函数
install_packages() {
    local packages=("$@")
    
    if [ ${#packages[@]} -eq 0 ]; then
        return 0
    fi
    
    # 包名映射
    local -A debian_packages=(
        ["openssl"]="openssl"
        ["crontab"]="cron"
        ["socat"]="socat"
        ["dig"]="dnsutils"
        ["git"]="git"
        ["idn"]="idn"
    )
    
    local -A centos_packages=(
        ["openssl"]="openssl"
        ["crontab"]="cronie"
        ["socat"]="socat"
        ["dig"]="bind-utils"
        ["git"]="git"
        ["idn"]="libidn"
    )
    
    local -A alpine_packages=(
        ["openssl"]="openssl"
        ["crontab"]="dcron"  # Alpine 有 dcron, fcron, cronie 多种
        ["socat"]="socat"
        ["dig"]="bind-tools"
        ["git"]="git"
        ["idn"]="libidn"
    )
    
    echo -e "${BLUE}[*] 安装包: ${packages[*]}${NC}"
    
    if command -v apt-get &> /dev/null; then
        # Debian/Ubuntu
        local install_list=()
        for cmd in "${packages[@]}"; do
            local pkg="${debian_packages[$cmd]:-$cmd}"
            install_list+=("$pkg")
        done
        
        echo -e "${BLUE}[*] 使用 apt-get 安装: ${install_list[*]}${NC}"
        
        if apt-get update && apt-get install -y "${install_list[@]}"; then
            echo -e "${GREEN}[✓] 依赖安装成功${NC}"
            return 0
        else
            echo -e "${RED}[✗] 依赖安装失败${NC}"
            
            # 尝试分开安装
            echo -e "${YELLOW}[!] 尝试单独安装...${NC}"
            for pkg in "${install_list[@]}"; do
                if apt-get install -y "$pkg"; then
                    echo -e "${GREEN}[✓] 安装成功: $pkg${NC}"
                else
                    echo -e "${RED}[✗] 安装失败: $pkg${NC}"
                fi
            done
            
            return 1
        fi
        
    elif command -v yum &> /dev/null; then
        # CentOS/RHEL 7及以下
        local install_list=()
        for cmd in "${packages[@]}"; do
            local pkg="${centos_packages[$cmd]:-$cmd}"
            install_list+=("$pkg")
        done
        
        echo -e "${BLUE}[*] 使用 yum 安装: ${install_list[*]}${NC}"
        
        if yum install -y "${install_list[@]}"; then
            echo -e "${GREEN}[✓] 依赖安装成功${NC}"
            return 0
        else
            echo -e "${RED}[✗] 依赖安装失败${NC}"
            return 1
        fi
        
    elif command -v dnf &> /dev/null; then
        # Fedora/CentOS 8+
        local install_list=()
        for cmd in "${packages[@]}"; do
            local pkg="${centos_packages[$cmd]:-$cmd}"
            install_list+=("$pkg")
        done
        
        echo -e "${BLUE}[*] 使用 dnf 安装: ${install_list[*]}${NC}"
        
        if dnf install -y "${install_list[@]}"; then
            echo -e "${GREEN}[✓] 依赖安装成功${NC}"
            return 0
        else
            echo -e "${RED}[✗] 依赖安装失败${NC}"
            return 1
        fi
        
    elif command -v apk &> /dev/null; then
        # Alpine Linux
        local install_list=()
        for cmd in "${packages[@]}"; do
            local pkg="${alpine_packages[$cmd]:-$cmd}"
            install_list+=("$pkg")
        done
        
        echo -e "${BLUE}[*] 使用 apk 安装: ${install_list[*]}${NC}"
        
        if apk add --no-cache "${install_list[@]}"; then
            echo -e "${GREEN}[✓] 依赖安装成功${NC}"
            return 0
        else
            echo -e "${RED}[✗] 依赖安装失败${NC}"
            
            # Alpine 的 cron 可能有不同包名
            if [[ " ${packages[*]} " =~ " crontab " ]]; then
                echo -e "${YELLOW}[!] 尝试不同的cron包...${NC}"
                for cron_pkg in "dcron" "fcron" "cronie"; do
                    if apk add --no-cache "$cron_pkg"; then
                        echo -e "${GREEN}[✓] 安装成功: $cron_pkg (替代crontab)${NC}"
                        return 0
                    fi
                done
            fi
            
            return 1
        fi
        
    else
        echo -e "${RED}[✗] 无法确定包管理器${NC}"
        echo -e "${YELLOW}[!] 请手动安装以下命令:${NC}"
        for cmd in "${packages[@]}"; do
            echo "  - $cmd"
            case "$cmd" in
                "openssl")
                    echo "    # 几乎所有Linux发行版都需要此命令"
                    ;;
                "crontab")
                    echo "    # 自动续期必需，但可手动运行续期命令替代"
                    ;;
            esac
        done
        
        echo -e "\n${YELLOW}[!] 安装建议:${NC}"
        echo "1. 先尝试安装核心依赖：openssl 和 crontab"
        echo "2. 如无法安装crontab，可手动运行续期：~/.acme.sh/acme.sh --cron"
        echo "3. 可选依赖不是必须的"
        
        return 1
    fi
}

# 安装acme.sh
install_acme() {
    echo -e "${BLUE}[*] 检查acme.sh安装...${NC}"
    
    if [ -f "$ACME_BIN" ]; then
        echo -e "${GREEN}[✓] acme.sh已安装${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}[!] acme.sh未安装，开始安装...${NC}"
    
    # 尝试官方安装
    echo -e "${BLUE}[*] 尝试官方安装...${NC}"
    if curl -fsSL https://get.acme.sh | sh; then
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
            
            # ==================== 改进的证书文件查找逻辑开始 ====================
            local cert_file=""
            
            # 1. 首先检查域名加各种后缀的文件（最高优先级）
            local domain_cert_files=(
                "$cert_dir/$domain.cer"
                "$cert_dir/$domain.crt"
                "$cert_dir/$domain.pem"
            )
            
            for file in "${domain_cert_files[@]}"; do
                if [ -f "$file" ]; then
                    cert_file="$file"
                    break
                fi
            done
            
            # 2. 如果没有找到，检查完整链证书
            if [ -z "$cert_file" ]; then
                local fullchain_files=(
                    "$cert_dir/fullchain.cer"
                    "$cert_dir/fullchain.crt"
                    "$cert_dir/fullchain.pem"
                )
                
                for file in "${fullchain_files[@]}"; do
                    if [ -f "$file" ]; then
                        cert_file="$file"
                        break
                    fi
                done
            fi
            
            # 3. 如果还没有找到，检查通用证书文件名
            if [ -z "$cert_file" ]; then
                local generic_cert_files=(
                    "$cert_dir/cert.pem"
                    "$cert_dir/certificate.pem"
                    "$cert_dir/cert.cer"
                    "$cert_dir/cert.crt"
                )
                
                for file in "${generic_cert_files[@]}"; do
                    if [ -f "$file" ]; then
                        cert_file="$file"
                        break
                    fi
                done
            fi
            
            # 4. 最后的手段：查找任何证书文件
            if [ -z "$cert_file" ]; then
                local any_cert=$(find "$cert_dir" -maxdepth 1 -type f \( -name "*.cer" -o -name "*.crt" -o -name "*.pem" \) 2>/dev/null | head -1)
                if [ -n "$any_cert" ]; then
                    cert_file="$any_cert"
                fi
            fi
            # ==================== 改进的证书文件查找逻辑结束 ====================
            
            # 如果有证书文件
            if [ -n "$cert_file" ]; then
                # 如果指定了目标域名
                if [ -n "$target_domain" ]; then
                    if [ "$domain" = "$target_domain" ]; then
                        # 找到目标域名的证书
                        _CERT_DIR="$cert_dir"
                        _CERT_PATH="$cert_file"
                        
                        # ==================== 改进的私钥查找逻辑开始 ====================
                        # 查找私钥
                        local key_file=""
                        local possible_key_files=(
                            "$cert_dir/$domain.key"
                            "$cert_dir/privkey.pem"
                            "$cert_dir/key.pem"
                            "$cert_dir/private.key"
                        )
                        
                        for file in "${possible_key_files[@]}"; do
                            if [ -f "$file" ]; then
                                key_file="$file"
                                break
                            fi
                        done
                        
                        # 如果还没有找到，查找任何.key或.pem文件
                        if [ -z "$key_file" ]; then
                            local any_key=$(find "$cert_dir" -maxdepth 1 -type f \( -name "*.key" -o -name "*key*.pem" \) 2>/dev/null | head -1)
                            if [ -n "$any_key" ]; then
                                key_file="$any_key"
                            fi
                        fi
                        
                        if [ -n "$key_file" ]; then
                            _KEY_PATH="$key_file"
                        fi
                  
                        # ==================== 改进的CA证书查找逻辑开始 ====================
                        # 查找CA证书
                        local ca_file=""
                        local possible_ca_files=(
                            "$cert_dir/ca.cer"
                            "$cert_dir/ca.crt"
                            "$cert_dir/chain.pem"
                            "$cert_dir/ca.pem"
                            "$cert_dir/chain.crt"
                        )
                        
                        for file in "${possible_ca_files[@]}"; do
                            if [ -f "$file" ]; then
                                ca_file="$file"
                                break
                            fi
                        done
                        
                        if [ -n "$ca_file" ]; then
                            _CA_PATH="$ca_file"
                        fi
         
                        # ==================== 改进的完整链证书查找逻辑开始 ====================
                        # 查找完整链证书
                        local fullchain_file=""
                        local possible_fullchain_files=(
                            "$cert_dir/fullchain.cer"
                            "$cert_dir/fullchain.crt"
                            "$cert_dir/fullchain.pem"
                        )
                        
                        for file in "${possible_fullchain_files[@]}"; do
                            if [ -f "$file" ]; then
                                fullchain_file="$file"
                                break
                            fi
                        done
                        
                        if [ -n "$fullchain_file" ]; then
                            _FULLCHAIN_PATH="$fullchain_file"
                        fi
                        # ==================== 改进的完整链证书查找逻辑结束 ====================
                        
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

# 显示证书详细信息函数 - 修复重复显示问题
show_cert_detail() {
    local domain="$1"
    local cert_dir="$2"
    
    echo -e "${BLUE}[*] 解析证书目录: $cert_dir${NC}"
    
    # 查找证书文件（主要证书）
    local cert_file=""
    local cert_candidates=()
    
    # 优先查找域名命名的证书文件
    local domain_cert_files=(
        "$cert_dir/$domain.cer"
        "$cert_dir/$domain.crt"
        "$cert_dir/$domain.pem"
    )
    
    for file in "${domain_cert_files[@]}"; do
        if [ -f "$file" ]; then
            cert_file="$file"
            echo "  - 证书: $file"
            break
        fi
    done
    
    # 如果没有找到域名证书，查找通用证书文件
    if [ -z "$cert_file" ]; then
        local generic_cert_files=(
            "$cert_dir/cert.pem"
            "$cert_dir/certificate.pem"
            "$cert_dir/cert.cer"
            "$cert_dir/cert.crt"
        )
        
        for file in "${generic_cert_files[@]}"; do
            if [ -f "$file" ]; then
                cert_file="$file"
                echo "  - 证书: $file"
                break
            fi
        done
    
    # 查找私钥
    local key_file=""
    local possible_key_files=(
        "$cert_dir/$domain.key"
        "$cert_dir/privkey.pem"
        "$cert_dir/key.pem"
        "$cert_dir/private.key"
    )
    
    for file in "${possible_key_files[@]}"; do
        if [ -f "$file" ]; then
            key_file="$file"
            echo "  - 私钥: $file"
            break
        fi
    done
    
    # 如果还没有找到，查找任何.key文件
    if [ -z "$key_file" ]; then
        local any_key=$(find "$cert_dir" -maxdepth 1 -type f -name "*.key" 2>/dev/null | head -1)
        if [ -n "$any_key" ]; then
            echo "  - 私钥: $any_key"
        fi
    fi
    
    # 查找完整链证书
    local fullchain_files=(
        "$cert_dir/fullchain.cer"
        "$cert_dir/fullchain.crt"
        "$cert_dir/fullchain.pem"
    )
    
    for file in "${fullchain_files[@]}"; do
        if [ -f "$file" ] && [ "$file" != "$cert_file" ]; then  # 避免重复显示
            echo "  - 完整链: $file"
            break
        fi
    done
    
    # 查找CA证书
    local ca_files=(
        "$cert_dir/ca.cer"
        "$cert_dir/ca.crt"
        "$cert_dir/chain.pem"
        "$cert_dir/ca.pem"
        "$cert_dir/chain.crt"
    )
    
    for file in "${ca_files[@]}"; do
        if [ -f "$file" ] && [ "$file" != "$cert_file" ]; then  # 避免重复显示
            echo "  - CA证书: $file"
            break
        fi
    done
    
    # 如果有证书文件，显示证书摘要
    if [ -n "$cert_file" ]; then
        echo -e "${YELLOW}证书摘要:${NC}"
        openssl x509 -in "$cert_file" -noout -subject -issuer -dates 2>/dev/null || echo "  (无法读取证书信息)"
        
        # 显示证书有效期（天数和到期时间）
        echo -e "${YELLOW}证书有效期:${NC}"
        local expiry_info
        expiry_info=$(openssl x509 -in "$cert_file" -noout -dates 2>/dev/null)
        if [ $? -eq 0 ]; then
            local not_before=$(echo "$expiry_info" | grep "notBefore" | cut -d= -f2)
            local not_after=$(echo "$expiry_info" | grep "notAfter" | cut -d= -f2)
            echo "  生效时间: $not_before"
            echo "  到期时间: $not_after"
            
            # 计算剩余天数
            local now_seconds=$(date +%s)
            local expiry_seconds=$(date -d "$not_after" +%s 2>/dev/null || echo "")
            if [ -n "$expiry_seconds" ] && [ "$expiry_seconds" -gt "$now_seconds" ]; then
                local days_left=$(( (expiry_seconds - now_seconds) / 86400 ))
                echo "  剩余天数: $days_left 天"
            fi
        else
            echo "  (无法获取有效期信息)"
        fi
    else
        echo -e "${YELLOW}[!] 未找到证书文件${NC}"
    fi
}

# 检查DNS记录 - 支持通配符域名（修复版）
check_dns_record() {
    local domain="$1"
    local txt_record="$2"
    local max_attempts=36
    local attempt=1
    
    echo -e "${BLUE}[*] 检查DNS记录: _acme-challenge.$domain${NC}"
    
    # 处理通配符域名 - 修复判断逻辑
    local check_domain="_acme-challenge.$domain"
    if [[ "${domain:0:2}" == "*." ]]; then
        # 如果是通配符域名，需要检查通配符记录
        check_domain="_acme-challenge.${domain:2}"
        echo -e "${YELLOW}[!] 通配符域名检测: 实际检查 $check_domain${NC}"
    fi
    
    # DNS服务器列表
    local dns_servers=("8.8.8.8" "1.1.1.1" "1.0.0.1" "8.8.4.4")
    local required_success=2  # 至少需要2个DNS服务器返回正确结果
    
    while [ $attempt -le $max_attempts ]; do
        echo -ne "${YELLOW}[!] 尝试 $attempt/$max_attempts...\r${NC}"
        
        local success=0
        local results=()
        
        for dns_server in "${dns_servers[@]}"; do
            local query_result
            query_result=$(dig +short TXT "$check_domain" @"$dns_server" 2>/dev/null)
            
            # 清理结果：去除引号，合并多行
            local cleaned_result=""
            if [ -n "$query_result" ]; then
                # 合并多行并去除引号
                cleaned_result=$(echo "$query_result" | tr '\n' ' ' | sed 's/"//g' | xargs)
            fi
            
            if [[ "$cleaned_result" == *"$txt_record"* ]]; then
                ((success++))
                results+=("✓ $dns_server: 匹配")
            else
                results+=("✗ $dns_server: '$cleaned_result'")
            fi
        done
        
        if [ $success -ge $required_success ]; then
            echo -e "\n${GREEN}[✓] DNS记录已在 $success/${#dns_servers[@]} 个DNS服务器生效${NC}"
            return 0
        fi
        
        sleep 5
        ((attempt++))
    done
    
    echo -e "\n${YELLOW}[!] DNS记录检查超时: $check_domain${NC}"
    echo -e "${YELLOW}[!] 最终检查结果:${NC}"
    for result in "${results[@]}"; do
        echo "  $result"
    done
    
    read -p "是否继续尝试验证？(y/n): " continue_anyway
    if [[ $continue_anyway =~ ^[Yy]$ ]]; then
        return 0
    else
        echo -e "${YELLOW}[!] 您可以稍后手动执行续期:${NC}"
        echo "  $ACME_BIN --renew $domain_params --force"
        return 1
    fi
}

# 注册证书颁发机构
register_ca() {
    local ca="$1"
    local email="$2"
    
    case "$ca" in
        "letsencrypt")
            "$ACME_BIN" --register-account -m "$email" \
                --server letsencrypt || return 1
            ;;
        "zerossl")
            echo -e "${YELLOW}[!] ZeroSSL需要EAB凭证${NC}"
            read -p "请输入EAB Key ID: " eab_kid
            read -p "请输入EAB HMAC Key: " eab_hmac
            
            "$ACME_BIN" --register-account -m "$email" \
                --server zerossl \
                --eab-kid "$eab_kid" \
                --eab-hmac-key "$eab_hmac" || return 1
            ;;
        "buypass")
            "$ACME_BIN" --register-account -m "$email" \
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

# 申请证书 - 支持多域名版本（修复手动模式）
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
    
    if [ "$mode" = "manual" ]; then
        echo -e "${YELLOW}[!] 使用手动DNS验证模式${NC}"
        echo -e "${YELLOW}[!] 注意：每个域名都需要单独添加DNS TXT记录${NC}"
        
        # 创建临时日志文件（安全版本）
        create_temp_dir
        local log_file="$TEMP_DIR/acme_manual.log"
        
        echo -e "${BLUE}[*] 正在获取DNS验证信息...${NC}"
        
        # 构建acme.sh命令 - 只获取TXT记录，不立即验证
        local get_txt_cmd=("$ACME_BIN" "--issue" "--dns")
        for domain in "${domains[@]}"; do
            get_txt_cmd+=("-d" "$domain")
        done
        
        if [ -n "$email" ]; then
            get_txt_cmd+=("-m" "$email")
        fi
        
        get_txt_cmd+=("--server" "$ca" "--yes-I-know-dns-manual-mode-enough-go-ahead-please" "--log-level" "2")
        
        echo -e "${BLUE}[*] 执行命令...${NC}"
        echo -e "${YELLOW}[!] 命令: ${get_txt_cmd[*]}${NC}"
        
        # 执行命令并捕获输出 - 重要的是获取输出，而不是检查退出码
        local cmd_output=""
        cmd_output=$("${get_txt_cmd[@]}" 2>&1 | tee "$log_file")
        local exit_code=${PIPESTATUS[0]}
        
        # 显示命令输出
        echo "$cmd_output"
        
        # 重要修复：在手动模式下，acme.sh会显示TXT记录然后退出（非零状态）
        # 这是正常行为，不是错误！
        
        # 检查是否成功获取了TXT记录
        local found_txt_record=false
        
        for domain in "${domains[@]}"; do
            if grep -q "TXT value" "$log_file" && grep -q "$domain" "$log_file"; then
                found_txt_record=true
                break
            fi
        done
        
        if [ "$found_txt_record" = false ]; then
            # 检查是否是"证书已存在"的情况
            if grep -qi "already exists" "$cmd_output" || grep -qi "already issued" "$cmd_output"; then
                echo -e "${YELLOW}[!] 检测到该域名可能已有证书${NC}"
                echo -e "${YELLOW}[!] 尝试续期现有证书...${NC}"
                
                # 尝试续期
                local renew_cmd=("$ACME_BIN" "--renew")
                for domain in "${domains[@]}"; do
                    renew_cmd+=("-d" "$domain")
                done
                renew_cmd+=("--force")
                
                if [ "$ca" != "letsencrypt" ]; then
                    renew_cmd+=("--server" "$ca")
                fi
                
                if "${renew_cmd[@]}"; then
                    echo -e "${GREEN}[✓] 证书续期成功${NC}"
                    return 0
                else
                    echo -e "${RED}[✗] 证书续期失败${NC}"
                    return 1
                fi
            else
                echo -e "${RED}[✗] 获取DNS验证信息失败，未找到TXT记录${NC}"
                return 1
            fi
        fi
        
        # 解析日志，获取每个域名的TXT记录
        declare -A domain_txt_records
        
        for domain in "${domains[@]}"; do
            # 从日志中提取该域名的TXT记录
            local txt_record=""
            
            # 从命令输出中直接提取（更可靠）
            txt_record=$(echo "$cmd_output" | grep -A 2 "Domain: '_acme-challenge.$domain'" | grep "TXT value:" | sed -n "s/.*TXT value: '\([^']*\)'.*/\1/p")
            
            if [ -z "$txt_record" ]; then
                txt_record=$(echo "$cmd_output" | grep -i "txt value:" | grep -i "$domain" | sed -n "s/.*TXT value: '\([^']*\)'.*/\1/p")
            fi
            
            if [ -z "$txt_record" ]; then
                txt_record=$(echo "$cmd_output" | grep -i "TXT value:" | tail -1 | sed -n "s/.*TXT value: '\([^']*\)'.*/\1/p")
            fi
            
            if [ -z "$txt_record" ]; then
                echo -e "${YELLOW}[!] 无法自动获取域名 $domain 的TXT记录${NC}"
                echo -e "${YELLOW}[!] 请从上面的输出中手动查找TXT记录值${NC}"
                read -p "请手动输入 _acme-challenge.$domain 的TXT记录值: " txt_record
            fi
            
            if [ -n "$txt_record" ]; then
                domain_txt_records["$domain"]="$txt_record"
                echo -e "${GREEN}[✓] 获取到域名 $domain 的TXT记录${NC}"
            fi
        done
        
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
        echo -e "${YELLOW}[!] 您可以使用以下命令检查DNS记录:${NC}"
        echo "  dig +short TXT _acme-challenge.$domain @8.8.8.8"
        echo "  nslookup -type=TXT _acme-challenge.$domain"
        echo ""
        
        # 等待用户确认
        echo -e "${BLUE}[*] 等待您添加DNS记录...${NC}"
        read -p "DNS记录添加完成并等待生效后，按回车键继续验证..."
        
        # 检查所有域名的DNS记录
        local all_dns_valid=true
        for domain in "${domains[@]}"; do
            local txt_record="${domain_txt_records[$domain]}"
            if [ -n "$txt_record" ]; then
                echo -e "${BLUE}[*] 检查域名 $domain 的DNS记录...${NC}"
                if ! check_dns_record "$domain" "$txt_record"; then
                    echo -e "${RED}[✗] 域名 $domain 的DNS验证失败${NC}"
                    all_dns_valid=false
                fi
            fi
        done
        
        if [ "$all_dns_valid" = false ]; then
            echo -e "${RED}[✗] 部分域名DNS验证失败${NC}"
            return 1
        fi
        
        # 步骤2：完成证书申请
        echo -e "\n${BLUE}[*] 所有域名DNS验证通过，正在签发证书...${NC}"
        
        local renew_cmd=("$ACME_BIN" "--renew")
        for domain in "${domains[@]}"; do
            renew_cmd+=("-d" "$domain")
        done
        renew_cmd+=("--force" "--yes-I-know-dns-manual-mode-enough-go-ahead-please")
        
        if [ "$ca" != "letsencrypt" ]; then
            renew_cmd+=("--server" "$ca")
        fi
        
        echo -e "${YELLOW}[!] 执行命令: ${renew_cmd[*]}${NC}"
        
        if "${renew_cmd[@]}"; then
            echo -e "${GREEN}[✓] 证书申请成功！${NC}"
            
            # 显示证书信息
            echo -e "\n${BLUE}[*] 显示证书信息...${NC}"
            # 将主域名传递给证书列表函数
            local clean_domain="${primary_domain//\*/_}"
            list_certificates "$clean_domain"
            
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
        echo "  3. 执行申请命令：<服务商为dnsapi中脚本的服务商名称，去除 \".sh\">"
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
        
        # 构建包含所有域名的命令（使用数组）
        local cmd=("$ACME_BIN" "--issue" "--dns" "$dns_api")
        for domain in "${domains[@]}"; do
            cmd+=("-d" "$domain")
        done
        cmd+=("--server" "$ca")
        
        if [ -n "$email" ]; then
            cmd+=("-m" "$email")
        fi
        
        echo -e "${BLUE}[*] 正在申请证书...${NC}"
        echo -e "${YELLOW}[!] 命令: ${cmd[*]}${NC}"
        
        if "${cmd[@]}"; then
            echo -e "${GREEN}[✓] 证书申请成功${NC}"
            unset CF_Key CF_Email CF_Token 2>/dev/null
            
            # 显示证书信息
            echo -e "\n${BLUE}[*] 显示证书信息...${NC}"
            # 将主域名传递给证书列表函数
            local clean_domain="${primary_domain//\*/_}"
            list_certificates "$clean_domain"
            
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
    
    # 执行证书申请
    issue_certificate "${domains[@]}" "$ca" "$mode" "$email"
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
    if "$ACME_BIN" --renew --domain "$domain" --force; then
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
        echo "  $ACME_BIN --renew -d $domain --force --debug"
        
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
            
            local file_type="证书"
            if [[ "$cert_dir" == *"_ecc" ]]; then
                file_type="ECC证书"
            elif [ -f "$cert_dir/fullchain.cer" ] || [ -f "$cert_dir/fullchain.crt" ]; then
                file_type="完整链证书"
            fi
            
            if [ -n "$expiry_date" ]; then
                echo "$index) $cert_name - $file_type"
                echo "    到期时间: $expiry_date"
                echo "    目录位置: $cert_dir"
            else
                echo "$index) $cert_name - $file_type"
                echo "    目录位置: $cert_dir"
            fi
        else
            echo "$index) $cert_name"
            echo "    目录位置: $cert_dir"
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
    if "$ACME_BIN" --remove --domain "$domain" 2>/dev/null; then
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

# 列出证书 - 优化版：支持按序号查看详细路径信息，可接收参数
list_certificates() {
    local target_domain="$1"  # 可选参数：如果指定域名，直接显示该域名证书信息
    
    # 如果有参数，直接显示指定域名的证书信息
    if [ -n "$target_domain" ]; then
        echo -e "\n${BLUE}=== 证书信息: $target_domain ===${NC}"
        
        # 使用统一的证书查找函数查找指定域名的证书
        if find_certificates "$target_domain"; then
            # 显示找到的证书信息
            echo -e "${GREEN}[✓] 找到证书: $target_domain${NC}"
            echo -e "${BLUE}========================================${NC}"
            echo -e "${YELLOW}[*] 证书详细路径信息:${NC}"
            
            # 使用show_cert_detail函数显示详细信息
            show_cert_detail "$target_domain" "$_CERT_DIR"
            
            echo -e "${BLUE}========================================${NC}"
            return 0
        else
            echo -e "${YELLOW}[!] 未找到域名 $target_domain 的证书${NC}"
            return 1
        fi
    fi
    
    # 如果没有参数，显示交互式菜单（原逻辑）
    echo -e "\n${BLUE}=== 证书列表 ===${NC}"
    
    # 使用统一的证书查找函数查找所有证书
    find_certificates
    
    if [ ${#_CERT_ARRAY[@]} -eq 0 ]; then
        echo -e "${YELLOW}[!] 没有找到证书${NC}"
        echo -e "\n${YELLOW}按回车键返回主菜单...${NC}"
        return 1
    fi
    
    local certs=("${_CERT_ARRAY[@]}")
    local cert_dirs=("${_CERT_DIR_ARRAY[@]}")
    
    echo -e "${GREEN}[✓] 找到 ${#certs[@]} 个证书:${NC}\n"
    
    # 显示证书列表（交互式菜单部分保持不变）
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
                echo "    目录位置: $cert_dir"
            else
                echo "$((i+1))) $cert_name - $file_type"
                echo "    目录位置: $cert_dir"
            fi
        else
            echo "$((i+1))) $cert_name"
            echo "    目录位置: $cert_dir"
        fi
        echo ""
    done
    
    # 询问用户是否要查看特定证书的详细路径（交互式部分保持不变）
    echo -e "${BLUE}----------------------------------------${NC}"
    echo -e "${YELLOW}[?] 您可以输入证书序号查看详细文件路径${NC}"
    echo -e "${YELLOW}[?] 输入0返回主菜单${NC}"
    echo -e "${BLUE}----------------------------------------${NC}"
    
    while true; do
        read -p "请输入证书序号查看详细路径 (0返回): " selected_index
        
        if [ -z "$selected_index" ]; then
            continue
        fi
        
        if [[ "$selected_index" =~ ^[0]$ ]]; then
            echo -e "${BLUE}[*] 返回主菜单${NC}"
            break
        fi
        
        if ! [[ "$selected_index" =~ ^[0-9]+$ ]] || [ "$selected_index" -lt 1 ] || [ "$selected_index" -gt ${#certs[@]} ]; then
            echo -e "${RED}[✗] 无效的序号，请输入1-${#certs[@]}之间的数字${NC}"
            continue
        fi
        
        local domain="${certs[$((selected_index-1))]}"
        local cert_dir="${cert_dirs[$((selected_index-1))]}"
        
        # 显示选中证书的详细信息
        echo -e "\n${GREEN}[✓] 证书: $domain${NC}"
        echo -e "${BLUE}========================================${NC}"
        echo -e "${YELLOW}[*] 证书详细路径信息:${NC}"
        
        # 使用新增的show_cert_detail函数
        show_cert_detail "$domain" "$cert_dir"
        
        echo -e "${BLUE}========================================${NC}"
        echo ""
        echo -e "${YELLOW}按任意键返回证书列表继续查看其他证书...${NC}"
        read -n 1 -s -r
        echo ""
        
        # 重新显示证书列表
        echo -e "${GREEN}[Success] 证书列表: ${NC}"
        for i in "${!certs[@]}"; do
            local cert_name="${certs[$i]}"
            echo "  $((i+1))) $cert_name"
        done
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
    
    # 使用安全临时目录
    create_temp_dir
    local backup_dir="$TEMP_DIR/acme_backup"
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
    if [ -f "$ACME_BIN" ]; then
        "$ACME_BIN" --uninstall 2>/dev/null || true
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
        
        # 清理备份（由trap自动处理）
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
    if [ "$EUID" -eq 0 ]; then
        echo -e "${GREEN}[✓] 以ROOT权限运行${NC}"
    else
        echo -e "${YELLOW}[!] 以普通用户运行，部分功能受限${NC}"
        echo -e "${BLUE}[!] 提示：使用sudo可获得完整功能${NC}"
        echo ""
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
    
    main_menu
}

# 运行主程序
main
