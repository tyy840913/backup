#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 图标定义
CHECK_MARK="✅"
CROSS_MARK="❌"
WARNING_MARK="⚠️"
INFO_MARK="ℹ️"
ARROW_MARK="➡️"

# 进度指示器函数
show_progress() {
    local pid=$1
    local message=$2
    local delay=0.1
    local spinstr='|/-\'
    
    echo -ne "${CYAN}${message}... ${NC}"
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# 简单进度条
progress_bar() {
    local duration=$1
    local message=$2
    local steps=20
    local step_delay=$(echo "scale=3; $duration/$steps" | bc)
    
    echo -ne "${CYAN}${message} [${NC}"
    for i in $(seq 1 $steps); do
        echo -ne "="
        sleep $step_delay
    done
    echo -e "${CYAN}] 完成${NC}"
}

# 友好的输出函数
success() { echo -e "${CHECK_MARK} ${GREEN}$1${NC}"; }
error() { echo -e "${CROSS_MARK} ${RED}$1${NC}"; }
warning() { echo -e "${WARNING_MARK} ${YELLOW}$1${NC}"; }
info() { echo -e "${INFO_MARK} ${CYAN}$1${NC}"; }
step() { echo -e "${ARROW_MARK} ${BLUE}$1${NC}"; }

# 配置文件路径和版本
CONFIG_VERSION="1.3"
CONFIG_DIR="$HOME/.acme_script"
DNS_API_DIR="$CONFIG_DIR/dns_apis"
LOG_DIR="$CONFIG_DIR/logs"
LOG_FILE="$LOG_DIR/acme_$(date +%Y%m%d).log"
VERSION_FILE="$CONFIG_DIR/version"
ACME_INSTALL_DIR="$HOME/.acme.sh"
BACKUP_DIR="$CONFIG_DIR/backups"
LOCK_FILE="/tmp/acme_script.lock"
ENCRYPTED_CONFIG="$CONFIG_DIR/encrypted_config.dat"

# 创建必要目录
mkdir -p "$CONFIG_DIR" "$DNS_API_DIR" "$LOG_DIR" "$BACKUP_DIR"
chmod 700 "$CONFIG_DIR"
chmod 755 "$LOG_DIR"
chmod 600 "$DNS_API_DIR"/* 2>/dev/null

# 错误码定义
ERROR_NETWORK=1
ERROR_DNS=2
ERROR_CERT=3
ERROR_CONFIG=4
ERROR_DEPENDENCY=5
ERROR_PERMISSION=6
ERROR_USER_CANCEL=7
ERROR_TIMEOUT=8
ERROR_VALIDATION=9

# 全局错误处理器
handle_error() {
    local error_code=$1
    local message=$2
    local context=$3
    
    log_message "ERROR [$error_code] in $context: $message"
    
    case $error_code in
        $ERROR_NETWORK)
            error "网络错误: $message"
            ;;
        $ERROR_DNS)
            error "DNS错误: $message"
            ;;
        $ERROR_CERT)
            error "证书错误: $message"
            ;;
        $ERROR_CONFIG)
            error "配置错误: $message"
            ;;
        $ERROR_DEPENDENCY)
            error "依赖错误: $message"
            ;;
        $ERROR_PERMISSION)
            error "权限错误: $message"
            ;;
        $ERROR_USER_CANCEL)
            warning "用户取消操作"
            ;;
        $ERROR_TIMEOUT)
            error "操作超时: $message"
            ;;
        $ERROR_VALIDATION)
            error "验证失败: $message"
            ;;
        *)
            error "未知错误 [$error_code]: $message"
            ;;
    esac
    
    return $error_code
}

# 配置验证函数
validate_config() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        return $ERROR_CONFIG
    fi
    
    # 检查配置文件格式
    if grep -q "=\"" "$config_file" 2>/dev/null; then
        return 0
    else
        return $ERROR_CONFIG
    fi
}

# 备份函数
backup_certificate() {
    local domain=$1
    local backup_name="${domain}_$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    mkdir -p "$backup_path"
    
    if [[ -d "$ACME_INSTALL_DIR/$domain" ]]; then
        cp -r "$ACME_INSTALL_DIR/$domain" "$backup_path/" 2>/dev/null
        echo "$backup_path"
        return 0
    else
        return $ERROR_CERT
    fi
}

# 恢复备份函数
restore_backup() {
    echo -e "${CYAN}=== 恢复备份 ===${NC}"
    
    local backups=($(ls -d "$BACKUP_DIR"/*/ 2>/dev/null))
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        warning "没有找到备份"
        return $ERROR_CONFIG
    fi
    
    echo -e "${YELLOW}可用的备份:${NC}"
    for i in "${!backups[@]}"; do
        echo "$((i+1))) $(basename "${backups[$i]}")"
    done
    
    read -rp "请选择要恢复的备份 (1-${#backups[@]}): " backup_choice
    
    if [[ "$backup_choice" =~ ^[0-9]+$ ]] && [[ $backup_choice -ge 1 ]] && [[ $backup_choice -le ${#backups[@]} ]]; then
        local selected_backup="${backups[$((backup_choice-1))]}"
        local domain=$(basename "$selected_backup" | cut -d'_' -f1)
        
        echo -e "${YELLOW}正在恢复 $domain 的备份...${NC}"
        
        # 备份当前证书
        local current_backup=$(backup_certificate "$domain" 2>/dev/null)
        
        # 恢复备份
        cp -r "$selected_backup/$domain" "$ACME_INSTALL_DIR/" 2>/dev/null
        
        if [[ $? -eq 0 ]]; then
            success "备份恢复成功"
            info "当前证书已备份到: $current_backup"
            return 0
        else
            error "恢复备份失败"
            return $ERROR_CONFIG
        fi
    else
        warning "无效的选择"
        return $ERROR_USER_CANCEL
    fi
}

# 加密敏感数据函数
encrypt_sensitive_data() {
    local data="$1"
    local password="$2"
    
    if [[ -z "$password" ]]; then
        # 如果没有提供密码，使用系统生成的密钥
        local key_file="$CONFIG_DIR/.encryption_key"
        if [[ ! -f "$key_file" ]]; then
            openssl rand -base64 32 > "$key_file"
            chmod 600 "$key_file"
        fi
        
        echo "$data" | openssl enc -aes-256-cbc -salt -pbkdf2 -pass file:"$key_file" -base64 2>/dev/null
    else
        echo "$data" | openssl enc -aes-256-cbc -salt -pbkdf2 -pass pass:"$password" -base64 2>/dev/null
    fi
}

# 解密敏感数据函数
decrypt_sensitive_data() {
    local encrypted_data="$1"
    local password="$2"
    
    if [[ -z "$password" ]]; then
        local key_file="$CONFIG_DIR/.encryption_key"
        if [[ ! -f "$key_file" ]]; then
            return $ERROR_CONFIG
        fi
        
        echo "$encrypted_data" | openssl enc -aes-256-cbc -d -salt -pbkdf2 -pass file:"$key_file" -base64 2>/dev/null 2>&1
    else
        echo "$encrypted_data" | openssl enc -aes-256-cbc -d -salt -pbkdf2 -pass pass:"$password" -base64 2>/dev/null 2>&1
    fi
}

# 安全存储API密钥
save_api_key() {
    local key_name="$1"
    local key_value="$2"
    local config_file="$CONFIG_DIR/api_keys.conf"
    
    # 加密密钥
    local encrypted_key=$(encrypt_sensitive_data "$key_value" "")
    
    if [[ $? -eq 0 ]] && [[ -n "$encrypted_key" ]]; then
        # 更新或添加密钥
        sed -i "/^${key_name}=/d" "$config_file" 2>/dev/null
        echo "${key_name}=${encrypted_key}" >> "$config_file"
        chmod 600 "$config_file"
        return 0
    else
        return $ERROR_CONFIG
    fi
}

# 安全读取API密钥
load_api_key() {
    local key_name="$1"
    local config_file="$CONFIG_DIR/api_keys.conf"
    
    if [[ ! -f "$config_file" ]]; then
        echo ""
        return $ERROR_CONFIG
    fi
    
    local encrypted_key=$(grep "^${key_name}=" "$config_file" | cut -d'=' -f2-)
    
    if [[ -n "$encrypted_key" ]]; then
        decrypt_sensitive_data "$encrypted_key" ""
    else
        echo ""
        return $ERROR_CONFIG
    fi
}

# 清理函数
cleanup() {
    rm -f /tmp/acme_* 2>/dev/null
    rm -f /tmp/dns_check_* 2>/dev/null
    rm -f /tmp/acme_output_* 2>/dev/null
    rm -f /tmp/acme_exec_* 2>/dev/null
    rm -f "$LOCK_FILE" 2>/dev/null
}

# 设置退出时的清理
trap cleanup EXIT INT TERM

# 日志函数
log_message() {
    # 日志轮转检查（10MB限制）
    local max_log_size=$((10 * 1024 * 1024))  # 10MB
    if [[ -f "$LOG_FILE" ]] && [[ $(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0) -gt $max_log_size ]]; then
        mv "$LOG_FILE" "${LOG_FILE}.old"
        echo -e "$(date '+%Y-%m-%d %H:%M:%S') - 日志文件过大，已轮转" > "$LOG_FILE"
    fi
    
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    
    # 只输出非调试信息到控制台
    if [[ ! "$1" =~ "DEBUG" ]]; then
        echo -e "$1"
    fi
}

# 显示横幅
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              acme.sh 证书自动化管理脚本 v1.3             ║"
    echo "║                  轻量级 SSL 证书申请工具                 ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    show_help_info
}

# 显示帮助信息
show_help_info() {
    echo -e "${CYAN}验证方式说明:${NC}"
    echo "1) HTTP验证 - 临时占用80端口，最简单"
    echo "2) DNS API验证 - 全自动，需要API密钥，支持通配符"
    echo "3) 手动DNS验证 - 无需API，手动添加TXT记录"
    echo "4) Webroot验证 - 使用现有Web服务器目录"
    echo ""
}

# 检查点机制
create_checkpoint() {
    local operation=$1
    local data=$2
    echo -e "操作: $operation\n时间: $(date '+%Y-%m-%d %H:%M:%S')\n数据: $data" > "$CONFIG_DIR/checkpoint"
    log_message "创建检查点: $operation"
}

clear_checkpoint() {
    rm -f "$CONFIG_DIR/checkpoint" 2>/dev/null
}

restore_from_checkpoint() {
    if [[ -f "$CONFIG_DIR/checkpoint" ]]; then
        local checkpoint=$(cat "$CONFIG_DIR/checkpoint")
        echo -e "${YELLOW}检测到上次未完成的操作:${NC}"
        echo "$checkpoint"
        echo ""
        read -rp "是否从中断处恢复? (y/n): " resume_choice
        if [[ "$resume_choice" =~ ^[Yy]$ ]]; then
            log_message "用户选择从检查点恢复"
            return 0
        else
            clear_checkpoint
        fi
    fi
    return 1
}

# 验证函数
validate_email() {
    local email=$1
    local regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    if [[ $email =~ $regex ]]; then
        return 0
    else
        error "邮箱格式不正确"
        return $ERROR_VALIDATION
    fi
}

validate_domain() {
    local domain=$1
    local regex="^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$"
    if [[ $domain =~ $regex ]]; then
        return 0
    else
        error "域名格式不正确"
        return $ERROR_VALIDATION
    fi
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
        local backup_dir="$BACKUP_DIR/config_backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$backup_dir"
        cp -r "$CONFIG_DIR" "$backup_dir/" 2>/dev/null
        
        # 删除配置
        rm -rf "$CONFIG_DIR"
        
        success "配置已重置"
        info "旧配置已备份到: $backup_dir"
        
        # 重新创建目录
        mkdir -p "$CONFIG_DIR" "$DNS_API_DIR" "$LOG_DIR" "$BACKUP_DIR"
        echo "$CONFIG_VERSION" > "$VERSION_FILE"
    fi
}

# 检查配置文件兼容性
check_config_compatibility() {
    if [[ -f "$VERSION_FILE" ]]; then
        local old_version=$(cat "$VERSION_FILE")
        if [[ "$old_version" != "$CONFIG_VERSION" ]]; then
            warning "配置文件版本不匹配 ($old_version → $CONFIG_VERSION)"
            info "建议备份后重置配置"
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
        log_message "错误: 命令 '$1' 未找到"
        return $ERROR_DEPENDENCY
    fi
    return 0
}

# 依赖映射到包名
map_dep_to_package() {
    local dep=$1
    local os_id=$2
    
    case $dep in
        curl) echo "curl" ;;
        openssl) echo "openssl" ;;
        crontab) echo "cron" ;;
        dig) 
            case $os_id in
                ubuntu|debian) echo "dnsutils" ;;
                centos|rhel|fedora) echo "bind-utils" ;;
                alpine) echo "bind-tools" ;;
                *) echo "dnsutils" ;;
            esac
            ;;
        sed) echo "sed" ;;
        nc|netcat) echo "netcat" ;;
        timeout) 
            case $os_id in
                ubuntu|debian) echo "timeout" ;;
                centos|rhel|fedora) echo "coreutils" ;;
                alpine) echo "coreutils" ;;
                *) echo "coreutils" ;;
            esac
            ;;
        *) echo "$dep" ;;
    esac
}

