#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# 打印彩色信息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

print_menu() {
    echo -e "${PURPLE}[MENU]${NC} $1"
}

# 全局变量
FINAL_CONFIG_NAME=""
PRIMARY_DOMAIN=""
domains=()
ip_mode=""
config_type=""
backend_port=""
web_root=""
SUBDOMAIN_CONFIGS=()
PATH_CONFIGS=()

# 检测系统信息
detect_system() {
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
        OS_NAME="$NAME"
        
        # 只支持 apt 和 apk
        if command -v apt-get &> /dev/null; then
            PKG_MANAGER="apt"
            PKG_INSTALL="apt-get install -y"
            PKG_UPDATE="apt-get update"
        elif command -v apk &> /dev/null; then
            PKG_MANAGER="apk"
            PKG_INSTALL="apk add"
            PKG_UPDATE="apk update"
        else
            print_error "只支持 apt (Debian/Ubuntu) 和 apk (Alpine) 系统"
            exit 1
        fi
        
        print_info "检测到系统: $OS_NAME"
        print_info "包管理器: $PKG_MANAGER"
    else
        print_error "无法检测操作系统"
        exit 1
    fi
}

# 检查并安装依赖
install_dependencies() {
    print_step "检查系统依赖..."
    
    detect_system
    
    # 定义软件包名称
    if [ "$PKG_MANAGER" = "apt" ]; then
        PKG_NGINX="nginx"
        PKG_CURL="curl"
    elif [ "$PKG_MANAGER" = "apk" ]; then
        PKG_NGINX="nginx"
        PKG_CURL="curl"
    fi
    
    # 更新包管理器
    print_info "更新包管理器缓存..."
    eval $PKG_UPDATE
    
    # 检查并安装必要软件
    local deps=("$PKG_NGINX" "$PKG_CURL")
    local to_install=()
    
    for dep in "${deps[@]}"; do
        if [ "$PKG_MANAGER" = "apk" ]; then
            if ! apk info -e "$dep" &> /dev/null; then
                to_install+=("$dep")
            fi
        else
            if ! command -v "$(basename "$dep")" &> /dev/null; then
                to_install+=("$dep")
            fi
        fi
    done
    
    if [ ${#to_install[@]} -ne 0 ]; then
        print_info "安装缺失的依赖: ${to_install[*]}"
        eval "$PKG_INSTALL ${to_install[*]}"
    else
        print_success "所有依赖已安装"
    fi
    
    # 检查并安装acme.sh（如果需要）
    if [ ! -f "/root/.acme.sh/acme.sh" ]; then
        print_info "安装 acme.sh..."
        curl https://woskee.ae.kg/https://raw.githubusercontent.com/acmesh-official/acme.sh/master/acme.sh | sh -s
        print_success "acme.sh 安装完成"
    else
        print_success "acme.sh 已安装，跳过安装"
    fi
}

# 获取用户输入
get_user_input() {
    print_step "获取配置信息"
    
    # 获取域名
    while true; do
        echo
        print_info "请输入域名（多个域名用空格分隔，第一个为主域名）:"
        read -r domain_input
        
        if [ -z "$domain_input" ]; then
            print_error "域名不能为空，请重新输入"
            continue
        fi
        
        # 将输入的域名转换为数组
        IFS=' ' read -ra domains <<< "$domain_input"
        
        # 验证域名格式
        local valid=true
        for domain in "${domains[@]}"; do
            if ! [[ $domain =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                print_error "域名格式不正确: $domain"
                valid=false
                break
            fi
        done
        
        if [ "$valid" = true ]; then
            PRIMARY_DOMAIN="${domains[0]}"
            break
        fi
    done
    
    echo
    print_success "主域名: $PRIMARY_DOMAIN"
    if [ ${#domains[@]} -gt 1 ]; then
        print_info "其他域名: ${domains[@]:1}"
    fi
    
    # 获取正式配置文件名称
    echo
    print_info "请输入正式配置文件名（不含.conf后缀，默认使用主域名）:"
    read -r config_name_input
    if [ -z "$config_name_input" ]; then
        FINAL_CONFIG_NAME="${PRIMARY_DOMAIN}.conf"
    else
        FINAL_CONFIG_NAME="${config_name_input}.conf"
    fi
    print_success "正式配置文件: $FINAL_CONFIG_NAME"
    
    # 选择IP版本
    echo
    print_info "请选择使用的网络协议:"
    echo "1) IPv4 (默认)"
    echo "2) IPv6"
    while true; do
        read -p "请选择 (1/2): " ip_choice
        ip_choice=${ip_choice:-1}
        case $ip_choice in
            1) ip_mode="ipv4"; break ;;
            2) ip_mode="ipv6"; break ;;
            *) print_error "无效选择，请重新输入" ;;
        esac
    done
    
    print_success "使用 $ip_mode 协议"
    
    # 选择配置类型
    echo
    print_info "请选择Nginx配置类型:"
    echo "1) 仅申请证书（测试用）"
    echo "2) 静态文件服务"
    echo "3) 反向代理后端服务（默认）"
    while true; do
        read -p "请选择 (1/2/3): " config_choice
        config_choice=${config_choice:-3}
        case $config_choice in
            1) config_type="cert_only"; break ;;
            2) config_type="static"; break ;;
            3) config_type="proxy"; break ;;
            *) print_error "无效选择，请重新输入" ;;
        esac
    done
    
    if [ "$config_type" = "proxy" ]; then
        print_success "配置类型: 反向代理"
    elif [ "$config_type" = "static" ]; then
        print_success "配置类型: 静态文件"
    else
        print_success "配置类型: 仅申请证书"
    fi
    
    # 如果是反向代理，获取后端端口
    if [ "$config_type" = "proxy" ]; then
        while true; do
            echo
            print_info "请输入后端服务端口（必须输入）:"
            read -r backend_port
            
            if [ -z "$backend_port" ]; then
                print_error "端口号不能为空"
                continue
            fi
            
            if [[ $backend_port =~ ^[0-9]+$ ]] && [ $backend_port -gt 0 ] && [ $backend_port -lt 65536 ]; then
                print_success "后端端口: $backend_port"
                break
            else
                print_error "端口号必须是1-65535之间的数字"
            fi
        done
    fi
    
    # 如果是静态文件，获取网站目录
    if [ "$config_type" = "static" ]; then
        read -p "请输入网站根目录 (默认: /var/www/html): " web_root
        web_root=${web_root:-/var/www/html}
        print_success "网站根目录: $web_root"
    fi
}

