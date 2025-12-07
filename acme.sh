#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置文件路径和版本
CONFIG_VERSION="1.1"
CONFIG_DIR="$HOME/.acme_script"
DNS_API_DIR="$CONFIG_DIR/dns_apis"
LOG_DIR="$CONFIG_DIR/logs"
LOG_FILE="$LOG_DIR/acme_$(date +%Y%m%d).log"
VERSION_FILE="$CONFIG_DIR/version"
ACME_INSTALL_DIR="$HOME/.acme.sh"

# 创建必要目录
mkdir -p "$CONFIG_DIR" "$DNS_API_DIR" "$LOG_DIR"

# 日志函数
log_message() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo -e "$1"
}

# 显示横幅
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              acme.sh 证书自动化管理脚本 v1.1             ║"
    echo "║                  轻量级 SSL 证书申请工具                 ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# 检查配置文件兼容性
check_config_compatibility() {
    if [[ -f "$VERSION_FILE" ]]; then
        local old_version=$(cat "$VERSION_FILE")
        if [[ "$old_version" != "$CONFIG_VERSION" ]]; then
            echo -e "${YELLOW}警告: 配置文件版本不匹配 ($old_version → $CONFIG_VERSION)${NC}"
            echo -e "${CYAN}建议备份后重置配置${NC}"
            read -rp "是否重置配置? (y/n): " reset_choice
            if [[ "$reset_choice" =~ ^[Yy]$ ]]; then
                reset_configuration
            fi
        fi
    fi
    echo "$CONFIG_VERSION" > "$VERSION_FILE"
}

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_message "${RED}错误: 命令 '$1' 未找到${NC}"
        return 1
    fi
    return 0
}

# 检查依赖
check_dependencies() {
    local missing_deps=()
    
    # 检查curl
    if ! check_command "curl"; then
        missing_deps+=("curl")
    fi
    
    # 检查openssl
    if ! check_command "openssl"; then
        missing_deps+=("openssl")
    fi
    
    # 检查crontab（用于自动续期）
    if ! check_command "crontab"; then
        missing_deps+=("cron")
    fi
    
    # 检查dig（用于DNS排错）
    if ! check_command "dig"; then
        missing_deps+=("dnsutils")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_message "${RED}缺少必要的依赖: ${missing_deps[*]}${NC}"
        read -rp "$(echo -e "${YELLOW}是否要自动安装缺少的依赖? (y/n): ${NC}")" install_choice
        if [[ "$install_choice" =~ ^[Yy]$ ]]; then
            install_dependencies "${missing_deps[@]}"
        else
            log_message "${RED}请手动安装缺少的依赖后重新运行脚本。${NC}"
            exit 1
        fi
    fi
}

# 安装依赖
install_dependencies() {
    local os_id
    os_id=$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    
    log_message "${BLUE}检测到系统: $os_id${NC}"
    log_message "${BLUE}开始安装依赖...${NC}"
    
    case $os_id in
        ubuntu|debian)
            apt-get update
            apt-get install -y "$@"
            ;;
        centos|rhel|fedora)
            yum install -y epel-release
            yum install -y "$@"
            ;;
        alpine)
            apk add --no-cache "$@"
            ;;
        *)
            log_message "${RED}不支持的Linux发行版，请手动安装依赖。${NC}"
            exit 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        log_message "${GREEN}依赖安装完成！${NC}"
    else
        log_message "${RED}依赖安装失败，请手动安装。${NC}"
        exit 1
    fi
}

# 安装或检查 acme.sh
install_acme() {
    echo -e "${CYAN}检查 acme.sh 安装状态...${NC}"
    
    if [[ -f "$ACME_INSTALL_DIR/acme.sh" ]] || command -v acme.sh &> /dev/null; then
        echo -e "${GREEN}✓ acme.sh 已安装${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}acme.sh 未安装，开始安装...${NC}"
    echo -e "${CYAN}安装选项:${NC}"
    echo "1) 在线安装（推荐）"
    echo "2) 从 GitHub 安装"
    echo "3) 手动安装"
    
    read -rp "请选择安装方式 (1/2/3): " install_method
    
    case $install_method in
        1)
            # 在线安装
            echo -e "${BLUE}正在从官方源安装 acme.sh...${NC}"
            curl https://get.acme.sh | sh -s email=my@example.com
            ;;
        2)
            # 从 GitHub 安装
            echo -e "${BLUE}正在从 GitHub 安装 acme.sh...${NC}"
            git clone https://github.com/acmesh-official/acme.sh.git "$ACME_INSTALL_DIR"
            cd "$ACME_INSTALL_DIR" || exit 1
            ./acme.sh --install
            ;;
        3)
            echo -e "${YELLOW}请手动安装 acme.sh:${NC}"
            echo "访问: https://github.com/acmesh-official/acme.sh"
            echo "或运行: curl https://get.acme.sh | sh"
            read -rp "按回车键继续..."
            return 1
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            return 1
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ acme.sh 安装成功！${NC}"
        # 重新加载环境变量
        source ~/.bashrc 2>/dev/null || source ~/.profile 2>/dev/null || source ~/.bash_profile 2>/dev/null
        return 0
    else
        echo -e "${RED}✗ acme.sh 安装失败${NC}"
        return 1
    fi
}

# 获取 acme.sh 命令路径（优化版）
get_acme_cmd() {
    local possible_paths=(
        "acme.sh"
        "$HOME/.acme.sh/acme.sh"
        "/usr/local/bin/acme.sh"
        "/opt/acme.sh/acme.sh"
        "/root/.acme.sh/acme.sh"
    )
    
    for cmd in "${possible_paths[@]}"; do
        if command -v "$cmd" &> /dev/null || [[ -f "$cmd" && -x "$cmd" ]]; then
            echo "$cmd"
            return 0
        fi
    done
    
    echo -e "${YELLOW}警告: 未找到acme.sh命令，尝试在PATH中搜索...${NC}"
    
    # 最后尝试在PATH中搜索
    local found_cmd=$(which acme.sh 2>/dev/null || command -v acme.sh 2>/dev/null)
    if [[ -n "$found_cmd" ]]; then
        echo "$found_cmd"
        return 0
    fi
    
    echo ""
    return 1
}