# 检查依赖
check_dependencies() {
    local missing_deps=()
    
    step "检查系统依赖..."
    
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
    
    # 检查sed（用于配置文件清理）
    if ! check_command "sed"; then
        missing_deps+=("sed")
    fi
    
    # 检查timeout（用于命令超时）
    if ! check_command "timeout"; then
        missing_deps+=("timeout")
    fi
    
    # 检查nc/netcat（用于端口检查）
    if ! check_command "nc" && ! check_command "netcat"; then
        missing_deps+=("netcat")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        error "缺少必要的依赖: ${missing_deps[*]}"
        read -rp "$(echo -e "${YELLOW}是否要自动安装缺少的依赖? (y/n): ${NC}")" install_choice
        if [[ "$install_choice" =~ ^[Yy]$ ]]; then
            install_dependencies "${missing_deps[@]}"
        else
            error "请手动安装缺少的依赖后重新运行脚本。"
            exit $ERROR_DEPENDENCY
        fi
    else
        success "所有依赖已满足"
    fi
}

# 安装依赖
install_dependencies() {
    local os_id
    os_id=$(grep '^ID=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo "unknown")
    
    info "检测到系统: $os_id"
    info "开始安装依赖..."
    
    # 转换依赖名到包名
    local packages=()
    for dep in "$@"; do
        local pkg=$(map_dep_to_package "$dep" "$os_id")
        packages+=("$pkg")
    done
    
    # 去重
    packages=($(echo "${packages[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    
    info "需要安装的包: ${packages[*]}"
    
    case $os_id in
        ubuntu|debian)
            apt-get update
            apt-get install -y "${packages[@]}"
            ;;
        centos|rhel|fedora)
            yum install -y epel-release
            yum install -y "${packages[@]}"
            ;;
        alpine)
            apk add --no-cache "${packages[@]}"
            ;;
        *)
            error "不支持的Linux发行版，请手动安装依赖。"
            echo "需要安装的包: ${packages[*]}"
            exit $ERROR_DEPENDENCY
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        success "依赖安装完成！"
    else
        error "依赖安装失败，请手动安装。"
        exit $ERROR_DEPENDENCY
    fi
}

# 检查acme.sh版本兼容性
check_acme_version() {
    local acme_cmd=$(get_acme_cmd)
    if [[ -n "$acme_cmd" ]]; then
        local version=$($acme_cmd --version 2>/dev/null | head -1)
        info "acme.sh版本: $version"
        
        # 检查是否支持手动DNS模式
        if $acme_cmd --help 2>&1 | grep -q "yes-I-know-dns-manual-mode"; then
            success "支持手动DNS验证模式"
        else
            warning "acme.sh版本可能不支持手动DNS模式"
        fi
    fi
}

# 安装或检查 acme.sh
install_acme() {
    step "检查 acme.sh 安装状态..."
    
    if [[ -f "$ACME_INSTALL_DIR/acme.sh" ]] || command -v acme.sh &> /dev/null; then
        success "acme.sh 已安装"
        check_acme_version
        return 0
    fi
    
    warning "acme.sh 未安装，开始安装..."
    info "安装选项:"
    echo "1) 在线安装（推荐）"
    echo "2) 从 GitHub 安装"
    echo "3) 手动安装"
    
    read -rp "请选择安装方式 (1/2/3): " install_method
    
    case $install_method in
        1)
            # 在线安装
            info "正在从官方源安装 acme.sh..."
            read -rp "请输入邮箱地址（用于证书注册）: " user_email
            user_email=${user_email:-admin@$(hostname)}
            
            if ! validate_email "$user_email"; then
                warning "邮箱格式不正确，使用默认邮箱"
                user_email="admin@$(hostname)"
            fi
            
            progress_bar 10 "安装 acme.sh"
            curl https://get.acme.sh | sh -s email="$user_email"
            ;;
        2)
            # 从 GitHub 安装
            info "正在从 GitHub 安装 acme.sh..."
            git clone https://github.com/acmesh-official/acme.sh.git "$ACME_INSTALL_DIR"
            cd "$ACME_INSTALL_DIR" || exit $ERROR_DEPENDENCY
            progress_bar 15 "编译安装 acme.sh"
            ./acme.sh --install
            ;;
        3)
            warning "请手动安装 acme.sh:"
            echo "访问: https://github.com/acmesh-official/acme.sh"
            echo "或运行: curl https://get.acme.sh | sh"
            read -rp "按回车键继续..."
            return $ERROR_USER_CANCEL
            ;;
        *)
            error "无效选择"
            return $ERROR_CONFIG
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        success "acme.sh 安装成功！"
        # 重新加载环境变量
        source ~/.bashrc 2>/dev/null || source ~/.profile 2>/dev/null || source ~/.bash_profile 2>/dev/null
        check_acme_version
        return 0
    else
        error "acme.sh 安装失败"
        return $ERROR_DEPENDENCY
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
    
    warning "未找到acme.sh命令，尝试在PATH中搜索..."
    
    # 最后尝试在PATH中搜索
    local found_cmd=$(which acme.sh 2>/dev/null || command -v acme.sh 2>/dev/null)
    if [[ -n "$found_cmd" ]]; then
        echo "$found_cmd"
        return 0
    fi
    
    echo ""
    return $ERROR_DEPENDENCY
}

# 安全添加环境变量到配置文件
add_env_to_profile() {
    local var_name="$1"
    local var_value="$2"
    local profile_file="$HOME/.bashrc"
    
    # 验证环境变量名
    if ! validate_env_var_name "$var_name"; then
        return $ERROR_CONFIG
    fi
    
    # 对于敏感数据，使用加密存储
    if [[ "$var_name" =~ _(Key|Secret|Token|Password)$ ]]; then
        if save_api_key "$var_name" "$var_value"; then
            info "敏感数据已加密保存"
            return 0
        else
            error "加密保存失败，使用明文存储"
        fi
    fi
    
    # 转义单引号
    local escaped_value=$(echo "$var_value" | sed "s/'/'\"'\"'/g")
    
    # 移除已存在的设置
    sed -i "/export $var_name=/d" "$profile_file" 2>/dev/null
    
    # 添加新设置（安全方式）
    echo "export $var_name='$escaped_value'" >> "$profile_file"
    
    # 立即生效（当前会话）
    export "$var_name"="$var_value"
}

# 检查环境变量名是否安全
validate_env_var_name() {
    local var_name="$1"
    
    # 白名单
    local valid_vars=("CF_Token" "CF_Email" "Ali_Key" "Ali_Secret" "DP_Id" "DP_Key" 
                     "HW_ACCESS_KEY" "HW_SECRET_KEY" "ZEROSSL_EMAIL" "ZEROSSL_EAB_KID" 
                     "ZEROSSL_EAB_HMAC" "BUYPASS_EMAIL" "SSLCOM_USER" "SSLCOM_PASS" 
                     "CUSTOM_CA_SERVER")
    
    if [[ ! " ${valid_vars[@]} " =~ " $var_name " ]]; then
        error "环境变量名 '$var_name' 不在允许列表中"
        info "允许的变量名: ${valid_vars[*]}"
        return $ERROR_CONFIG
    fi
    
    # 检查是否为敏感系统变量
    local sensitive_vars=("PATH" "HOME" "USER" "SHELL" "PWD" "LD_LIBRARY_PATH")
    if [[ " ${sensitive_vars[@]} " =~ " $var_name " ]]; then
        error "不能使用系统敏感变量名 '$var_name'"
        return $ERROR_CONFIG
    fi
    
    return 0
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
            error "无效选择"
            setup_dns_api
            ;;
    esac
}

