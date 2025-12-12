#!/bin/bash

# =======================================================
# Web服务器配置生成器 (v6.0 修复配置填充错误/优化流程)
# =======================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 全局变量
declare -a PROXY_MAPPINGS 
# 存储映射，格式: TYPE|MATCHER|BACKEND_URL/ROOT_PATH|SET_HOST_BOOL

# 打印带颜色的消息 (重定向到 stderr 以防被变量捕获)
print_color() {
    echo -e "${2}${1}${NC}" >&2
}

# 显示标题
print_title() {
    echo "==========================================" >&2
    echo " Web服务器配置生成器 (v6.0 修复填充版)" >&2
    echo "==========================================" >&2
    echo "" >&2
}

# 显示菜单 (用于选择 Nginx 或 Caddy)
show_menu() {
    print_title
    echo "请选择要生成的服务器配置:"
    echo "1. Nginx"
    echo "2. Caddy"
    echo "3. 退出"
    echo ""
}

# =======================================================
# 模块一: 输入与校验 (自动补全、去重、格式校验)
# =======================================================

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
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

# 智能路径规范化: 强制左斜杠，去除右斜杠
normalize_path() {
    local path=$1
    # 1. 去除开头的 '/'
    path=${path#/}
    # 2. 去除末尾的 '/'
    path=${path%/}
    # 3. 添加强制的开头的 '/'
    echo "/$path"
}

# 获取后端服务信息 (IP/端口/协议 自动补全)
# *** 核心修复: 将所有提示信息重定向到标准错误 (>&2) 或使用 print_color，
# *** 确保只有最终的 URL 被函数调用者捕获。
get_backend_info() {
    local backend_url=""
    
    while true; do
        echo "请输入后端服务地址" >&2
        echo "支持格式: 8080 (自动补全为 http://127.0.0.1:8080) 或 192.168.1.1:8000" >&2
        read -p "地址: " backend_input
        
        if [ -z "$backend_input" ]; then print_color "错误: 地址不能为空" "$RED"; continue; fi

        # 1. 剥离协议头
        backend_input=${backend_input#http://}
        backend_input=${backend_input#https://}
        
        # 2. 纯端口自动补全逻辑
        if [[ "$backend_input" =~ ^[0-9]+$ ]]; then
            if validate_port "$backend_input"; then
                backend_url="http://127.0.0.1:${backend_input}"
                print_color "自动补全为: $backend_url" "$YELLOW"
                break
            else
                print_color "错误: 端口无效" "$RED"
                continue
            fi
        fi

        # 3. 常规 Host:Port 解析
        if [[ "$backend_input" =~ :[0-9]+$ ]]; then
            backend_host=$(echo "$backend_input" | cut -d: -f1)
            backend_port=$(echo "$backend_input" | cut -d: -f2)
        else
            backend_host="$backend_input"
            backend_port="80"
        fi
        
        # 4. 协议选择
        if validate_ip "$backend_host" || [ "$backend_host" == "localhost" ]; then
            backend_url="http://${backend_host}:${backend_port}"
        elif validate_domain "$backend_host"; then
            echo "检测到域名，请选择后端协议 (1. HTTP / 2. HTTPS):" >&2
            read -p "请选择 [1-2]: " protocol_choice
            protocol_choice=${protocol_choice:-1}
            [ "$protocol_choice" == "2" ] && backend_url="https://${backend_host}:${backend_port}" || backend_url="http://${backend_host}:${backend_port}"
        else
            print_color "错误: Host格式无效" "$RED"
            continue
        fi
        break
    done
    
    # 确保只有最终结果进入标准输出，被 $(...) 捕获
    echo "$backend_url"
}

# 自动复制Nginx配置文件 (保持不变)
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
                print_color "配置测试失败，请手动检查文件！已自动清理链接。" "$RED"
                sudo rm -f "/etc/nginx/sites-enabled/$config_file"
            fi
        else
            print_color "错误: Nginx sites-available/sites-enabled 目录不存在" "$RED"
        fi
    fi
}

# 获取通用配置 (端口、SSL、安全、性能 - 收集输入)
get_generic_config() {
    # 确保变量在每次运行时清空
    http_port=""
    https_port=""
    server_names=""
    ssl_cert=""
    ssl_key=""
    enable_301_redirect=false
    need_497=false
    enable_hsts=false
    strong_security=false
    enable_gzip=false
    enable_static_cache=false

    echo "" >&2
    print_color "=== Web服务通用配置 ===" "$BLUE"

    # 1. 端口模式选择
    while true; do
        echo "请选择端口配置模式: 1. 标准(80/443) 2. 自定义" >&2
        read -p "请选择 [1-2]: " port_mode
        case $port_mode in
            1) http_port=80; https_port=443; enable_301_redirect=true; break ;;
            2)
                read -p "请输入监听端口: " custom_port
                if ! validate_port "$custom_port"; then continue; fi
                read -p "是否启用HTTPS (SSL)? [Y/n]: " enable_ssl
                enable_ssl=${enable_ssl:-y}
                if [[ ! "$enable_ssl" =~ ^[Nn] ]]; then
                    http_port=""; https_port=$custom_port
                    [ "$https_port" -ne 443 ] && need_497=true || need_497=false
                else
                    http_port=$custom_port; https_port=""
                fi
                enable_301_redirect=false
                break
                ;;
            *) print_color "无效选择" "$RED" ;;
        esac
    done

    # 2. 域名输入
    echo "" >&2
    read -p "请输入主域名 (多个用空格分隔，留空为localhost): " server_names
    if [ -z "$server_names" ]; then server_names="localhost"; fi

    # 3. SSL配置 (如果启用HTTPS)
    if [ -n "$https_port" ]; then
        echo "" >&2
        print_color "=== SSL/安全配置 ===" "$BLUE"
        read -p "SSL证书路径 (默认: /etc/ssl/certs/fullchain.pem): " ssl_cert
        [ -z "$ssl_cert" ] && ssl_cert="/etc/ssl/certs/fullchain.pem"
        read -p "SSL私钥路径 (默认: /etc/ssl/private/privkey.key): " ssl_key
        [ -z "$ssl_key" ] && ssl_key="/etc/ssl/private/privkey.key"
        
        read -e -p "是否应用推荐的安全配置(HSTS/OCSP/TLS1.2+)? [Y/n]: " enable_security
        enable_security=${enable_security:-y}
        if [[ ! "$enable_security" =~ ^[Nn] ]]; then
            enable_hsts=true; enable_ocsp=true; strong_security=true
        else
            enable_hsts=false; enable_ocsp=false; strong_security=false
        fi
    fi

    # 4. 性能优化
    echo "" >&2
    print_color "=== 性能优化配置 ===" "$BLUE"
    read -e -p "是否应用性能优化（Gzip、静态文件长缓存）? [Y/n]: " enable_perf
    enable_perf=${enable_perf:-y}
    if [[ ! "$enable_perf" =~ ^[Nn] ]]; then
        enable_gzip=true; enable_static_cache=true
    else
        enable_gzip=false; enable_static_cache=false
    fi
}

