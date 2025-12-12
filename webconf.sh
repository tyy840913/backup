#!/bin/bash

# ==========================================
# Web服务器配置生成器 (v3.0 高级映射版)
# ==========================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 全局变量
declare -a PROXY_MAPPINGS 
# 存储映射，格式: TYPE|MATCHER|BACKEND_URL/ROOT_PATH|SET_HOST_BOOL
# TYPE: ROOT_STATIC, ROOT_PROXY, PATH_PROXY, SUBDOMAIN_PROXY

# 打印带颜色的消息
print_color() {
    echo -e "${2}${1}${NC}"
}

# 显示标题
print_title() {
    echo "=========================================="
    echo "    Web服务器配置生成器 (v3.0 高级映射)"
    echo "=========================================="
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

# 验证函数 (省略，与v2.1一致，确保代码完整性)
validate_port() {
    local port=$1
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        return 1
    fi
    return 0
}
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0
    else
        return 1
    fi
}
validate_domain() {
    local domain=$1
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}
# ==========================================

# 智能路径规范化: 强制左斜杠，去除右斜杠
normalize_path() {
    local path=$1
    # 1. Strip potential leading '/'
    path=${path#/}
    # 2. Strip potential trailing '/'
    path=${path%/}
    # 3. Add mandatory leading '/'
    echo "/$path"
}

# 获取后端服务信息 (IP/端口/协议)
get_backend_info() {
    local backend_url=""
    
    while true; do
        echo "请输入后端服务地址"
        echo "支持格式:"
        echo "  - 纯端口: 8080 (自动补全为 http://127.0.0.1:8080)"
        echo "  - IP/域名+端口: 10.0.0.5:3000 / api.local:8080"
        read -p "地址: " backend_input
        
        if [ -z "$backend_input" ]; then
            print_color "错误: 地址不能为空" "$RED"
            continue
        fi

        # 1. 剥离协议头
        backend_input=${backend_input#http://}
        backend_input=${backend_input#https://}
        
        # 2. 仅端口自动补全逻辑
        if [[ "$backend_input" =~ ^[0-9]+$ ]]; then
            if validate_port "$backend_input"; then
                backend_host="127.0.0.1"
                backend_port="$backend_input"
                backend_url="http://${backend_host}:${backend_port}"
                print_color "检测到纯端口输入，自动补全为: $backend_url" "$YELLOW"
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
        
        # 4. 验证与协议选择
        if validate_ip "$backend_host" || [ "$backend_host" == "localhost" ]; then
            backend_url="http://${backend_host}:${backend_port}"
            print_color "检测到IP地址，使用HTTP协议: $backend_url" "$YELLOW"
            break
        elif validate_domain "$backend_host"; then
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
    echo "$backend_url"
}

# 获取通用配置 (端口、SSL、安全、性能)
get_generic_config() {
    echo ""
    print_color "=== Web服务通用配置 ===" "$BLUE"

    # 1. 端口模式
    while true; do
        echo "请选择端口配置模式:"
        echo "1. 标准端口 (80/443，自动HTTP到HTTPS重定向)"
        echo "2. 自定义端口"
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

    # 2. 域名
    echo ""
    read -p "请输入主域名 (多个用空格分隔，留空为localhost): " server_names
    if [ -z "$server_names" ]; then server_names="localhost"; fi

    # 3. SSL配置
    if [ -n "$https_port" ]; then
        echo ""
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
    echo ""
    print_color "=== 性能优化配置 ===" "$BLUE"
    read -e -p "是否应用性能优化（Gzip、静态文件长缓存）? [Y/n]: " enable_perf
    enable_perf=${enable_perf:-y}
    if [[ ! "$enable_perf" =~ ^[Nn] ]]; then
        enable_gzip=true; enable_static_cache=true
    else
        enable_gzip=false; enable_static_cache=false
    fi
}

# 获取反代和静态映射配置 (高级逻辑)
get_proxy_mappings() {
    PROXY_MAPPINGS=() # 清空旧映射
    root_path=""
    
    print_color "=== 映射配置 (根路径 '/') ===" "$BLUE"
    
    # 1. 根路径 (Default) 强制配置
    while true; do
        echo "请定义主域名根路径 '/' 的默认行为:"
        echo "1. 静态网站 (指向本地目录)"
        echo "2. 全站反向代理 (将所有请求代理到后端服务)"
        read -p "请选择 [1-2]: " root_mode
        
        if [ "$root_mode" == "1" ]; then
            read -p "请输入网站根目录 (默认: /var/www/html): " root_path
            [ -z "$root_path" ] && root_path="/var/www/html"
            PROXY_MAPPINGS+=("ROOT_STATIC|/|$root_path|false")
            break
        elif [ "$root_mode" == "2" ]; then
            print_color "--- 全站反代目标 ---" "$YELLOW"
            local backend_url=$(get_backend_info)
            read -e -p "是否传递Host头? (推荐开启) [Y/n]: " pass_host
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
        print_color "=== 添加新的映射 ===" "$BLUE"
        echo "当前已配置 ${#PROXY_MAPPINGS[@]} 个映射"
        
        read -e -p "是否添加额外的路径反代或子域名反代? [Y/n]: " continue_add
        if [[ ! "$continue_add" =~ ^[Yy] ]]; then break; fi
        
        echo "请选择要添加的映射类型:"
        echo "1. 路径反向代理 (例如: /api)"
        echo "2. 子域名反向代理 (例如: api.yourdomain.com)"
        read -p "请选择 [1-2]: " map_type
        
        if [ "$map_type" == "1" ]; then
            # 路径反代
            while true; do
                read -p "请输入路径 (例如: api): " path_input
                local path_matcher=$(normalize_path "$path_input")
                
                # 检查路径是否冲突 (冲突指的是 / 或者已经配置过的路径)
                if [[ "$path_matcher" == "/" ]]; then
                    print_color "错误: 根路径 '/' 已配置，请选择路径反代。" "$RED"
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
            # 子域名反代
            while true; do
                read -p "请输入子域名部分 (例如: api 或 *.dev): " subdomain_input
                if [ -z "$subdomain_input" ]; then
                    print_color "子域名不能为空" "$RED"
                else
                    break
                fi
            done
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

# 自动复制Nginx配置文件 (与v2.1一致，省略)
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
    echo "# 主域名: $server_names" >> "$config_file"
    echo "" >> "$config_file"
    
    # --- 1. 定义所有要生成的 server_name 列表 ---
    declare -a all_nginx_server_blocks
    
    # a. 添加主域名块 (包括所有主域名)
    all_nginx_server_blocks+=("MAIN|$server_names")
    
    # b. 添加子域名块
    for mapping in "${PROXY_MAPPINGS[@]}"; do
        IFS='|' read -r type matcher backend_url set_host <<< "$mapping"
        if [ "$type" == "SUBDOMAIN_PROXY" ]; then
            local sub_server_names=""
            for domain in $server_names; do
                if [ "$matcher" == "*" ]; then
                    sub_server_names+=" $matcher.${domain} www.$matcher.${domain}"
                else
                    sub_server_names+=" ${matcher}.${domain}"
                fi
            done
            # Subdomains use the same port settings as main domain
            all_nginx_server_blocks+=("SUB|$sub_server_names")
        fi
    done
    
    # --- 2. 循环生成 server block ---
    
    for block_info in "${all_nginx_server_blocks[@]}"; do
        IFS='|' read -r block_type block_server_names <<< "$block_info"
        
        # --- HTTP 重定向块 ---
        if [ -n "$http_port" ] && [ "$enable_301_redirect" = true ] && [ -n "$https_port" ]; then
            echo "server {" >> "$config_file"
            echo "    listen $http_port;" >> "$config_file"
            echo "    listen [::]:$http_port;" >> "$config_file"
            echo "    server_name $block_server_names;" >> "$config_file"
            echo "    return 301 https://\$host\$request_uri;" >> "$config_file"
            echo "}" >> "$config_file"
            echo "" >> "$config_file"
        fi
        
        # --- 主配置块 (HTTPS/HTTP) ---
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
        echo "" >> "$config_file"
        
        # SSL配置 (仅HTTPS)
        if [ -n "$https_port" ]; then
            echo "    ssl_certificate $ssl_cert;" >> "$config_file"
            echo "    ssl_certificate_key $ssl_key;" >> "$config_file"
            echo "    ssl_protocols TLSv1.2 TLSv1.3;" >> "$config_file"
            # 简化或高级加密套件
            [ "$strong_security" = true ] && echo "    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:..." >> "$config_file" || echo "    ssl_ciphers HIGH:!aNULL:!MD5;" >> "$config_file"
            [ "$enable_hsts" = true ] && echo "    add_header Strict-Transport-Security \"max-age=31536000; includeSubDomains\" always;" >> "$config_file"
            [ "$enable_ocsp" = true ] && echo "    ssl_stapling on; ssl_stapling_verify on;" >> "$config_file"
            echo "" >> "$config_file"
        fi
        
        # 通用头
        echo "    add_header X-Frame-Options \"SAMEORIGIN\" always;" >> "$config_file"
        
        # 性能优化 (仅适用于主块或静态块)
        if [ "$enable_gzip" = true ]; then
            echo "    gzip on; gzip_types text/plain text/css application/json application/javascript text/xml;" >> "$config_file"
        fi
        
        # --- Location 映射 ---
        for mapping in "${PROXY_MAPPINGS[@]}"; do
            IFS='|' read -r type matcher backend_url root_or_set_host <<< "$mapping"
            
            # 路径反代/根路径/静态配置 只在 主域名 server block 中处理
            if [ "$block_type" == "MAIN" ]; then
                if [ "$type" == "PATH_PROXY" ] || [ "$type" == "ROOT_PROXY" ]; then
                    local set_host=$root_or_set_host
                    echo "    location ${matcher} {" >> "$config_file"
                    echo "        proxy_pass $backend_url;" >> "$config_file"
                    [ "$set_host" = "true" ] && echo "        proxy_set_header Host \$host;" >> "$config_file"
                    echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$config_file"
                    echo "        proxy_set_header Upgrade \$http_upgrade;" >> "$config_file"
                    echo "        proxy_set_header Connection \"upgrade\";" >> "$config_file"
                    echo "    }" >> "$config_file"
                elif [ "$type" == "ROOT_STATIC" ]; then
                    local root_path=$root_or_set_host
                    echo "    root $root_path;" >> "$config_file"
                    echo "    index index.html index.htm;" >> "$config_file"
                    echo "" >> "$config_file"
                    echo "    location / {" >> "$config_file"
                    echo "        try_files \$uri \$uri/ =404;" >> "$config_file"
                    echo "    }" >> "$config_file"
                    
                    if [ "$enable_static_cache" = true ]; then
                        echo "    location ~* \.(jpg|png|css|js|woff) { expires 1y; add_header Cache-Control \"public, immutable\"; }" >> "$config_file"
                    fi
                fi
            fi
            
            # 子域名反代 只在 子域名 server block 中处理
            if [ "$block_type" == "SUB" ] && [ "$type" == "SUBDOMAIN_PROXY" ]; then
                 local sub_matcher=$(echo "$block_server_names" | awk '{print $1}') # 取第一个子域名作为判断依据
                 if [[ "$sub_matcher" == *"${matcher}"* ]]; then
                    local set_host=$root_or_set_host
                    echo "    location / {" >> "$config_file" # 子域名块默认代理整个 /
                    echo "        proxy_pass $backend_url;" >> "$config_file"
                    [ "$set_host" = "true" ] && echo "        proxy_set_header Host \$host;" >> "$config_file"
                    echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$config_file"
                    echo "        proxy_set_header Upgrade \$http_upgrade;" >> "$config_file"
                    echo "        proxy_set_header Connection \"upgrade\";" >> "$config_file"
                    echo "    }" >> "$config_file"
                    break # 跳出内层循环，因为子域名块已完成
                 fi
            fi
        done
        
        echo "}" >> "$config_file"
        echo "" >> "$config_file"
    done
    
    print_color "Nginx配置文件已生成: $config_file" "$GREEN"
    copy_nginx_config "$config_file"
}

# 生成Caddy配置 (简化，Caddyfile在一个文件中处理所有域名)
generate_caddy_config() {
    config_file="caddy_${server_names%% *}_$(date +%Y%m%d_%H%M%S).caddyfile"
    
    echo "# Caddy配置文件 - 生成于 $(date)" > "$config_file"
    
    # Caddy 主块 (包含主域名和所有子域名)
    local all_domains="$server_names"
    for mapping in "${PROXY_MAPPINGS[@]}"; do
        IFS='|' read -r type matcher backend_url set_host <<< "$mapping"
        if [ "$type" == "SUBDOMAIN_PROXY" ]; then
            for domain in $server_names; do
                all_domains+=" ${matcher}.${domain}"
            done
        fi
    done
    
    echo "$all_domains {" >> "$config_file"
    
    # 端口和重定向 (Caddy自动处理443/80，无需手动写)
    if [ -n "$http_port" ] && [ "$enable_301_redirect" = true ]; then
        echo "    # Caddy默认会自动将 HTTP 重定向到 HTTPS" >> "$config_file"
    fi
    if [ -n "$https_port" ]; then
        echo "    # Caddy会自动签发并管理证书" >> "$config_file"
    fi
    
    # 通用头
    echo "    header X-Frame-Options SAMEORIGIN" >> "$config_file"
    [ "$enable_hsts" = true ] && echo "    header Strict-Transport-Security \"max-age=31536000; includeSubDomains; preload\"" >> "$config_file"
    
    # 性能
    [ "$enable_gzip" = true ] && echo "    encode gzip zstd" >> "$config_file"

    # --- 映射列表 ---
    for mapping in "${PROXY_MAPPINGS[@]}"; do
        IFS='|' read -r type matcher backend_url root_or_set_host <<< "$mapping"
        
        if [ "$type" == "ROOT_STATIC" ]; then
            local root_path=$root_or_set_host
            echo "    root * $root_path" >> "$config_file"
            echo "    file_server" >> "$config_file"
            [ "$enable_static_cache" = true ] && echo "    header * Cache-Control \"public, max-age=31536000, immutable\"" >> "$config_file"
            
        elif [ "$type" == "ROOT_PROXY" ] || [ "$type" == "PATH_PROXY" ]; then
            local set_host=$root_or_set_host
            # Caddy路径匹配要求左侧斜杠，右侧星号匹配 (但我们只匹配精确路径，所以不需要星号)
            echo "    reverse_proxy ${matcher} $backend_url {" >> "$config_file"
            [ "$set_host" = "true" ] && echo "        header_up Host {host}" >> "$config_file"
            echo "        header_up X-Real-IP {remote_host}" >> "$config_file"
            echo "    }" >> "$config_file"

        elif [ "$type" == "SUBDOMAIN_PROXY" ]; then
            local set_host=$root_or_set_host
            # Caddy 子域名反代需要一个新的 block，但为了简化，这里假设 Caddy 会将所有子域名合并处理 (这在 Caddy 中是默认行为)
            # 或者我们必须为每个子域名单独创建一个 block
            # 考虑到 Nginx 已经拆分了，Caddy 也应该拆分以确保配置明确
            
            # --- Caddy 必须为 SUBDOMAIN 创建独立块 ---
            # 暂时跳过 SUBDOMAIN PROXY 在主块中的处理，稍后单独生成
            : # do nothing
        fi
    done
    
    echo "}" >> "$config_file"
    echo "" >> "$config_file"
    
    # --- 单独生成子域名块 ---
    for mapping in "${PROXY_MAPPINGS[@]}"; do
        IFS='|' read -r type matcher backend_url set_host <<< "$mapping"
        if [ "$type" == "SUBDOMAIN_PROXY" ]; then
            for domain in $server_names; do
                local sub_domain="${matcher}.${domain}"
                echo "${sub_domain} {" >> "$config_file"
                echo "    reverse_proxy $backend_url {" >> "$config_file"
                [ "$set_host" = "true" ] && echo "        header_up Host {host}" >> "$config_file"
                echo "        header_up X-Real-IP {remote_host}" >> "$config_file"
                echo "    }" >> "$config_file"
                echo "}" >> "$config_file"
                echo "" >> "$config_file"
            done
        fi
    done
    
    print_color "Caddy配置文件已生成: $config_file" "$GREEN"
    # Caddy安装逻辑 (省略，与v2.1一致)
}

# 主程序
main() {
    while true; do
        # 1. 通用配置 (端口、SSL、安全、性能)
        get_generic_config
        
        # 2. 映射配置 (根路径、路径/子域名反代)
        get_proxy_mappings
        
        # 3. 服务器类型选择与生成
        show_menu
        read -p "请选择 [1-3]: " choice
        
        case $choice in
            1) generate_nginx_config ;;
            2) generate_caddy_config ;;
            3) print_color "再见！" "$GREEN"; exit 0 ;;
            *) print_color "无效选择，请重试" "$RED"; continue ;;
        esac
        
        echo ""
        read -e -p "是否继续生成其他配置? (将清空当前所有输入状态) [Y/n]: " cont
        [[ "$cont" =~ ^[Nn] ]] && break
    done
    print_color "再见！" "$GREEN"
}

main