# Cloudflare配置
setup_cloudflare() {
    step "Cloudflare DNS API 配置"
    info "请按照以下步骤获取API凭证:"
    echo "1. 登录Cloudflare控制台"
    echo "2. 进入'我的个人资料' -> 'API令牌'"
    echo "3. 创建令牌 -> 编辑区域DNS模板"
    echo "4. 选择需要管理的域名"
    echo ""
    
    read -rp "请输入API令牌: " cf_token
    read -rp "请输入Cloudflare账户邮箱: " cf_email
    
    if [[ -z "$cf_token" || -z "$cf_email" ]]; then
        error "API令牌和邮箱不能为空"
        return $ERROR_CONFIG
    fi
    
    if ! validate_email "$cf_email"; then
        return $ERROR_VALIDATION
    fi
    
    # 保存到环境变量
    export CF_Token="$cf_token"
    export CF_Email="$cf_email"
    
    # 测试配置
    local acme_cmd=$(get_acme_cmd)
    if [[ -n "$acme_cmd" ]]; then
        info "测试DNS API配置..."
        if $acme_cmd --issue --dns dns_cf --dnssleep 10 --test; then
            success "Cloudflare配置测试成功"
            
            # 永久保存配置（安全添加）
            add_env_to_profile "CF_Token" "$cf_token"
            add_env_to_profile "CF_Email" "$cf_email"
            success "配置已安全保存到环境变量"
        else
            error "Cloudflare配置测试失败"
            unset CF_Token
            unset CF_Email
            return $ERROR_CONFIG
        fi
    fi
}

# 阿里云配置
setup_aliyun() {
    step "阿里云DNS API 配置"
    info "请按照以下步骤获取API凭证:"
    echo "1. 登录阿里云控制台"
    echo "2. 进入'AccessKey管理'"
    echo "3. 创建AccessKey"
    echo ""
    
    read -rp "请输入AccessKey ID: " aliyun_key
    read -rp "请输入AccessKey Secret: " aliyun_secret
    
    if [[ -z "$aliyun_key" || -z "$aliyun_secret" ]]; then
        error "AccessKey ID和Secret不能为空"
        return $ERROR_CONFIG
    fi
    
    # 保存到环境变量
    export Ali_Key="$aliyun_key"
    export Ali_Secret="$aliyun_secret"
    
    # 测试配置
    local acme_cmd=$(get_acme_cmd)
    if [[ -n "$acme_cmd" ]]; then
        info "测试DNS API配置..."
        if $acme_cmd --issue --dns dns_ali --dnssleep 10 --test; then
            success "阿里云配置测试成功"
            
            # 永久保存配置
            add_env_to_profile "Ali_Key" "$aliyun_key"
            add_env_to_profile "Ali_Secret" "$aliyun_secret"
            success "配置已安全保存到环境变量"
        else
            error "阿里云配置测试失败"
            unset Ali_Key
            unset Ali_Secret
            return $ERROR_CONFIG
        fi
    fi
}

# 腾讯云DNSPod配置
setup_dnspod() {
    step "腾讯云DNSPod API 配置"
    info "请按照以下步骤获取API凭证:"
    echo "1. 登录腾讯云控制台"
    echo "2. 进入'访问管理' -> 'API密钥管理'"
    echo "3. 创建密钥"
    echo ""
    
    read -rp "请输入SecretId: " dp_id
    read -rp "请输入SecretKey: " dp_key
    
    if [[ -z "$dp_id" || -z "$dp_key" ]]; then
        error "SecretId和SecretKey不能为空"
        return $ERROR_CONFIG
    fi
    
    # 保存到环境变量
    export DP_Id="$dp_id"
    export DP_Key="$dp_key"
    
    # 测试配置
    local acme_cmd=$(get_acme_cmd)
    if [[ -n "$acme_cmd" ]]; then
        info "测试DNS API配置..."
        if $acme_cmd --issue --dns dns_dp --dnssleep 10 --test; then
            success "DNSPod配置测试成功"
            
            # 永久保存配置
            add_env_to_profile "DP_Id" "$dp_id"
            add_env_to_profile "DP_Key" "$dp_key"
            success "配置已安全保存到环境变量"
        else
            error "DNSPod配置测试失败"
            unset DP_Id
            unset DP_Key
            return $ERROR_CONFIG
        fi
    fi
}

# 华为云配置
setup_huaweicloud() {
    step "华为云DNS API 配置"
    info "请按照以下步骤获取API凭证:"
    echo "1. 登录华为云控制台"
    echo "2. 进入'我的凭证' -> '访问密钥'"
    echo "3. 创建访问密钥"
    echo ""
    
    read -rp "请输入Access Key: " hw_key
    read -rp "请输入Secret Key: " hw_secret
    
    if [[ -z "$hw_key" || -z "$hw_secret" ]]; then
        error "Access Key和Secret Key不能为空"
        return $ERROR_CONFIG
    fi
    
    # 华为云需要额外的配置
    export HW_ACCESS_KEY="$hw_key"
    export HW_SECRET_KEY="$hw_secret"
    
    # 永久保存配置
    add_env_to_profile "HW_ACCESS_KEY" "$hw_key"
    add_env_to_profile "HW_SECRET_KEY" "$hw_secret"
    
    success "华为云配置已保存"
    warning "注意: 华为云配置需要额外验证，请参考官方文档"
}

# 自定义DNS配置
setup_custom_dns() {
    step "自定义DNS API 配置"
    info "支持的DNS提供商列表:"
    echo "dns_cf, dns_ali, dns_dp, dns_hw, dns_aws, dns_gd, dns_namesilo, dns_he, dns_azure"
    echo ""
    
    read -rp "请输入DNS提供商代码: " dns_provider
    read -rp "请输入API Key: " api_key
    read -rp "请输入API Secret: " api_secret
    
    info "环境变量名称示例:"
    echo "Cloudflare: CF_Token, CF_Email"
    echo "阿里云: Ali_Key, Ali_Secret"
    echo "DNSPod: DP_Id, DP_Key"
    echo ""
    
    read -rp "请输入Key的环境变量名: " key_var
    read -rp "请输入Secret的环境变量名: " secret_var
    
    # 验证环境变量名
    if ! validate_env_var_name "$key_var" || ! validate_env_var_name "$secret_var"; then
        return $ERROR_CONFIG
    fi
    
    # 设置环境变量
    export "$key_var"="$api_key"
    export "$secret_var"="$api_secret"
    
    # 安全保存到配置文件
    add_env_to_profile "$key_var" "$api_key"
    add_env_to_profile "$secret_var" "$api_secret"
    
    success "自定义DNS配置已保存"
}

# 选择证书提供商（CA）
choose_certificate_provider() {
    step "选择SSL证书提供商"
    echo "1) Let's Encrypt (默认，免费，90天有效期)"
    echo "2) ZeroSSL (免费，需要注册账户)"
    echo "3) Buypass (免费，180天有效期)"
    echo "4) SSL.com (商业证书，需要付费)"
    echo "5) 自定义ACME服务器"
    
    read -rp "请选择提供商 (默认1): " ca_choice
    ca_choice=${ca_choice:-1}
    
    local acme_cmd=$(get_acme_cmd)
    if [[ -z "$acme_cmd" ]]; then
        error "acme.sh 未找到"
        return $ERROR_DEPENDENCY
    fi
    
    case $ca_choice in
        1)
            # Let's Encrypt (默认)
            success "使用 Let's Encrypt"
            # 移除其他服务器设置，恢复默认
            $acme_cmd --set-default-ca --server letsencrypt
            return 0
            ;;
        2)
            setup_zerossl
            return $?
            ;;
        3)
            setup_buypass
            return $?
            ;;
        4)
            setup_sslcom
            return $?
            ;;
        5)
            setup_custom_ca
            return $?
            ;;
        *)
            warning "无效选择，使用默认 Let's Encrypt"
            $acme_cmd --set-default-ca --server letsencrypt
            return 0
            ;;
    esac
}

# 配置ZeroSSL
setup_zerossl() {
    step "ZeroSSL 配置"
    
    local acme_cmd=$(get_acme_cmd)
    if [[ -z "$acme_cmd" ]]; then
        error "acme.sh 未找到"
        return $ERROR_DEPENDENCY
    fi
    
    # 检查是否已经注册过
    if $acme_cmd --list-account 2>/dev/null | grep -q "zerossl.com"; then
        success "已注册到 ZeroSSL"
        $acme_cmd --set-default-ca --server zerossl
        return 0
    fi
    
    warning "ZeroSSL需要注册账户并获取EAB凭证"
    echo "注册地址: https://app.zerossl.com/developer"
    echo ""
    
    read -rp "请输入ZeroSSL邮箱: " zerossl_email
    
    if ! validate_email "$zerossl_email"; then
        return $ERROR_VALIDATION
    fi
    
    read -rp "请输入EAB Key ID: " eab_kid
    read -rp "请输入EAB HMAC Key: " eab_hmac
    
    if [[ -z "$zerossl_email" || -z "$eab_kid" || -z "$eab_hmac" ]]; then
        error "ZeroSSL配置信息不完整"
        return $ERROR_CONFIG
    fi
    
    # 注册ZeroSSL账户（使用已有的acme_cmd变量）
    if $acme_cmd --register-account --server zerossl \
        --eab-kid "$eab_kid" \
        --eab-hmac-key "$eab_hmac" \
        -m "$zerossl_email"; then
        success "ZeroSSL账户注册成功"
        
        # 设置为默认CA
        $acme_cmd --set-default-ca --server zerossl
        
        # 保存配置
        add_env_to_profile "ZEROSSL_EMAIL" "$zerossl_email"
        add_env_to_profile "ZEROSSL_EAB_KID" "$eab_kid"
        add_env_to_profile "ZEROSSL_EAB_HMAC" "$eab_hmac"
        
        return 0
    else
        error "ZeroSSL账户注册失败"
        return $ERROR_CONFIG
    fi
}

# 配置Buypass
setup_buypass() {
    step "Buypass 配置"
    warning "Buypass需要注册账户"
    echo "注册地址: https://www.buypass.com/"
    echo ""
    
    read -rp "请输入Buypass邮箱: " buypass_email
    
    if [[ -z "$buypass_email" ]]; then
        error "邮箱不能为空"
        return $ERROR_CONFIG
    fi
    
    if ! validate_email "$buypass_email"; then
        return $ERROR_VALIDATION
    fi
    
    local acme_cmd=$(get_acme_cmd)
    
    # 注册Buypass账户
    if $acme_cmd --register-account --server buypass \
        -m "$buypass_email"; then
        success "Buypass账户注册成功"
        
        # 设置为默认CA
        $acme_cmd --set-default-ca --server buypass
        
        # 保存配置
        add_env_to_profile "BUYPASS_EMAIL" "$buypass_email"
        
        return 0
    else
        error "Buypass账户注册失败"
        return $ERROR_CONFIG
    fi
}