# 安全添加环境变量到配置文件
add_env_to_profile() {
    local var_name="$1"
    local var_value="$2"
    local profile_file="$HOME/.bashrc"
    
    # 移除已存在的设置
    sed -i "/export $var_name=/d" "$profile_file" 2>/dev/null
    
    # 添加新设置
    echo "export $var_name='$var_value'" >> "$profile_file"
    
    # 立即生效（当前会话）
    export "$var_name"="$var_value"
}

# 配置DNS API
setup_dns_api() {
    echo -e "${CYAN}选择DNS服务商:${NC}"
    echo "1) Cloudflare"
    echo "2) 阿里云 (Aliyun)"
    echo "3) 腾讯云 (DNSPod)"
    echo "4) 华为云"
    echo "5) 自定义DNS API"
    echo "0) 返回主菜单"
    
    read -rp "请选择: " dns_choice
    
    case $dns_choice in
        1)
            setup_cloudflare
            ;;
        2)
            setup_aliyun
            ;;
        3)
            setup_dnspod
            ;;
        4)
            setup_huaweicloud
            ;;
        5)
            setup_custom_dns
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            setup_dns_api
            ;;
    esac
}

# Cloudflare配置
setup_cloudflare() {
    echo -e "${YELLOW}=== Cloudflare DNS API 配置 ===${NC}"
    echo -e "${CYAN}请按照以下步骤获取API凭证:${NC}"
    echo "1. 登录Cloudflare控制台"
    echo "2. 进入'我的个人资料' -> 'API令牌'"
    echo "3. 创建令牌 -> 编辑区域DNS模板"
    echo "4. 选择需要管理的域名"
    echo ""
    
    read -rp "请输入API令牌: " cf_token
    read -rp "请输入Cloudflare账户邮箱: " cf_email
    
    if [[ -z "$cf_token" || -z "$cf_email" ]]; then
        echo -e "${RED}API令牌和邮箱不能为空${NC}"
        return 1
    fi
    
    # 保存到环境变量
    export CF_Token="$cf_token"
    export CF_Email="$cf_email"
    
    # 测试配置
    local acme_cmd=$(get_acme_cmd)
    if [[ -n "$acme_cmd" ]]; then
        echo -e "${BLUE}测试DNS API配置...${NC}"
        if $acme_cmd --issue --dns dns_cf --dnssleep 10 --test; then
            echo -e "${GREEN}✓ Cloudflare配置测试成功${NC}"
            
            # 永久保存配置（安全添加）
            add_env_to_profile "CF_Token" "$cf_token"
            add_env_to_profile "CF_Email" "$cf_email"
            echo -e "${GREEN}配置已安全保存到环境变量${NC}"
        else
            echo -e "${RED}✗ Cloudflare配置测试失败${NC}"
            unset CF_Token
            unset CF_Email
            return 1
        fi
    fi
}

# 阿里云配置
setup_aliyun() {
    echo -e "${YELLOW}=== 阿里云DNS API 配置 ===${NC}"
    echo -e "${CYAN}请按照以下步骤获取API凭证:${NC}"
    echo "1. 登录阿里云控制台"
    echo "2. 进入'AccessKey管理'"
    echo "3. 创建AccessKey"
    echo ""
    
    read -rp "请输入AccessKey ID: " aliyun_key
    read -rp "请输入AccessKey Secret: " aliyun_secret
    
    if [[ -z "$aliyun_key" || -z "$aliyun_secret" ]]; then
        echo -e "${RED}AccessKey ID和Secret不能为空${NC}"
        return 1
    fi
    
    # 保存到环境变量
    export Ali_Key="$aliyun_key"
    export Ali_Secret="$aliyun_secret"
    
    # 测试配置
    local acme_cmd=$(get_acme_cmd)
    if [[ -n "$acme_cmd" ]]; then
        echo -e "${BLUE}测试DNS API配置...${NC}"
        if $acme_cmd --issue --dns dns_ali --dnssleep 10 --test; then
            echo -e "${GREEN}✓ 阿里云配置测试成功${NC}"
            
            # 永久保存配置
            add_env_to_profile "Ali_Key" "$aliyun_key"
            add_env_to_profile "Ali_Secret" "$aliyun_secret"
            echo -e "${GREEN}配置已安全保存到环境变量${NC}"
        else
            echo -e "${RED}✗ 阿里云配置测试失败${NC}"
            unset Ali_Key
            unset Ali_Secret
            return 1
        fi
    fi
}

# 腾讯云DNSPod配置
setup_dnspod() {
    echo -e "${YELLOW}=== 腾讯云DNSPod API 配置 ===${NC}"
    echo -e "${CYAN}请按照以下步骤获取API凭证:${NC}"
    echo "1. 登录腾讯云控制台"
    echo "2. 进入'访问管理' -> 'API密钥管理'"
    echo "3. 创建密钥"
    echo ""
    
    read -rp "请输入SecretId: " dp_id
    read -rp "请输入SecretKey: " dp_key
    
    if [[ -z "$dp_id" || -z "$dp_key" ]]; then
        echo -e "${RED}SecretId和SecretKey不能为空${NC}"
        return 1
    fi
    
    # 保存到环境变量
    export DP_Id="$dp_id"
    export DP_Key="$dp_key"
    
    # 测试配置
    local acme_cmd=$(get_acme_cmd)
    if [[ -n "$acme_cmd" ]]; then
        echo -e "${BLUE}测试DNS API配置...${NC}"
        if $acme_cmd --issue --dns dns_dp --dnssleep 10 --test; then
            echo -e "${GREEN}✓ DNSPod配置测试成功${NC}"
            
            # 永久保存配置
            add_env_to_profile "DP_Id" "$dp_id"
            add_env_to_profile "DP_Key" "$dp_key"
            echo -e "${GREEN}配置已安全保存到环境变量${NC}"
        else
            echo -e "${RED}✗ DNSPod配置测试失败${NC}"
            unset DP_Id
            unset DP_Key
            return 1
        fi
    fi
}

