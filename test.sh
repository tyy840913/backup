#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # 结束颜色

# 打印带颜色的消息
print_color() {
    echo -e "${2}${1}${NC}"
}

# 显示标题
print_title() {
    echo "========================================"
    echo "    Web服务器配置生成器（增强版）"
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

# 输入验证函数：端口
validate_port() {
    local port=$1
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        print_color "错误: 端口号必须是1-65535之间的数字" "$RED"
        return 1
    fi
    return 0
}

# 验证IPv4格式
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
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

# 验证路径格式
validate_path() {
    local path=$1
    if [[ $path =~ ^\/[a-zA-Z0-9_\-\.\/]*$ ]]; then
        return 0
    else
        return 1
    fi
}

# 获取后端配置
get_backend_config() {
    local backend_type=$1
    
    case $backend_type in
        "single")
            get_single_backend_config
            ;;
        "multi")
            get_multi_backend_config
            ;;
    esac
}

# 获取单后端配置
get_single_backend_config() {
    while true; do
        read -p "请输入后端服务地址 (IP、域名或带端口的地址，如 127.0.0.1:8080): " backend_input

        if [ -z "$backend_input" ]; then
            print_color "错误: 后端地址不能为空" "$RED"
            continue
        fi

        # 检查是否包含端口
        if [[ $backend_input =~ :[0-9]+$ ]]; then
            backend_host=$(echo "$backend_input" | awk -F: '{print $1}')
            backend_port=$(echo "$backend_input" | awk -F: '{print $2}')
        else
            backend_host="$backend_input"
            backend_port="80"
        fi

        # 验证输入的是IP还是域名
        if validate_ip "$backend_host" || validate_domain "$backend_host"; then
            # 询问协议
            echo "请选择后端协议:"
            echo "1. HTTP (默认)"
            echo "2. HTTPS"
            read -p "请选择 [1-2]: " protocol_choice
            protocol_choice=${protocol_choice:-1}
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
            print_color "错误: 请输入有效的 IP 地址或域名" "$RED"
        fi
    done

    read -p "请输入代理路径 (例如: /api/, 留空为 /): " proxy_path_input
    if [ -z "$proxy_path_input" ]; then
        proxy_path="/"
    else
        # 确保路径以/开头
        if [[ ! "$proxy_path_input" =~ ^/ ]]; then
            proxy_path_input="/$proxy_path_input"
        fi
        proxy_path="$proxy_path_input"
    fi

    read -e -p "是否传递 Host 头? [Y/n]: " pass_host
    pass_host=${pass_host:-y}
    if [[ ! "$pass_host" =~ ^[Nn] ]]; then
        proxy_set_host=true
    else
        proxy_set_host=false
    fi
}

# 获取多后端配置
get_multi_backend_config() {
    multi_backends=()
    
    echo ""
    print_color "=== 根域名处理配置 ===" "$PURPLE"
    echo "请选择根域名的处理方式:"
    echo "1. 返回 404 (不处理根路径)"
    echo "2. 代理到特定后端"
    echo "3. 服务静态文件"
    read -p "请选择 [1-3]: " root_choice
    
    case $root_choice in
        2)
            echo "配置根域名代理后端..."
            get_single_backend_config
            multi_backends+=("root:$proxy_path:$backend_url:$proxy_set_host")
            ;;
        3)
            read -p "请输入静态文件根目录 (默认: /var/www/html): " static_root
            static_root=${static_root:-/var/www/html}
            multi_backends+=("root:static:$static_root")
            ;;
        *)
            multi_backends+=("root:404")
            print_color "根路径将返回 404" "$YELLOW"
            ;;
    esac
    
    echo ""
    print_color "=== 多后端代理配置 ===" "$PURPLE"
    echo "请选择多后端代理类型:"
    echo "1. 路径代理 (如 /api/* 代理到不同后端)"
    echo "2. 子域名代理 (如 api.domain.com 代理到不同后端)"
    read -p "请选择 [1-2]: " multi_type_choice
    
    if [ $multi_type_choice -eq 1 ]; then
        get_path_based_proxies
    else
        get_subdomain_based_proxies
    fi
}