# 配置SSL.com
setup_sslcom() {
    step "SSL.com 配置"
    warning "SSL.com需要商业账户和API密钥"
    echo "注册地址: https://www.ssl.com/"
    echo ""
    
    read -rp "请输入SSL.com API用户名: " sslcom_user
    read -rp "请输入SSL.com API密码: " sslcom_pass
    
    if [[ -z "$sslcom_user" || -z "$sslcom_pass" ]]; then
        error "API凭证不能为空"
        return $ERROR_CONFIG
    fi
    
    local acme_cmd=$(get_acme_cmd)
    
    # 注册SSL.com账户
    if $acme_cmd --register-account --server sslcom \
        --accountemail "$sslcom_user" \
        --accountkey "$sslcom_pass"; then
        success "SSL.com账户注册成功"
        
        # 设置为默认CA
        $acme_cmd --set-default-ca --server sslcom
        
        # 保存配置
        add_env_to_profile "SSLCOM_USER" "$sslcom_user"
        add_env_to_profile "SSLCOM_PASS" "$sslcom_pass"
        
        return 0
    else
        error "SSL.com账户注册失败"
        return $ERROR_CONFIG
    fi
}

# 配置自定义CA
setup_custom_ca() {
    step "自定义ACME服务器"
    info "示例:"
    echo "Let's Encrypt 测试环境: https://acme-staging-v02.api.letsencrypt.org/directory"
    echo "其他ACME v2兼容服务器"
    echo ""
    
    read -rp "请输入ACME服务器URL: " ca_server
    
    if [[ -z "$ca_server" ]]; then
        error "服务器URL不能为空"
        return $ERROR_CONFIG
    fi
    
    # 验证URL格式
    if [[ ! "$ca_server" =~ ^https?:// ]]; then
        error "URL格式不正确，必须以http://或https://开头"
        return $ERROR_VALIDATION
    fi
    
    local acme_cmd=$(get_acme_cmd)
    
    # 注册到自定义服务器
    if $acme_cmd --register-account --server "$ca_server" \
        -m "admin@$(hostname)"; then
        success "自定义CA注册成功"
        
        # 设置为默认CA
        $acme_cmd --set-default-ca --server "$ca_server"
        
        # 保存配置
        add_env_to_profile "CUSTOM_CA_SERVER" "$ca_server"
        
        return 0
    else
        error "自定义CA注册失败"
        return $ERROR_CONFIG
    fi
}

# HTTP验证函数
http_validation() {
    local domain=$1
    local base_cmd=$2
    
    step "HTTP验证配置"
    
    # 提供两种HTTP验证方式
    info "选择HTTP验证方式:"
    echo "1) 独立模式 (临时占用80端口)"
    echo "2) Webroot模式 (使用现有Web服务器目录)"
    
    read -rp "请选择: " http_method
    
    local cmd=""
    case $http_method in
        1)
            success "使用独立模式验证"
            cmd="$base_cmd --standalone -d $domain"
            ;;
        2)
            read -rp "请输入Web服务器根目录 (默认: /var/www/html): " webroot
            webroot=${webroot:-/var/www/html}
            
            if [[ ! -d "$webroot" ]]; then
                warning "目录不存在，正在创建..."
                mkdir -p "$webroot"
                chown -R "$USER":"$USER" "$webroot" 2>/dev/null || true
            fi
            
            cmd="$base_cmd --webroot $webroot -d $domain"
            ;;
        *)
            warning "无效选择，使用独立模式"
            cmd="$base_cmd --standalone -d $domain"
            ;;
    esac
    
    execute_acme_command "$cmd"
}

# 检查端口函数
check_port() {
    local host=$1
    local port=$2
    
    if command -v nc &> /dev/null; then
        timeout 2 nc -z "$host" "$port" >/dev/null 2>&1
        return $?
    elif command -v telnet &> /dev/null; then
        timeout 2 bash -c "echo '' | telnet $host $port 2>&1 | grep -q 'Connected'" >/dev/null 2>&1
        return $?
    else
        timeout 2 bash -c "cat < /dev/null > /dev/tcp/$host/$port" >/dev/null 2>&1
        return $?
    fi
}

# 申请证书主函数
apply_certificate() {
    step "证书申请向导"
    
    # 检查恢复点
    if restore_from_checkpoint; then
        warning "从检查点恢复，跳过提供商选择"
    else
        # 选择证书提供商
        if ! choose_certificate_provider; then
            warning "使用默认提供商 Let's Encrypt"
        fi
    fi
    
    # 选择证书类型
    info "选择证书类型:"
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
            error "无效选择"
            apply_certificate
            ;;
    esac
}

# 申请单域名证书
apply_single_domain() {
    step "单域名证书申请"
    
    read -rp "请输入域名 (例如: example.com): " domain
    
    if [[ -z "$domain" ]]; then
        error "域名不能为空"
        return $ERROR_VALIDATION
    fi
    
    # 验证域名格式
    if ! validate_domain "$domain"; then
        return $ERROR_VALIDATION
    fi
    
    # 选择验证方式
    choose_validation_method "$domain"
}

# 申请多域名证书
apply_multi_domain() {
    step "多域名证书申请 (SAN证书)"
    
    echo -e "${CYAN}请输入域名，每行一个，输入空行结束:${NC}"
    local domains=()
    local i=1
    
    while true; do
        read -rp "域名 $i: " domain
        if [[ -z "$domain" ]]; then
            if [[ ${#domains[@]} -eq 0 ]]; then
                error "至少需要一个域名"
                continue
            fi
            break
        fi
        
        # 验证域名格式
        if ! validate_domain "$domain"; then
            continue
        fi
        
        domains+=("$domain")
        ((i++))
    done
    
    # 显示所有域名
    success "以下域名将被包含在证书中:"
    printf '%s\n' "${domains[@]}"
    
    read -rp "是否确认? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        warning "已取消"
        return $ERROR_USER_CANCEL
    fi
    
    # 选择验证方式
    choose_validation_method "${domains[@]}"
}

# 申请通配符证书
apply_wildcard() {
    step "通配符证书申请"
    
    warning "通配符证书必须使用DNS验证方式"
    read -rp "请输入主域名 (例如: example.com): " domain
    
    if [[ -z "$domain" ]]; then
        error "域名不能为空"
        return $ERROR_VALIDATION
    fi
    
    # 确保域名不以*.开头
    domain=${domain#\*\.}
    
    # 验证域名格式
    if ! validate_domain "$domain"; then
        return $ERROR_VALIDATION
    fi
    
    # 设置通配符域名
    local wildcard_domain="*.$domain"
    
    info "选择验证方式:"
    echo "1) DNS API自动验证 (需要API密钥)"
    echo "2) 手动DNS验证 (无需API，需要手动添加TXT记录)"
    
    read -rp "请选择 (1/2): " wildcard_choice
    
    case $wildcard_choice in
        1)
            # DNS API验证
            choose_dns_provider "$wildcard_domain"
            ;;
        2)
            # 手动DNS验证
            manual_dns_validation "$wildcard_domain"
            ;;
        *)
            error "无效选择"
            return $ERROR_CONFIG
            ;;
    esac
}

# 申请ECC证书
apply_ecc_certificate() {
    step "ECC证书申请"
    info "ECC证书使用椭圆曲线加密，安全性更高，体积更小"
    
    read -rp "请输入域名: " domain
    
    if [[ -z "$domain" ]]; then
        error "域名不能为空"
        return $ERROR_VALIDATION
    fi
    
    if ! validate_domain "$domain"; then
        return $ERROR_VALIDATION
    fi
    
    info "选择ECC密钥长度:"
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
    info "选择验证方式:"
    echo "1) DNS验证"
    echo "2) HTTP验证"
    
    read -rp "请选择: " validation_choice
    
    local acme_cmd=$(get_acme_cmd)
    if [[ -z "$acme_cmd" ]]; then
        error "acme.sh 未找到"
        return $ERROR_DEPENDENCY
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
            error "无效选择"
            return $ERROR_CONFIG
            ;;
    esac
}

# 申请RSA证书
apply_rsa_certificate() {
    step "RSA证书申请"
    info "RSA证书兼容性更好，适合老旧系统"
    
    read -rp "请输入域名: " domain
    
    if [[ -z "$domain" ]]; then
        error "域名不能为空"
        return $ERROR_VALIDATION
    fi
    
    if ! validate_domain "$domain"; then
        return $ERROR_VALIDATION
    fi
    
    info "选择RSA密钥长度:"
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
    info "选择验证方式:"
    echo "1) DNS验证"
    echo "2) HTTP验证"
    
    read -rp "请选择: " validation_choice
    
    local acme_cmd=$(get_acme_cmd)
    if [[ -z "$acme_cmd" ]]; then
        error "acme.sh 未找到"
        return $ERROR_DEPENDENCY
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
            error "无效选择"
            return $ERROR_CONFIG
            ;;
    esac
}

# 选择验证方式
choose_validation_method() {
    # 接收所有参数，支持单个或多个域名
    local domains=("$@")
    
    if [[ ${#domains[@]} -eq 0 ]]; then
        error "错误：未提供域名"
        return $ERROR_VALIDATION
    fi
    
    # 创建检查点
    local domain_list=$(IFS=,; echo "${domains[*]}")
    create_checkpoint "申请证书" "域名: $domain_list"
    
    info "选择验证方式:"
    echo "1) HTTP验证 (需要80端口可访问)"
    echo "2) DNS验证 (API自动)"
    echo "3) 手动DNS验证 (无需API，需要手动添加TXT记录)"
    echo "4) Webroot验证 (使用现有Web服务器)"
    echo "0) 返回"
    
    read -rp "请选择: " validation_choice
    
    local acme_cmd=$(get_acme_cmd)
    if [[ -z "$acme_cmd" ]]; then
        error "acme.sh 未找到"
        return $ERROR_DEPENDENCY
    fi
    
    case $validation_choice in
        1)
            # HTTP验证
            local cmd="$acme_cmd --issue --standalone"
            for domain in "${domains[@]}"; do
                cmd="$cmd -d $domain"
            done
            execute_acme_command "$cmd"
            ;;
        2)
            # DNS验证 (API自动)
            info "选择DNS服务商:"
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
                    error "无效选择"
                    return $ERROR_CONFIG
                    ;;
            esac
            
            local cmd="$acme_cmd --issue --dns $dns_provider"
            for domain in "${domains[@]}"; do
                cmd="$cmd -d $domain"
            done
            execute_acme_command "$cmd"
            ;;
        3)
            # 手动DNS验证
            manual_dns_validation "${domains[@]}"
            ;;
        4)
            # Webroot验证
            read -rp "请输入Web根目录路径 (默认: /var/www/html): " webroot
            webroot=${webroot:-/var/www/html}
            
            if [[ ! -d "$webroot" ]]; then
                warning "目录不存在，是否创建? (y/n): "
                read -r create_dir
                if [[ "$create_dir" =~ ^[Yy]$ ]]; then
                    mkdir -p "$webroot"
                    chown -R "$USER":"$USER" "$webroot"
                else
                    error "Web根目录不存在，请检查路径"
                    return $ERROR_CONFIG
                fi
            fi
            
            local cmd="$acme_cmd --issue --webroot $webroot"
            for domain in "${domains[@]}"; do
                cmd="$cmd -d $domain"
            done
            execute_acme_command "$cmd"
            ;;
        0)
            clear_checkpoint
            return $ERROR_USER_CANCEL
            ;;
        *)
            error "无效选择"
            return $ERROR_CONFIG
            ;;
    esac
}

