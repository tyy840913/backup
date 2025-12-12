#!/bin/bash

# ==========================================
# Web服务器配置生成器 (v2.1 IPv6 & 智能补全版)
# ==========================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_color() {
    echo -e "${2}${1}${NC}"
}

# 显示标题
print_title() {
    echo "========================================"
    echo "    Web服务器配置生成器 (v2.1)"
    echo "========================================"
    echo ""
}

# 显示菜单
show_menu() {
    print_title
    echo "请选择要生成的服务器配置:"
    echo "1. Nginx"
    echo "2. Caddy"
    echo "3. 退出"
    echo ""
}

# 输入验证函数
validate_port() {
    local port=$1
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    return 0
}

# 验证IP地址格式
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}

# 验证域名格式
validate_domain() {
    local domain=$1
    # 简单的域名验证正则
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

# 获取Web服务配置
get_web_config() {
    # === 初始化变量 ===
    http_port=""
    https_port=""
    server_names=""
    root_path=""
    ssl_cert=""
    ssl_key=""
    enable_301_redirect=false
    is_standard=false
    need_497=false
    enable_hsts=false
    enable_ocsp=false
    strong_security=false
    enable_gzip=false
    enable_static_cache=false
    enable_proxy=false
    proxy_set_host=false
    backend_url=""
    proxy_path="/"
    # =================
    
    echo ""
    print_color "=== Web服务基本配置 ===" "$BLUE"
    
    # 端口模式选择
    while true; do
        echo ""
        echo "请选择端口配置模式:"
        echo "1. 标准端口 (80/443，自动HTTP到HTTPS重定向)"
        echo "2. 自定义端口"
        read -p "请选择 [1-2]: " port_mode
        
        case $port_mode in
            1)
                http_port=80
                https_port=443
                enable_301_redirect=true
                is_standard=true
                break
                ;;
            2)
                is_standard=false
                while true; do
                    read -p "请输入监听端口: " custom_port
                    if validate_port "$custom_port"; then
                        break
                    else
                        print_color "错误: 端口号必须是1-65535之间的数字" "$RED"
                    fi
                done
                
                echo ""
                read -p "是否启用HTTPS (SSL)? [Y/n]: " enable_ssl
                enable_ssl=${enable_ssl:-y}
                if [[ ! "$enable_ssl" =~ ^[Nn] ]]; then
                    http_port=""
                    https_port=$custom_port
                    enable_301_redirect=false
                    
                    if [ "$https_port" -ne 443 ]; then
                        need_497=true
                    else
                        need_497=false
                    fi
                else
                    http_port=$custom_port
                    https_port=""
                    enable_301_redirect=false
                fi
                break
                ;;
            *)
                print_color "无效选择，请重试" "$RED"
                ;;
        esac
    done
    
    # 获取域名
    echo ""
    read -p "请输入域名 (多个域名用空格分隔，留空为localhost): " server_names
    if [ -z "$server_names" ]; then
        server_names="localhost"
    fi
    
    # 获取根目录
    echo ""
    read -p "请输入网站根目录 (默认: /var/www/html): " root_path
    if [ -z "$root_path" ]; then
        root_path="/var/www/html"
    fi
    
    # SSL配置
    if [ -n "$https_port" ]; then
        echo ""
        print_color "=== SSL证书配置 ===" "$BLUE"
        read -p "SSL证书路径 (默认: /etc/ssl/certs/ssl-cert-snakeoil.pem): " ssl_cert
        if [ -z "$ssl_cert" ]; then
            ssl_cert="/etc/ssl/certs/ssl-cert-snakeoil.pem"
        fi
        
        read -p "SSL私钥路径 (默认: /etc/ssl/private/ssl-cert-snakeoil.key): " ssl_key
        if [ -z "$ssl_key" ]; then
            ssl_key="/etc/ssl/private/ssl-cert-snakeoil.key"
        fi
        
        echo ""
        print_color "=== 安全加固配置 ===" "$BLUE"
        read -e -p "是否应用推荐的安全配置(HSTS/OCSP/TLS1.2+)? [Y/n]: " enable_security
        enable_security=${enable_security:-y}
        if [[ ! "$enable_security" =~ ^[Nn] ]]; then
            enable_hsts=true
            enable_ocsp=true
            strong_security=true
        else
            enable_hsts=false
            enable_ocsp=false
            strong_security=false
        fi
    fi
    
    # 性能优化配置
    echo ""
    print_color "=== 性能优化配置 ===" "$BLUE"
    read -e -p "是否应用性能优化（Gzip、缓存头）? [Y/n]: " enable_perf
    enable_perf=${enable_perf:-y}
    if [[ ! "$enable_perf" =~ ^[Nn] ]]; then
        enable_gzip=true
        enable_static_cache=true
    else
        enable_gzip=false
        enable_static_cache=false
    fi
    
    # 反向代理配置
    echo ""
    print_color "=== 反向代理配置 ===" "$BLUE"
    read -e -p "是否需要配置反向代理? [Y/n]: " need_proxy
    need_proxy=${need_proxy:-y}
    if [[ ! "$need_proxy" =~ ^[Nn] ]]; then
        enable_proxy=true
    
        while true; do
            echo "请输入后端服务地址"
            echo "支持格式:"
            echo "  - 仅端口: 8080 (自动补全为 http://127.0.0.1:8080)"
            echo "  - IP+端口: 10.0.0.5:3000"
            echo "  - 域名+端口: backend.local:8080"
            read -p "地址: " backend_input
            
            if [ -z "$backend_input" ]; then
                print_color "错误: 地址不能为空" "$RED"
                continue
            fi

            # 1. 剥离协议头
            backend_input=${backend_input#http://}
            backend_input=${backend_input#https://}
            
            # === [新增] 仅端口自动补全逻辑 ===
            if [[ "$backend_input" =~ ^[0-9]+$ ]]; then
                # 如果输入全是数字，且在有效端口范围内
                if validate_port "$backend_input"; then
                    backend_host="127.0.0.1"
                    backend_port="$backend_input"
                    backend_url="http://${backend_host}:${backend_port}"
                    print_color "检测到纯端口输入，自动补全为: $backend_url" "$YELLOW"
                    break
                else
                    print_color "错误: 端口无效 (必须在 1-65535 之间)" "$RED"
                    continue
                fi
            # ===============================

            # 2. 常规 Host:Port 解析
            elif [[ $backend_input =~ :[0-9]+$ ]]; then
                backend_host=$(echo "$backend_input" | cut -d: -f1)
                backend_port=$(echo "$backend_input" | cut -d: -f2)
            else
                backend_host="$backend_input"
                backend_port="80"
            fi
            
            # 3. 验证与协议选择
            if validate_ip "$backend_host"; then
                backend_url="http://${backend_host}:${backend_port}"
                print_color "检测到IP地址，使用HTTP协议: $backend_url" "$YELLOW"
                break
            elif validate_domain "$backend_host" || [ "$backend_host" == "localhost" ]; then
                echo "检测到域名，请选择后端协议:"
                echo "1. HTTP (默认)"
                echo "2. HTTPS"
                read -p "请选择 [1-2]: " protocol_choice
                protocol_choice=${protocol_choice:-1}

                case $protocol_choice in
                    2) backend_url="https://${backend_host}:${backend_port}" ;;
                    *) backend_url="http://${backend_host}:${backend_port}" ;;
                esac
                break
            else
                print_color "错误: 格式无效，请输入有效的 IP、域名或纯端口号" "$RED"
            fi
        done
        
        read -p "请输入代理路径 (例如: /api/, 留空为 /): " proxy_path
        if [ -z "$proxy_path" ]; then
            proxy_path="/"
        fi
        
        read -e -p "是否传递Host头? (推荐开启) [Y/n]: " pass_host
        pass_host=${pass_host:-y}
        if [[ ! "$pass_host" =~ ^[Nn] ]]; then
            proxy_set_host=true
        else
            proxy_set_host=false
        fi
    else
        enable_proxy=false
        backend_url=""
        proxy_path="/"
        proxy_set_host=false
    fi
}