# 获取反代和静态映射配置 (逻辑保持不变)
get_proxy_mappings() {
    PROXY_MAPPINGS=() # 清空旧映射
    
    print_color "=== 映射配置 (根路径 '/') ===" "$BLUE"
    
    # 1. 根路径 (Default) 强制配置
    while true; do
        echo "请定义主域名根路径 '/' 的默认行为: 1. 静态网站 2. 全站反向代理" >&2
        read -p "请选择 [1-2]: " root_mode
        
        if [ "$root_mode" == "1" ]; then
            read -p "请输入网站根目录 (默认: /var/www/html): " root_path
            [ -z "$root_path" ] && root_path="/var/www/html"
            PROXY_MAPPINGS+=("ROOT_STATIC|/|$root_path|false")
            break
        elif [ "$root_mode" == "2" ]; then
            print_color "--- 全站反代目标 ---" "$YELLOW"
            # get_backend_info 现在只会输出 URL，不会污染 stdout
            local backend_url=$(get_backend_info)
            read -e -p "是否传递Host头? [Y/n]: " pass_host
            pass_host=${pass_host:-y}
            local set_host=$([[ ! "$pass_host" =~ ^[Nn] ]] && echo "true" || echo "false")
            PROXY_MAPPINGS+=("ROOT_PROXY|/|$backend_url|$set_host")
            break
        else
            print_color "无效选择" "$RED"
        fi
    done
    
    # 2. 循环添加其他映射
    while true; do
        echo "" >&2
        print_color "=== 添加额外的映射 ===" "$BLUE"
        echo "当前已配置 ${#PROXY_MAPPINGS[@]} 个映射" >&2
        
        echo "请选择要添加的映射类型: 1. 路径反向代理 2. 子域名反向代理 3. 完成" >&2
        read -p "请选择 [1-3]: " map_type
        
        if [ "$map_type" == "3" ]; then break; fi
        
        if [ "$map_type" == "1" ]; then
            while true; do
                read -p "请输入路径 (例如: api): " path_input
                local path_matcher=$(normalize_path "$path_input")
                if [[ "$path_matcher" == "/" ]]; then
                    print_color "错误: 根路径 '/' 已配置。" "$RED"
                else
                    break
                fi
            done
            print_color "--- 路径反代目标 ---" "$YELLOW"
            local backend_url=$(get_backend_info)
            read -e -p "是否传递Host头? [Y/n]: " pass_host
            pass_host=${pass_host:-y}
            local set_host=$([[ ! "$pass_host" =~ ^[Nn] ]] && echo "true" || echo "false")
            PROXY_MAPPINGS+=("PATH_PROXY|$path_matcher|$backend_url|$set_host")
            print_color ">> 路径反代 [$path_matcher] -> [$backend_url] 已添加" "$GREEN"
            
        elif [ "$map_type" == "2" ]; then
            read -p "请输入子域名部分 (例如: api 或 *): " subdomain_input
            if [ -z "$subdomain_input" ]; then print_color "子域名不能为空" "$RED"; continue; fi
            print_color "--- 子域名反代目标 ---" "$YELLOW"
            local backend_url=$(get_backend_info)
            read -e -p "是否传递Host头? [Y/n]: " pass_host
            pass_host=${pass_host:-y}
            local set_host=$([[ ! "$pass_host" =~ ^[Nn] ]] && echo "true" || echo "false")
            PROXY_MAPPINGS+=("SUBDOMAIN_PROXY|$subdomain_input|$backend_url|$set_host")
            print_color ">> 子域名反代 [$subdomain_input.*] -> [$backend_url] 已添加" "$GREEN"
        else
            print_color "无效选择，请重试" "$RED"
        fi
    done
}