# 创建acme-challenge目录
create_acme_challenge_dir() {
    print_step "准备证书验证目录"
    
    local acme_dir="/var/www/acme-challenge"
    
    mkdir -p "$acme_dir/.well-known/acme-challenge"
    
    # 设置权限
    chmod -R 755 "$acme_dir"
    
    # 尝试设置正确的用户
    if id -u www-data &> /dev/null; then
        chown -R www-data:www-data "$acme_dir"
    elif id -u nginx &> /dev/null; then
        chown -R nginx:nginx "$acme_dir"
    fi
    
    print_success "证书验证目录: $acme_dir/.well-known/acme-challenge"
}

# 生成初始Nginx配置（用于证书申请阶段）
generate_initial_config() {
    print_step "生成Nginx配置（证书申请阶段）"
    
    # 根据IP模式设置监听配置
    local listen_80=""
    local listen_443=""
    
    if [ "$ip_mode" = "ipv6" ]; then
        listen_80="listen [::]:80;"
        listen_443="listen [::]:443;"
    else
        listen_80="listen 80;"
        listen_443="listen 443;"
    fi
    
    # 构建server_names
    local server_names=""
    for domain in "${domains[@]}"; do
        server_names="$server_names $domain"
    done
    
    # 配置路径
    local config_path="/etc/nginx/conf.d/$FINAL_CONFIG_NAME"
    
    # 生成一个单独的server块用于证书验证
    cat > "$config_path" << EOF
# 阶段1: 证书申请阶段配置
# 生成时间: $(date)
# 域名:$server_names

# 证书验证专用server块
server {
    $listen_80
    server_name$server_names;
    
    location /.well-known/acme-challenge/ {
        root /var/www/acme-challenge;
    }
    
    location / {
        return 200 "Domain verification in progress for:$server_names";
        add_header Content-Type text/plain;
    }
}

server {
    $listen_443
    server_name$server_names;
    
    location / {
        return 404;
    }
}
EOF
    
    print_success "生成证书申请阶段配置"
    
    # 测试并重载Nginx配置
    if nginx -t; then
        systemctl reload nginx
        print_success "Nginx配置已应用"
    else
        print_error "Nginx配置测试失败"
        exit 1
    fi
}