# 获取基于路径的代理配置
get_path_based_proxies() {
    while true; do
        echo ""
        print_color "添加路径代理规则" "$CYAN"
        read -p "请输入代理路径 (如 /api/, 输入 'done' 结束): " path_input
        
        if [ "$path_input" = "done" ]; then
            break
        fi
        
        if [ -z "$path_input" ]; then
            print_color "路径不能为空" "$RED"
            continue
        fi
        
        # 确保路径以/开头
        if [[ ! "$path_input" =~ ^/ ]]; then
            path_input="/$path_input"
        fi
        
        # 获取后端配置
        get_single_backend_config
        multi_backends+=("path:$path_input:$backend_url:$proxy_set_host")
        
        read -e -p "是否继续添加路径代理? [Y/n]: " continue_add
        continue_add=${continue_add:-y}
        if [[ "$continue_add" =~ ^[Nn] ]]; then
            break
        fi
    done
}

# 获取基于子域名的代理配置
get_subdomain_based_proxies() {
    while true; do
        echo ""
        print_color "添加子域名代理规则" "$CYAN"
        read -p "请输入子域名 (如 api, 输入 'done' 结束): " subdomain_input
        
        if [ "$subdomain_input" = "done" ]; then
            break
        fi
        
        if [ -z "$subdomain_input" ]; then
            print_color "子域名不能为空" "$RED"
            continue
        fi
        
        # 获取后端配置
        get_single_backend_config
        multi_backends+=("subdomain:$subdomain_input:$backend_url:$proxy_set_host")
        
        read -e -p "是否继续添加子域名代理? [Y/n]: " continue_add
        continue_add=${continue_add:-y}
        if [[ "$continue_add" =~ ^[Nn] ]]; then
            break
        fi
    done
}

# 获取Web服务配置
get_web_config() {
    # 初始化变量
    need_497=false
    is_standard=false
    enable_301_redirect=false
    enable_proxy=false
    proxy_type="single"
    enable_gzip=false
    enable_static_cache=false
    enable_hsts=false
    enable_ocsp=false
    strong_security=false
    ssl_cert=""
    ssl_key=""
    backend_url=""
    proxy_path="/"
    proxy_set_host=false
    multi_backends=()

    echo ""
    print_color "=== Web服务基本配置 ===" "$BLUE"

    # 端口模式选择
    while true; do
        echo ""
        echo "请选择端口配置模式:"
        echo "1. 标准端口 (HTTP=80, HTTPS=443，自动HTTP到HTTPS重定向)"
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
                    read -p "请输入监听端口（如果是HTTPS请输入HTTPS端口，否则输入HTTP端口）: " custom_port
                    if validate_port "$custom_port"; then
                        break
                    fi
                done

                echo ""
                read -e -p "此端口用于 HTTPS 吗？（Y/n）: " enable_ssl
                enable_ssl=${enable_ssl:-y}
                if [[ ! "$enable_ssl" =~ ^[Nn] ]]; then
                    https_port=$custom_port
                    http_port=""
                    enable_301_redirect=false
                    # 仅当非标准且启用 HTTPS 时才需要处理 497
                    if [ "$https_port" -ne 443 ]; then
                        need_497=true
                    else
                        need_497=false
                    fi
                else
                    http_port=$custom_port
                    https_port=""
                    enable_301_redirect=false
                    need_497=false
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
    read -p "请输入域名 (多个域名用空格分隔, 留空为 localhost): " server_names
    if [ -z "$server_names" ]; then
        server_names="localhost"
    fi

    # 根目录（仅在未启用反向代理或混合模式时询问）
    echo ""
    read -p "请输入网站根目录 (默认: /var/www/html): " root_path
    if [ -z "$root_path" ]; then
        root_path="/var/www/html"
    fi

    # SSL配置（如果启用了HTTPS）
    if [ -n "$https_port" ]; then
        echo ""
        print_color "=== SSL证书配置 ===" "$BLUE"
        print_color "注意：建议使用由受信任 CA 签发的证书文件路径" "$YELLOW"
        read -p "SSL证书路径 (默认: /etc/ssl/certs/ssl-cert-snakeoil.pem): " ssl_cert_input
        ssl_cert_input=${ssl_cert_input:-/etc/ssl/certs/ssl-cert-snakeoil.pem}
        ssl_cert="$ssl_cert_input"

        read -p "SSL私钥路径 (默认: /etc/ssl/private/ssl-cert-snakeoil.key): " ssl_key_input
        ssl_key_input=${ssl_key_input:-/etc/ssl/private/ssl-cert-snakeoil.key}
        ssl_key="$ssl_key_input"

        # 安全加固选项
        echo ""
        print_color "=== 安全加固配置 ===" "$BLUE"
        echo "推荐配置包括：HSTS、OCSP Stapling、TLS 1.2+"
        read -e -p "是否应用推荐的安全配置（包含 HSTS，但 OCSP 将单独询问）? [Y/n]: " enable_security
        enable_security=${enable_security:-y}
        if [[ ! "$enable_security" =~ ^[Nn] ]]; then
            enable_hsts=true
            strong_security=true
        else
            enable_hsts=false
            strong_security=false
        fi

        # 单独询问是否启用 OCSP Stapling
        read -e -p "是否启用 OCSP Stapling? [Y/n]: " ocsp_choice
        ocsp_choice=${ocsp_choice:-y}

        if [[ "$ocsp_choice" =~ ^[Yy] ]]; then
            enable_ocsp=true
        else
            enable_ocsp=false
        fi
    else
        enable_hsts=false
        enable_ocsp=false
        strong_security=false
        ssl_cert=""
        ssl_key=""
    fi

    # 性能优化配置
    echo ""
    print_color "=== 性能优化配置 ===" "$BLUE"
    read -e -p "是否应用性能优化（Gzip、缓存头、静态文件长缓存）? [Y/n]: " enable_perf
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
    echo "请选择代理模式:"
    echo "1. 纯静态文件服务"
    echo "2. 单后端反向代理"
    echo "3. 多后端反向代理（混合模式）"
    read -p "请选择 [1-3]: " proxy_mode

    case $proxy_mode in
        2)
            enable_proxy=true
            proxy_type="single"
            get_backend_config "single"
            ;;
        3)
            enable_proxy=true
            proxy_type="multi"
            get_backend_config "multi"
            ;;
        *)
            enable_proxy=false
            proxy_type="static"
            ;;
    esac
}