# =======================================================
# 模块二: Nginx 通用配置生成 (可共享的配置项)
# =======================================================

# Nginx 通用 SSL/TLS 配置生成
generate_nginx_ssl_config() {
    local config=""
    if [ -n "$https_port" ]; then
        config+="\n    # 通用 SSL/TLS 配置 (适用于所有 HTTPS 监听块)\n"
        config+="    ssl_certificate $ssl_cert;\n"
        config+="    ssl_certificate_key $ssl_key;\n"
        
        # 性能优化: SSL会话缓存
        config+="    ssl_session_timeout 1d;\n"
        config+="    ssl_session_cache shared:SSL:10m;\n"
        
        config+="    ssl_protocols TLSv1.2 TLSv1.3;\n"
        
        if [ "$strong_security" = true ]; then
            # 官方推荐的现代高安全性密码套件
            config+="    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';\n"
            config+="    ssl_prefer_server_ciphers off;\n"
        else
            config+="    ssl_ciphers HIGH:!aNULL:!MD5;\n"
        fi
        
        [ "$enable_ocsp" = true ] && config+="    ssl_stapling on; ssl_stapling_verify on; resolver 8.8.8.8 8.8.4.4 valid=300s; resolver_timeout 5s;\n"
    fi
    echo -e "$config"
}

