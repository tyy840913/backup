#!/bin/bash

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
    echo "    Web服务器配置生成器（优化版）"
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
        print_color "错误: 端口号必须是1-65535之间的数字" "$RED"
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
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

# 获取Web服务配置
get_web_config() {
    # 初始化变量
    need_497=false
    
    echo ""
    print_color "=== Web服务基本配置 ===" "$BLUE"
    
    # 简化的端口模式选择
    while true; do
        echo ""
        echo "请选择端口配置模式:"
        echo "1. 标准端口 (80/443，自动HTTP到HTTPS重定向)"
        echo "2. 自定义端口"
        read -p "请选择 [1-2]: " port_mode
        
        case $port_mode in
            1)
                # 标准端口：80重定向到443
                http_port=80
                https_port=443
                enable_301_redirect=true
                is_standard=true
                break
                ;;
            2)
                # 自定义端口
                is_standard=false
                while true; do
                    read -p "请输入监听端口: " custom_port
                    if validate_port "$custom_port"; then
                        break
                    fi
                done
                
                echo ""
                read -p "是否启用HTTPS (SSL)? [y/N]: " enable_ssl
                if [[ "$enable_ssl" =~ ^[Yy] ]]; then
                    http_port=""
                    https_port=$custom_port
                    enable_301_redirect=false
                    
                    # 非标准HTTPS端口强制处理497
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
    
    # 获取根目录（仅在未启用反向代理时询问）
    echo ""
    read -p "请输入网站根目录 (默认: /var/www/html): " root_path
    if [ -z "$root_path" ]; then
        root_path="/var/www/html"
    fi
    
    # SSL配置（如果启用了HTTPS）
    if [ -n "$https_port" ]; then
        echo ""
        print_color "=== SSL证书配置 ===" "$BLUE"
        print_color "注意：请优先使用证书链" "$YELLOW"
        read -p "SSL证书路径 (默认: /etc/ssl/certs/ssl-cert-snakeoil.pem): " ssl_cert
        if [ -z "$ssl_cert" ]; then
            ssl_cert="/etc/ssl/certs/ssl-cert-snakeoil.pem"
        fi
        
        read -p "SSL私钥路径 (默认: /etc/ssl/private/ssl-cert-snakeoil.key): " ssl_key
        if [ -z "$ssl_key" ]; then
            ssl_key="/etc/ssl/private/ssl-cert-snakeoil.key"
        fi
        
        # 安全加固
        echo ""
        print_color "=== 安全加固配置 ===" "$BLUE"
        echo "推荐配置包括：HSTS、OCSP Stapling、TLS 1.2+"
        read -e -p "是否应用推荐的安全配置? [Y/n]: " -i "y" enable_security
        if [[ ! "$enable_security" =~ ^[Nn] ]]; then
            enable_hsts=true
            enable_ocsp=true
            strong_security=true
        else
            enable_hsts=false
            enable_ocsp=false
            strong_security=false
        fi
    else
        enable_hsts=false
        enable_ocsp=false
        strong_security=false
        ssl_cert=""
        ssl_key=""
    fi
    
    # 性能优化配置（仅在未启用反向代理时询问）
    echo ""
    print_color "=== 性能优化配置 ===" "$BLUE"
    read -e -p "是否应用性能优化（Gzip、缓存头、静态文件长缓存）? [Y/n]: " -i "y" enable_perf
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
    read -e -p "是否需要配置反向代理? [y/N]: " -i "n" need_proxy
    if [[ "$need_proxy" =~ ^[Yy] ]]; then
        enable_proxy=true
        
        while true; do
            read -p "请输入后端服务地址 (IP、域名或带端口的地址，如 127.0.0.1:8080): " backend_input
            
            if [ -z "$backend_input" ]; then
                print_color "错误: 后端地址不能为空" "$RED"
                continue
            fi
            
            # 检查是否包含端口
            if [[ $backend_input =~ :[0-9]+$ ]]; then
                # 已经包含端口
                backend_host=$(echo "$backend_input" | cut -d: -f1)
                backend_port=$(echo "$backend_input" | cut -d: -f2)
            else
                # 不含端口，使用默认端口
                backend_host="$backend_input"
                backend_port="80"
            fi
            
            # 验证输入的是IP还是域名
            if validate_ip "$backend_host"; then
                # 如果是IP地址，强制使用HTTP
                backend_url="http://${backend_host}:${backend_port}"
                print_color "检测到IP地址，自动使用HTTP协议: $backend_url" "$YELLOW"
                break
            elif validate_domain "$backend_host"; then
                # 如果是域名，让用户选择协议
                echo "检测到域名，请选择协议:"
                echo "1. HTTP (默认)"
                echo "2. HTTPS"
                read -p "请选择 [1-2]: " protocol_choice
                
                case $protocol_choice in
                    2)
                        backend_url="https://${backend_host}:${backend_port}"
                        ;;
                    *)
                        backend_url="http://${backend_host}:${backend_port}"
                        ;;
                esac
                break
            else
                print_color "错误: 请输入有效的IP地址或域名" "$RED"
            fi
        done
        
        read -p "请输入代理路径 (例如: /api/, 留空为 /): " proxy_path
        if [ -z "$proxy_path" ]; then
            proxy_path="/"
        fi
        
        read -e -p "是否传递Host头? [Y/n]: " -i "y" pass_host
        if [[ ! "$pass_host" =~ ^[Nn] ]]; then
            proxy_set_host=true
        else
            proxy_set_host=false
        fi
        
        # 反向代理模式下，禁用静态文件相关配置
        enable_gzip=false
        enable_static_cache=false
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
    read -e -p "是否将配置文件复制到Nginx目录并启用? [Y/n]: " -i "y" install_choice
    
    if [[ ! "$install_choice" =~ ^[Nn] ]]; then
        # 检查Nginx目录是否存在
        if [ -d "/etc/nginx/sites-available" ] && [ -d "/etc/nginx/sites-enabled" ]; then
            sudo cp "$config_file" "/etc/nginx/sites-available/"
            sudo ln -sf "/etc/nginx/sites-available/$config_file" "/etc/nginx/sites-enabled/"
            
            # 测试配置
            print_color "测试Nginx配置..." "$YELLOW"
            if sudo nginx -t; then
                print_color "配置测试成功！" "$GREEN"
                read -e -p "是否立即重载Nginx配置? [Y/n]: " -i "y" reload_choice
                if [[ ! "$reload_choice" =~ ^[Nn] ]]; then
                    sudo systemctl reload nginx
                    print_color "Nginx配置已重载！" "$GREEN"
                fi
            else
                print_color "配置测试失败，请检查配置文件！" "$RED"
                # 移除有问题的配置
                sudo rm -f "/etc/nginx/sites-enabled/$config_file"
                sudo rm -f "/etc/nginx/sites-available/$config_file"
            fi
        else
            print_color "错误: Nginx目录不存在，请手动复制配置文件" "$RED"
        fi
    fi
}