# 自动复制 Nginx 配置
copy_nginx_config() {
    local config_file=$1

    echo ""
    print_color "=== Nginx配置安装 ===" "$BLUE"
    read -e -p "是否将配置文件复制到 Nginx 目录并启用? [Y/n]: " install_choice
    install_choice=${install_choice:-y}
    if [[ ! "$install_choice" =~ ^[Nn] ]]; then
        if [ "$EUID" -eq 0 ]; then
            if [ -d "/etc/nginx/sites-available" ] && [ -d "/etc/nginx/sites-enabled" ]; then
                cp "$config_file" "/etc/nginx/sites-available/"
                ln -sf "/etc/nginx/sites-available/$config_file" "/etc/nginx/sites-enabled/$config_file"

                print_color "测试 Nginx 配置..." "$YELLOW"
                if nginx -t; then
                    print_color "配置测试成功！" "$GREEN"
                    read -e -p "是否立即重载 Nginx 配置? [Y/n]: " reload_choice
                    reload_choice=${reload_choice:-y}
                    if [[ ! "$reload_choice" =~ ^[Nn] ]]; then
                        systemctl reload nginx
                        print_color "Nginx 配置已重载！" "$GREEN"
                    fi
                else
                    print_color "配置测试失败，请检查配置文件！" "$RED"
                    rm -f "/etc/nginx/sites-enabled/$config_file"
                    rm -f "/etc/nginx/sites-available/$config_file"
                fi
            else
                print_color "错误: 目标 Nginx 目录不存在，请手动复制配置文件" "$RED"
            fi
        else
            print_color "当前非 root，脚本不会使用 自动复制。请手动执行以下命令（替换为你的文件名）：" "$YELLOW"
            echo "cp $config_file /etc/nginx/sites-available/"
            echo "ln -s /etc/nginx/sites-available/$config_file /etc/nginx/sites-enabled/$config_file"
            echo "nginx -t && systemctl reload nginx"
        fi
    fi
}