# 申请证书 - 修正：申请多域名证书
issue_certificate() {
    print_step "申请SSL证书"
    
    # 构建域名参数
    local domain_args=""
    for domain in "${domains[@]}"; do
        domain_args="$domain_args -d $domain"
    done
    
    echo
    print_info "正在申请证书，请稍候..."
    print_info "申请多域名证书，包含: ${domains[*]}"
    
    # 根据IP模式选择申请参数
    local acme_args=""
    if [ "$ip_mode" = "ipv6" ]; then
        acme_args="--listen-v6"
    fi
    
    # 申请多域名证书
    if /root/.acme.sh/acme.sh --issue \
        $domain_args \
        --webroot /var/www/acme-challenge \
        $acme_args \
        --server letsencrypt \
        --keylength ec-256 \
        --force; then
        
        print_success "证书申请成功！"
        
        # 获取证书目录
        CERT_DIR="/root/.acme.sh/${PRIMARY_DOMAIN}_ecc"
        if [ -d "$CERT_DIR" ]; then
            print_info "证书目录: $CERT_DIR"
            print_info "证书文件: $CERT_DIR/fullchain.cer"
            print_info "私钥文件: $CERT_DIR/$PRIMARY_DOMAIN.key"
            
            # 验证证书包含的所有域名
            echo
            print_info "验证证书包含的域名:"
            local cert_file="$CERT_DIR/fullchain.cer"
            if [ -f "$cert_file" ]; then
                # 使用openssl查看证书的SAN字段
                local san_domains=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | \
                    grep -A1 "Subject Alternative Name" | tail -n1 | \
                    sed 's/DNS://g' | sed 's/, /\n/g' | sed 's/^[[:space:]]*//')
                
                if [ -n "$san_domains" ]; then
                    echo "$san_domains" | while read domain; do
                        echo "  ✓ $domain"
                    done
                    
                    # 检查是否所有域名都在证书中
                    for domain in "${domains[@]}"; do
                        if echo "$san_domains" | grep -q "^$domain$"; then
                            print_success "域名 $domain 在证书中"
                        else
                            print_error "域名 $domain 不在证书中！"
                        fi
                    done
                else
                    print_warning "无法读取证书的SAN字段"
                    print_warning "这可能是单域名证书，只包含主域名"
                fi
            fi
        fi
    else
        print_error "证书申请失败"
        exit 1
    fi
}

# 添加额外配置的交互界面
add_additional_configs() {
    print_step "添加额外配置"
    
    while true; do
        echo
        print_menu "是否要为主域名添加额外配置？"
        echo "1) 不添加，完成配置"
        echo "2) 通过子域名添加配置"
        echo "3) 通过路径添加配置"
        read -p "请选择 (1/2/3): " add_choice
        
        case $add_choice in
            1)
                print_success "跳过额外配置"
                break
                ;;
            2)
                add_subdomain_config
                ;;
            3)
                add_path_config
                ;;
            *)
                print_error "无效选择"
                continue
                ;;
        esac
        
        echo
        print_menu "是否继续添加更多配置？"
        echo "1) 继续添加"
        echo "2) 完成配置"
        read -p "请选择 (1/2): " continue_choice
        
        if [ "$continue_choice" != "1" ]; then
            break
        fi
    done
}