# Nginx 通用安全/性能头和Gzip配置生成
generate_nginx_security_and_performance() {
    local config=""
    config+="\n    # 通用安全/性能头配置\n"
    config+="    add_header X-Frame-Options \"SAMEORIGIN\" always;\n"
    [ "$enable_hsts" = true ] && config+="    add_header Strict-Transport-Security \"max-age=31536000; includeSubDomains\" always; # HSTS\n"

    if [ "$enable_gzip" = true ]; then
        config+="    gzip on;\n"
        config+="    gzip_comp_level 5;\n"
        config+="    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;\n"
        config+="    gzip_min_length 256;\n"
    fi
    echo -e "$config\n"
}

# =======================================================
# 模块三: Caddy 通用配置生成 (可共享的配置项)
# =======================================================

# Caddy 通用安全/性能配置生成
generate_caddy_security_and_performance() {
    local config=""
    
    # 自动处理 HTTPS/证书/重定向 (如果 https_port 存在)
    if [ -n "$https_port" ]; then
        config+="    # Caddy会自动处理 80 -> 443 的重定向和证书签发\n"
        # 如果使用自定义证书路径，则配置tls
        if [ -n "$ssl_cert" ] && [ "$ssl_cert" != "/etc/ssl/certs/fullchain.pem" ]; then
            config+="    tls $ssl_cert $ssl_key\n"
        fi
    fi
    
    # 通用头 (Caddy最佳实践)
    config+="    header {\n"
    config+="        X-Frame-Options SAMEORIGIN\n"
    [ "$enable_hsts" = true ] && config+="        Strict-Transport-Security \"max-age=31536000; includeSubDomains; preload\"\n"
    config+="    }\n"
    
    # 性能 (Caddy默认支持 Gzip 和 Zstd)
    [ "$enable_gzip" = true ] && config+="    encode gzip zstd\n"
    
    echo -e "$config"
}


# =======================================================
# 模块四: 主配置生成器 (专注于反代/静态逻辑关系)
# =======================================================