# 华为云配置
setup_huaweicloud() {
    echo -e "${YELLOW}=== 华为云DNS API 配置 ===${NC}"
    echo -e "${CYAN}请按照以下步骤获取API凭证:${NC}"
    echo "1. 登录华为云控制台"
    echo "2. 进入'我的凭证' -> '访问密钥'"
    echo "3. 创建访问密钥"
    echo ""
    
    read -rp "请输入Access Key: " hw_key
    read -rp "请输入Secret Key: " hw_secret
    
    if [[ -z "$hw_key" || -z "$hw_secret" ]]; then
        echo -e "${RED}Access Key和Secret Key不能为空${NC}"
        return 1
    fi
    
    # 华为云需要额外的配置
    export HW_ACCESS_KEY="$hw_key"
    export HW_SECRET_KEY="$hw_secret"
    
    # 永久保存配置
    add_env_to_profile "HW_ACCESS_KEY" "$hw_key"
    add_env_to_profile "HW_SECRET_KEY" "$hw_secret"
    
    echo -e "${GREEN}华为云配置已保存${NC}"
    echo -e "${YELLOW}注意: 华为云配置需要额外验证，请参考官方文档${NC}"
}

# 自定义DNS配置
setup_custom_dns() {
    echo -e "${YELLOW}=== 自定义DNS API 配置 ===${NC}"
    echo -e "${CYAN}支持的DNS提供商列表:${NC}"
    echo "dns_cf, dns_ali, dns_dp, dns_hw, dns_aws, dns_gd, dns_namesilo, dns_he, dns_azure"
    echo ""
    
    read -rp "请输入DNS提供商代码: " dns_provider
    read -rp "请输入API Key: " api_key
    read -rp "请输入API Secret: " api_secret
    
    echo -e "${CYAN}环境变量名称示例:${NC}"
    echo "Cloudflare: CF_Token, CF_Email"
    echo "阿里云: Ali_Key, Ali_Secret"
    echo "DNSPod: DP_Id, DP_Key"
    echo ""
    
    read -rp "请输入Key的环境变量名: " key_var
    read -rp "请输入Secret的环境变量名: " secret_var
    
    # 设置环境变量
    export "$key_var"="$api_key"
    export "$secret_var"="$api_secret"
    
    # 安全保存到配置文件
    add_env_to_profile "$key_var" "$api_key"
    add_env_to_profile "$secret_var" "$api_secret"
    
    echo -e "${GREEN}自定义DNS配置已保存${NC}"
}

# 申请证书主函数
apply_certificate() {
    echo -e "${CYAN}=== 证书申请向导 ===${NC}"
    
    # 选择证书类型
    echo -e "${YELLOW}选择证书类型:${NC}"
    echo "1) 单域名证书"
    echo "2) 多域名证书 (SAN证书)"
    echo "3) 通配符证书 (*.example.com)"
    echo "4) ECC证书 (椭圆曲线加密，更安全)"
    echo "5) RSA证书 (兼容性更好)"
    echo "0) 返回主菜单"
    
    read -rp "请选择: " cert_type
    
    case $cert_type in
        1)
            apply_single_domain
            ;;
        2)
            apply_multi_domain
            ;;
        3)
            apply_wildcard
            ;;
        4)
            apply_ecc_certificate
            ;;
        5)
            apply_rsa_certificate
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            apply_certificate
            ;;
    esac
}

# 申请单域名证书
apply_single_domain() {
    echo -e "${YELLOW}=== 单域名证书申请 ===${NC}"
    
    read -rp "请输入域名 (例如: example.com): " domain
    
    if [[ -z "$domain" ]]; then
        echo -e "${RED}域名不能为空${NC}"
        return 1
    fi
    
    # 验证域名格式
    if ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$ ]]; then
        echo -e "${RED}域名格式不正确${NC}"
        return 1
    fi
    
    # 选择验证方式
    choose_validation_method "$domain"
}

# 申请多域名证书
apply_multi_domain() {
    echo -e "${YELLOW}=== 多域名证书申请 (SAN证书) ===${NC}"
    
    echo -e "${CYAN}请输入域名，每行一个，输入空行结束:${NC}"
    local domains=()
    local i=1
    
    while true; do
        read -rp "域名 $i: " domain
        if [[ -z "$domain" ]]; then
            if [[ ${#domains[@]} -eq 0 ]]; then
                echo -e "${RED}至少需要一个域名${NC}"
                continue
            fi
            break
        fi
        
        # 验证域名格式
        if ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$ ]]; then
            echo -e "${RED}域名 '$domain' 格式不正确，请重新输入${NC}"
            continue
        fi
        
        domains+=("$domain")
        ((i++))
    done
    
    # 显示所有域名
    echo -e "${GREEN}以下域名将被包含在证书中:${NC}"
    printf '%s\n' "${domains[@]}"
    
    read -rp "是否确认? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}已取消${NC}"
        return
    fi
    
    # 选择验证方式
    choose_validation_method "$(printf '%s ' "${domains[@]}")"
}

# 申请通配符证书
apply_wildcard() {
    echo -e "${YELLOW}=== 通配符证书申请 ===${NC}"
    
    echo -e "${CYAN}注意: 通配符证书必须使用DNS验证方式${NC}"
    read -rp "请输入主域名 (例如: example.com): " domain
    
    if [[ -z "$domain" ]]; then
        echo -e "${RED}域名不能为空${NC}"
        return 1
    fi
    
    # 确保域名不以*.开头
    domain=${domain#\*\.}
    
    # 验证域名格式
    if ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$ ]]; then
        echo -e "${RED}域名格式不正确${NC}"
        return 1
    fi
    
    # 设置通配符域名
    wildcard_domain="*.$domain"
    
    # 选择DNS验证方式
    choose_dns_provider "$wildcard_domain"
}

# 申请ECC证书
apply_ecc_certificate() {
    echo -e "${YELLOW}=== ECC证书申请 ===${NC}"
    echo -e "${CYAN}ECC证书使用椭圆曲线加密，安全性更高，体积更小${NC}"
    
    read -rp "请输入域名: " domain
    
    if [[ -z "$domain" ]]; then
        echo -e "${RED}域名不能为空${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}选择ECC密钥长度:${NC}"
    echo "1) prime256v1 (推荐)"
    echo "2) secp384r1"
    echo "3) secp521r1"
    
    read -rp "请选择: " ecc_choice
    
    local keylength=""
    case $ecc_choice in
        1) keylength="prime256v1" ;;
        2) keylength="secp384r1" ;;
        3) keylength="secp521r1" ;;
        *) keylength="prime256v1" ;;
    esac
    
    # 选择验证方式
    echo -e "${YELLOW}选择验证方式:${NC}"
    echo "1) DNS验证"
    echo "2) HTTP验证"
    
    read -rp "请选择: " validation_choice
    
    local acme_cmd=$(get_acme_cmd)
    if [[ -z "$acme_cmd" ]]; then
        echo -e "${RED}acme.sh 未找到${NC}"
        return 1
    fi
    
    local cmd="$acme_cmd --issue --keylength ec-$keylength"
    
    case $validation_choice in
        1)
            choose_dns_provider "$domain" "$cmd"
            ;;
        2)
            http_validation "$domain" "$cmd"
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            return 1
            ;;
    esac
}