# 添加子域名配置
add_subdomain_config() {
    echo
    print_info "添加子域名配置"
    
    # 获取子域名
    while true; do
        print_info "请输入子域名前缀（如: api, admin, app 等）:"
        read -r sub_prefix
        
        if [ -z "$sub_prefix" ]; then
            print_error "子域名前缀不能为空"
            continue
        fi
        
        if [[ $sub_prefix =~ ^[a-zA-Z0-9-]+$ ]]; then
            subdomain="$sub_prefix.$PRIMARY_DOMAIN"
            print_success "子域名: $subdomain"
            break
        else
            print_error "子域名前缀只能包含字母、数字和连字符"
        fi
    done
    
    # 选择配置类型
    echo
    print_info "请选择子域名配置类型:"
    echo "1) 反向代理到后端服务"
    echo "2) 静态文件服务"
    while true; do
        read -p "请选择 (1/2): " sub_type_choice
        case $sub_type_choice in
            1) sub_type="proxy"; break ;;
            2) sub_type="static"; break ;;
            *) print_error "无效选择" ;;
        esac
    done
    
    local sub_port=""
    local sub_root=""
    
    if [ "$sub_type" = "proxy" ]; then
        while true; do
            echo
            print_info "请输入后端服务端口:"
            read -r sub_port
            
            if [ -z "$sub_port" ]; then
                print_error "端口号不能为空"
                continue
            fi
            
            if [[ $sub_port =~ ^[0-9]+$ ]] && [ $sub_port -gt 0 ] && [ $sub_port -lt 65536 ]; then
                print_success "后端端口: $sub_port"
                break
            else
                print_error "端口号必须是1-65535之间的数字"
            fi
        done
    else
        read -p "请输入网站根目录 (默认: /var/www/$sub_prefix): " sub_root
        sub_root=${sub_root:-/var/www/$sub_prefix}
        print_success "网站根目录: $sub_root"
    fi
    
    # 保存配置
    SUBDOMAIN_CONFIGS+=("$subdomain|$sub_type|$sub_port|$sub_root")
    print_success "子域名配置已保存: $subdomain ($sub_type)"
}

# 添加路径配置
add_path_config() {
    echo
    print_info "添加路径配置"
    
    # 获取路径
    while true; do
        print_info "请输入路径前缀（如: /api/, /admin/, /app/ 等）:"
        read -r path_prefix
        
        if [ -z "$path_prefix" ]; then
            print_error "路径前缀不能为空"
            continue
        fi
        
        # 确保路径以/开头
        if [[ $path_prefix != /* ]]; then
            path_prefix="/$path_prefix"
        fi
        
        # 确保路径以/结尾（对于路径配置很重要）
        if [[ $path_prefix != */ ]]; then
            path_prefix="$path_prefix/"
        fi
        
        print_success "路径: $path_prefix"
        break
    done
    
    # 选择配置类型
    echo
    print_info "请选择路径配置类型:"
    echo "1) 反向代理到后端服务"
    echo "2) 静态文件服务"
    while true; do
        read -p "请选择 (1/2): " path_type_choice
        case $path_type_choice in
            1) path_type="proxy"; break ;;
            2) path_type="static"; break ;;
            *) print_error "无效选择" ;;
        esac
    done
    
    local path_port=""
    local path_root=""
    
    if [ "$path_type" = "proxy" ]; then
        while true; do
            echo
            print_info "请输入后端服务端口:"
            read -r path_port
            
            if [ -z "$path_port" ]; then
                print_error "端口号不能为空"
                continue
            fi
            
            if [[ $path_port =~ ^[0-9]+$ ]] && [ $path_port -gt 0 ] && [ $path_port -lt 65536 ]; then
                print_success "后端端口: $path_port"
                break
            else
                print_error "端口号必须是1-65535之间的数字"
            fi
        done
    else
        read -p "请输入网站根目录 (默认: /var/www$(echo $path_prefix | sed 's|/$||')): " path_root
        path_root=${path_root:-/var/www$(echo $path_prefix | sed 's|/$||')}
        print_success "网站根目录: $path_root"
    fi
    
    # 保存配置
    PATH_CONFIGS+=("$path_prefix|$path_type|$path_port|$path_root")
    print_success "路径配置已保存: $path_prefix ($path_type)"
}