# 生成Nginx配置
generate_nginx_config() {
    local config_file="nginx_${server_names%% *}_$(date +%Y%m%d_%H%M%S).conf"
    
    echo "# Nginx配置文件 - 生成于 $(date)" > "$config_file"
    echo "# 遵循模块化设计，通用配置已单独提取" >> "$config_file"
    echo "" >> "$config_file"

    # --- 1. 定义所有 server_name 列表 ---
    declare -a all_nginx_server_blocks
    local all_server_names="$server_names"
    all_nginx_server_blocks+=("MAIN|$server_names")
    
    for mapping in "${PROXY_MAPPINGS[@]}"; do
        IFS='|' read -r type matcher backend_url set_host <<< "$mapping"
        if [ "$type" == "SUBDOMAIN_PROXY" ]; then
            local sub_server_names=""
            for domain in $server_names; do
                local full_sub_domain="${matcher}.${domain}"
                sub_server_names+=" ${full_sub_domain}"
                all_server_names+=" ${full_sub_domain}"
            done
            all_nginx_server_blocks+=("SUB|$sub_server_names")
        fi
    done

    # --- 2. 生成 CONSOLIDATED HTTP 重定向块 (IPv4 和 IPv6) ---
    if [ -n "$http_port" ] && [ "$enable_301_redirect" = true ] && [ -n "$https_port" ]; then
        echo "server {" >> "$config_file"
        echo "    # HTTP 重定向到 HTTPS (同时监听 IPv4 和 IPv6)" >> "$config_file"
        echo "    listen $http_port;" >> "$config_file"
        echo "    listen [::]:$http_port;" >> "$config_file" 
        echo "    server_name $all_server_names;" >> "$config_file"
        echo "    return 301 https://\$host\$request_uri;" >> "$config_file"
        echo "}" >> "$config_file"
        echo "" >> "$config_file"
    fi
    
    # --- 3. 循环生成 HTTPS/HTTP 主配置块 (应用通用配置和反代逻辑) ---
    
    local COMMON_SSL_CONFIG=$(generate_nginx_ssl_config)
    local COMMON_SEC_PERF_CONFIG=$(generate_nginx_security_and_performance)
    
    for block_info in "${all_nginx_server_blocks[@]}"; do
        IFS='|' read -r block_type block_server_names <<< "$block_info"
        
        echo "server {" >> "$config_file"
        
        if [ -n "$https_port" ]; then
            echo "    listen ${https_port} ssl http2;" >> "$config_file"
            echo "    listen [::]:${https_port} ssl http2;" >> "$config_file" 
            [ "$need_497" = true ] && echo "    error_page 497 https://\$host:${https_port}\$request_uri;" >> "$config_file"
        elif [ -n "$http_port" ]; then
            echo "    listen $http_port;" >> "$config_file"
            echo "    listen [::]:$http_port;" >> "$config_file" 
        fi
        
        echo "    server_name $block_server_names;" >> "$config_file"
        
        # 插入通用 SSL 配置
        if [ -n "$https_port" ]; then
            echo -e "$COMMON_SSL_CONFIG" >> "$config_file"
        fi
        
        # 插入通用 安全/性能 配置
        echo -e "$COMMON_SEC_PERF_CONFIG" >> "$config_file"
        
        # --- Location 映射 (反代逻辑关系) ---
        for mapping in "${PROXY_MAPPINGS[@]}"; do
            IFS='|' read -r type matcher backend_url root_or_set_host <<< "$mapping"
            
            # 路径反代/根路径/静态配置 只在 主域名 server block (MAIN) 中处理
            if [ "$block_type" == "MAIN" ]; then
                if [ "$type" == "PATH_PROXY" ]; then
                    local set_host=$root_or_set_host
                    
                    echo "    location ${matcher}/ {" >> "$config_file"
                    echo "        # 路径反向代理: Nginx会自动剥离路径尾部的 '/' 并转发" >> "$config_file"
                    echo "        proxy_pass $backend_url/;" >> "$config_file"
                    [ "$set_host" = "true" ] && echo "        proxy_set_header Host \$host;" >> "$config_file"
                    echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$config_file"
                    echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" >> "$config_file"
                    echo "        proxy_set_header Upgrade \$http_upgrade;" >> "$config_file" 
                    echo "        proxy_set_header Connection \"upgrade\";" >> "$config_file" 
                    echo "    }" >> "$config_file"

                elif [ "$type" == "ROOT_PROXY" ]; then
                    local set_host=$root_or_set_host
                    echo "    location / {" >> "$config_file"
                    echo "        # 根路径全站反向代理" >> "$config_file"
                    echo "        proxy_pass $backend_url;" >> "$config_file" 
                    [ "$set_host" = "true" ] && echo "        proxy_set_header Host \$host;" >> "$config_file"
                    echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$config_file"
                    echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" >> "$config_file"
                    echo "        proxy_set_header Upgrade \$http_upgrade;" >> "$config_file" 
                    echo "        proxy_set_header Connection \"upgrade\";" >> "$config_file" 
                    echo "    }" >> "$config_file"

                elif [ "$type" == "ROOT_STATIC" ]; then
                    local root_path=$root_or_set_host
                    echo "    # 静态网站根目录配置" >> "$config_file"
                    echo "    root $root_path;" >> "$config_file"
                    echo "    index index.html index.htm;" >> "$config_file"
                    
                    # 静态文件服务和缓存逻辑
                    echo "    location / {" >> "$config_file"
                    echo "        try_files \$uri \$uri/ =404;" >> "$config_file"
                    echo "    }" >> "$config_file"
                    
                    if [ "$enable_static_cache" = true ]; then
                        echo "    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|eot|ttf|otf|svg|mp4|webm|pdf)$ {" >> "$config_file"
                        echo "        expires 1y;" >> "$config_file"
                        echo "        add_header Cache-Control \"public, immutable\";" >> "$config_file"
                        echo "        try_files \$uri =404;" >> "$config_file"
                        echo "    }" >> "$config_file"
                    fi
                fi
            fi
            
            # 子域名反代 只在 子域名 server block (SUB) 中处理
            if [ "$block_type" == "SUB" ] && [ "$type" == "SUBDOMAIN_PROXY" ]; then
                 local sub_prefix=$(echo "$block_server_names" | awk '{print $1}' | cut -d. -f1) 
                 if [ "$sub_prefix" == "$matcher" ] || [ "$matcher" == "*" ]; then
                    local set_host=$root_or_set_host
                    echo "    location / {" >> "$config_file" 
                    echo "        # 子域名全站反向代理" >> "$config_file"
                    echo "        proxy_pass $backend_url;" >> "$config_file" 
                    [ "$set_host" = "true" ] && echo "        proxy_set_header Host \$host;" >> "$config_file"
                    echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$config_file"
                    echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" >> "$config_file"
                    echo "        proxy_set_header Upgrade \$http_upgrade;" >> "$config_file" 
                    echo "        proxy_set_header Connection \"upgrade\";" >> "$config_file" 
                    echo "    }" >> "$config_file"
                    break 
                 fi
            fi
        done
        
        echo "}" >> "$config_file"
        echo "" >> "$config_file"
    done
    
    print_color "Nginx配置文件已生成: $config_file" "$GREEN"
    copy_nginx_config "$config_file"
}

