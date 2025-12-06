#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置文件路径
CONFIG_DIR="$HOME/.acme_script"
CONFIG_FILE="$CONFIG_DIR/config"
DNS_API_DIR="$CONFIG_DIR/dns_apis"
LOG_DIR="$CONFIG_DIR/logs"
LOG_FILE="$LOG_DIR/acme_$(date +%Y%m%d).log"

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
    echo "║                  ACME 证书自动化管理脚本                 ║"
    echo "║                  全面支持所有申请场景                    ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# 检查依赖
check_dependencies() {
    local missing_deps=()
    
    # 检查certbot
    if ! command -v certbot &> /dev/null; then
        missing_deps+=("certbot")
    fi
    
    # 检查curl
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    # 检查openssl
    if ! command -v openssl &> /dev/null; then
        missing_deps+=("openssl")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_message "${RED}缺少必要的依赖: ${missing_deps[*]}${NC}"
        echo -e "${YELLOW}是否要自动安装缺少的依赖? (y/n): ${NC}"
        read -r install_choice
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
    
    cat > "$DNS_API_DIR/cloudflare.ini" << EOF
# Cloudflare API credentials
dns_cloudflare_api_token = $cf_token
dns_cloudflare_email = $cf_email
EOF
    
    chmod 600 "$DNS_API_DIR/cloudflare.ini"
    echo -e "${GREEN}Cloudflare配置已保存${NC}"
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
    
    cat > "$DNS_API_DIR/aliyun.ini" << EOF
# Aliyun API credentials
dns_aliyun_access_key = $aliyun_key
dns_aliyun_access_key_secret = $aliyun_secret
EOF
    
    chmod 600 "$DNS_API_DIR/aliyun.ini"
    echo -e "${GREEN}阿里云配置已保存${NC}"
}

# 证书申请主函数
apply_certificate() {
    echo -e "${CYAN}=== 证书申请向导 ===${NC}"
    
    # 选择证书类型
    echo -e "${YELLOW}选择证书类型:${NC}"
    echo "1) 单域名证书"
    echo "2) 多域名证书 (SAN证书)"
    echo "3) 通配符证书 (*.example.com)"
    echo "4) 多域名通配符混合证书"
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
            apply_mixed
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
    choose_validation_method "${domains[*]}"
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
    
    # 选择DNS验证方式
    choose_dns_provider "$domain" "wildcard"
}

# 申请混合证书
apply_mixed() {
    echo -e "${YELLOW}=== 混合证书申请 ===${NC}"
    
    echo -e "${CYAN}请输入域名，可包含普通域名和通配符域名${NC}"
    echo "示例:"
    echo "  example.com"
    echo "  *.example.com"
    echo "  www.example.com"
    echo "  *.sub.example.com"
    echo ""
    
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
        
        domains+=("$domain")
        ((i++))
    done
    
    # 检查是否包含通配符
    local has_wildcard=false
    for domain in "${domains[@]}"; do
        if [[ "$domain" == \*\.* ]]; then
            has_wildcard=true
            break
        fi
    done
    
    if [[ "$has_wildcard" == true ]]; then
        echo -e "${CYAN}检测到通配符域名，必须使用DNS验证${NC}"
        choose_dns_provider "$(printf '%s,' "${domains[@]}")" "mixed"
    else
        choose_validation_method "$(printf '%s,' "${domains[@]}")"
    fi
}

# 选择验证方式
choose_validation_method() {
    local domains=$1
    
    echo -e "${YELLOW}选择验证方式:${NC}"
    echo "1) HTTP验证 (需要80端口可访问)"
    echo "2) DNS验证 (支持通配符)"
    echo "3) TLS-ALPN验证 (需要443端口)"
    echo "0) 返回"
    
    read -rp "请选择: " validation_choice
    
    case $validation_choice in
        1)
            http_validation "$domains"
            ;;
        2)
            choose_dns_provider "$domains" "standard"
            ;;
        3)
            tls_alpn_validation "$domains"
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            choose_validation_method "$domains"
            ;;
    esac
}