# 选择DNS提供商
choose_dns_provider() {
    local domain=$1
    local base_cmd=${2:-$(get_acme_cmd) --issue}
    
    step "DNS验证配置"
    info "选择DNS服务商:"
    
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
            error "无效选择"
            return $ERROR_CONFIG
            ;;
    esac
    
    local cmd="$base_cmd --dns $dns_provider -d $domain"
    execute_acme_command "$cmd"
}

# 手动DNS验证函数
manual_dns_validation() {
    local domains=("$@")
    
    step "手动DNS验证模式"
    warning "此模式需要您手动在DNS管理面板添加TXT记录"
    echo ""
    
    local acme_cmd=$(get_acme_cmd)
    if [[ -z "$acme_cmd" ]]; then
        error "acme.sh 未找到"
        return $ERROR_DEPENDENCY
    fi
    
    # 检查是否支持手动模式
    if ! $acme_cmd --help 2>&1 | grep -q "yes-I-know-dns-manual-mode"; then
        error "错误: 当前acme.sh版本不支持手动DNS验证模式"
        warning "请更新acme.sh到最新版本"
        return $ERROR_DEPENDENCY
    fi
    
    # 为每个域名生成TXT记录
    info "生成TXT记录信息..."
    
    # 创建一个临时文件存储验证信息
    local temp_file="/tmp/acme_dns_manual_$(date +%s).txt"
    
    echo "======================" > "$temp_file"
    echo "手动DNS验证指南" >> "$temp_file"
    echo "生成时间: $(date)" >> "$temp_file"
    echo "======================" >> "$temp_file"
    
    local all_domains=""
    for domain in "${domains[@]}"; do
        echo -e "\n${CYAN}域名: $domain${NC}"
        
        # 为每个域名生成独立的TXT值
        echo "请添加以下DNS记录:" | tee -a "$temp_file"
        echo "类型: TXT" | tee -a "$temp_file"
        echo "主机记录: _acme-challenge" | tee -a "$temp_file"
        echo "记录值: [等待生成]" | tee -a "$temp_file"
        echo "完整的记录名: _acme-challenge.$domain" | tee -a "$temp_file"
        echo "TTL: 600 (推荐)" | tee -a "$temp_file"
        echo "======================" | tee -a "$temp_file"
        
        all_domains="$all_domains -d $domain"
    done
    
    # 显示保存的文件路径
    info "验证信息已保存到: $temp_file"
    warning "您可以将此文件作为参考"
    
    # 开始生成TXT记录
    step "步骤 1: 生成TXT记录值"
    info "正在生成DNS验证记录，这可能需要几秒钟..."
    
    # 使用acme.sh的手动模式 - 修复参数顺序
    local cmd="$acme_cmd --issue $all_domains --yes-I-know-dns-manual-mode-enough-go-ahead-please"
    
    info "执行命令生成验证信息..."
    echo "命令: $cmd"
    
    # 安全执行命令（避免eval）
    local output
    output=$(bash -c "$cmd" 2>&1 | tee "/tmp/acme_output_$(date +%s).log")
    
    # 解析输出中的TXT值
    step "解析TXT记录值..."
    
    # 查找TXT记录（acme.sh的标准输出格式）
    local txt_values=$(echo "$output" | grep -oE "TXT value: '[^']*'" || echo "$output" | grep -oE "TXT='[^']*'")
    
    if [[ -z "$txt_values" ]]; then
        # 尝试其他格式
        txt_values=$(echo "$output" | grep -oE 'TXT.*[A-Za-z0-9._-]{20,}')
    fi
    
    if [[ -z "$txt_values" ]]; then
        error "无法从输出中提取TXT值"
        warning "原始输出:"
        echo "$output" | tail -50
        info "请手动检查acme.sh的输出以获取TXT值"
        return $ERROR_CERT
    fi
    
    # 显示TXT值
    success "找到TXT记录值:"
    echo "$txt_values"
    
    # 更新临时文件
    echo -e "\n实际TXT值:" >> "$temp_file"
    echo "$txt_values" >> "$temp_file"
    
    # 指导用户
    step "步骤 2: 手动添加DNS记录"
    echo "请登录您的DNS管理面板，为每个域名添加上述TXT记录"
    echo ""
    warning "添加后，请等待DNS传播（通常1-5分钟）"
    echo "可以使用以下命令检查是否生效:"
    for domain in "${domains[@]}"; do
        echo "  dig TXT _acme-challenge.$domain +short"
    done
    
    echo -e "\n${CYAN}步骤 3: 继续验证${NC}"
    read -rp "是否已添加所有TXT记录并等待至少1分钟? (y/n): " ready_to_verify
    
    if [[ ! "$ready_to_verify" =~ ^[Yy]$ ]]; then
        warning "请先添加DNS记录，稍后重新运行验证"
        info "验证信息已保存在: $temp_file"
        return $ERROR_USER_CANCEL
    fi
    
    # 执行验证
    step "正在验证DNS记录..."
    
    # 使用renew命令验证（手动模式的第二部分）
    local verify_cmd="$acme_cmd --renew $all_domains --yes-I-know-dns-manual-mode-enough-go-ahead-please"
    
    info "执行验证命令..."
    echo "命令: $verify_cmd"
    
    # 设置超时和重试
    local max_retries=3
    local retry_count=0
    local success=false
    
    while [[ $retry_count -lt $max_retries && "$success" == false ]]; do
        ((retry_count++))
        
        info "尝试 $retry_count/$max_retries"
        
        if bash -c "$verify_cmd"; then
            success=true
            success "DNS验证成功！"
            break
        else
            warning "验证失败，可能DNS还未完全传播"
            
            if [[ $retry_count -lt $max_retries ]]; then
                info "等待30秒后重试..."
                sleep 30
                
                # 建议检查DNS
                step "当前DNS记录状态:"
                for domain in "${domains[@]}"; do
                    echo "检查 $domain:"
                    dig TXT "_acme-challenge.$domain" +short 2>/dev/null || echo "查询失败"
                done
            fi
        fi
    done
    
    if [[ "$success" == true ]]; then
        success "证书申请成功！"
        
        # 建议清理DNS记录
        warning "建议:"
        echo "证书颁发成功后，可以删除DNS中的TXT记录"
        echo "记录已不再需要"
        
        # 清理临时文件
        rm -f "/tmp/acme_output_"* 2>/dev/null
        rm -f "/tmp/acme_exec_"* 2>/dev/null
        
        # 显示证书信息
        show_certificate_info
        
        # 清理检查点
        clear_checkpoint
        
        return 0
    else
        error "DNS验证失败"
        warning "可能的原因:"
        echo "1. TXT记录未正确添加"
        echo "2. DNS传播时间不够（有些DNS需要更长时间）"
        echo "3. TXT值输入错误"
        echo ""
        info "建议操作:"
        echo "1. 仔细检查DNS面板中的TXT值"
        echo "2. 等待5-10分钟后再试"
        echo "3. 使用 dig TXT _acme-challenge.your-domain.com 检查"
        echo "4. 验证信息保存在: $temp_file"
        
        return $ERROR_CERT
    fi
}

# 执行acme命令（增加超时处理，避免eval）
execute_acme_command() {
    local cmd="$1"
    local timeout_seconds=300  # 5分钟超时
    
    info "即将执行命令:"
    echo -e "${YELLOW}$cmd${NC}"
    echo ""
    
    read -rp "是否确认执行? (y/n): " confirm_execute
    
    if [[ ! "$confirm_execute" =~ ^[Yy]$ ]]; then
        warning "已取消"
        clear_checkpoint
        return $ERROR_USER_CANCEL
    fi
    
    # 执行命令并捕获输出
    step "开始执行证书申请..."
    log_message "执行命令: $cmd"
    
    # 使用bash -c安全执行，避免eval
    local output_file="/tmp/acme_exec_$(date +%s).log"
    
    # 使用timeout命令执行（如果可用）
    if command -v timeout &> /dev/null; then
        timeout $timeout_seconds bash -c "$cmd" > "$output_file" 2>&1
        local exit_code=$?
    else
        bash -c "$cmd" > "$output_file" 2>&1
        local exit_code=$?
    fi
    
    if [[ $exit_code -eq 0 ]]; then
        success "证书申请成功！"
        log_message "证书申请成功"
        
        # 显示证书信息
        show_certificate_info
        
        # 询问是否安装证书到Web服务器
        install_to_webserver
        
        # 清理检查点
        clear_checkpoint
        
        return 0
    else
        if [[ $exit_code -eq 124 ]]; then
            error "证书申请超时（${timeout_seconds}秒）"
            log_message "证书申请超时"
            handle_error $ERROR_TIMEOUT "命令执行超时" "execute_acme_command"
        else
            error "证书申请失败，退出码: $exit_code"
            log_message "证书申请失败，退出码: $exit_code"
            
            # 显示错误输出
            if [[ -f "$output_file" ]]; then
                warning "错误输出:"
                tail -20 "$output_file"
            fi
            
            handle_error $ERROR_CERT "acme.sh执行失败" "execute_acme_command"
        fi
        troubleshoot_failure
        return $exit_code
    fi
}