# 生成Nginx配置
generate_nginx_config() {
    config_file="nginx_${server_names%% *}_$(date +%Y%m%d_%H%M%S).conf"
    
    echo "# Nginx配置文件 - 生成于 $(date)" > "$config_file"
    echo "# 域名: $server_names" >> "$config_file"
    echo "# 端口配置: HTTP=$http_port, HTTPS=$https_port, 重定向=$enable_301_redirect" >> "$config_file"
    echo "# 反向代理: $enable_proxy" >> "$config_file"
    echo "" >> "$config_file"
    
    # 如果有HTTP端口且需要重定向，先生成HTTP server块进行重定向
    if [ -n "$http_port" ] && [ "$enable_301_redirect" = true ] && [ -n "$https_port" ]; then
        echo "# HTTP到HTTPS重定向" >> "$config_file"
        echo "server {" >> "$config_file"
        echo "    listen $http_port;" >> "$config_file"
        echo "    server_name $server_names;" >> "$config_file"
        echo "    return 301 https://\$server_name\$request_uri;" >> "$config_file"
        echo "}" >> "$config_file"
        echo "" >> "$config_file"
    fi
    
    # 主server块（HTTPS或HTTP）
    if [ -n "$https_port" ]; then
        echo "# HTTPS主配置" >> "$config_file"
        echo "server {" >> "$config_file"
        echo "    listen ${https_port} ssl http2;" >> "$config_file"
        if [ "$need_497" = true ]; then
            echo "    error_page 497 https://\$host:${https_port}\$request_uri;" >> "$config_file"
        fi
    elif [ -n "$http_port" ]; then
        echo "# HTTP主配置" >> "$config_file"
        echo "server {" >> "$config_file"
        echo "    listen $http_port;" >> "$config_file"
    fi
    
    echo "    server_name $server_names;" >> "$config_file"
    
    # 仅在未启用反向代理时添加root和index配置
    if [ "$enable_proxy" = false ]; then
        echo "    root $root_path;" >> "$config_file"
        echo "    index index.html index.htm index.php;" >> "$config_file"
    else
        echo "    # 反向代理模式，无需root目录配置" >> "$config_file"
    fi
    echo "" >> "$config_file"
    
    # SSL配置（仅HTTPS）
    if [ -n "$https_port" ]; then
        echo "    # SSL配置" >> "$config_file"
        echo "    ssl_certificate $ssl_cert;" >> "$config_file"
        echo "    ssl_certificate_key $ssl_key;" >> "$config_file"
        
        if [ "$strong_security" = true ]; then
            echo "    ssl_protocols TLSv1.2 TLSv1.3;" >> "$config_file"
            echo "    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;" >> "$config_file"
        else
            echo "    ssl_protocols TLSv1.2 TLSv1.3;" >> "$config_file"
            echo "    ssl_ciphers HIGH:!aNULL:!MD5;" >> "$config_file"
        fi
        echo "    ssl_prefer_server_ciphers off;" >> "$config_file"
        echo "    ssl_session_cache shared:SSL:10m;" >> "$config_file"
        echo "    ssl_session_timeout 10m;" >> "$config_file"
        echo "" >> "$config_file"
        
        # HSTS
        if [ "$enable_hsts" = true ]; then
            echo "    add_header Strict-Transport-Security \"max-age=31536000; includeSubDomains\" always;" >> "$config_file"
            echo "" >> "$config_file"
        fi
        
        # OCSP Stapling
        if [ "$enable_ocsp" = true ]; then
            echo "    ssl_stapling on;" >> "$config_file"
            echo "    ssl_stapling_verify on;" >> "$config_file"
            echo "    resolver 8.8.8.8 8.8.4.4 valid=300s;" >> "$config_file"
            echo "    resolver_timeout 5s;" >> "$config_file"
            echo "" >> "$config_file"
        fi
    fi
    
    # 通用安全头
    echo "    # 安全头" >> "$config_file"
    echo "    add_header X-Frame-Options \"SAMEORIGIN\" always;" >> "$config_file"
    echo "    add_header X-Content-Type-Options \"nosniff\" always;" >> "$config_file"
    echo "    add_header X-XSS-Protection \"1; mode=block\" always;" >> "$config_file"
    echo "" >> "$config_file"
    
    # 反向代理配置（仅在启用时添加）
    if [ "$enable_proxy" = true ]; then
        echo "    # 反向代理" >> "$config_file"
        echo "    location $proxy_path {" >> "$config_file"
        echo "        proxy_pass $backend_url;" >> "$config_file"
        if [ "$proxy_set_host" = true ]; then
            echo "        proxy_set_header Host \$host;" >> "$config_file"
        fi
        echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$config_file"
        echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" >> "$config_file"
        echo "        proxy_set_header X-Forwarded-Proto \$scheme;" >> "$config_file"
        echo "    }" >> "$config_file"
        echo "" >> "$config_file"
    fi
    
    # 静态文件配置（仅在未启用反向代理时添加）
    if [ "$enable_proxy" = false ]; then
        if [ "$enable_gzip" = true ]; then
            echo "    # Gzip压缩" >> "$config_file"
            echo "    gzip on;" >> "$config_file"
            echo "    gzip_vary on;" >> "$config_file"
            echo "    gzip_min_length 1024;" >> "$config_file"
            echo "    gzip_types text/plain text/css text/xml text/javascript application/javascript application/json;" >> "$config_file"
            echo "" >> "$config_file"
        fi

        if [ "$enable_static_cache" = true ]; then
            echo "    # 静态文件缓存" >> "$config_file"
            echo "    location ~* \\.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg|eot)\$ {" >> "$config_file"
            echo "        expires 1y;" >> "$config_file"
            echo "        add_header Cache-Control \"public, immutable\";" >> "$config_file"
            echo "    }" >> "$config_file"
            echo "" >> "$config_file"
        fi

        echo "    # 默认请求处理" >> "$config_file"
        echo "    location / {" >> "$config_file"
        echo "        try_files \$uri \$uri/ =404;" >> "$config_file"
        echo "    }" >> "$config_file"
    fi
    
    echo "}" >> "$config_file"
    
    print_color "Nginx配置文件已生成: $config_file" "$GREEN"
    echo ""
    print_color "使用方法:" "$YELLOW"
    echo "sudo cp $config_file /etc/nginx/sites-available/"
    echo "sudo ln -s /etc/nginx/sites-available/$config_file /etc/nginx/sites-enabled/"
    echo "sudo nginx -t && sudo systemctl reload nginx"
    echo ""
    
    # 提供自动复制选项
    copy_nginx_config "$config_file"
}