# 生成路径配置块
generate_path_config_blocks() {
    local config_blocks=""
    
    for path_config in "${PATH_CONFIGS[@]}"; do
        IFS='|' read -r path_prefix path_type path_port path_root <<< "$path_config"
        
        if [ "$path_type" = "proxy" ]; then
            config_blocks+="
    # $path_prefix 路径反向代理
    location $path_prefix {
        proxy_pass http://127.0.0.1:$path_port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # 可选：添加WebSocket支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \"upgrade\";
    }"
        else
            config_blocks+="
    # $path_prefix 路径静态文件
    location $path_prefix {
        root $path_root;
        index index.html index.htm;
        try_files \$uri \$uri/ =404;
    }"
        fi
    done
    
    echo "$config_blocks"
}

# 更新Nginx配置（添加SSL证书和重定向，以及额外配置）
update_final_config() {
    print_step "更新Nginx配置（添加SSL证书和额外配置）"
    
    # 获取证书目录
    local cert_dir="/root/.acme.sh/${PRIMARY_DOMAIN}_ecc"
    if [ ! -d "$cert_dir" ]; then
        print_error "证书目录不存在: $cert_dir"
        exit 1
    fi
    
    # 检查证书文件
    local cert_file="$cert_dir/fullchain.cer"
    local key_file="$cert_dir/$PRIMARY_DOMAIN.key"
    
    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
        print_error "证书文件不存在"
        exit 1
    fi
    
    # 根据IP模式设置监听配置
    local listen_80=""
    local listen_443=""
    
    if [ "$ip_mode" = "ipv6" ]; then
        listen_80="listen [::]:80;"
        listen_443="listen [::]:443 ssl;"
    else
        listen_80="listen 80;"
        listen_443="listen 443 ssl;"
    fi
    
    # 构建server_names
    local server_names=""
    for domain in "${domains[@]}"; do
        server_names="$server_names $domain"
    done
    
    # 配置路径
    local config_path="/etc/nginx/conf.d/$FINAL_CONFIG_NAME"
    
    # 生成路径配置块
    local path_config_blocks=$(generate_path_config_blocks)
    
    # 生成主配置
    cat > "$config_path" << EOF
# 最终SSL配置
# 生成时间: $(date)
# 域名:$server_names
# IP模式: $ip_mode

# 80端口重定向服务器
server {
    $listen_80
    server_name$server_names;
    
    location /.well-known/acme-challenge/ {
        root /var/www/acme-challenge;
    }
    
    # 重定向所有HTTP请求到HTTPS
    location / {
        return 301 https://\$host\$request_uri;
    }
}

# 主HTTPS服务器 - $PRIMARY_DOMAIN
server {
    $listen_443
    server_name$server_names;
    
    # SSL证书配置
    ssl_certificate $cert_file;
    ssl_certificate_key $key_file;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    
    # SSL会话配置
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    
    # 证书验证路径
    location /.well-known/acme-challenge/ {
        root /var/www/acme-challenge;
    }
    
    # 安全响应头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
EOF
    
    # 添加主配置内容
    if [ "$config_type" = "proxy" ]; then
        cat >> "$config_path" << EOF
    # 主域名反向代理
    location / {
        proxy_pass http://127.0.0.1:$backend_port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # 可选：添加WebSocket支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # 可选：增加超时时间
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
EOF
    elif [ "$config_type" = "static" ]; then
        cat >> "$config_path" << EOF
    # 主域名静态文件服务
    root $web_root;
    index index.html index.htm;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
EOF
    else
        cat >> "$config_path" << EOF
    # 证书测试模式
    location / {
        return 200 "SSL Certificate is working for all domains!";
        add_header Content-Type text/plain;
    }
EOF
    fi
    
    # 添加路径配置
    if [ -n "$path_config_blocks" ]; then
        cat >> "$config_path" << EOF
    # 路径配置$path_config_blocks
EOF
    fi
    
    # 结束主服务器配置
    cat >> "$config_path" << EOF
}

EOF
    
    # 添加子域名服务器配置
    for sub_config in "${SUBDOMAIN_CONFIGS[@]}"; do
        IFS='|' read -r subdomain sub_type sub_port sub_root <<< "$sub_config"
        
        # 构建子域名server_names
        local sub_server_names="$subdomain"
        for domain in "${domains[@]:1}"; do
            # 为其他域名也添加相应的子域名
            if [[ $domain == *"$PRIMARY_DOMAIN" ]]; then
                sub_domain_part=$(echo "$domain" | sed "s/$PRIMARY_DOMAIN\$//" | sed 's/\.$//')
                if [ -n "$sub_domain_part" ]; then
                    sub_server_names="$sub_server_names $sub_domain_part.$subdomain"
                fi
            fi
        done
        
        cat >> "$config_path" << EOF
# 子域名服务器 - $subdomain
server {
    $listen_443
    server_name $sub_server_names;
    
    # SSL证书配置（使用主域名的通配符证书）
    ssl_certificate $cert_file;
    ssl_certificate_key $key_file;
    ssl_protocols TLSv1.2 TLSv1.3;
    
    # 证书验证路径
    location /.well-known/acme-challenge/ {
        root /var/www/acme-challenge;
    }
    
EOF
        
        if [ "$sub_type" = "proxy" ]; then
            cat >> "$config_path" << EOF
    # 子域名反向代理
    location / {
        proxy_pass http://127.0.0.1:$sub_port;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        else
            cat >> "$config_path" << EOF
    # 子域名静态文件服务
    root $sub_root;
    index index.html index.htm;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
        fi
        
        echo >> "$config_path"
    done
    
    print_success "更新最终配置，包含主域名和额外配置"
    
    # 测试并重载Nginx配置
    if nginx -t; then
        systemctl reload nginx
        print_success "Nginx最终配置已应用"
    else
        print_error "Nginx配置测试失败"
        exit 1
    fi
}

# 设置自动续期
setup_auto_renew() {
    print_step "设置证书自动续期"
    
    # 根据IP模式设置参数
    local acme_args=""
    if [ "$ip_mode" = "ipv6" ]; then
        acme_args="--listen-v6"
    fi
    
    # 设置定时任务（每天凌晨2点检查续期）
    local cron_cmd="0 2 * * * /root/.acme.sh/acme.sh --cron $acme_args >> /var/log/acme.sh.log 2>&1"
    
    # 清理旧的定时任务（如果存在）
    (crontab -l 2>/dev/null | grep -v "acme.sh --cron") | crontab -
    
    # 添加新的定时任务
    echo "$cron_cmd" | crontab -
    
    print_success "自动续期已设置"
    print_info "执行时间: 每天凌晨2点"
    
    if [ "$ip_mode" = "ipv6" ]; then
        print_info "使用IPv6网络进行续期"
    fi
}

# 显示总结信息
show_summary() {
    print_step "部署完成"
    echo
    echo -e "${GREEN}══════════════════════════════════════════════${NC}"
    echo -e "${GREEN}             SSL证书部署完成                  ${NC}"
    echo -e "${GREEN}══════════════════════════════════════════════${NC}"
    echo
    echo -e "${CYAN}部署信息:${NC}"
    echo "主域名:     $PRIMARY_DOMAIN"
    [ ${#domains[@]} -gt 1 ] && echo "其他域名:   ${domains[@]:1}"
    echo "IP模式:     $ip_mode"
    echo "配置类型:   $config_type"
    
    if [ "$config_type" = "proxy" ]; then
        echo "后端端口:   $backend_port"
    elif [ "$config_type" = "static" ]; then
        echo "网站目录:   $web_root"
    fi
    
    # 显示路径配置
    if [ ${#PATH_CONFIGS[@]} -gt 0 ]; then
        echo
        echo -e "${CYAN}路径配置:${NC}"
        for path_config in "${PATH_CONFIGS[@]}"; do
            IFS='|' read -r path_prefix path_type path_port path_root <<< "$path_config"
            echo "路径: $path_prefix ($path_type)"
            if [ "$path_type" = "proxy" ]; then
                echo "后端端口: $path_port"
            else
                echo "网站目录: $path_root"
            fi
        done
    fi
    
    # 显示子域名配置
    if [ ${#SUBDOMAIN_CONFIGS[@]} -gt 0 ]; then
        echo
        echo -e "${CYAN}子域名配置:${NC}"
        for sub_config in "${SUBDOMAIN_CONFIGS[@]}"; do
            IFS='|' read -r subdomain sub_type sub_port sub_root <<< "$sub_config"
            echo "子域名: $subdomain ($sub_type)"
            if [ "$sub_type" = "proxy" ]; then
                echo "后端端口: $sub_port"
            else
                echo "网站目录: $sub_root"
            fi
        done
    fi
    
    echo
    echo -e "${CYAN}证书信息:${NC}"
    echo "证书目录:   /root/.acme.sh/${PRIMARY_DOMAIN}_ecc"
    
    echo
    echo -e "${CYAN}配置文件:${NC}"
    echo "/etc/nginx/conf.d/$FINAL_CONFIG_NAME"
    
    echo
    echo -e "${CYAN}测试命令:${NC}"
    for domain in "${domains[@]}"; do
        echo "测试 $domain: curl -I https://$domain"
    done
    
    for sub_config in "${SUBDOMAIN_CONFIGS[@]}"; do
        IFS='|' read -r subdomain sub_type sub_port sub_root <<< "$sub_config"
        echo "测试 $subdomain: curl -I https://$subdomain"
    done
    
    echo
    echo -e "${CYAN}路径访问:${NC}"
    for path_config in "${PATH_CONFIGS[@]}"; do
        IFS='|' read -r path_prefix path_type path_port path_root <<< "$path_config"
        echo "访问 $path_prefix: https://$PRIMARY_DOMAIN$path_prefix"
    done
    
    echo
    echo -e "${GREEN}完成！请测试所有域名和路径:${NC}"
    for domain in "${domains[@]}"; do
        echo "https://$domain"
    done
    
    for sub_config in "${SUBDOMAIN_CONFIGS[@]}"; do
        IFS='|' read -r subdomain sub_type sub_port sub_root <<< "$sub_config"
        echo "https://$subdomain"
    done
    
    for path_config in "${PATH_CONFIGS[@]}"; do
        IFS='|' read -r path_prefix path_type path_port path_root <<< "$path_config"
        echo "https://$PRIMARY_DOMAIN$path_prefix"
    done
    echo
}

# 主函数
main() {
    clear
    echo -e "${CYAN}"
    echo "══════════════════════════════════════════════"
    echo "         SSL证书自动部署脚本"
    echo "    支持多域名、子域名、路径配置"
    echo "══════════════════════════════════════════════"
    echo -e "${NC}"

    # 检查root权限
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用root权限运行"
        exit 1
    fi

    # 执行步骤
    install_dependencies

    # 检查是否通过命令行参数传入了域名
    if [ $# -gt 0 ]; then
        # 使用命令行参数作为主域名
        PRIMARY_DOMAIN="$1"
        domains=("$PRIMARY_DOMAIN")

        # 如果提供了第二个参数，作为其他域名
        if [ $# -gt 1 ]; then
            shift
            for arg in "$@"; do
                domains+=("$arg")
            done
        fi

        print_success "使用命令行参数的域名: ${domains[*]}"
    else
        # 交互式获取用户输入
        get_user_input
    fi

    create_acme_challenge_dir
    
    # 第一阶段：生成初始配置（无301重定向）
    generate_initial_config
    
    # 第二阶段：申请证书
    issue_certificate
    
    # 添加额外配置的交互界面
    add_additional_configs
    
    # 第三阶段：更新配置（添加SSL证书和301重定向）
    update_final_config
    
    # 设置自动续期
    setup_auto_renew
    
    # 显示总结
    show_summary
}

# 运行主函数
main "$@"