# 申请RSA证书
apply_rsa_certificate() {
    echo -e "${YELLOW}=== RSA证书申请 ===${NC}"
    echo -e "${CYAN}RSA证书兼容性更好，适合老旧系统${NC}"
    
    read -rp "请输入域名: " domain
    
    if [[ -z "$domain" ]]; then
        echo -e "${RED}域名不能为空${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}选择RSA密钥长度:${NC}"
    echo "1) 2048位 (推荐)"
    echo "2) 3072位"
    echo "3) 4096位"
    
    read -rp "请选择: " rsa_choice
    
    local keylength=""
    case $rsa_choice in
        1) keylength="2048" ;;
        2) keylength="3072" ;;
        3) keylength="4096" ;;
        *) keylength="2048" ;;
    esac
    
    # 选择验证方式
    echo -e "${YELLOW}选择验证方式:${NC}"
    echo "1) DNS验证"
    echo "2) HTTP验证"
    
    read -rp "请选择: " validation_choice
    
    local acme_cmd=$(get_acme_cmd)
    if [[ -z "$acme_cmd" ]]; then
        echo -e "${RED}acme.sh 未找到${NC}"
        return 1
    fi
    
    local cmd="$acme_cmd --issue --keylength $keylength"
    
    case $validation_choice in
        1)
            choose_dns_provider "$domain" "$cmd"
            ;;
        2)
            http_validation "$domain" "$cmd"
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            return 1
            ;;
    esac
}

# 选择验证方式
choose_validation_method() {
    local domain=$1
    
    echo -e "${YELLOW}选择验证方式:${NC}"
    echo "1) HTTP验证 (需要80端口可访问)"
    echo "2) DNS验证 (支持通配符)"
    echo "3) Webroot验证 (使用现有Web服务器)"
    echo "0) 返回"
    
    read -rp "请选择: " validation_choice
    
    local acme_cmd=$(get_acme_cmd)
    if [[ -z "$acme_cmd" ]]; then
        echo -e "${RED}acme.sh 未找到${NC}"
        return 1
    fi
    
    local cmd="$acme_cmd --issue"
    
    case $validation_choice in
        1)
            cmd="$cmd --standalone"
            execute_acme_command "$cmd -d $domain"
            ;;
        2)
            choose_dns_provider "$domain" "$cmd"
            ;;
        3)
            webroot_validation "$domain" "$cmd"
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            choose_validation_method "$domain"
            ;;
    esac
}

# HTTP验证
http_validation() {
    local domain=$1
    local base_cmd=$2
    
    echo -e "${YELLOW}=== HTTP验证配置 ===${NC}"
    echo -e "${CYAN}请确保您的服务器80端口可被外网访问${NC}"
    
    local cmd="$base_cmd --standalone -d $domain"
    execute_acme_command "$cmd"
}

# Webroot验证
webroot_validation() {
    local domain=$1
    local base_cmd=$2
    
    echo -e "${YELLOW}=== Webroot验证配置 ===${NC}"
    
    read -rp "请输入Web根目录路径 (默认: /var/www/html): " webroot
    webroot=${webroot:-/var/www/html}
    
    if [[ ! -d "$webroot" ]]; then
        echo -e "${YELLOW}目录不存在，是否创建? (y/n): ${NC}"
        read -r create_dir
        if [[ "$create_dir" =~ ^[Yy]$ ]]; then
            mkdir -p "$webroot"
            chown -R "$USER":"$USER" "$webroot"
        else
            echo -e "${RED}Web根目录不存在，请检查路径${NC}"
            return 1
        fi
    fi
    
    local cmd="$base_cmd --webroot $webroot -d $domain"
    execute_acme_command "$cmd"
}

# 选择DNS提供商
choose_dns_provider() {
    local domain=$1
    local base_cmd=${2:-$(get_acme_cmd) --issue}
    
    echo -e "${YELLOW}=== DNS验证配置 ===${NC}"
    echo -e "${CYAN}选择DNS服务商:${NC}"
    
    echo "1) Cloudflare"
    echo "2) 阿里云"
    echo "3) 腾讯云(DNSPod)"
    echo "4) 华为云"
    echo "5) 其他DNS提供商"
    
    read -rp "请选择: " dns_choice
    
    local dns_provider=""
    case $dns_choice in
        1) dns_provider="dns_cf" ;;
        2) dns_provider="dns_ali" ;;
        3) dns_provider="dns_dp" ;;
        4) dns_provider="dns_hw" ;;
        5)
            read -rp "请输入DNS提供商代码: " custom_provider
            dns_provider="$custom_provider"
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            return 1
            ;;
    esac
    
    local cmd="$base_cmd --dns $dns_provider -d $domain"
    execute_acme_command "$cmd"
}