# 生成Caddy配置
generate_caddy_config() {
    config_file="caddy_${server_names%% *}_$(date +%Y%m%d_%H%M%S).caddyfile"
    
    echo "# Caddy配置文件 - 生成于 $(date)" > "$config_file"
    echo "# 域名: $server_names" >> "$config_file"
    echo "# 端口配置: HTTP=$http_port, HTTPS=$https_port" >> "$config_file"
    echo "# 反向代理: $enable_proxy" >> "$config_file"
    echo "" >> "$config_file"
    
    # 为每个域名生成块
    for domain in $server_names; do
        # 标准端口HTTP到HTTPS重定向
        if [ -n "$http_port" ] && [ -n "$https_port" ] && [ "$enable_301_redirect" = true ]; then
            echo "# HTTP到HTTPS重定向（标准端口）" >> "$config_file"
            if [ "$http_port" -ne 80 ]; then
                echo "${domain}:${http_port} {" >> "$config_file"
            else
                echo "http://${domain} {" >> "$config_file"
            fi
            echo "    redir https://${domain}{uri} permanent" >> "$config_file"
            echo "}" >> "$config_file"
            echo "" >> "$config_file"
        fi
        
        # 主配置块
        if [ -n "$https_port" ]; then
            if [ "$https_port" -ne 443 ]; then
                echo "${domain}:${https_port} {" >> "$config_file"
            else
                echo "${domain} {" >> "$config_file"
            fi
        elif [ -n "$http_port" ]; then
            if [ "$http_port" -ne 80 ]; then
                echo "${domain}:${http_port} {" >> "$config_file"
            else
                echo "${domain} {" >> "$config_file"
            fi
        fi
        
        # TLS/SSL配置
        if [ -n "$https_port" ]; then
            if [ -n "$ssl_cert" ] && [ "$ssl_cert" != "/etc/ssl/certs/ssl-cert-snakeoil.pem" ]; then
                echo "    tls $ssl_cert $ssl_key" >> "$config_file"
            fi
            
            if [ "$strong_security" = true ]; then
                echo "    tls {" >> "$config_file"
                echo "        protocols tls1.2 tls1.3" >> "$config_file"
                echo "    }" >> "$config_file"
                echo "" >> "$config_file"
            fi
            
            # HSTS
            if [ "$enable_hsts" = true ]; then
                echo "    header Strict-Transport-Security \"max-age=31536000; includeSubDomains; preload\"" >> "$config_file"
            fi
        fi
        
        # 安全头
        echo "    header X-Frame-Options SAMEORIGIN" >> "$config_file"
        echo "    header X-Content-Type-Options nosniff" >> "$config_file"
        echo "    header X-XSS-Protection \"1; mode=block\"" >> "$config_file"
        echo "" >> "$config_file"
        
        # 反向代理配置
        if [ "$enable_proxy" = true ]; then
            echo "    reverse_proxy /* $backend_url {" >> "$config_file"
            if [ "$proxy_set_host" = true ]; then
                echo "        header_up Host {host}" >> "$config_file"
            fi
            echo "        header_up X-Real-IP {remote_host}" >> "$config_file"
            echo "        header_up X-Forwarded-Proto {scheme}" >> "$config_file"
            echo "    }" >> "$config_file"
        else
            # 静态文件模式
            echo "    root * $root_path" >> "$config_file"
            echo "" >> "$config_file"
            
            if [ "$enable_gzip" = true ]; then
                echo "    encode gzip zstd" >> "$config_file"
                echo "" >> "$config_file"
            fi
            
            echo "    file_server" >> "$config_file"
            echo "" >> "$config_file"
            
            # 静态文件缓存
            if [ "$enable_static_cache" = true ]; then
                echo "    @static {" >> "$config_file"
                echo "        path *.jpg *.jpeg *.png *.gif *.ico *.css *.js *.woff *.woff2 *.ttf *.svg *.eot" >> "$config_file"
                echo "    }" >> "$config_file"
                echo "    header @static Cache-Control \"public, max-age=31536000, immutable\"" >> "$config_file"
                echo "" >> "$config_file"
            fi
        fi
        
        echo "}" >> "$config_file"
        echo "" >> "$config_file"
    done
    
    print_color "Caddy配置文件已生成: $config_file" "$GREEN"
    echo ""
    
    # Caddy配置安装功能
    echo ""
    print_color "=== Caddy配置安装 ===" "$BLUE"
    read -e -p "是否将配置文件添加到Caddyfile并验证? [Y/n]: " -i "y" install_choice
    
    if [[ ! "$install_choice" =~ ^[Nn] ]]; then
        # 检查Caddyfile是否存在
        if [ -f "/etc/caddy/Caddyfile" ]; then
            echo "" >> "/etc/caddy/Caddyfile"
            cat "$config_file" >> "/etc/caddy/Caddyfile"
            
            # 验证配置
            print_color "验证Caddy配置..." "$YELLOW"
            if sudo caddy validate --config /etc/caddy/Caddyfile; then
                print_color "配置验证成功！" "$GREEN"
                read -e -p "是否立即重载Caddy配置? [Y/n]: " -i "y" reload_choice
                if [[ ! "$reload_choice" =~ ^[Nn] ]]; then
                    sudo systemctl reload caddy
                    print_color "Caddy配置已重载！" "$GREEN"
                fi
            else
                print_color "配置验证失败，已回滚更改！" "$RED"
                # 回滚更改
                sudo sed -i "/$(basename "$config_file")/d" "/etc/caddy/Caddyfile"
            fi
        else
            print_color "Caddyfile不存在，创建新的Caddyfile..." "$YELLOW"
            sudo cp "$config_file" "/etc/caddy/Caddyfile"
            sudo chown caddy:caddy "/etc/caddy/Caddyfile"
            
            # 验证配置
            if sudo caddy validate --config /etc/caddy/Caddyfile; then
                print_color "配置验证成功！" "$GREEN"
                read -e -p "是否立即启动Caddy服务? [Y/n]: " -i "y" start_choice
                if [[ ! "$start_choice" =~ ^[Nn] ]]; then
                    sudo systemctl enable caddy
                    sudo systemctl start caddy
                    print_color "Caddy服务已启动！" "$GREEN"
                fi
            else
                print_color "配置验证失败！" "$RED"
                sudo rm -f "/etc/caddy/Caddyfile"
            fi
        fi
    fi
    
    echo ""
    print_color "使用方法:" "$YELLOW"
    echo "手动安装: cat $config_file >> /etc/caddy/Caddyfile"
    echo "配置验证: caddy validate --config /etc/caddy/Caddyfile"
    echo "重载服务: sudo systemctl reload caddy"
    echo ""
}

# 主程序
main() {
    while true; do
        show_menu
        read -p "请选择 [1-3]: " choice
        
        case $choice in
            1)
                get_web_config
                generate_nginx_config
                ;;
            2)
                get_web_config
                generate_caddy_config
                ;;
            3)
                print_color "再见！" "$GREEN"
                exit 0
                ;;
            *)
                print_color "无效选择，请重试" "$RED"
                ;;
        esac
        
        echo ""
        read -e -p "是否继续生成其他配置? [y/N]: " -i "n" cont
        if [[ ! "$cont" =~ ^[Yy] ]]; then
            print_color "再见！" "$GREEN"
            exit 0
        fi
    done
}

# 运行
main