# 自动复制Nginx配置文件
copy_nginx_config() {
    local config_file=$1
    echo ""
    print_color "=== Nginx配置安装 ===" "$BLUE"
    read -e -p "是否将配置文件复制到Nginx目录并启用? [Y/n]: " install_choice
    install_choice=${install_choice:-y}
    if [[ ! "$install_choice" =~ ^[Nn] ]]; then
        if [ -d "/etc/nginx/sites-available" ] && [ -d "/etc/nginx/sites-enabled" ]; then
            sudo cp "$config_file" "/etc/nginx/sites-available/"
            sudo ln -sf "/etc/nginx/sites-available/$config_file" "/etc/nginx/sites-enabled/"
            print_color "测试Nginx配置..." "$YELLOW"
            if sudo nginx -t; then
                print_color "配置测试成功！" "$GREEN"
                read -e -p "是否立即重载Nginx配置? [Y/n]: " reload_choice  
                reload_choice=${reload_choice:-y}
                if [[ ! "$reload_choice" =~ ^[Nn] ]]; then
                    sudo systemctl reload nginx
                    print_color "Nginx配置已重载！" "$GREEN"
                fi
            else
                print_color "配置测试失败，已自动清理！" "$RED"
                sudo rm -f "/etc/nginx/sites-enabled/$config_file"
                sudo rm -f "/etc/nginx/sites-available/$config_file"
            fi
        else
            print_color "错误: Nginx目录不存在" "$RED"
        fi
    fi
}