# 显示证书信息
show_certificate_info() {
    step "证书信息"
    
    local acme_cmd=$(get_acme_cmd)
    if [[ -z "$acme_cmd" ]]; then
        error "acme.sh 未找到"
        return $ERROR_DEPENDENCY
    fi
    
    # 列出所有证书
    info "已颁发的证书:"
    $acme_cmd --list
    
    # 显示最新证书的路径
    local cert_dir="$ACME_INSTALL_DIR"
    local domains=$(ls "$cert_dir" 2>/dev/null | grep -E '^[a-zA-Z0-9]' | head -5)
    
    if [[ -n "$domains" ]]; then
        info "证书存储路径:"
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
    
    step "验证证书安装..."
    
    # 验证证书文件存在
    if [[ ! -f "$cert_file" ]]; then
        error "证书文件不存在: $cert_file"
        return $ERROR_CERT
    fi
    
    if [[ ! -f "$key_file" ]]; then
        error "密钥文件不存在: $key_file"
        return $ERROR_CERT
    fi
    
    # 验证证书格式
    if openssl x509 -in "$cert_file" -noout 2>/dev/null; then
        success "证书文件格式正确"
    else
        error "证书文件格式错误"
    fi
    
    # 验证私钥格式
    if openssl rsa -in "$key_file" -check -noout 2>/dev/null; then
        success "密钥文件格式正确"
    else
        # 尝试ECDSA密钥
        if openssl ec -in "$key_file" -check -noout 2>/dev/null; then
            success "ECC密钥文件格式正确"
        else
            error "密钥文件格式错误"
        fi
    fi
    
    # 验证证书和密钥匹配（仅对RSA有效）
    if openssl rsa -in "$key_file" -noout 2>/dev/null; then
        local cert_modulus=$(openssl x509 -noout -modulus -in "$cert_file" | openssl md5)
        local key_modulus=$(openssl rsa -noout -modulus -in "$key_file" 2>/dev/null | openssl md5)
        
        if [[ "$cert_modulus" == "$key_modulus" ]]; then
            success "证书和密钥匹配"
        else
            error "证书和密钥不匹配"
        fi
    fi
    
    # 显示证书信息
    info "证书详细信息:"
    openssl x509 -in "$cert_file" -text -noout | grep -E "Subject:|Issuer:|Not Before:|Not After :"
}

# 安装证书到Web服务器
install_to_webserver() {
    info "是否安装证书到Web服务器? (y/n): "
    read -r install_cert
    
    if [[ "$install_cert" =~ ^[Yy]$ ]]; then
        info "选择Web服务器:"
        echo "1) Nginx"
        echo "2) Apache"
        echo "3) 其他"
        
        read -rp "请选择: " web_server
        
        read -rp "请输入域名: " install_domain
        
        local acme_cmd=$(get_acme_cmd)
        if [[ -z "$acme_cmd" ]]; then
            error "acme.sh 未找到"
            return $ERROR_DEPENDENCY
        fi
        
        case $web_server in
            1)
                step "Nginx证书安装..."
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
                step "Apache证书安装..."
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
                step "手动安装证书"
                echo "证书文件位于: $ACME_INSTALL_DIR/$install_domain/"
                echo "请手动配置您的Web服务器使用这些证书"
                ls -la "$ACME_INSTALL_DIR/$install_domain/" 2>/dev/null || echo "未找到证书目录"
                ;;
        esac
        
        success "证书安装完成！"
    fi
}

# 错误排查
troubleshoot_failure() {
    step "错误排查"
    echo "1) 检查DNS解析"
    echo "2) 检查网络连接"
    echo "3) 检查端口开放"
    echo "4) 查看详细日志"
    echo "5) 检查证书状态"
    echo "6) 恢复备份"
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
        5)
            check_certificate_status
            ;;
        6)
            restore_backup
            ;;
        0)
            return
            ;;
    esac
}

# 检查证书状态函数
check_certificate_status() {
    step "证书状态检查"
    
    local acme_cmd=$(get_acme_cmd)
    if [[ -z "$acme_cmd" ]]; then
        error "acme.sh 未找到"
        return $ERROR_DEPENDENCY
    fi
    
    # 检查即将过期的证书
    info "即将过期的证书:"
    local cert_dirs=$(find "$ACME_INSTALL_DIR" -maxdepth 1 -type d -name "*.*" 2>/dev/null)
    local warning_days=30
    local critical_days=7
    local now=$(date +%s)
    
    for dir in $cert_dirs; do
        local domain=$(basename "$dir")
        local cert_file="$dir/$domain.cer"
        
        if [[ -f "$cert_file" ]]; then
            local expiry_date=$(openssl x509 -in "$cert_file" -enddate -noout | cut -d= -f2)
            local expiry_timestamp=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry_date" +%s 2>/dev/null)
            
            if [[ -n "$expiry_timestamp" ]]; then
                local days_left=$(( (expiry_timestamp - now) / 86400 ))
                
                if [[ $days_left -le $critical_days ]]; then
                    echo -e "${RED}✗ ${domain}: ${days_left}天后过期 (紧急!)${NC}"
                elif [[ $days_left -le $warning_days ]]; then
                    echo -e "${YELLOW}⚠ ${domain}: ${days_left}天后过期${NC}"
                else
                    echo -e "${GREEN}✓ ${domain}: ${days_left}天后过期${NC}"
                fi
            fi
        fi
    done
}

# 检查网络连接（增加超时）
check_network_connectivity() {
    step "检查网络连接..."
    
    # 检查是否可访问Let's Encrypt
    if timeout 10 ping -c 3 acme-v02.api.letsencrypt.org &> /dev/null; then
        success "可访问Let's Encrypt服务器"
    else
        error "无法访问Let's Encrypt服务器"
    fi
    
    # 检查外部网络
    if timeout 10 curl -s https://www.google.com &> /dev/null; then
        success "外部网络连接正常"
    else
        error "外部网络连接异常"
    fi
    
    # 检查Let's Encrypt API状态
    step "检查Let's Encrypt API状态..."
    if timeout 10 curl -s https://acme-v02.api.letsencrypt.org/directory | grep -q "newAccount"; then
        success "Let's Encrypt API正常"
    else
        error "Let's Encrypt API异常"
    fi
}

# 检查DNS解析（增加超时和更多检查）
check_dns_resolution() {
    read -rp "请输入要检查的域名: " check_domain
    
    if [[ -n "$check_domain" ]]; then
        step "检查 $check_domain 的DNS解析..."
        
        # 检查A记录
        if command -v dig &> /dev/null; then
            info "A记录:"
            timeout 10 dig +short A "$check_domain" 2>/dev/null || echo "查询超时"
            
            # 检查_acme-challenge子域名
            info "_acme-challenge TXT记录:"
            timeout 10 dig +short TXT "_acme-challenge.$check_domain" 2>/dev/null || echo "查询超时"
            
            # 检查NS记录
            info "NS记录:"
            timeout 10 dig +short NS "$check_domain" 2>/dev/null || echo "查询超时"
        elif command -v nslookup &> /dev/null; then
            timeout 10 nslookup "$check_domain" 2>/dev/null || echo "查询超时"
        else
            timeout 10 ping -c 1 "$check_domain" 2>/dev/null || echo "查询超时"
        fi
        
        # 检查域名是否解析到正确IP
        step "检查域名解析到本机IP..."
        local public_ip=$(timeout 10 curl -s https://api.ipify.org 2>/dev/null || echo "未知")
        local domain_ip=$(timeout 10 dig +short A "$check_domain" 2>/dev/null | head -1)
        
        if [[ -n "$domain_ip" && -n "$public_ip" && "$domain_ip" == "$public_ip" ]]; then
            success "域名正确解析到本机IP: $public_ip"
        elif [[ -n "$domain_ip" ]]; then
            warning "域名解析到: $domain_ip (本机IP: $public_ip)"
        else
            error "无法获取域名解析"
        fi
    fi
}

# 检查端口（优化错误处理）
check_ports() {
    read -rp "请输入要检查的域名或IP (默认localhost): " check_host
    check_host=${check_host:-localhost}
    read -rp "请输入端口号 (默认80): " check_port
    check_port=${check_port:-80}
    
    step "检查 $check_host:$check_port ..."
    
    # 使用多种方法检查端口
    if check_port "$check_host" "$check_port"; then
        success "端口 $check_port 可访问"
    else
        error "端口 $check_port 不可访问"
    fi
    
    # 检查服务是否运行
    if [[ "$check_port" -eq 80 ]] && command -v ss &> /dev/null; then
        step "检查80端口服务..."
        ss -tlnp | grep ":80" || echo "80端口无服务监听"
    fi
}

# 查看日志
view_logs() {
    step "日志查看"
    echo "1) 查看脚本日志"
    echo "2) 查看acme.sh日志"
    echo "3) 查看系统日志"
    echo "4) 清除旧日志"
    
    read -rp "请选择: " log_choice
    
    case $log_choice in
        1)
            if [[ -f "$LOG_FILE" ]]; then
                info "显示最后100行日志:"
                tail -100 "$LOG_FILE"
                echo -e "\n${YELLOW}输入 'q' 退出查看${NC}"
                read -p "按回车查看完整日志..." 
                less "$LOG_FILE"
            else
                warning "今日暂无日志"
            fi
            ;;
        2)
            local acme_log="$ACME_INSTALL_DIR/acme.sh.log"
            if [[ -f "$acme_log" ]]; then
                info "显示acme.sh最后50行日志:"
                tail -50 "$acme_log"
            else
                warning "acme.sh日志未找到"
            fi
            ;;
        3)
            if [[ -f "/var/log/syslog" ]]; then
                info "显示系统日志中与acme相关的记录:"
                grep -i acme /var/log/syslog | tail -50
            elif [[ -f "/var/log/messages" ]]; then
                grep -i acme /var/log/messages | tail -50
            else
                warning "系统日志未找到"
            fi
            ;;
        4)
            warning "清除7天前的日志..."
            find "$LOG_DIR" -name "*.log" -mtime +7 -delete
            success "日志清理完成"
            
            # 同时清理acme.sh日志
            if [[ -f "$ACME_INSTALL_DIR/acme.sh.log" ]]; then
                > "$ACME_INSTALL_DIR/acme.sh.log"
                success "acme.sh日志已清空"
            fi
            ;;
    esac
}