# 生成 Nginx 多后端配置
generate_nginx_multi_config() {
    local config_file=$1
    
    # HTTP -> HTTPS 重定向
    if [ -n "$http_port" ] && [ "$enable_301_redirect" = true ] && [ -n "$https_port" ]; then
        echo "# HTTP到HTTPS重定向" >> "$config_file"
        echo "server {" >> "$config_file"
        echo "    listen ${http_port};" >> "$config_file"
        echo "    listen [::]:${http_port};" >> "$config_file"
        echo "    server_name $server_names;" >> "$config_file"
        if [ "$https_port" -ne 443 ]; then
            echo "    return 301 https://\$host:${https_port}\$request_uri;" >> "$config_file"
        else
            echo "    return 301 https://\$host\$request_uri;" >> "$config_file"
        fi
        echo "}" >> "$config_file"
        echo "" >> "$config_file"
    fi

    # 主 server 块
    if [ -n "$https_port" ]; then
        echo "# HTTPS主配置" >> "$config_file"
        echo "server {" >> "$config_file"
        echo "    listen ${https_port} ssl http2;" >> "$config_file"
        echo "    listen [::]:${https_port} ssl http2;" >> "$config_file"
        if [ "$need_497" = true ]; then
            echo "    # 处理 497: HTTP 请求到 HTTPS 端口的情况" >> "$config_file"
            if [ "$https_port" -ne 443 ]; then
                echo "    error_page 497 https://\$host:${https_port}\$request_uri;" >> "$config_file"
            else
                echo "    error_page 497 https://\$host\$request_uri;" >> "$config_file"
            fi
        fi
    elif [ -n "$http_port" ]; then
        echo "# HTTP主配置" >> "$config_file"
        echo "server {" >> "$config_file"
        echo "    listen ${http_port};" >> "$config_file"
        echo "    listen [::]:${http_port};" >> "$config_file"
    fi

    echo "    server_name $server_names;" >> "$config_file"
    echo "" >> "$config_file"

    # SSL 配置
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

    # 处理多后端配置
    for backend_config in "${multi_backends[@]}"; do
        IFS=':' read -r config_type config_value1 config_value2 config_value3 <<< "$backend_config"
        
        case $config_type in
            "root")
                case $config_value1 in
                    "static")
                        echo "    # 根路径静态文件服务" >> "$config_file"
                        echo "    location / {" >> "$config_file"
                        echo "        root $config_value2;" >> "$config_file"
                        echo "        index index.html index.htm index.php;" >> "$config_file"
                        echo "        try_files \$uri \$uri/ =404;" >> "$config_file"
                        echo "    }" >> "$config_file"
                        echo "" >> "$config_file"
                        ;;
                    "404")
                        echo "    # 根路径返回404" >> "$config_file"
                        echo "    location / {" >> "$config_file"
                        echo "        return 404;" >> "$config_file"
                        echo "    }" >> "$config_file"
                        echo "" >> "$config_file"
                        ;;
                    *)
                        echo "    # 根路径代理" >> "$config_file"
                        echo "    location / {" >> "$config_file"
                        echo "        proxy_pass $config_value2;" >> "$config_file"
                        if [ "$config_value3" = "true" ]; then
                            echo "        proxy_set_header Host \$host;" >> "$config_file"
                        fi
                        echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$config_file"
                        echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" >> "$config_file"
                        echo "        proxy_set_header X-Forwarded-Proto \$scheme;" >> "$config_file"
                        echo "    }" >> "$config_file"
                        echo "" >> "$config_file"
                        ;;
                esac
                ;;
            "path")
                echo "    # 路径代理: $config_value1" >> "$config_file"
                echo "    location $config_value1 {" >> "$config_file"
                echo "        proxy_pass $config_value2;" >> "$config_file"
                if [ "$config_value3" = "true" ]; then
                    echo "        proxy_set_header Host \$host;" >> "$config_file"
                fi
                echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$config_file"
                echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" >> "$config_file"
                echo "        proxy_set_header X-Forwarded-Proto \$scheme;" >> "$config_file"
                echo "    }" >> "$config_file"
                echo "" >> "$config_file"
                ;;
            "subdomain")
                echo "    # 子域名代理: $config_value1" >> "$config_file"
                echo "    # 注意：需要DNS配置将子域名指向同一服务器" >> "$config_file"
                echo "" >> "$config_file"
                ;;
        esac
    done

    # 静态文件优化（仅在非纯代理模式时添加）
    if [ "$proxy_type" != "multi" ] || [[ ! "${multi_backends[*]}" =~ "static" ]]; then
        if [ "$enable_gzip" = true ]; then
            echo "    # Gzip 压缩" >> "$config_file"
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
    fi

    echo "}" >> "$config_file"
}