# 生成Caddy配置 (保持不变，Caddy天然支持IPv6)
generate_caddy_config() {
    local config_file="caddy_${server_names%% *}_$(date +%Y%m%d_%H%M%S).caddyfile"
    
    echo "# Caddy配置文件 - 生成于 $(date)" > "$config_file"
    echo "# 遵循模块化设计，通用配置已单独提取" >> "$config_file"
    echo "# Caddy 默认支持 IPv6，无需单独配置 listen [::]:<port>" >> "$config_file"
    echo "" >> "$config_file"
    
    # --- 1. 定义所有要生成的 Caddy Block ---
    declare -a all_caddy_blocks
    local all_domains="$server_names"
    all_caddy_blocks+=("MAIN|$all_domains")
    
    for mapping in "${PROXY_MAPPINGS[@]}"; do
        IFS='|' read -r type matcher backend_url set_host <<< "$mapping"
        if [ "$type" == "SUBDOMAIN_PROXY" ]; then
            for domain in $server_names; do
                local sub_domain="${matcher}.${domain}"
                all_caddy_blocks+=("SUB|$sub_domain")
            done
        fi
    done
    
    # --- 2. 循环生成 Caddy block (应用通用配置和反代逻辑) ---
    local COMMON_SEC_PERF_CONFIG=$(generate_caddy_security_and_performance)
    
    for block_info in "${all_caddy_blocks[@]}"; do
        IFS='|' read -r block_type block_server_names <<< "$block_info"
        
        echo "$block_server_names {" >> "$config_file"
        
        # 插入通用 安全/性能 配置
        echo -e "$COMMON_SEC_PERF_CONFIG" >> "$config_file"
        
        # --- 映射列表 (反代逻辑关系) ---
        for mapping in "${PROXY_MAPPINGS[@]}"; do
            IFS='|' read -r type matcher backend_url root_or_set_host <<< "$mapping"
            
            if [ "$block_type" == "MAIN" ]; then
                # 静态根目录
                if [ "$type" == "ROOT_STATIC" ]; then
                    local root_path=$root_or_set_host
                    echo "    root * $root_path" >> "$config_file"
                    echo "    file_server" >> "$config_file"
                    
                    # 静态文件缓存
                    if [ "$enable_static_cache" = true ]; then
                        echo "    header /\.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|eot|ttf|otf|svg|mp4|webm|pdf)$ Cache-Control \"public, max-age=31536000, immutable\"" >> "$config_file"
                    fi
                    
                # 全站代理或路径代理
                elif [ "$type" == "ROOT_PROXY" ] || [ "$type" == "PATH_PROXY" ]; then
                    local set_host=$root_or_set_host
                    local path_match=$matcher
                    
                    echo "    # 反向代理: $path_match* 到 $backend_url" >> "$config_file"
                    echo "    reverse_proxy $path_match* $backend_url {" >> "$config_file"
                    [ "$set_host" = "true" ] && echo "        header_up Host {host}" >> "$config_file"
                    echo "    }" >> "$config_file"
                fi
            
            elif [ "$block_type" == "SUB" ] && [ "$type" == "SUBDOMAIN_PROXY" ]; then
                 local sub_domain=$(echo "$block_server_names" | awk '{print $1}')
                 if [[ "$sub_domain" == *"$matcher".* ]]; then
                    local set_host=$root_or_set_host
                    echo "    # 子域名全站反向代理到 $backend_url" >> "$config_file"
                    echo "    reverse_proxy $backend_url {" >> "$config_file"
                    [ "$set_host" = "true" ] && echo "        header_up Host {host}" >> "$config_file"
                    echo "    }" >> "$config_file"
                    break
                 fi
            fi
        done
        
        echo "}" >> "$config_file"
        echo "" >> "$config_file"
    done
    
    print_color "Caddy配置文件已生成: $config_file" "$GREEN"
    
    # Caddy安装逻辑 (简单复制和验证)
    read -e -p "是否将配置内容追加到 /etc/caddy/Caddyfile 并验证? [Y/n]: " install_choice
    install_choice=${install_choice:-y}
    if [[ ! "$install_choice" =~ ^[Nn] ]]; then
        if [ -f "/etc/caddy/Caddyfile" ]; then
            echo "" >> "/etc/caddy/Caddyfile"
            cat "$config_file" >> "/etc/caddy/Caddyfile"
            
            if sudo caddy validate --config /etc/caddy/Caddyfile; then
                print_color "配置验证成功！请手动重载 Caddy 服务。" "$GREEN"
            else
                print_color "配置验证失败，请手动检查 /etc/caddy/Caddyfile 中的错误！" "$RED"
            fi
        else
            print_color "错误: Caddyfile 路径 /etc/caddy/Caddyfile 不存在" "$RED"
        fi
    fi
}

# 主程序 (已优化流程)
main() {
    while true; do
        
        # 1. 服务器类型选择 (Nginx/Caddy) - 放在最前面
        show_menu
        read -p "请选择 [1-3]: " choice

        case $choice in
            1 | 2)
                # 2. 获取所有通用配置 (端口、SSL、安全、性能)
                get_generic_config
                
                # 3. 获取所有映射配置 (根路径、路径/子域名反代)
                get_proxy_mappings
                
                # 4. 生成配置
                if [ "$choice" == "1" ]; then
                    generate_nginx_config
                else
                    generate_caddy_config
                fi
                ;;
            3)
                print_color "再见！" "$GREEN"; exit 0
                ;;
            *)
                print_color "无效选择，请重试" "$RED"; continue
                ;;
        esac
        
        echo ""
        read -e -p "是否继续生成其他配置? (将清空当前所有输入状态) [Y/n]: " cont
        [[ "$cont" =~ ^[Nn] ]] && break
    done
    print_color "再见！" "$GREEN"
}

main