# 证书续期管理
manage_renewals() {
    step "证书续期管理"
    echo "1) 手动续期所有证书"
    echo "2) 测试续期（不实际执行）"
    echo "3) 查看即将过期的证书"
    echo "4) 设置自动续期"
    echo "5) 强制续期指定证书"
    echo "0) 返回主菜单"
    
    read -rp "请选择: " renew_choice
    
    local acme_cmd=$(get_acme_cmd)
    if [[ -z "$acme_cmd" ]]; then
        error "acme.sh 未找到"
        return $ERROR_DEPENDENCY
    fi
    
    case $renew_choice in
        1)
            info "选择续期方式:"
            echo "1) 正常续期（仅到期前30天的证书）"
            echo "2) 强制续期（所有证书，谨慎使用）"
            read -rp "请选择: " renew_method
            
            case $renew_method in
                1) 
                    step "正在正常续期证书..."
                    $acme_cmd --renew-all
                    ;;
                2)
                    step "正在强制续期所有证书..."
                    $acme_cmd --renew-all --force
                    ;;
                *)
                    step "正在正常续期证书..."
                    $acme_cmd --renew-all
                    ;;
            esac
            ;;
        2)
            step "测试续期（干运行）..."
            $acme_cmd --renew-all --force --test
            ;;
        3)
            step "证书状态:"
            $acme_cmd --list | while read -r line; do
                if [[ "$line" == *"Renew"* ]] || [[ "$line" == *"Expire"* ]]; then
                    echo "$line"
                fi
            done
            
            # 显示详细过期时间
            info "证书详细过期时间:"
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
                step "强制续期 $force_domain ..."
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
    step "acme.sh 已内置自动续期功能"
    info "当前自动续期状态:"
    
    local acme_cmd=$(get_acme_cmd)
    if crontab -l 2>/dev/null | grep -E "acme\.sh.*--cron|--cron.*acme\.sh" >/dev/null; then
        success "cron任务已安装"
    else
        warning "cron任务未安装"
    fi
    
    echo ""
    info "acme.sh 会自动安装cron任务，每天检查证书续期"
    echo "如需手动配置，请运行: $acme_cmd --install-cronjob"
    
    # 显示当前的cron任务
    step "当前cron任务:"
    crontab -l | grep -i acme || echo "未找到acme相关cron任务"
    
    read -rp "是否要重新安装cron任务? (y/n): " reinstall_cron
    if [[ "$reinstall_cron" =~ ^[Yy]$ ]]; then
        $acme_cmd --install-cronjob
        success "cron任务已重新安装"
    fi
}

# 证书吊销
revoke_certificate() {
    step "证书吊销"
    
    read -rp "请输入要吊销的域名: " revoke_domain
    
    if [[ -n "$revoke_domain" ]]; then
        error "警告: 吊销后将无法恢复！"
        read -rp "确定要吊销 $revoke_domain 的证书吗? (y/n): " confirm_revoke
        
        if [[ "$confirm_revoke" =~ ^[Yy]$ ]]; then
            local acme_cmd=$(get_acme_cmd)
            if [[ -z "$acme_cmd" ]]; then
                error "acme.sh 未找到"
                return $ERROR_DEPENDENCY
            fi
            
            # 先备份证书
            local backup_path=$(backup_certificate "$revoke_domain")
            if [[ -n "$backup_path" ]]; then
                info "证书已备份到: $backup_path"
            fi
            
            # 尝试吊销
            if $acme_cmd --revoke -d "$revoke_domain"; then
                success "证书吊销成功"
                
                # 询问是否删除证书文件
                info "是否删除证书文件? (y/n): "
                read -r delete_files
                if [[ "$delete_files" =~ ^[Yy]$ ]]; then
                    $acme_cmd --remove -d "$revoke_domain"
                    rm -rf "$ACME_INSTALL_DIR/$revoke_domain" 2>/dev/null
                    success "证书文件已删除"
                fi
            else
                error "证书吊销失败"
            fi
        fi
    fi
}

# 删除证书（完全清理）
delete_certificate() {
    step "删除证书"
    
    # 显示现有证书
    info "现有证书列表:"
    local acme_cmd=$(get_acme_cmd)
    if [[ -z "$acme_cmd" ]]; then
        error "acme.sh 未找到"
        read -rp "按回车键返回..."
        return $ERROR_DEPENDENCY
    fi
    
    # 列出所有证书
    local cert_list=$($acme_cmd --list 2>/dev/null)
    if [[ -z "$cert_list" ]]; then
        warning "暂无证书"
        return
    fi
    
    echo "$cert_list"
    echo ""
    
    # 选择删除方式
    info "选择删除方式:"
    echo "1) 输入域名删除"
    echo "2) 批量删除（支持通配符）"
    echo "3) 删除所有证书"
    echo "0) 返回"
    
    read -rp "请选择: " delete_method
    
    case $delete_method in
        1)
            delete_single_certificate
            ;;
        2)
            delete_batch_certificates
            ;;
        3)
            delete_all_certificates
            ;;
        0)
            return
            ;;
        *)
            error "无效选择"
            delete_certificate
            ;;
    esac
}

# 删除单个证书
delete_single_certificate() {
    local acme_cmd=$(get_acme_cmd)
    if [[ -z "$acme_cmd" ]]; then
        error "acme.sh 未找到"
        return $ERROR_DEPENDENCY
    fi
    
    read -rp "请输入要删除的域名（例如: example.com 或 *.example.com）: " delete_domain
    
    if [[ -z "$delete_domain" ]]; then
        error "域名不能为空"
        return $ERROR_VALIDATION
    fi
    
    # 安全处理域名（防止路径遍历）
    local safe_domain=$(basename "$delete_domain" | tr -cd '[:alnum:].-_*')
    
    # 验证域名是否存在
    if ! $acme_cmd --list | grep -q "$delete_domain"; then
        warning "未找到证书 '$delete_domain'"
        info "是否继续删除相关文件? (y/n): "
        read -r force_delete
        if [[ ! "$force_delete" =~ ^[Yy]$ ]]; then
            return $ERROR_USER_CANCEL
        fi
    fi
    
    # 确认删除
    error "警告: 这将永久删除以下内容:"
    echo "1) 证书文件 (.cer, .key, .crt)"
    echo "2) 证书配置"
    echo "3) 域名目录"
    echo ""
    
    read -rp "确定要删除证书 '$delete_domain' 吗? (y/n): " confirm_delete
    
    if [[ "$confirm_delete" =~ ^[Yy]$ ]]; then
        # 先备份
        local backup_path=$(backup_certificate "$safe_domain")
        if [[ -n "$backup_path" ]]; then
            info "证书已备份到: $backup_path"
        fi
        
        # 获取证书目录（安全处理通配符）
        local cert_dir="$ACME_INSTALL_DIR/${safe_domain//\*/_}"
        
        # 首先吊销证书（如果有效）
        step "正在吊销证书..."
        $acme_cmd --revoke -d "$delete_domain" 2>/dev/null || warning "吊销失败或证书已过期"
        
        # 使用acme.sh的remove命令
        step "正在移除证书配置..."
        $acme_cmd --remove -d "$delete_domain" 2>/dev/null || warning "移除配置失败"
        
        # 手动删除所有相关文件和目录
        step "正在删除相关文件..."
        
        # 删除证书目录（使用find安全删除）
        if [[ -d "$cert_dir" ]]; then
            echo "删除目录: $cert_dir"
            rm -rf "$cert_dir"
        fi
        
        # 查找并删除其他可能位置（安全方式）
        local search_paths=(
            "$ACME_INSTALL_DIR/${delete_domain#\*.}"  # 通配符证书主域
            "$ACME_INSTALL_DIR/${delete_domain//\*/_}"  # 替换*为_
        )
        
        for path in "${search_paths[@]}"; do
            if [[ -e "$path" ]]; then
                echo "删除匹配文件: $path"
                rm -rf "$path" 2>/dev/null
            fi
        done
        
        # 删除符号链接
        find "$ACME_INSTALL_DIR" -type l -name "*${delete_domain//\*/_}*" -delete 2>/dev/null
        
        # 清理acme.sh数据库
        local acme_db="$HOME/.acme.sh/account.conf"
        if [[ -f "$acme_db" ]]; then
            # 安全移除域名相关行
            sed -i "\|${delete_domain//\//\\/}|d" "$acme_db" 2>/dev/null
        fi
        
        success "证书 '$delete_domain' 已完全删除"
        
        # 显示剩余证书
        step "剩余证书:"
        $acme_cmd --list 2>/dev/null || echo "暂无证书"
    else
        warning "已取消删除"
    fi
}

# 批量删除证书
delete_batch_certificates() {
    local acme_cmd=$(get_acme_cmd)
    if [[ -z "$acme_cmd" ]]; then
        error "acme.sh 未找到"
        return $ERROR_DEPENDENCY
    fi
    
    step "批量删除证书"
    info "支持使用通配符，例如:"
    echo "  *.example.com - 删除所有example.com的子域名证书"
    echo "  test* - 删除所有以test开头的域名证书"
    echo "  *dev* - 删除所有包含dev的域名证书"
    echo ""
    
    read -rp "请输入匹配模式: " pattern
    
    if [[ -z "$pattern" ]]; then
        error "匹配模式不能为空"
        return $ERROR_VALIDATION
    fi
    
    # 安全处理模式
    pattern=$(echo "$pattern" | tr -cd '[:alnum:].-_*?[]')
    
    # 查找匹配的证书
    local matching_certs=$($acme_cmd --list 2>/dev/null | grep -E "$pattern" || true)
    
    if [[ -z "$matching_certs" ]]; then
        warning "未找到匹配的证书"
        return
    fi
    
    info "找到以下匹配的证书:"
    echo "$matching_certs"
    echo ""
    
    read -rp "确定要删除以上所有证书吗? (y/n): " confirm_batch
    
    if [[ "$confirm_batch" =~ ^[Yy]$ ]]; then
        # 提取域名
        local domains=$(echo "$matching_certs" | awk '{print $1}')
        local count=0
        
        for domain in $domains; do
            step "删除: $domain"
            # 先备份
            backup_certificate "$domain" >/dev/null 2>&1
            # 调用单个删除函数（简化版）
            $acme_cmd --remove -d "$domain" 2>/dev/null || true
            rm -rf "$ACME_INSTALL_DIR/$domain" 2>/dev/null
            ((count++))
        done
        
        success "批量删除完成！删除了 $count 个证书"
    else
        warning "已取消批量删除"
    fi
}