# 生成 Nginx 配置
generate_nginx_config() {
    config_file="nginx_${server_names%% *}_$(date +%Y%m%d_%H%M%S).conf"

    echo "# Nginx配置文件 - 生成于 $(date)" > "$config_file"
    echo "# 域名: $server_names" >> "$config_file"
    echo "# 端口配置: HTTP=$http_port, HTTPS=$https_port, 重定向=$enable_301_redirect" >> "$config_file"
    echo "# 代理模式: $proxy_type" >> "$config_file"
    echo "" >> "$config_file"

    if [ "$proxy_type" = "multi" ]; then
        generate_nginx_multi_config "$config_file"
    else
        # 原有的单后端/静态文件配置生成逻辑
        # HTTP -> HTTPS 重定向
        if [ -n "$http_port" ] && [ "$enable_301_redirect" = true ] && [ -n "$https_port" ]; then
            echo "# HTTP到HTTPS重定向" >> "$config_file"
            echo "server {" >> "$config_file"
            echo "    listen ${http_port};" >> "$config_file"
            echo "    listen [::]:${http_port};" >> "$config_file"
            echo "    server_name $server_names;" >> "$config_file"
            if [ "$https_port" -ne 443 ]; then
                echo "    return 301 https://\$host:${https_port}\$request_uri;" >> "$config_file"
            else
                echo "    return 301 https://\$host\$request_uri;" >> "$config_file"
            fi
            echo "}" >> "$config_file"
            echo "" >> "$config_file"
        fi

        # 主 server 块
        if [ -n "$https_port" ]; then
            echo "# HTTPS主配置" >> "$config_file"
            echo "server {" >> "$config_file"
            echo "    listen ${https_port} ssl http2;" >> "$config_file"
            echo "    listen [::]:${https_port} ssl http2;" >> "$config_file"
            if [ "$need_497" = true ]; then
                echo "    # 处理 497: HTTP 请求到 HTTPS 端口的情况" >> "$config_file"
                if [ "$https_port" -ne 443 ]; then
                    echo "    error_page 497 https://\$host:${https_port}\$request_uri;" >> "$config_file"
                else
                    echo "    error_page 497 https://\$host\$request_uri;" >> "$config_file"
                fi
            fi
        elif [ -n "$http_port" ]; then
            echo "# HTTP主配置" >> "$config_file"
            echo "server {" >> "$config_file"
            echo "    listen ${http_port};" >> "$config_file"
            echo "    listen [::]:${http_port};" >> "$config_file"
        fi

        echo "    server_name $server_names;" >> "$config_file"

        if [ "$enable_proxy" = false ]; then
            echo "    root $root_path;" >> "$config_file"
            echo "    index index.html index.htm index.php;" >> "$config_file"
        else
            echo "    # 反向代理模式" >> "$config_file"
        fi
        echo "" >> "$config_file"

        # SSL 配置
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

        # 反向代理配置
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

        # 静态文件配置
        if [ "$enable_proxy" = false ]; then
            if [ "$enable_gzip" = true ]; then
                echo "    # Gzip 压缩" >> "$config_file"
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
    fi

    print_color "Nginx配置文件已生成: $config_file" "$GREEN"
    echo ""
    print_color "使用方法:" "$YELLOW"
    echo "如果需要手动安装，请执行（非 root 时需加 sudo）："
    echo "cp $config_file /etc/nginx/sites-available/"
    echo "ln -s /etc/nginx/sites-available/$config_file /etc/nginx/sites-enabled/$config_file"
    echo "nginx -t && systemctl reload nginx"
    echo ""

    copy_nginx_config "$config_file"
}