# HTTP验证
http_validation() {
    local domains=$1
    
    echo -e "${YELLOW}=== HTTP验证配置 ===${NC}"
    echo -e "${CYAN}请确保您的服务器80端口可被外网访问${NC}"
    
    echo -e "${YELLOW}选择Web服务器类型:${NC}"
    echo "1) Nginx"
    echo "2) Apache"
    echo "3) 其他/手动配置"
    echo "4) 使用standalone模式 (临时占用80端口)"
    
    read -rp "请选择: " server_type
    
    local certbot_cmd="certbot certonly --agree-tos --no-eff-email --register-unsafely-without-email"
    
    case $server_type in
        1|2)
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
            
            # 将逗号分隔的域名转换为certbot参数
            IFS=',' read -ra domain_array <<< "$domains"
            local domain_args=""
            for domain in "${domain_array[@]}"; do
                domain_args+=" -d ${domain// /}"
            done
            
            certbot_cmd+=" --webroot -w $webroot $domain_args"
            ;;
        3)
            echo -e "${CYAN}请手动配置Web服务器验证${NC}"
            read -rp "请输入验证文件存放路径: " manual_path
            certbot_cmd+=" --webroot -w $manual_path -d ${domains//,/-d }"
            ;;
        4)
            echo -e "${YELLOW}注意: standalone模式将临时占用80端口${NC}"
            echo -e "${CYAN}请确保80端口未被占用，或同意脚本停止相关服务${NC}"
            
            # 检查端口占用
            if lsof -i :80 | grep LISTEN; then
                echo -e "${RED}80端口已被占用:${NC}"
                lsof -i :80
                echo -e "${YELLOW}是否尝试停止占用80端口的服务? (y/n): ${NC}"
                read -r stop_service
                if [[ "$stop_service" =~ ^[Yy]$ ]]; then
                    stop_port_80
                else
                    echo -e "${RED}无法继续，请手动释放80端口${NC}"
                    return 1
                fi
            fi
            
            certbot_cmd+=" --standalone -d ${domains//,/-d }"
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            return 1
            ;;
    esac
    
    execute_certbot "$certbot_cmd"
}