# 执行acme命令（增加超时处理）
execute_acme_command() {
    local cmd=$1
    local timeout_seconds=300  # 5分钟超时
    
    echo -e "${CYAN}即将执行命令:${NC}"
    echo -e "${YELLOW}$cmd${NC}"
    echo ""
    
    read -rp "是否确认执行? (y/n): " confirm_execute
    
    if [[ ! "$confirm_execute" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}已取消${NC}"
        return
    fi
    
    # 执行命令并捕获输出
    echo -e "${BLUE}开始执行证书申请...${NC}"
    log_message "执行命令: $cmd"
    
    # 使用timeout命令执行（如果可用）
    if command -v timeout &> /dev/null; then
        if timeout $timeout_seconds bash -c "$cmd"; then
            echo -e "${GREEN}证书申请成功！${NC}"
            log_message "证书申请成功"
            
            # 显示证书信息
            show_certificate_info
            
            # 询问是否安装证书到Web服务器
            install_to_webserver
            
        else
            local exit_code=$?
            if [[ $exit_code -eq 124 ]]; then
                echo -e "${RED}证书申请超时（${timeout_seconds}秒）${NC}"
                log_message "证书申请超时"
            else
                echo -e "${RED}证书申请失败，退出码: $exit_code${NC}"
                log_message "证书申请失败，退出码: $exit_code"
            fi
            troubleshoot_failure
        fi
    else
        # 如果没有timeout命令，直接执行
        if eval "$cmd"; then
            echo -e "${GREEN}证书申请成功！${NC}"
            log_message "证书申请成功"
            
            # 显示证书信息
            show_certificate_info
            
            # 询问是否安装证书到Web服务器
            install_to_webserver
            
        else
            echo -e "${RED}证书申请失败${NC}"
            log_message "证书申请失败"
            troubleshoot_failure
        fi
    fi
}

# 显示证书信息
show_certificate_info() {
    echo -e "${CYAN}证书信息:${NC}"
    
    local acme_cmd=$(get_acme_cmd)
    if [[ -z "$acme_cmd" ]]; then
        echo -e "${RED}acme.sh 未找到${NC}"
        return
    fi
    
    # 列出所有证书
    echo -e "${YELLOW}已颁发的证书:${NC}"
    $acme_cmd --list
    
    # 显示最新证书的路径
    local cert_dir="$ACME_INSTALL_DIR"
    local domains=$(ls "$cert_dir" 2>/dev/null | grep -E '^[a-zA-Z0-9]' | head -5)
    
    if [[ -n "$domains" ]]; then
        echo -e "${YELLOW}证书存储路径:${NC}"
        for domain in $domains; do
            if [[ -d "$cert_dir/$domain" ]]; then
                echo "域名: $domain"
                echo "证书文件: $cert_dir/$domain/$domain.cer"
                echo "密钥文件: $cert_dir/$domain/$domain.key"
                echo "CA证书: $cert_dir/$domain/ca.cer"
                echo "全链证书: $cert_dir/$domain/fullchain.cer"
                echo ""
            fi
        done
    fi
}

# 验证证书安装
verify_certificate_installation() {
    local domain=$1
    local cert_file=$2
    local key_file=$3
    
    echo -e "${CYAN}验证证书安装...${NC}"
    
    # 验证证书文件存在
    if [[ ! -f "$cert_file" ]]; then
        echo -e "${RED}✗ 证书文件不存在: $cert_file${NC}"
        return 1
    fi
    
    if [[ ! -f "$key_file" ]]; then
        echo -e "${RED}✗ 密钥文件不存在: $key_file${NC}"
        return 1
    fi
    
    # 验证证书格式
    if openssl x509 -in "$cert_file" -noout 2>/dev/null; then
        echo -e "${GREEN}✓ 证书文件格式正确${NC}"
    else
        echo -e "${RED}✗ 证书文件格式错误${NC}"
    fi
    
    # 验证私钥格式
    if openssl rsa -in "$key_file" -check -noout 2>/dev/null; then
        echo -e "${GREEN}✓ 密钥文件格式正确${NC}"
    else
        # 尝试ECDSA密钥
        if openssl ec -in "$key_file" -check -noout 2>/dev/null; then
            echo -e "${GREEN}✓ ECC密钥文件格式正确${NC}"
        else
            echo -e "${RED}✗ 密钥文件格式错误${NC}"
        fi
    fi
    
    # 验证证书和密钥匹配（仅对RSA有效）
    if openssl rsa -in "$key_file" -noout 2>/dev/null; then
        local cert_modulus=$(openssl x509 -noout -modulus -in "$cert_file" | openssl md5)
        local key_modulus=$(openssl rsa -noout -modulus -in "$key_file" 2>/dev/null | openssl md5)
        
        if [[ "$cert_modulus" == "$key_modulus" ]]; then
            echo -e "${GREEN}✓ 证书和密钥匹配${NC}"
        else
            echo -e "${RED}✗ 证书和密钥不匹配${NC}"
        fi
    fi
    
    # 显示证书信息
    echo -e "${CYAN}证书详细信息:${NC}"
    openssl x509 -in "$cert_file" -text -noout | grep -E "Subject:|Issuer:|Not Before:|Not After :"
}

# 安装证书到Web服务器
install_to_webserver() {
    echo -e "${CYAN}是否安装证书到Web服务器? (y/n): ${NC}"
    read -r install_cert
    
    if [[ "$install_cert" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}选择Web服务器:${NC}"
        echo "1) Nginx"
        echo "2) Apache"
        echo "3) 其他"
        
        read -rp "请选择: " web_server
        
        read -rp "请输入域名: " install_domain
        
        local acme_cmd=$(get_acme_cmd)
        if [[ -z "$acme_cmd" ]]; then
            echo -e "${RED}acme.sh 未找到${NC}"
            return
        fi
        
        case $web_server in
            1)
                echo -e "${YELLOW}Nginx证书安装...${NC}"
                read -rp "请输入Nginx配置目录 (默认: /etc/nginx/conf.d): " nginx_dir
                nginx_dir=${nginx_dir:-/etc/nginx/conf.d}
                
                mkdir -p "$nginx_dir"
                
                $acme_cmd --install-cert -d "$install_domain" \
                    --key-file "$nginx_dir/$install_domain.key" \
                    --fullchain-file "$nginx_dir/$install_domain.crt" \
                    --reloadcmd "systemctl reload nginx"
                
                # 验证安装
                verify_certificate_installation "$install_domain" \
                    "$nginx_dir/$install_domain.crt" \
                    "$nginx_dir/$install_domain.key"
                ;;
            2)
                echo -e "${YELLOW}Apache证书安装...${NC}"
                read -rp "请输入Apache配置目录 (默认: /etc/apache2/ssl): " apache_dir
                apache_dir=${apache_dir:-/etc/apache2/ssl}
                
                mkdir -p "$apache_dir"
                $acme_cmd --install-cert -d "$install_domain" \
                    --cert-file "$apache_dir/$install_domain.crt" \
                    --key-file "$apache_dir/$install_domain.key" \
                    --fullchain-file "$apache_dir/$install_domain-chain.crt" \
                    --reloadcmd "systemctl reload apache2"
                
                # 验证安装
                verify_certificate_installation "$install_domain" \
                    "$apache_dir/$install_domain.crt" \
                    "$apache_dir/$install_domain.key"
                ;;
            3)
                echo -e "${CYAN}手动安装证书${NC}"
                echo "证书文件位于: $ACME_INSTALL_DIR/$install_domain/"
                echo "请手动配置您的Web服务器使用这些证书"
                ls -la "$ACME_INSTALL_DIR/$install_domain/" 2>/dev/null || echo "未找到证书目录"
                ;;
        esac
        
        echo -e "${GREEN}证书安装完成！${NC}"
    fi
}