# 生成 Caddy 多后端配置
generate_caddy_multi_config() {
    local config_file=$1
    
    # 为每个域名生成配置块
    for domain in $server_names; do
        # HTTP->HTTPS 重定向（如果启用了HTTPS和重定向）
        if [ -n "$http_port" ] && [ -n "$https_port" ] && [ "$enable_301_redirect" = true ]; then
            echo "# HTTP到HTTPS重定向 - $domain" >> "$config_file"
            if [ "$http_port" -ne 80 ]; then
                # 非标准 HTTP 端口
                if [ "$https_port" -ne 443 ]; then
                    echo "${domain}:${http_port} {" >> "$config_file"
                    echo "    redir https://${domain}:${https_port}{uri} permanent" >> "$config_file"
                else
                    echo "${domain}:${http_port} {" >> "$config_file"
                    echo "    redir https://${domain}{uri} permanent" >> "$config_file"
                fi
            else
                # 标准 HTTP 端口 80
                if [ "$https_port" -ne 443 ]; then
                    echo "http://${domain} {" >> "$config_file"
                    echo "    redir https://${domain}:${https_port}{uri} permanent" >> "$config_file"
                else
                    echo "http://${domain} {" >> "$config_file"
                    echo "    redir https://${domain}{uri} permanent" >> "$config_file"
                fi
            fi
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

        # TLS/SSL 配置
        if [ -n "$https_port" ]; then
            if [ -n "$ssl_cert" ] && [ -f "$ssl_cert" ] && [ -n "$ssl_key" ] && [ -f "$ssl_key" ] && [ "$ssl_cert" != "/etc/ssl/certs/ssl-cert-snakeoil.pem" ]; then
                echo "    tls $ssl_cert $ssl_key" >> "$config_file"
            else
                if [ "$strong_security" = true ]; then
                    echo "    tls {" >> "$config_file"
                    echo "        protocols tls1.2 tls1.3" >> "$config_file"
                    echo "    }" >> "$config_file"
                fi
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

        # 处理多后端配置
        local has_static_root=false
        local has_root_proxy=false
        
        for backend_config in "${multi_backends[@]}"; do
            IFS=':' read -r config_type config_value1 config_value2 config_value3 <<< "$backend_config"
            
            case $config_type in
                "root")
                    case $config_value1 in
                        "static")
                            has_static_root=true
                            echo "    # 根路径静态文件服务" >> "$config_file"
                            echo "    root * $config_value2" >> "$config_file"
                            echo "    file_server" >> "$config_file"
                            echo "" >> "$config_file"
                            ;;
                        "404")
                            echo "    # 根路径返回404" >> "$config_file"
                            echo "    respond / 404" >> "$config_file"
                            echo "" >> "$config_file"
                            ;;
                        *)
                            has_root_proxy=true
                            echo "    # 根路径代理" >> "$config_file"
                            echo "    reverse_proxy $config_value2 {" >> "$config_file"
                            if [ "$config_value3" = "true" ]; then
                                echo "        header_up Host {host}" >> "$config_file"
                            fi
                            echo "        header_up X-Real-IP {remote_host}" >> "$config_file"
                            echo "        header_up X-Forwarded-Proto {scheme}" >> "$config_file"
                            echo "    }" >> "$config_file"
                            echo "" >> "$config_file"
                            ;;
                    esac
                    ;;
                "path")
                    echo "    # 路径代理: $config_value1" >> "$config_file"
                    echo "    handle_path $config_value1* {" >> "$config_file"
                    echo "        reverse_proxy $config_value2 {" >> "$config_file"
                    if [ "$config_value3" = "true" ]; then
                        echo "            header_up Host {host}" >> "$config_file"
                    fi
                    echo "            header_up X-Real-IP {remote_host}" >> "$config_file"
                    echo "            header_up X-Forwarded-Proto {scheme}" >> "$config_file"
                    echo "        }" >> "$config_file"
                    echo "    }" >> "$config_file"
                    echo "" >> "$config_file"
                    ;;
                "subdomain")
                    # 子域名配置需要单独的server块
                    echo "    # 子域名代理配置需要单独的server块" >> "$config_file"
                    echo "    # 请为子域名 $config_value1.$domain 创建单独的配置" >> "$config_file"
                    echo "" >> "$config_file"
                    ;;
            esac
        done

        # 如果没有根路径配置，添加默认的静态文件服务
        if [ "$has_static_root" = false ] && [ "$has_root_proxy" = false ] && [ ${#multi_backends[@]} -eq 0 ]; then
            echo "    # 默认静态文件服务" >> "$config_file"
            echo "    root * $root_path" >> "$config_file"
            echo "    file_server" >> "$config_file"
            echo "" >> "$config_file"
        fi

        # 静态文件优化（仅在非纯代理模式时添加）
        if [ "$has_static_root" = true ] || [ ${#multi_backends[@]} -eq 0 ]; then
            if [ "$enable_gzip" = true ]; then
                echo "    encode gzip zstd" >> "$config_file"
                echo "" >> "$config_file"
            fi

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
        
        # 为子域名代理生成单独的server块
        for backend_config in "${multi_backends[@]}"; do
            IFS=':' read -r config_type config_value1 config_value2 config_value3 <<< "$backend_config"
            
            if [ "$config_type" = "subdomain" ]; then
                echo "# 子域名代理: $config_value1.$domain" >> "$config_file"
                if [ -n "$https_port" ]; then
                    if [ "$https_port" -ne 443 ]; then
                        echo "$config_value1.$domain:${https_port} {" >> "$config_file"
                    else
                        echo "$config_value1.$domain {" >> "$config_file"
                    fi
                else
                    if [ "$http_port" -ne 80 ]; then
                        echo "$config_value1.$domain:${http_port} {" >> "$config_file"
                    else
                        echo "$config_value1.$domain {" >> "$config_file"
                    fi
                fi
                
                # TLS/SSL 配置
                if [ -n "$https_port" ]; then
                    if [ -n "$ssl_cert" ] && [ -f "$ssl_cert" ] && [ -n "$ssl_key" ] && [ -f "$ssl_key" ] && [ "$ssl_cert" != "/etc/ssl/certs/ssl-cert-snakeoil.pem" ]; then
                        echo "    tls $ssl_cert $ssl_key" >> "$config_file"
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

                echo "    reverse_proxy $config_value2 {" >> "$config_file"
                if [ "$config_value3" = "true" ]; then
                    echo "        header_up Host {host}" >> "$config_file"
                fi
                echo "        header_up X-Real-IP {remote_host}" >> "$config_file"
                echo "        header_up X-Forwarded-Proto {scheme}" >> "$config_file"
                echo "    }" >> "$config_file"
                echo "}" >> "$config_file"
                echo "" >> "$config_file"
            fi
        done
    done
}

# 生成 Caddy 配置
generate_caddy_config() {
    config_file="caddy_${server_names%% *}_$(date +%Y%m%d_%H%M%S).caddyfile"

    echo "# Caddy配置文件 - 生成于 $(date)" > "$config_file"
    echo "# 域名: $server_names" >> "$config_file"
    echo "# 端口配置: HTTP=$http_port, HTTPS=$https_port, 重定向=$enable_301_redirect" >> "$config_file"
    echo "# 代理模式: $proxy_type" >> "$config_file"
    echo "" >> "$config_file"

    if [ "$proxy_type" = "multi" ]; then
        generate_caddy_multi_config "$config_file"
    else
        # 单后端或静态文件配置
        for domain in $server_names; do
            # HTTP->HTTPS 重定向
            if [ -n "$http_port" ] && [ "$enable_301_redirect" = true ] && [ -n "$https_port" ]; then
                echo "# HTTP到HTTPS重定向" >> "$config_file"
                if [ "$http_port" -ne 80 ]; then
                    if [ "$https_port" -ne 443 ]; then
                        echo "${domain}:${http_port} {" >> "$config_file"
                        echo "    redir https://${domain}:${https_port}{uri} permanent" >> "$config_file"
                    else
                        echo "${domain}:${http_port} {" >> "$config_file"
                        echo "    redir https://${domain}{uri} permanent" >> "$config_file"
                    fi
                else
                    if [ "$https_port" -ne 443 ]; then
                        echo "http://${domain} {" >> "$config_file"
                        echo "    redir https://${domain}:${https_port}{uri} permanent" >> "$config_file"
                    else
                        echo "http://${domain} {" >> "$config_file"
                        echo "    redir https://${domain}{uri} permanent" >> "$config_file"
                    fi
                fi
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

            # TLS/SSL 配置
            if [ -n "$https_port" ]; then
                if [ -n "$ssl_cert" ] && [ -f "$ssl_cert" ] && [ -n "$ssl_key" ] && [ -f "$ssl_key" ] && [ "$ssl_cert" != "/etc/ssl/certs/ssl-cert-snakeoil.pem" ]; then
                    echo "    tls $ssl_cert $ssl_key" >> "$config_file"
                else
                    if [ "$strong_security" = true ]; then
                        echo "    tls {" >> "$config_file"
                        echo "        protocols tls1.2 tls1.3" >> "$config_file"
                        echo "    }" >> "$config_file"
                    fi
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
                echo "    reverse_proxy $proxy_path $backend_url {" >> "$config_file"
                if [ "$proxy_set_host" = true ]; then
                    echo "        header_up Host {host}" >> "$config_file"
                fi
                echo "        header_up X-Real-IP {remote_host}" >> "$config_file"
                echo "        header_up X-Forwarded-Proto {scheme}" >> "$config_file"
                echo "    }" >> "$config_file"
            else
                # 静态文件模式
                echo "    root * $root_path" >> "$config_file"
                echo "    file_server" >> "$config_file"
                echo "" >> "$config_file"

                if [ "$enable_gzip" = true ]; then
                    echo "    encode gzip zstd" >> "$config_file"
                    echo "" >> "$config_file"
                fi

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
    fi

    print_color "Caddy配置文件已生成: $config_file" "$GREEN"
    echo ""

    # Caddy 配置安装
    echo ""
    print_color "=== Caddy配置安装 ===" "$BLUE"
    read -e -p "是否将配置文件添加到 /etc/caddy/Caddyfile 并验证? [Y/n]: " install_choice
    install_choice=${install_choice:-y}
    if [[ ! "$install_choice" =~ ^[Nn] ]]; then
        if [ "$EUID" -eq 0 ]; then
            if [ -f "/etc/caddy/Caddyfile" ]; then
                # 备份原配置
                cp "/etc/caddy/Caddyfile" "/etc/caddy/Caddyfile.backup.$(date +%Y%m%d_%H%M%S)"
                
                echo "" >> "/etc/caddy/Caddyfile"
                echo "# 自动添加的配置 - 生成于 $(date)" >> "/etc/caddy/Caddyfile"
                cat "$config_file" >> "/etc/caddy/Caddyfile"

                print_color "验证 Caddy 配置..." "$YELLOW"
                if caddy validate --config /etc/caddy/Caddyfile; then
                    print_color "配置验证成功！" "$GREEN"
                    read -e -p "是否立即重载 Caddy 配置? [Y/n]: " reload_choice
                    reload_choice=${reload_choice:-y}
                    if [[ ! "$reload_choice" =~ ^[Nn] ]]; then
                        systemctl reload caddy
                        print_color "Caddy 配置已重载！" "$GREEN"
                    fi
                else
                    print_color "配置验证失败，已恢复备份！" "$RED"
                    # 恢复备份
                    mv "/etc/caddy/Caddyfile.backup."* "/etc/caddy/Caddyfile"
                fi
            else
                print_color "Caddyfile 不存在，创建新的 /etc/caddy/Caddyfile ..." "$YELLOW"
                cp "$config_file" "/etc/caddy/Caddyfile"
                chown caddy:caddy "/etc/caddy/Caddyfile"

                if caddy validate --config /etc/caddy/Caddyfile; then
                    print_color "配置验证成功！" "$GREEN"
                    read -e -p "是否立即启动并启用 Caddy 服务? [Y/n]: " start_choice
                    start_choice=${start_choice:-y}
                    if [[ ! "$start_choice" =~ ^[Nn] ]]; then
                        systemctl enable caddy
                        systemctl start caddy
                        print_color "Caddy 服务已启动！" "$GREEN"
                    fi
                else
                    print_color "配置验证失败！" "$RED"
                    rm -f "/etc/caddy/Caddyfile"
                fi
            fi
        else
            print_color "当前非 root，脚本不会使用 自动修改 Caddyfile。请手动执行以下命令：" "$YELLOW"
            echo "cp $config_file /etc/caddy/Caddyfile.new"
            echo "caddy validate --config /etc/caddy/Caddyfile.new"
            echo "# 如果验证成功，手动添加到现有配置或替换："
            echo "cat $config_file | tee -a /etc/caddy/Caddyfile"
            echo "systemctl reload caddy"
        fi
    fi

    echo ""
    print_color "使用方法:" "$YELLOW"
    echo "手动安装示例: cat $config_file >> /etc/caddy/Caddyfile"
    echo "配置验证: caddy validate --config /etc/caddy/Caddyfile"
    echo "重载服务: systemctl reload caddy"
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
        read -e -p "是否继续生成其他配置? [Y/n]: " cont
        cont=${cont:-y}
        if [[ "$cont" =~ ^[Nn] ]]; then
            print_color "再见！" "$GREEN"
            exit 0
        fi
    done
}

# 运行主程序
main