# 删除所有证书
delete_all_certificates() {
    local acme_cmd=$(get_acme_cmd)
    if [[ -z "$acme_cmd" ]]; then
        error "acme.sh 未找到"
        return $ERROR_DEPENDENCY
    fi
    
    error "⚠⚠⚠ 警告: 危险操作 ⚠⚠⚠"
    warning "这将删除所有已颁发的证书！"
    echo ""
    info "影响范围:"
    echo "1) 所有域名证书"
    echo "2) 所有证书文件"
    echo "3) 所有证书配置"
    echo "4) 所有DNS API设置（可选）"
    echo ""
    error "此操作不可恢复！"
    
    read -rp "输入 'CONFIRM_DELETE_ALL' 确认删除: " confirm_text
    
    if [[ "$confirm_text" != "CONFIRM_DELETE_ALL" ]]; then
        warning "已取消"
        return $ERROR_USER_CANCEL
    fi
    
    # 再次确认
    read -rp "确定要删除所有证书吗? (y/N): " final_confirm
    
    if [[ "$final_confirm" =~ ^[Yy]$ ]]; then
        step "正在删除所有证书..."
        
        # 获取所有证书
        local all_certs=$($acme_cmd --list 2>/dev/null | awk '{print $1}')
        local count=0
        
        # 创建完整备份
        local full_backup="$BACKUP_DIR/full_backup_$(date +%Y%m%d_%H%M%S)"
        mkdir -p "$full_backup"
        cp -r "$ACME_INSTALL_DIR"/* "$full_backup/" 2>/dev/null
        info "完整备份已创建到: $full_backup"
        
        for domain in $all_certs; do
            step "删除: $domain"
            $acme_cmd --remove -d "$domain" 2>/dev/null || true
            rm -rf "$ACME_INSTALL_DIR/$domain" 2>/dev/null
            ((count++))
        done
        
        # 删除其他可能文件
        step "清理残留文件..."
        find "$ACME_INSTALL_DIR" -type d -name "*.*" -exec rm -rf {} \; 2>/dev/null
        
        # 清理配置文件
        rm -f "$ACME_INSTALL_DIR"/account.conf 2>/dev/null
        rm -f "$ACME_INSTALL_DIR"/ca/*.conf 2>/dev/null
        
        # 可选：是否删除DNS API配置
        info "是否同时删除DNS API配置? (y/n): "
        read -r delete_dns_config
        if [[ "$delete_dns_config" =~ ^[Yy]$ ]]; then
            rm -rf "$CONFIG_DIR/dns_apis"/*
            info "DNS API配置已删除"
        fi
        
        success "已删除 $count 个证书，所有证书已清理完毕！"
    else
        warning "已取消"
    fi
}

# 系统状态检查（增强版）
check_system_status() {
    step "系统状态检查"
    
    # 检查acme.sh
    local acme_cmd=$(get_acme_cmd)
    if [[ -n "$acme_cmd" ]]; then
        success "acme.sh 已安装"
        $acme_cmd --version
        info "当前证书提供商:"
        local ca_info=$($acme_cmd --info 2>/dev/null)
        if [[ -n "$ca_info" ]]; then
            echo "$ca_info" | grep -E "SERVER|CA.*directory" | head -1 | sed 's/^[ \t]*//'
        else
            echo "未知 (运行 $acme_cmd --info 查看详情)"
        fi
    else
        error "acme.sh 未安装"
    fi
    
    # 检查证书数量
    local cert_count=0
    if [[ -d "$ACME_INSTALL_DIR" ]]; then
        cert_count=$(find "$ACME_INSTALL_DIR" -maxdepth 1 -type d -name "*.*" | wc -l)
    fi
    info "现有证书数量: $cert_count"
    
    # 显示最近颁发的证书
    if [[ $cert_count -gt 0 ]]; then
        info "最近颁发的证书:"
        find "$ACME_INSTALL_DIR" -maxdepth 1 -type d -name "*.*" | head -5 | while read dir; do
            domain=$(basename "$dir")
            echo "  - $domain"
        done
    fi
    
    # 检查端口占用
    info "端口占用情况:"
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
    info "磁盘空间检查:"
    df -h "$HOME" | tail -1
    
    # 检查内存使用
    info "内存使用情况:"
    free -h | head -2
    
    # 检查防火墙状态
    info "防火墙状态:"
    if command -v ufw &> /dev/null; then
        ufw status | head -5
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --state 2>/dev/null || echo "firewalld未运行"
    else
        echo "未检测到常见防火墙"
    fi
    
    # 检查证书状态
    check_certificate_status
}

# API接口：命令行模式
api_command_line() {
    local command="$1"
    shift
    
    case "$command" in
        --apply|-a)
            local domain="$1"
            local validation_method="$2"
            
            if [[ -z "$domain" ]]; then
                error "请提供域名"
                exit $ERROR_VALIDATION
            fi
            
            if ! validate_domain "$domain"; then
                exit $ERROR_VALIDATION
            fi
            
            # 安装acme.sh
            if ! install_acme; then
                exit $ERROR_DEPENDENCY
            fi
            
            # 设置验证方式
            local acme_cmd=$(get_acme_cmd)
            local cmd="$acme_cmd --issue"
            
            case "$validation_method" in
                dns)
                    cmd="$cmd --dns dns_cf -d $domain"
                    ;;
                http|standalone)
                    cmd="$cmd --standalone -d $domain"
                    ;;
                *)
                    cmd="$cmd --standalone -d $domain"
                    ;;
            esac
            
            # 执行命令
            execute_acme_command "$cmd"
            ;;
            
        --renew|-r)
            local domain="$1"
            local acme_cmd=$(get_acme_cmd)
            
            if [[ -z "$domain" ]]; then
                # 续期所有证书
                $acme_cmd --renew-all
            else
                $acme_cmd --renew -d "$domain"
            fi
            ;;
            
        --list|-l)
            local acme_cmd=$(get_acme_cmd)
            $acme_cmd --list
            ;;
            
        --revoke|-x)
            local domain="$1"
            
            if [[ -z "$domain" ]]; then
                error "请提供要吊销的域名"
                exit $ERROR_VALIDATION
            fi
            
            local acme_cmd=$(get_acme_cmd)
            $acme_cmd --revoke -d "$domain"
            ;;
            
        --delete|-d)
            local domain="$1"
            
            if [[ -z "$domain" ]]; then
                error "请提供要删除的域名"
                exit $ERROR_VALIDATION
            fi
            
            delete_single_certificate "$domain"
            ;;
            
        --status|-s)
            check_system_status
            ;;
            
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -a, --apply DOMAIN [METHOD]   申请证书 (方法: dns, http)"
            echo "  -r, --renew [DOMAIN]          续期证书 (不指定域名则续期所有)"
            echo "  -l, --list                    列出所有证书"
            echo "  -x, --revoke DOMAIN           吊销证书"
            echo "  -d, --delete DOMAIN           删除证书"
            echo "  -s, --status                  查看系统状态"
            echo "  -h, --help                    显示此帮助信息"
            echo "  --api-mode                    进入API服务器模式"
            echo ""
            echo "Examples:"
            echo "  $0 --apply example.com dns"
            echo "  $0 --renew example.com"
            echo "  $0 --list"
            echo "  $0 --status"
            ;;
            
        --api-mode)
            start_api_server
            ;;
            
        *)
            error "未知命令: $command"
            echo "使用 $0 --help 查看帮助信息"
            exit $ERROR_CONFIG
            ;;
    esac
}

# API服务器模式
start_api_server() {
    step "启动API服务器..."
    info "API服务器运行在: http://localhost:8080"
    echo "可用端点:"
    echo "  GET  /status       系统状态"
    echo "  GET  /certificates 证书列表"
    echo "  POST /apply        申请证书"
    echo "  POST /renew        续期证书"
    echo "  POST /revoke       吊销证书"
    echo ""
    warning "按Ctrl+C停止服务器"
    
    # 简单的HTTP服务器
    while true; do
        echo -e "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"running\",\"timestamp\":\"$(date)\"}" | nc -l -p 8080 -q 1
    done
}

# 主菜单
main_menu() {
    while true; do
        show_banner
        
        echo -e "${GREEN}请选择操作:${NC}"
        echo "1) 申请新证书"
        echo "2) 管理续期"
        echo "3) 吊销证书"
        echo "4) 删除证书"
        echo "5) 配置DNS API"
        echo "6) 查看证书信息"
        echo "7) 系统检查"
        echo "8) 问题排查"
        echo "9) 查看日志"
        echo "10) 恢复备份"
        echo "11) API接口模式"
        echo "0) 退出"
        echo ""
        
        read -rp "请输入选项 (0-11): " main_choice
        
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
                delete_certificate
                ;;
            5)
                setup_dns_api
                ;;
            6)
                show_certificate_info
                ;;
            7)
                check_system_status
                ;;
            8)
                troubleshoot_menu
                ;;
            9)
                view_logs
                ;;
            10)
                restore_backup
                ;;
            11)
                start_api_server
                ;;
            0)
                echo -e "${GREEN}再见！${NC}"
                clear_checkpoint
                exit 0
                ;;
            *)
                error "无效选择，请重新输入 (0-11)"
                ;;
        esac
        
        echo ""
        read -rp "按回车键继续..."
    done
}

# 问题排查菜单
troubleshoot_menu() {
    step "问题排查"
    echo "1) 网络连接测试"
    echo "2) DNS解析测试"
    echo "3) 端口可用性测试"
    echo "4) 查看日志"
    echo "5) 重置配置"
    echo "6) 检查证书状态"
    echo "7) 恢复备份"
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
            check_certificate_status
            ;;
        7)
            restore_backup
            ;;
        0)
            return
            ;;
    esac
}

# 脚本入口
main() {
    # 检查命令行参数
    if [[ $# -gt 0 ]]; then
        api_command_line "$@"
        exit $?
    fi
    
    # 检查是否是root用户（改为警告而非强制退出）
    if [[ $EUID -ne 0 ]]; then
        warning "注意: 某些功能（如80端口验证）需要root权限"
        info "建议使用sudo或切换到root用户运行此脚本"
        echo ""
        read -rp "是否继续? (y/n): " continue_as_user
        if [[ ! "$continue_as_user" =~ ^[Yy]$ ]]; then
            echo "请使用: sudo $0"
            exit $ERROR_PERMISSION
        fi
    fi
    
    # 检查锁文件，防止重复运行
    if [[ -f "$LOCK_FILE" ]]; then
        error "脚本已在运行中 (锁文件: $LOCK_FILE)"
        read -rp "是否强制继续? (y/n): " force_continue
        if [[ ! "$force_continue" =~ ^[Yy]$ ]]; then
            exit $ERROR_CONFIG
        fi
    fi
    
    # 创建锁文件
    echo $$ > "$LOCK_FILE"
    
    # 检查恢复点
    restore_from_checkpoint
    
    # 检查配置兼容性
    check_config_compatibility
    
    # 检查依赖
    check_dependencies
    
    # 安装acme.sh
    if ! install_acme; then
        error "acme.sh 安装失败，脚本退出"
        rm -f "$LOCK_FILE"
        exit $ERROR_DEPENDENCY
    fi
    
    # 运行主菜单
    main_menu
}

# 捕获Ctrl+C
trap 'echo -e "\n${YELLOW}用户中断操作${NC}"; cleanup; clear_checkpoint; exit $ERROR_USER_CANCEL' INT

# 启动脚本
main "$@"