# 错误排查
troubleshoot_failure() {
    echo -e "${YELLOW}=== 错误排查 ===${NC}"
    echo "1) 检查DNS解析"
    echo "2) 检查网络连接"
    echo "3) 检查端口开放"
    echo "4) 查看详细日志"
    echo "0) 返回"
    
    read -rp "请选择: " troubleshoot_choice
    
    case $troubleshoot_choice in
        1)
            check_dns_resolution
            ;;
        2)
            check_network_connectivity
            ;;
        3)
            check_ports
            ;;
        4)
            view_logs
            ;;
        0)
            return
            ;;
    esac
}

# 检查网络连接（增加超时）
check_network_connectivity() {
    echo -e "${YELLOW}检查网络连接...${NC}"
    
    # 检查是否可访问Let's Encrypt
    if timeout 10 ping -c 3 acme-v02.api.letsencrypt.org &> /dev/null; then
        echo -e "${GREEN}✓ 可访问Let's Encrypt服务器${NC}"
    else
        echo -e "${RED}✗ 无法访问Let's Encrypt服务器${NC}"
    fi
    
    # 检查外部网络
    if timeout 10 curl -s https://www.google.com &> /dev/null; then
        echo -e "${GREEN}✓ 外部网络连接正常${NC}"
    else
        echo -e "${RED}✗ 外部网络连接异常${NC}"
    fi
    
    # 检查Let's Encrypt API状态
    echo -e "${CYAN}检查Let's Encrypt API状态...${NC}"
    if timeout 10 curl -s https://acme-v02.api.letsencrypt.org/directory | grep -q "newAccount"; then
        echo -e "${GREEN}✓ Let's Encrypt API正常${NC}"
    else
        echo -e "${RED}✗ Let's Encrypt API异常${NC}"
    fi
}

# 检查DNS解析（增加超时和更多检查）
check_dns_resolution() {
    read -rp "请输入要检查的域名: " check_domain
    
    if [[ -n "$check_domain" ]]; then
        echo -e "${YELLOW}检查 $check_domain 的DNS解析...${NC}"
        
        # 检查A记录
        if command -v dig &> /dev/null; then
            echo -e "${CYAN}A记录:${NC}"
            timeout 10 dig +short A "$check_domain" 2>/dev/null || echo "查询超时"
            
            # 检查_acme-challenge子域名
            echo -e "${CYAN}_acme-challenge TXT记录:${NC}"
            timeout 10 dig +short TXT "_acme-challenge.$check_domain" 2>/dev/null || echo "查询超时"
            
            # 检查NS记录
            echo -e "${CYAN}NS记录:${NC}"
            timeout 10 dig +short NS "$check_domain" 2>/dev/null || echo "查询超时"
        elif command -v nslookup &> /dev/null; then
            timeout 10 nslookup "$check_domain" 2>/dev/null || echo "查询超时"
        else
            timeout 10 ping -c 1 "$check_domain" 2>/dev/null || echo "查询超时"
        fi
        
        # 检查域名是否解析到正确IP
        echo -e "${CYAN}检查域名解析到本机IP...${NC}"
        local public_ip=$(timeout 10 curl -s https://api.ipify.org 2>/dev/null || echo "未知")
        local domain_ip=$(timeout 10 dig +short A "$check_domain" 2>/dev/null | head -1)
        
        if [[ -n "$domain_ip" && -n "$public_ip" && "$domain_ip" == "$public_ip" ]]; then
            echo -e "${GREEN}✓ 域名正确解析到本机IP: $public_ip${NC}"
        elif [[ -n "$domain_ip" ]]; then
            echo -e "${YELLOW}⚠ 域名解析到: $domain_ip (本机IP: $public_ip)${NC}"
        else
            echo -e "${RED}✗ 无法获取域名解析${NC}"
        fi
    fi
}

# 检查端口（优化错误处理）
check_ports() {
    read -rp "请输入要检查的域名或IP (默认localhost): " check_host
    check_host=${check_host:-localhost}
    read -rp "请输入端口号 (默认80): " check_port
    check_port=${check_port:-80}
    
    echo -e "${YELLOW}检查 $check_host:$check_port ...${NC}"
    
    # 使用多种方法检查端口
    if command -v nc &> /dev/null; then
        if timeout 5 nc -z "$check_host" "$check_port" 2>/dev/null; then
            echo -e "${GREEN}✓ 端口 $check_port 可访问 (使用nc)${NC}"
        else
            echo -e "${RED}✗ 端口 $check_port 不可访问${NC}"
        fi
    elif command -v telnet &> /dev/null; then
        if timeout 5 bash -c "echo '' | telnet $check_host $check_port 2>&1 | grep -q 'Connected'"; then
            echo -e "${GREEN}✓ 端口 $check_port 可访问 (使用telnet)${NC}"
        else
            echo -e "${RED}✗ 端口 $check_port 不可访问${NC}"
        fi
    elif timeout 5 bash -c "cat < /dev/null > /dev/tcp/$check_host/$check_port" 2>/dev/null; then
        echo -e "${GREEN}✓ 端口 $check_port 可访问 (使用bash)${NC}"
    else
        echo -e "${RED}✗ 端口 $check_port 不可访问${NC}"
    fi
    
    # 检查服务是否运行
    if [[ "$check_port" -eq 80 ]] && command -v ss &> /dev/null; then
        echo -e "${CYAN}检查80端口服务...${NC}"
        ss -tlnp | grep ":80" || echo "80端口无服务监听"
    fi
}

# 查看日志
view_logs() {
    echo -e "${CYAN}=== 日志查看 ===${NC}"
    echo "1) 查看脚本日志"
    echo "2) 查看acme.sh日志"
    echo "3) 查看系统日志"
    echo "4) 清除旧日志"
    
    read -rp "请选择: " log_choice
    
    case $log_choice in
        1)
            if [[ -f "$LOG_FILE" ]]; then
                echo -e "${CYAN}显示最后100行日志:${NC}"
                tail -100 "$LOG_FILE"
                echo -e "\n${YELLOW}输入 'q' 退出查看${NC}"
                read -p "按回车查看完整日志..." 
                less "$LOG_FILE"
            else
                echo -e "${YELLOW}今日暂无日志${NC}"
            fi
            ;;
        2)
            local acme_log="$ACME_INSTALL_DIR/acme.sh.log"
            if [[ -f "$acme_log" ]]; then
                echo -e "${CYAN}显示acme.sh最后50行日志:${NC}"
                tail -50 "$acme_log"
            else
                echo -e "${YELLOW}acme.sh日志未找到${NC}"
            fi
            ;;
        3)
            if [[ -f "/var/log/syslog" ]]; then
                echo -e "${CYAN}显示系统日志中与acme相关的记录:${NC}"
                grep -i acme /var/log/syslog | tail -50
            elif [[ -f "/var/log/messages" ]]; then
                grep -i acme /var/log/messages | tail -50
            else
                echo -e "${YELLOW}系统日志未找到${NC}"
            fi
            ;;
        4)
            echo -e "${YELLOW}清除7天前的日志...${NC}"
            find "$LOG_DIR" -name "*.log" -mtime +7 -delete
            echo -e "${GREEN}日志清理完成${NC}"
            
            # 同时清理acme.sh日志
            if [[ -f "$ACME_INSTALL_DIR/acme.sh.log" ]]; then
                > "$ACME_INSTALL_DIR/acme.sh.log"
                echo -e "${GREEN}acme.sh日志已清空${NC}"
            fi
            ;;
    esac
}