# 生成Nginx配置
generate_nginx_config() {
    config_file="nginx_${server_names%% *}_$(date +%Y%m%d_%H%M%S).conf"
    
    echo "# Nginx配置文件 - 生成于 $(date)" > "$config_file"
    echo "# 域名: $server_names" >> "$config_file"
    echo "" >> "$config_file"
    
    # HTTP重定向块
    if [ -n "$http_port" ] && [ "$enable_301_redirect" = true ] && [ -n "$https_port" ]; then
        echo "server {" >> "$config_file"
        echo "    listen $http_port;" >> "$config_file"
        echo "    listen [::]:$http_port;" >> "$config_file" # === [新增] IPv6 监听 ===
        echo "    server_name $server_names;" >> "$config_file"
        echo "    return 301 https://\$host\$request_uri;" >> "$config_file"
        echo "}" >> "$config_file"
        echo "" >> "$config_file"
    fi
    
    # 主server块
    if [ -n "$https_port" ]; then
        echo "server {" >> "$config_file"
        # 兼容性写法，同时支持 IPv4 和 IPv6
        echo "    listen ${https_port} ssl http2;" >> "$config_file"
        echo "    listen [::]:${https_port} ssl http2;" >> "$config_file" # === [新增] IPv6 监听 ===
        
        if [ "$need_497" = true ]; then
            echo "    error_page 497 https://\$host:${https_port}\$request_uri;" >> "$config_file"
        fi
    elif [ -n "$http_port" ]; then
        echo "server {" >> "$config_file"
        echo "    listen $http_port;" >> "$config_file"
        echo "    listen [::]:$http_port;" >> "$config_file" # === [新增] IPv6 监听 ===
    fi
    
    echo "    server_name $server_names;" >> "$config_file"
    
    # 根目录配置
    if [ "$enable_proxy" = false ] || [ "$proxy_path" != "/" ]; then
        echo "    root $root_path;" >> "$config_file"
        echo "    index index.html index.htm index.php;" >> "$config_file"
    fi
    echo "" >> "$config_file"
    
    # SSL配置
    if [ -n "$https_port" ]; then
        echo "    # SSL配置" >> "$config_file"
        echo "    ssl_certificate $ssl_cert;" >> "$config_file"
        echo "    ssl_certificate_key $ssl_key;" >> "$config_file"
        echo "    ssl_protocols TLSv1.2 TLSv1.3;" >> "$config_file"
        echo "    ssl_ciphers HIGH:!aNULL:!MD5;" >> "$config_file"
        echo "    ssl_prefer_server_ciphers off;" >> "$config_file"
        
        if [ "$enable_hsts" = true ]; then
            echo "    add_header Strict-Transport-Security \"max-age=31536000; includeSubDomains\" always;" >> "$config_file"
        fi
        
        if [ "$enable_ocsp" = true ]; then
            echo "    ssl_stapling on;" >> "$config_file"
            echo "    ssl_stapling_verify on;" >> "$config_file"
            echo "    resolver 8.8.8.8 valid=300s;" >> "$config_file"
            echo "    resolver_timeout 5s;" >> "$config_file"
        fi
        echo "" >> "$config_file"
    fi
    
    # 反向代理
    if [ "$enable_proxy" = true ]; then
        echo "    location $proxy_path {" >> "$config_file"
        echo "        proxy_pass $backend_url;" >> "$config_file"
        if [ "$proxy_set_host" = true ]; then
            echo "        proxy_set_header Host \$host;" >> "$config_file"
        fi
        echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$config_file"
        echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" >> "$config_file"
        echo "        proxy_set_header X-Forwarded-Proto \$scheme;" >> "$config_file"
        echo "        proxy_set_header Upgrade \$http_upgrade;" >> "$config_file"
        echo "        proxy_set_header Connection \"upgrade\";" >> "$config_file"
        echo "    }" >> "$config_file"
        echo "" >> "$config_file"
    fi
    
    # 静态优化
    if [ "$enable_proxy" = false ] || [ "$proxy_path" != "/" ]; then
        if [ "$enable_gzip" = true ]; then
            echo "    gzip on;" >> "$config_file"
            echo "    gzip_types text/plain text/css application/json application/javascript text/xml;" >> "$config_file"
        fi
        
        echo "    location / {" >> "$config_file"
        echo "        try_files \$uri \$uri/ =404;" >> "$config_file"
        echo "    }" >> "$config_file"
    fi
    
    echo "}" >> "$config_file"
    
    print_color "Nginx配置文件已生成: $config_file" "$GREEN"
    copy_nginx_config "$config_file"
}