# DNS验证
choose_dns_provider() {
    local domains=$1
    local cert_type=$2
    
    echo -e "${YELLOW}=== DNS验证配置 ===${NC}"
    echo -e "${CYAN}选择DNS服务商:${NC}"
    
    # 检查已配置的DNS API
    local dns_apis=()
    if [[ -d "$DNS_API_DIR" ]]; then
        dns_apis=("$DNS_API_DIR"/*.ini)
    fi
    
    local i=1
    declare -A api_map
    
    echo "$i) Cloudflare"; api_map[$i]="cloudflare"; ((i++))
    echo "$i) 阿里云"; api_map[$i]="aliyun"; ((i++))
    echo "$i) 腾讯云(DNSPod)"; api_map[$i]="dnspod"; ((i++))
    echo "$i) 华为云"; api_map[$i]="huaweicloud"; ((i++))
    
    # 显示已保存的配置
    for api_file in "${dns_apis[@]}"; do
        if [[ -f "$api_file" ]]; then
            local api_name=$(basename "$api_file" .ini)
            if [[ ! " ${api_map[@]} " =~ " $api_name " ]]; then
                echo "$i) $api_name (已配置)"; api_map[$i]="$api_name"; ((i++))
            fi
        fi
    done
    
    echo "0) 返回"
    
    read -rp "请选择: " dns_choice
    
    if [[ "$dns_choice" == "0" ]]; then
        return
    fi
    
    local selected_api=${api_map[$dns_choice]}
    
    if [[ -z "$selected_api" ]]; then
        echo -e "${RED}无效选择${NC}"
        choose_dns_provider "$domains" "$cert_type"
        return
    fi
    
    # 检查配置是否存在，不存在则创建
    if [[ ! -f "$DNS_API_DIR/$selected_api.ini" ]] && [[ ! "$selected_api" =~ ^(cloudflare|aliyun|dnspod|huaweicloud)$ ]]; then
        setup_custom_dns "$selected_api"
    fi
    
    # 构建certbot命令
    local certbot_cmd="certbot certonly --agree-tos --no-eff-email --register-unsafely-without-email"
    certbot_cmd+=" --dns-$selected_api"
    
    if [[ -f "$DNS_API_DIR/$selected_api.ini" ]]; then
        certbot_cmd+=" --dns-$selected_api-credentials $DNS_API_DIR/$selected_api.ini"
    fi
    
    # 添加域名参数
    IFS=',' read -ra domain_array <<< "$domains"
    for domain in "${domain_array[@]}"; do
        certbot_cmd+=" -d ${domain// /}"
    done
    
    # 对于通配符，添加推荐参数
    if [[ "$cert_type" == "wildcard" || "$cert_type" == "mixed" ]]; then
        certbot_cmd+=" --preferred-challenges dns-01"
    fi
    
    execute_certbot "$certbot_cmd"
}

# 停止80端口服务
stop_port_80() {
    echo -e "${YELLOW}尝试停止占用80端口的服务...${NC}"
    
    # 尝试常见服务
    local services=("nginx" "apache2" "httpd" "lighttpd")
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "${YELLOW}停止 $service 服务${NC}"
            systemctl stop "$service"
        fi
    done
    
    # 检查是否还有进程占用80端口
    if lsof -i :80 | grep LISTEN; then
        echo -e "${RED}仍有进程占用80端口，请手动处理:${NC}"
        lsof -i :80
        return 1
    fi
    
    echo -e "${GREEN}80端口已释放${NC}"
}

# 执行certbot命令
execute_certbot() {
    local certbot_cmd=$1
    
    echo -e "${CYAN}即将执行命令:${NC}"
    echo -e "${YELLOW}$certbot_cmd${NC}"
    echo ""
    
    read -rp "是否确认执行? (y/n): " confirm_execute
    
    if [[ ! "$confirm_execute" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}已取消${NC}"
        return
    fi
    
    # 执行命令并捕获输出
    echo -e "${BLUE}开始执行证书申请...${NC}"
    log_message "执行命令: $certbot_cmd"
    
    if eval "$certbot_cmd"; then
        echo -e "${GREEN}证书申请成功！${NC}"
        log_message "证书申请成功"
        
        # 显示证书信息
        show_certificate_info
        
        # 询问是否设置自动续期
        setup_auto_renew
        
        # 询问是否安装证书到Web服务器
        install_to_webserver
        
    else
        echo -e "${RED}证书申请失败${NC}"
        log_message "证书申请失败"
        
        # 提供错误排查建议
        troubleshoot_failure
    fi
}

# 显示证书信息
show_certificate_info() {
    echo -e "${CYAN}证书信息:${NC}"
    
    # 查找最新的证书
    local cert_dir="/etc/letsencrypt/live"
    local latest_cert=$(ls -t "$cert_dir" | head -1)
    
    if [[ -n "$latest_cert" ]]; then
        local cert_path="$cert_dir/$latest_cert/fullchain.pem"
        
        echo -e "${YELLOW}证书位置:${NC} $cert_path"
        
        # 显示证书详细信息
        if openssl x509 -in "$cert_path" -noout -text 2>/dev/null | grep -A1 "Subject:"; then
            echo -e "${YELLOW}有效期:${NC}"
            openssl x509 -in "$cert_path" -noout -dates | sed 's/notBefore=//; s/notAfter=//'
            
            echo -e "${YELLOW}证书链:${NC}"
            openssl x509 -in "$cert_path" -noout -issuer
            
            # 显示SAN信息
            local san_info=$(openssl x509 -in "$cert_path" -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name:")
            if [[ -n "$san_info" ]]; then
                echo -e "${YELLOW}备用名称(SAN):${NC}"
                echo "$san_info"
            fi
        fi
    else
        echo -e "${RED}未找到证书${NC}"
    fi
}

# 设置自动续期
setup_auto_renew() {
    echo -e "${CYAN}是否设置自动续期? (y/n): ${NC}"
    read -r setup_renew
    
    if [[ "$setup_renew" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}选择续期检查频率:${NC}"
        echo "1) 每天检查 (推荐)"
        echo "2) 每周检查"
        echo "3) 每月检查"
        
        read -rp "请选择: " renew_freq
        
        local cron_schedule=""
        case $renew_freq in
            1) cron_schedule="0 0 * * *" ;;    # 每天午夜
            2) cron_schedule="0 0 * * 0" ;;    # 每周日午夜
            3) cron_schedule="0 0 1 * *" ;;    # 每月1号午夜
            *) cron_schedule="0 0 * * *" ;;    # 默认每天
        esac
        
        # 创建续期脚本
        local renew_script="$CONFIG_DIR/renew_certs.sh"
        cat > "$renew_script" << 'EOF'
#!/bin/bash
# 证书自动续期脚本

echo "=== $(date) 证书续期检查 ===" >> /var/log/acme_renew.log

# 尝试续期所有证书
if certbot renew --quiet --post-hook "systemctl reload nginx apache2"; then
    echo "证书续期成功" >> /var/log/acme_renew.log
else
    echo "证书续期失败" >> /var/log/acme_renew.log
    # 发送通知邮件
    echo "证书续期失败，请手动检查" | mail -s "证书续期失败通知" admin@example.com
fi
EOF
        
        chmod +x "$renew_script"
        
        # 添加到crontab
        (crontab -l 2>/dev/null; echo "$cron_schedule $renew_script") | crontab -
        
        echo -e "${GREEN}自动续期已设置完成！${NC}"
        echo -e "${YELLOW}续期脚本位置:${NC} $renew_script"
        echo -e "${YELLOW}日志文件:${NC} /var/log/acme_renew.log"
    fi
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
        
        # 查找最新的证书
        local cert_dir="/etc/letsencrypt/live"
        local latest_cert=$(ls -t "$cert_dir" | head -1)
        
        if [[ -n "$latest_cert" ]]; then
            local cert_path="$cert_dir/$latest_cert"
            
            case $web_server in
                1)
                    setup_nginx_cert "$cert_path" "$latest_cert"
                    ;;
                2)
                    setup_apache_cert "$cert_path" "$latest_cert"
                    ;;
                3)
                    echo -e "${CYAN}证书位置:${NC}"
                    echo "证书文件: $cert_path/fullchain.pem"
                    echo "私钥文件: $cert_path/privkey.pem"
                    echo "请手动配置您的Web服务器使用这些证书"
                    ;;
            esac
        fi
    fi
}

# 设置Nginx证书
setup_nginx_cert() {
    local cert_path=$1
    local domain=$2
    
    echo -e "${YELLOW}配置Nginx使用SSL证书${NC}"
    
    # 检查Nginx是否安装
    if ! command -v nginx &> /dev/null; then
        echo -e "${RED}Nginx未安装${NC}"
        return 1
    fi
    
    # 询问是否创建新的server block
    echo -e "${CYAN}是否创建新的Nginx server block? (y/n): ${NC}"
    read -r create_new
    
    if [[ "$create_new" =~ ^[Yy]$ ]]; then
        local nginx_available="/etc/nginx/sites-available"
        local nginx_enabled="/etc/nginx/sites-enabled"
        
        # 创建SSL配置文件
        local config_file="$nginx_available/$domain-ssl"
        
        cat > "$config_file" << EOF
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $domain;
    
    ssl_certificate $cert_path/fullchain.pem;
    ssl_certificate_key $cert_path/privkey.pem;
    
    # SSL优化设置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    
    # 其他配置...
    root /var/www/html;
    index index.html index.htm;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
}

# HTTP重定向到HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name $domain;
    return 301 https://\$server_name\$request_uri;
}
EOF
        
        # 启用配置
        ln -sf "$config_file" "$nginx_enabled/"
        
        # 测试Nginx配置
        echo -e "${CYAN}测试Nginx配置...${NC}"
        if nginx -t; then
            echo -e "${GREEN}Nginx配置测试通过${NC}"
            echo -e "${CYAN}是否重启Nginx使配置生效? (y/n): ${NC}"
            read -r restart_nginx
            if [[ "$restart_nginx" =~ ^[Yy]$ ]]; then
                systemctl restart nginx
                echo -e "${GREEN}Nginx已重启，SSL证书已生效${NC}"
            fi
        else
            echo -e "${RED}Nginx配置测试失败，请检查配置文件${NC}"
        fi
        
    else
        echo -e "${CYAN}请手动编辑Nginx配置，添加以下内容:${NC}"
        echo ""
        echo "ssl_certificate $cert_path/fullchain.pem;"
        echo "ssl_certificate_key $cert_path/privkey.pem;"
        echo ""
    fi
}

# 错误排查
troubleshoot_failure() {
    echo -e "${YELLOW}=== 错误排查 ===${NC}"
    echo "1) 检查网络连接"
    echo "2) 检查DNS解析"
    echo "3) 检查端口开放情况"
    echo "4) 查看详细日志"
    echo "5) 尝试不同的验证方式"
    echo "0) 返回主菜单"
    
    read -rp "请选择排查项: " troubleshoot_choice
    
    case $troubleshoot_choice in
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
            echo -e "${CYAN}建议尝试DNS验证方式${NC}"
            ;;
        0)
            return
            ;;
    esac
}

# 检查网络连接
check_network_connectivity() {
    echo -e "${YELLOW}检查网络连接...${NC}"
    
    # 检查是否可访问Let's Encrypt
    if ping -c 3 acme-v02.api.letsencrypt.org &> /dev/null; then
        echo -e "${GREEN}✓ 可访问Let's Encrypt服务器${NC}"
    else
        echo -e "${RED}✗ 无法访问Let's Encrypt服务器${NC}"
    fi
    
    # 检查外部网络
    if curl -s --connect-timeout 10 https://www.google.com &> /dev/null; then
        echo -e "${GREEN}✓ 外部网络连接正常${NC}"
    else
        echo -e "${RED}✗ 外部网络连接异常${NC}"
    fi
}

# 续期管理
manage_renewals() {
    echo -e "${CYAN}=== 证书续期管理 ===${NC}"
    echo "1) 手动续期所有证书"
    echo "2) 测试续期（不实际执行）"
    echo "3) 查看即将过期的证书"
    echo "4) 设置续期通知"
    echo "0) 返回主菜单"
    
    read -rp "请选择: " renew_choice
    
    case $renew_choice in
        1)
            echo -e "${YELLOW}正在续期所有证书...${NC}"
            certbot renew --force-renewal
            ;;
        2)
            echo -e "${YELLOW}测试续期（干运行）...${NC}"
            certbot renew --dry-run
            ;;
        3)
            echo -e "${YELLOW}即将过期的证书:${NC}"
            certbot certificates | grep -E "(VALID|EXPIRED)"
            ;;
        4)
            setup_renewal_notifications
            ;;
        0)
            return
            ;;
    esac
}

# 证书吊销
revoke_certificate() {
    echo -e "${CYAN}=== 证书吊销 ===${NC}"
    
    # 列出所有证书
    echo -e "${YELLOW}现有证书:${NC}"
    certbot certificates
    
    read -rp "请输入要吊销的域名: " revoke_domain
    
    if [[ -n "$revoke_domain" ]]; then
        echo -e "${RED}警告: 吊销后将无法恢复！${NC}"
        read -rp "确定要吊销 $revoke_domain 的证书吗? (y/n): " confirm_revoke
        
        if [[ "$confirm_revoke" =~ ^[Yy]$ ]]; then
            certbot revoke --cert-name "$revoke_domain"
            
            # 询问是否删除证书文件
            echo -e "${CYAN}是否删除证书文件? (y/n): ${NC}"
            read -r delete_files
            if [[ "$delete_files" =~ ^[Yy]$ ]]; then
                certbot delete --cert-name "$revoke_domain"
            fi
        fi
    fi
}

# 批量操作
batch_operations() {
    echo -e "${CYAN}=== 批量操作 ===${NC}"
    echo "1) 批量申请证书（从文件读取域名）"
    echo "2) 批量续期证书"
    echo "3) 批量检查证书状态"
    echo "0) 返回主菜单"
    
    read -rp "请选择: " batch_choice
    
    case $batch_choice in
        1)
            batch_apply_certificates
            ;;
        2)
            batch_renew_certificates
            ;;
        3)
            batch_check_certificates
            ;;
        0)
            return
            ;;
    esac
}

# 批量申请证书
batch_apply_certificates() {
    echo -e "${YELLOW}批量申请证书${NC}"
    
    read -rp "请输入包含域名的文件路径（每行一个域名）: " domain_file
    
    if [[ ! -f "$domain_file" ]]; then
        echo -e "${RED}文件不存在${NC}"
        return 1
    fi
    
    # 选择验证方式
    echo -e "${CYAN}选择验证方式:${NC}"
    echo "1) DNS验证 (适用于批量)"
    echo "2) HTTP验证"
    
    read -rp "请选择: " batch_validation
    
    local success_count=0
    local fail_count=0
    
    while IFS= read -r domain || [[ -n "$domain" ]]; do
        domain=$(echo "$domain" | xargs)  # 去除空白字符
        
        if [[ -n "$domain" ]]; then
            echo -e "${CYAN}处理域名: $domain${NC}"
            
            if [[ "$batch_validation" == "1" ]]; then
                # DNS验证
                choose_dns_provider "$domain" "standard"
            else
                # HTTP验证
                http_validation "$domain"
            fi
            
            if [[ $? -eq 0 ]]; then
                ((success_count++))
            else
                ((fail_count++))
            fi
        fi
    done < "$domain_file"
    
    echo -e "${GREEN}批量处理完成${NC}"
    echo -e "成功: $success_count"
    echo -e "失败: $fail_count"
}

# 主菜单
main_menu() {
    while true; do
        show_banner
        
        echo -e "${GREEN}请选择操作:${NC}"
        echo "1) 申请新证书"
        echo "2) 管理续期"
        echo "3) 吊销证书"
        echo "4) 批量操作"
        echo "5) 配置DNS API"
        echo "6) 查看证书信息"
        echo "7) 系统检查"
        echo "8) 问题排查"
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
                batch_operations
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

# 系统状态检查
check_system_status() {
    echo -e "${CYAN}=== 系统状态检查 ===${NC}"
    
    # 检查certbot版本
    if certbot --version &> /dev/null; then
        echo -e "${GREEN}✓ Certbot已安装${NC}"
        certbot --version
    else
        echo -e "${RED}✗ Certbot未安装${NC}"
    fi
    
    # 检查证书目录
    local cert_count=$(ls /etc/letsencrypt/live 2>/dev/null | wc -l)
    echo -e "${YELLOW}现有证书数量: $cert_count${NC}"
    
    # 检查续期状态
    echo -e "${YELLOW}续期状态:${NC}"
    certbot renew --dry-run 2>&1 | tail -5
    
    # 检查端口占用
    echo -e "${YELLOW}端口占用情况:${NC}"
    for port in 80 443; do
        if lsof -i :$port &> /dev/null; then
            echo -e "端口 $port: ${RED}已占用${NC}"
            lsof -i :$port | grep LISTEN | head -1
        else
            echo -e "端口 $port: ${GREEN}空闲${NC}"
        fi
    done
}

# 问题排查菜单
troubleshoot_menu() {
    echo -e "${CYAN}=== 问题排查 ===${NC}"
    echo "1) 网络连接测试"
    echo "2) DNS解析测试"
    echo "3) 端口可用性测试"
    echo "4) 查看申请日志"
    echo "5) 重置脚本配置"
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
        0)
            return
            ;;
    esac
}

# 检查DNS解析
check_dns_resolution() {
    read -rp "请输入要检查的域名: " check_domain
    
    if [[ -n "$check_domain" ]]; then
        echo -e "${YELLOW}检查 $check_domain 的DNS解析...${NC}"
        
        # 检查A记录
        echo -e "${CYAN}A记录:${NC}"
        dig +short A "$check_domain"
        
        # 检查CAA记录（证书颁发机构授权）
        echo -e "${CYAN}CAA记录:${NC}"
        dig +short CAA "$check_domain"
        
        # 检查TXT记录
        echo -e "${CYAN}TXT记录:${NC}"
        dig +short TXT "$check_domain"
        
        # 检查_acme-challenge子域名
        echo -e "${CYAN}_acme-challenge记录:${NC}"
        dig +short TXT "_acme-challenge.$check_domain"
    fi
}

# 检查端口
check_ports() {
    read -rp "请输入要检查的域名或IP: " check_host
    read -rp "请输入端口号（默认80）: " check_port
    check_port=${check_port:-80}
    
    echo -e "${YELLOW}检查 $check_host:$check_port ...${NC}"
    
    if timeout 5 nc -z "$check_host" "$check_port"; then
        echo -e "${GREEN}✓ 端口 $check_port 可访问${NC}"
    else
        echo -e "${RED}✗ 端口 $check_port 不可访问${NC}"
        
        # 检查本地防火墙
        if command -v firewall-cmd &> /dev/null; then
            echo -e "${YELLOW}检查防火墙...${NC}"
            firewall-cmd --list-ports | grep "$check_port"
        fi
        
        # 检查SELinux
        if command -v getenforce &> /dev/null; then
            echo -e "${YELLOW}SELinux状态: $(getenforce)${NC}"
        fi
    fi
}

# 查看日志
view_logs() {
    echo -e "${CYAN}=== 日志查看 ===${NC}"
    echo "1) 查看今日日志"
    echo "2) 查看Certbot日志"
    echo "3) 查看系统日志"
    echo "4) 清除旧日志"
    
    read -rp "请选择: " log_choice
    
    case $log_choice in
        1)
            if [[ -f "$LOG_FILE" ]]; then
                less "$LOG_FILE"
            else
                echo -e "${YELLOW}今日暂无日志${NC}"
            fi
            ;;
        2)
            journalctl -u certbot -n 50 --no-pager
            ;;
        3)
            tail -50 /var/log/syslog | grep -i certbot
            ;;
        4)
            echo -e "${YELLOW}清除7天前的日志...${NC}"
            find "$LOG_DIR" -name "*.log" -mtime +7 -delete
            echo -e "${GREEN}日志清理完成${NC}"
            ;;
    esac
}

# 重置配置
reset_configuration() {
    echo -e "${RED}警告: 这将重置所有配置${NC}"
    read -rp "确定要重置吗? (y/n): " confirm_reset
    
    if [[ "$confirm_reset" =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        echo -e "${GREEN}配置已重置${NC}"
    fi
}

# 脚本入口
main() {
    # 检查是否是root用户
    if [[ $EUID -ne 0 ]]; then
        echo "错误：本脚本必须在root用户下运行！"
        echo "请先切换到root用户：sudo su -"
        echo "然后执行：bash $(basename $0)"
        exit 1
    fi
    
    # 检查依赖
    check_dependencies
    
    # 运行主菜单
    main_menu
}

# 捕获Ctrl+C
trap 'echo -e "\n${YELLOW}用户中断操作${NC}"; exit 1' INT

# 启动脚本
main