# 证书续期管理
manage_renewals() {
    echo -e "${CYAN}=== 证书续期管理 ===${NC}"
    echo "1) 手动续期所有证书"
    echo "2) 测试续期（不实际执行）"
    echo "3) 查看即将过期的证书"
    echo "4) 设置自动续期"
    echo "5) 强制续期指定证书"
    echo "0) 返回主菜单"
    
    read -rp "请选择: " renew_choice
    
    local acme_cmd=$(get_acme_cmd)
    if [[ -z "$acme_cmd" ]]; then
        echo -e "${RED}acme.sh 未找到${NC}"
        return
    fi
    
    case $renew_choice in
        1)
            echo -e "${YELLOW}正在续期所有证书...${NC}"
            $acme_cmd --renew-all --force
            ;;
        2)
            echo -e "${YELLOW}测试续期（干运行）...${NC}"
            $acme_cmd --renew-all --force --test
            ;;
        3)
            echo -e "${YELLOW}证书状态:${NC}"
            $acme_cmd --list | while read -r line; do
                if [[ "$line" == *"Renew"* ]] || [[ "$line" == *"Expire"* ]]; then
                    echo "$line"
                fi
            done
            
            # 显示详细过期时间
            echo -e "\n${CYAN}证书详细过期时间:${NC}"
            local cert_dirs=$(ls -d "$ACME_INSTALL_DIR"/*/ 2>/dev/null)
            for dir in $cert_dirs; do
                domain=$(basename "$dir")
                cert_file="$dir/$domain.cer"
                if [[ -f "$cert_file" ]]; then
                    expiry_date=$(openssl x509 -in "$cert_file" -enddate -noout | cut -d= -f2)
                    echo "$domain 过期时间: $expiry_date"
                fi
            done
            ;;
        4)
            setup_auto_renew
            ;;
        5)
            read -rp "请输入要强制续期的域名: " force_domain
            if [[ -n "$force_domain" ]]; then
                echo -e "${YELLOW}强制续期 $force_domain ...${NC}"
                $acme_cmd --renew -d "$force_domain" --force
            fi
            ;;
        0)
            return
            ;;
    esac
}

# 设置自动续期
setup_auto_renew() {
    echo -e "${CYAN}acme.sh 已内置自动续期功能${NC}"
    echo -e "${YELLOW}当前自动续期状态:${NC}"
    
    local acme_cmd=$(get_acme_cmd)
    $acme_cmd --cron --help | grep -i cron
    
    echo ""
    echo -e "${GREEN}acme.sh 会自动安装cron任务，每天检查证书续期${NC}"
    echo "如需手动配置，请运行: $acme_cmd --install-cronjob"
    
    # 显示当前的cron任务
    echo -e "\n${CYAN}当前cron任务:${NC}"
    crontab -l | grep -i acme || echo "未找到acme相关cron任务"
    
    echo -e "\n${YELLOW}是否要重新安装cron任务? (y/n): ${NC}"
    read -r reinstall_cron
    if [[ "$reinstall_cron" =~ ^[Yy]$ ]]; then
        $acme_cmd --install-cronjob
        echo -e "${GREEN}cron任务已重新安装${NC}"
    fi
}

# 证书吊销
revoke_certificate() {
    echo -e "${CYAN}=== 证书吊销 ===${NC}"
    
    read -rp "请输入要吊销的域名: " revoke_domain
    
    if [[ -n "$revoke_domain" ]]; then
        echo -e "${RED}警告: 吊销后将无法恢复！${NC}"
        read -rp "确定要吊销 $revoke_domain 的证书吗? (y/n): " confirm_revoke
        
        if [[ "$confirm_revoke" =~ ^[Yy]$ ]]; then
            local acme_cmd=$(get_acme_cmd)
            if [[ -z "$acme_cmd" ]]; then
                echo -e "${RED}acme.sh 未找到${NC}"
                return
            fi
            
            # 先尝试吊销
            if $acme_cmd --revoke -d "$revoke_domain"; then
                echo -e "${GREEN}证书吊销成功${NC}"
                
                # 询问是否删除证书文件
                echo -e "${CYAN}是否删除证书文件? (y/n): ${NC}"
                read -r delete_files
                if [[ "$delete_files" =~ ^[Yy]$ ]]; then
                    $acme_cmd --remove -d "$revoke_domain"
                    rm -rf "$ACME_INSTALL_DIR/$revoke_domain" 2>/dev/null
                    echo -e "${GREEN}证书文件已删除${NC}"
                fi
            else
                echo -e "${RED}证书吊销失败${NC}"
            fi
        fi
    fi
}

# 系统状态检查（增强版）
check_system_status() {
    echo -e "${CYAN}=== 系统状态检查 ===${NC}"
    
    # 检查acme.sh
    local acme_cmd=$(get_acme_cmd)
    if [[ -n "$acme_cmd" ]]; then
        echo -e "${GREEN}✓ acme.sh 已安装${NC}"
        $acme_cmd --version
    else
        echo -e "${RED}✗ acme.sh 未安装${NC}"
    fi
    
    # 检查证书数量
    local cert_count=0
    if [[ -d "$ACME_INSTALL_DIR" ]]; then
        cert_count=$(find "$ACME_INSTALL_DIR" -maxdepth 1 -type d -name "*.*" | wc -l)
    fi
    echo -e "${YELLOW}现有证书数量: $cert_count${NC}"
    
    # 显示最近颁发的证书
    if [[ $cert_count -gt 0 ]]; then
        echo -e "${CYAN}最近颁发的证书:${NC}"
        find "$ACME_INSTALL_DIR" -maxdepth 1 -type d -name "*.*" | head -5 | while read dir; do
            domain=$(basename "$dir")
            echo "  - $domain"
        done
    fi
    
    # 检查端口占用
    echo -e "${YELLOW}端口占用情况:${NC}"
    for port in 80 443; do
        if command -v ss &> /dev/null; then
            local port_info=$(ss -tln | grep ":$port")
            if [[ -n "$port_info" ]]; then
                echo -e "端口 $port: ${RED}已占用${NC}"
                echo "占用进程:"
                echo "$port_info"
            else
                echo -e "端口 $port: ${GREEN}空闲${NC}"
            fi
        elif command -v netstat &> /dev/null; then
            if netstat -tln | grep ":$port" &> /dev/null; then
                echo -e "端口 $port: ${RED}已占用${NC}"
            else
                echo -e "端口 $port: ${GREEN}空闲${NC}"
            fi
        fi
    done
    
    # 检查磁盘空间
    echo -e "${CYAN}磁盘空间检查:${NC}"
    df -h "$HOME" | tail -1
    
    # 检查内存使用
    echo -e "${CYAN}内存使用情况:${NC}"
    free -h | head -2
    
    # 检查防火墙状态
    echo -e "${CYAN}防火墙状态:${NC}"
    if command -v ufw &> /dev/null; then
        ufw status | head -5
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --state 2>/dev/null || echo "firewalld未运行"
    else
        echo "未检测到常见防火墙"
    fi
}

# 主菜单
main_menu() {
    while true; do
        show_banner
        
        echo -e "${GREEN}请选择操作:${NC}"
        echo "1) 申请新证书"
        echo "2) 管理续期"
        echo "3) 吊销证书"
        echo "4) 配置DNS API"
        echo "5) 查看证书信息"
        echo "6) 系统检查"
        echo "7) 问题排查"
        echo "8) 查看日志"
        echo "0) 退出"
        echo ""
        
        read -rp "请输入选项 (0-8): " main_choice
        
        case $main_choice in
            1)
                apply_certificate
                ;;
            2)
                manage_renewals
                ;;
            3)
                revoke_certificate
                ;;
            4)
                setup_dns_api
                ;;
            5)
                show_certificate_info
                ;;
            6)
                check_system_status
                ;;
            7)
                troubleshoot_menu
                ;;
            8)
                view_logs
                ;;
            0)
                echo -e "${GREEN}再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择，请重新输入${NC}"
                ;;
        esac
        
        echo ""
        read -rp "按回车键继续..."
    done
}

# 问题排查菜单
troubleshoot_menu() {
    echo -e "${CYAN}=== 问题排查 ===${NC}"
    echo "1) 网络连接测试"
    echo "2) DNS解析测试"
    echo "3) 端口可用性测试"
    echo "4) 查看日志"
    echo "5) 重置配置"
    echo "6) 检查证书状态"
    echo "0) 返回"
    
    read -rp "请选择: " troubleshoot_menu_choice
    
    case $troubleshoot_menu_choice in
        1)
            check_network_connectivity
            ;;
        2)
            check_dns_resolution
            ;;
        3)
            check_ports
            ;;
        4)
            view_logs
            ;;
        5)
            reset_configuration
            ;;
        6)
            check_system_status
            ;;
        0)
            return
            ;;
    esac
}

# 重置配置
reset_configuration() {
    echo -e "${RED}警告: 这将重置所有配置${NC}"
    echo -e "${YELLOW}将删除以下内容:${NC}"
    echo "1) 所有DNS API配置"
    echo "2) 脚本日志"
    echo "3) 脚本配置文件"
    echo ""
    echo -e "${CYAN}注: 不会删除acme.sh和已颁发的证书${NC}"
    
    read -rp "确定要重置吗? (y/n): " confirm_reset
    
    if [[ "$confirm_reset" =~ ^[Yy]$ ]]; then
        # 备份旧配置
        local backup_dir="/tmp/acme_backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        cp -r "$CONFIG_DIR" "$backup_dir/" 2>/dev/null
        
        # 删除配置
        rm -rf "$CONFIG_DIR"
        
        echo -e "${GREEN}配置已重置${NC}"
        echo -e "${YELLOW}旧配置已备份到: $backup_dir${NC}"
        
        # 重新创建目录
        mkdir -p "$CONFIG_DIR" "$DNS_API_DIR" "$LOG_DIR"
        echo "$CONFIG_VERSION" > "$VERSION_FILE"
    fi
}

# 脚本入口
main() {
    # 检查是否是root用户
    if [[ $EUID -ne 0 ]]; then
        echo "错误：本脚本必须在root用户下运行！"
        echo "请先切换到root用户：sudo su -"
        exit 1
    fi
    
    # 检查配置兼容性
    check_config_compatibility
    
    # 检查依赖
    check_dependencies
    
    # 安装acme.sh
    if ! install_acme; then
        echo -e "${RED}acme.sh 安装失败，脚本退出${NC}"
        exit 1
    fi
    
    # 运行主菜单
    main_menu
}

# 捕获Ctrl+C
trap 'echo -e "\n${YELLOW}用户中断操作${NC}"; exit 1' INT

# 启动脚本
main