# 生成Caddy配置 (Caddy默认支持IPv6，无需额外监听配置)
generate_caddy_config() {
    config_file="caddy_${server_names%% *}_$(date +%Y%m%d_%H%M%S).caddyfile"
    
    echo "# Caddy配置文件" > "$config_file"
    echo "# 域名: $server_names" >> "$config_file"
    echo "" >> "$config_file"
    
    for domain in $server_names; do
        # 端口重定向
        if [ -n "$http_port" ] && [ -n "$https_port" ] && [ "$enable_301_redirect" = true ]; then
             if [ "$http_port" -ne 80 ]; then
                echo "${domain}:${http_port} {" >> "$config_file"
            else
                echo "http://${domain} {" >> "$config_file"
            fi
            echo "    redir https://${domain}{uri} permanent" >> "$config_file"
            echo "}" >> "$config_file"
            echo "" >> "$config_file"
        fi
        
        # 主配置
        if [ -n "$https_port" ]; then
            [ "$https_port" -ne 443 ] && echo "${domain}:${https_port} {" >> "$config_file" || echo "${domain} {" >> "$config_file"
        elif [ -n "$http_port" ]; then
            [ "$http_port" -ne 80 ] && echo "${domain}:${http_port} {" >> "$config_file" || echo "${domain} {" >> "$config_file"
        fi
        
        # TLS
        if [ -n "$https_port" ] && [ -n "$ssl_cert" ] && [ "$ssl_cert" != "/etc/ssl/certs/ssl-cert-snakeoil.pem" ]; then
            echo "    tls $ssl_cert $ssl_key" >> "$config_file"
        fi
        
        # 反代
        if [ "$enable_proxy" = true ]; then
            echo "    reverse_proxy $proxy_path* $backend_url {" >> "$config_file"
            [ "$proxy_set_host" = true ] && echo "        header_up Host {host}" >> "$config_file"
            echo "        header_up X-Real-IP {remote_host}" >> "$config_file"
            echo "    }" >> "$config_file"
        else
            echo "    root * $root_path" >> "$config_file"
            echo "    file_server" >> "$config_file"
            [ "$enable_gzip" = true ] && echo "    encode gzip zstd" >> "$config_file"
        fi
        
        echo "}" >> "$config_file"
        echo "" >> "$config_file"
    done
    
    print_color "Caddy配置文件已生成: $config_file" "$GREEN"
    
    # Caddy安装逻辑
    read -e -p "是否将配置文件添加到Caddyfile并验证? [Y/n]: " install_choice
    install_choice=${install_choice:-y}
    if [[ ! "$install_choice" =~ ^[Nn] ]]; then
        if [ -f "/etc/caddy/Caddyfile" ]; then
            if grep -q "$server_names" "/etc/caddy/Caddyfile"; then
                print_color "警告: 域名可能已存在，跳过追加！" "$RED"
                return
            fi
            echo "" >> "/etc/caddy/Caddyfile"
            cat "$config_file" >> "/etc/caddy/Caddyfile"
            
            if sudo caddy validate --config /etc/caddy/Caddyfile; then
                print_color "验证成功！" "$GREEN"
                sudo systemctl reload caddy
            else
                print_color "验证失败，请手动检查文件！" "$RED"
            fi
        fi
    fi
}

# 主程序
main() {
    while true; do
        show_menu
        read -p "请选择 [1-3]: " choice
        case $choice in
            1) get_web_config; generate_nginx_config ;;
            2) get_web_config; generate_caddy_config ;;
            3) exit 0 ;;
            *) print_color "无效选择" "$RED" ;;
        esac
        read -e -p "是否继续? [Y/n]: " cont
        [[ "$cont" =~ ^[Nn] ]] && exit 0
    done
}

main