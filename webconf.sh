#!/bin/bash

# =======================================================
# Web服务器配置生成器 (v1.0.2 - 增强版)
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
config_output_file=""  # 自定义输出文件名
ssl_auto_found="false" # 标记是否成功自动找到证书

# 打印带颜色的消息 (重定向到 stderr 以防被变量捕获)
print_color() {
    echo -e "${2}${1}${NC}" >&2
}

# 显示标题
print_title() {
    echo "============================================" >&2
    echo " Web服务器配置生成器 (v1.0.2 增强版)" >&2
    echo "============================================" >&2
    echo "" >&2
}

# 显示主菜单 (用于选择 Nginx 或 Caddy)
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
validate_domain() {
    if [[ ! "$1" =~ ^[a-zA-Z0-9.-]+$ ]]; then
        print_color "错误: 域名格式不正确。" "$RED"
        return 1
    fi
    return 0
}

validate_path() {
    if [[ ! "$1" =~ ^/.*$ ]]; then
        print_color "错误: 路径必须以 '/' 开头。" "$RED"
        return 1
    fi
    return 0
}

validate_port() {
    if [[ ! "$1" =~ ^[0-9]+$ ]] || [ "$1" -lt 1 ] || [ "$1" -gt 65535 ]; then
        print_color "错误: 端口号必须是 1 到 65535 之间的数字。" "$RED"
        return 1
    fi
    return 0
}

validate_ip_port() {
    # 允许格式: port, ip:port, host:port, http://host:port
    local input="$1"
    if [[ "$input" =~ ^([0-9]+)$ ]]; then
        return 0 # 纯端口
    elif [[ "$input" =~ ^(http|https):// ]]; then
        return 0 # 完整 URL
    elif [[ "$input" =~ ^[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
        return 0 # host:port
    fi
    print_color "错误: 后端地址格式不正确，应为 port, host:port 或完整的 URL (http(s)://...)" "$RED"
    return 1
}

# =======================================================
# 模块二: 核心配置获取 (SSL 自动查找、端口设置)
# =======================================================

# 智能获取后端地址 (自动补全 127.0.0.1)
get_backend_info() {
    local prompt_msg="$1"
    local result_var="$2"
    local backend_url
    while true; do
        read -p "$prompt_msg (e.g. 8080, 127.0.0.1:8080): " backend_url
        if validate_ip_port "$backend_url"; then
            # 如果只是纯数字端口，自动补全为 http://127.0.0.1:port
            if [[ "$backend_url" =~ ^[0-9]+$ ]]; then
                backend_url="http://127.0.0.1:$backend_url"
            fi
            # 如果是 host:port，自动补全为 http://host:port
            if [[ "$backend_url" =~ ^[a-zA-Z0-9.-]+:[0-9]+$ ]]; then
                backend_url="http://$backend_url"
            fi
            eval "$result_var=\"$backend_url\""
            break
        fi
    done
}

# 证书自动查找增强版 (核心修改在此处)
auto_find_ssl_cert() {
    local domain="$1"
    local cert_var="$2"
    local key_var="$3"
    
    # 只搜索最常用的两个证书工具目录
    local search_dirs=(
        # 1. acme.sh (最常用)
        "$HOME/.acme.sh/$domain"
        "$HOME/.acme.sh/$domain\_ecc"
        "/root/.acme.sh/$domain"
        "/root/.acme.sh/$domain\_ecc"
        
        # 2. certbot (Python写的官方工具)
        "/etc/letsencrypt/live/$domain"
        "/etc/letsencrypt/live/$domain-0001"
    )
    
    local found_cert=""
    local found_key=""
    
    # 证书文件优先级
    local cert_patterns=(
        "fullchain.cer" "fullchain.pem"    # 证书链优先
        "$domain.cer" "$domain.pem"        # 域名命名的证书
        "cert.cer" "cert.pem"              # 通用名称
    )
    
    # 私钥文件优先级  
    local key_patterns=(
        "$domain.key"                       # 域名命名的私钥
        "privkey.pem" "private.key"         # 标准名称
    )
    
    # 先精确搜索已知目录
    for dir in "${search_dirs[@]}"; do
        if [ -d "$dir" ]; then
            # 查找证书文件
            for cert_pattern in "${cert_patterns[@]}"; do
                if [ -f "$dir/$cert_pattern" ]; then
                    found_cert="$dir/$cert_pattern"
                    break
                fi
            done
            
            # 查找私钥文件
            for key_pattern in "${key_patterns[@]}"; do
                if [ -f "$dir/$key_pattern" ]; then
                    found_key="$dir/$key_pattern"
                    break
                fi
            done
            
            if [ -n "$found_cert" ] && [ -n "$found_key" ]; then
                eval "$cert_var=\"$found_cert\""
                eval "$key_var=\"$found_key\""
                print_color "✅ 自动找到证书: $found_cert" "$GREEN"
                print_color "✅ 自动找到私钥: $found_key" "$GREEN"
                return 0
            fi
        fi
    done
    
    # 如果精确搜索失败，在acme.sh目录下进行模糊搜索
    if [ -d "$HOME/.acme.sh" ]; then
        local fuzzy_dir=$(find "$HOME/.acme.sh" -maxdepth 1 -type d -name "*$domain*" | head -1)
        if [ -n "$fuzzy_dir" ] && [ -d "$fuzzy_dir" ]; then
            print_color "🔍 在acme.sh目录下模糊找到: $fuzzy_dir" "$YELLOW"
            
            for cert_pattern in "${cert_patterns[@]}"; do
                if [ -f "$fuzzy_dir/$cert_pattern" ]; then
                    found_cert="$fuzzy_dir/$cert_pattern"
                    break
                fi
            done
            
            for key_pattern in "${key_patterns[@]}"; do
                if [ -f "$fuzzy_dir/$key_pattern" ]; then
                    found_key="$fuzzy_dir/$key_pattern"
                    break
                fi
            done
            
            if [ -n "$found_cert" ] && [ -n "$found_key" ]; then
                eval "$cert_var=\"$found_cert\""
                eval "$key_var=\"$found_key\""
                print_color "✅ 模糊搜索找到证书: $found_cert" "$GREEN"
                print_color "✅ 模糊搜索找到私钥: $found_key" "$GREEN"
                return 0
            fi
        fi
    fi
    
    print_color "❌ 无法自动找到证书，请手动指定路径" "$RED"
    return 1
}

# 获取通用配置 (域名、端口、SSL)
get_generic_config() {
    print_color "--- 1. 站点基础配置 ---" "$BLUE"
    # 获取主域名
    while true; do
        read -p "请输入主域名 (e.g. example.com): " primary_domain
        if validate_domain "$primary_domain"; then
            break
        fi
    done
    
    # 端口选择
    read -p "是否使用标准端口 (HTTP: 80, HTTPS: 443)? [y/N]: " use_standard_port
    use_standard_port=${use_standard_port:-N}
    if [[ "$use_standard_port" =~ ^[Yy]$ ]]; then
        is_https="true"
        listen_port="443"
        listen_port_http="80"
    else
        listen_port_http="" # 非标准模式不监听 80 端口
        # HTTPS 选择
        read -p "是否启用 HTTPS? [Y/n]: " enable_https
        enable_https=${enable_https:-Y}
        if [[ "$enable_https" =~ ^[Yy]$ ]]; then
            is_https="true"
            while true; do
                read -p "请输入 HTTPS 监听端口 (e.g. 8443): " listen_port
                if validate_port "$listen_port"; then break; fi
            done
        else
            is_https="false"
            while true; do
                read -p "请输入 HTTP 监听端口 (e.g. 8080): " listen_port
                if validate_port "$listen_port"; then break; fi
            done
        fi
    fi

    # SSL 证书处理 (仅当启用 HTTPS 时)
    if [ "$is_https" == "true" ]; then
        print_color "--- 2. SSL 证书配置 ---" "$BLUE"
        
        # 尝试自动查找证书
        auto_find_ssl_cert "$primary_domain" ssl_cert_path ssl_key_path
        
        if [ "$ssl_auto_found" == "true" ]; then
            print_color "✅ 自动找到证书路径:" "$GREEN"
            print_color "   证书: $ssl_cert_path" "$GREEN"
            print_color "   私钥: $ssl_key_path" "$GREEN"
        elif [ "$choice" == "2" ] && [[ "$use_standard_port" =~ ^[Yy]$ ]]; then
            print_color "🔔 Caddy 在标准 80/443 端口会自动签发证书，无需手动配置。" "$YELLOW"
            ssl_cert_path="Caddy_Auto"
            ssl_key_path="Caddy_Auto"
        else
            print_color "⚠️ 自动查找证书失败。请手动输入路径或提供自定义根目录。" "$YELLOW"
            read -p "请提供证书文件完整路径: " ssl_cert_path
            read -p "请提供私钥文件完整路径: " ssl_key_path
        fi
    fi

    # 清空映射数组
    PROXY_MAPPINGS=()
    print_color "当前域名: $primary_domain | 监听端口: $listen_port" "$YELLOW"
}

# =======================================================
# 模块三: 映射配置 (反代/静态文件)
# =======================================================

get_proxy_mappings() {
    print_color "--- 3. 映射配置 (反向代理 / 静态文件) ---" "$BLUE"
    
    # 1. 根路径映射 (必须有一个)
    print_color "请配置根路径 '/' 的映射（网站主体）：" "$YELLOW"
    
    while true; do
        read -p "选择映射类型 (1: 静态文件 / 2: 反向代理): " root_type
        if [ "$root_type" == "1" ]; then
            read -p "请输入静态文件根目录（绝对路径，e.g. /var/www/html): " root_path
            PROXY_MAPPINGS+=("ROOT_STATIC|/|$root_path|N")
            break
        elif [ "$root_type" == "2" ]; then
            get_backend_info "请输入 '/' 对应的后端地址" root_backend_url
            read -p "是否设置 'Host' 请求头为 '$primary_domain' (Y/n)? " set_host
            set_host=${set_host:-Y}
            set_host_bool="N"
            if [[ "$set_host" =~ ^[Yy]$ ]]; then
                set_host_bool="Y"
            fi
            PROXY_MAPPINGS+=("ROOT_PROXY|/|$root_backend_url|$set_host_bool")
            break
        else
            print_color "输入无效，请重新输入 1 或 2。" "$RED"
        fi
    done

    # 2. 路径/子域名反代 (可选多个)
    while true; do
        read -p "是否添加其他路径或子域名反向代理? [Y/n]: " add_more
        add_more=${add_more:-N}
        if [[ "$add_more" =~ ^[Yy]$ ]]; then
            
            read -p "选择映射类型 (1: 路径反代 / 2: 子域名反代): " sub_type
            
            if [ "$sub_type" == "1" ]; then
                # 路径反代
                while true; do
                    read -p "请输入匹配路径 (以 / 开头, e.g. /api): " path_match
                    if validate_path "$path_match"; then break; fi
                done
                get_backend_info "请输入 $path_match 对应的后端地址" path_backend_url
                read -p "是否设置 'Host' 请求头为 '$primary_domain' (Y/n)? " set_host
                set_host=${set_host:-Y}
                set_host_bool="N"
                if [[ "$set_host" =~ ^[Yy]$ ]]; then set_host_bool="Y"; fi

                # 确保路径不以斜杠结尾 (Nginx 最佳实践)
                path_match=$(echo "$path_match" | sed 's/\/$//')
                PROXY_MAPPINGS+=("PATH_PROXY|$path_match|$path_backend_url|$set_host_bool")
            
            elif [ "$sub_type" == "2" ]; then
                # 子域名反代
                while true; do
                    read -p "请输入子域名 (e.g. git.example.com): " sub_domain
                    if validate_domain "$sub_domain"; then break; fi
                done
                get_backend_info "请输入 $sub_domain 对应的后端地址" sub_backend_url
                read -p "是否设置 'Host' 请求头为 '$sub_domain' (Y/n)? " set_host
                set_host=${set_host:-Y}
                set_host_bool="N"
                if [[ "$set_host" =~ ^[Yy]$ ]]; then set_host_bool="Y"; fi
                
                PROXY_MAPPINGS+=("SUB_PROXY|$sub_domain|$sub_backend_url|$set_host_bool")

            else
                print_color "输入无效，请重新输入 1 或 2。" "$RED"
            fi
        else
            break
        fi
    done
}

# 自定义文件名
get_filename_choice() {
    read -p "请输入配置文件名称 (默认为 ${primary_domain}.conf/${primary_domain}.caddyfile): " config_name
    if [ -n "$config_name" ]; then
        # 确保文件名只包含字母、数字、点或下划线
        config_output_file=$(echo "$config_name" | tr -cd '[:alnum:]._')
    else
        config_output_file="$primary_domain"
    fi
}

# =======================================================
# 模块四: NGINX 配置生成
# =======================================================

generate_nginx_security_and_performance() {
    cat << EOF
    # 安全和性能优化
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header X-XSS-Protection "1; mode=block";
    
    # 禁用版本显示
    server_tokens off;
    
    # 启用 Gzip 压缩 (按需开启)
    # gzip on;
    # gzip_types text/plain application/javascript text/css application/xml;
    # gzip_min_length 1k;
EOF
}

# Nginx 配置主生成器
generate_nginx_config() {
    print_color "--- 正在生成 Nginx 配置 ---" "$BLUE"
    config_file="${config_output_file}.conf"
    
    # 储存所有 server 块的数组
    declare -a all_nginx_server_blocks=()
    
    # 1. HTTP 重定向块 (如果使用标准端口)
    if [[ "$use_standard_port" =~ ^[Yy]$ ]]; then
        http_redirect_block=$(cat << EOF
server {
    listen 80;
    server_name $primary_domain $(for mapping in "${PROXY_MAPPINGS[@]}"; do
        IFS='|' read -r type matcher backend set_host <<< "$mapping"
        if [ "$type" == "SUB_PROXY" ]; then echo "$matcher"; fi
    done);

    # 强制跳转到 HTTPS
    return 301 https://\$host\$request_uri;
}
EOF
)
        all_nginx_server_blocks+=("$http_redirect_block")
    fi

    # 2. 主要 HTTPS/HTTP 块
    
    # 构造监听行
    listen_line="listen $listen_port"
    if [ "$is_https" == "true" ]; then
        listen_line="$listen_line ssl"
    fi
    
    # 构造 SSL 行
    ssl_lines=""
    if [ "$is_https" == "true" ] && [ "$ssl_cert_path" != "Caddy_Auto" ]; then
        ssl_lines=$(cat << EOF
    ssl_certificate $ssl_cert_path;
    ssl_certificate_key $ssl_key_path;
    ssl_session_cache shared:SSL:10m;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
EOF
)
    fi
    
    # 构造 Location 块
    nginx_locations=""
    for mapping in "${PROXY_MAPPINGS[@]}"; do
        IFS='|' read -r type matcher backend_or_root set_host <<< "$mapping"
        
        if [ "$type" == "ROOT_STATIC" ]; then
            # 静态文件
            nginx_locations+=$(cat << EOF

    # 根路径静态文件映射
    location / {
        root $backend_or_root;
        index index.html index.htm;
        try_files \$uri \$uri/ =404;
    }
EOF
)
        elif [ "$type" == "ROOT_PROXY" ] || [ "$type" == "PATH_PROXY" ]; then
            # 反向代理 (路径反代)
            nginx_locations+=$(cat << EOF

    # 路径反向代理: $matcher -> $backend_or_root
    location $matcher {
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass $backend_or_root; # 注意: 后面没有斜杠，Nginx会传递完整路径
EOF
)
            if [ "$set_host" == "Y" ]; then
                nginx_locations+=$(cat << EOF
        proxy_set_header Host \$host;
EOF
)
            fi
            nginx_locations+="    }"
        fi
    done
    
    # 主要 Server 块
    main_server_block=$(cat << EOF
server {
    $listen_line;
    server_name $primary_domain $(for mapping in "${PROXY_MAPPINGS[@]}"; do
        IFS='|' read -r type matcher backend set_host <<< "$mapping"
        if [ "$type" == "SUB_PROXY" ]; then echo "$matcher"; fi
    done);
    
    # 当非 443 端口收到 HTTP 请求时的错误处理
    error_page 497 = @handle_497;
    location @handle_497 {
        return 301 https://\$host:$listen_port\$request_uri;
    }
    
    $ssl_lines
    $(generate_nginx_security_and_performance)
    
    $nginx_locations
}
EOF
)
    all_nginx_server_blocks+=("$main_server_block")
    
    # 3. 子域名单独的反代 Server 块
    for mapping in "${PROXY_MAPPINGS[@]}"; do
        IFS='|' read -r type matcher backend_or_root set_host <<< "$mapping"
        
        if [ "$type" == "SUB_PROXY" ]; then
            sub_domain="$matcher"
            sub_backend_url="$backend_or_root"
            
            sub_proxy_block=$(cat << EOF
server {
    $listen_line;
    server_name $sub_domain;
    
    # 当非 443 端口收到 HTTP 请求时的错误处理
    error_page 497 = @handle_497;
    location @handle_497 {
        return 301 https://\$host:$listen_port\$request_uri;
    }
    
    $ssl_lines
    $(generate_nginx_security_and_performance)
    
    # 子域名反向代理
    location / {
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass $sub_backend_url;
EOF
)
            if [ "$set_host" == "Y" ]; then
                sub_proxy_block+=$(cat << EOF
        proxy_set_header Host \$host;
EOF
)
            fi
            sub_proxy_block+="    }"
            sub_proxy_block+=$(cat << EOF
}
EOF
)
            all_nginx_server_blocks+=("$sub_proxy_block")
        fi
    done
    
    # 写入文件
    (
    echo "# Nginx 配置生成于 $(date)"
    echo "# ------------------------------------------------------------------"
    for block in "${all_nginx_server_blocks[@]}"; do
        echo "$block"
    done
    echo "# ------------------------------------------------------------------"
    ) > "$config_file"
    
    print_color "✅ Nginx 配置已生成到文件: $config_file" "$GREEN"
    
    # 询问是否应用配置
    read -p "是否尝试将配置放入 /etc/nginx/conf.d/ 并重载 Nginx? [y/N]: " apply_nginx
    if [[ "$apply_nginx" =~ ^[Yy]$ ]]; then
        if [ ! -d "/etc/nginx/conf.d" ]; then
            print_color "错误: 目标目录 /etc/nginx/conf.d 不存在或权限不足。" "$RED"
            return
        fi
        
        sudo cp "$config_file" "/etc/nginx/conf.d/"
        print_color "正在重载 Nginx 服务..." "$YELLOW"
        if sudo nginx -t && sudo systemctl reload nginx; then
            print_color "Nginx 配置已成功应用并重载！" "$GREEN"
            print_color "站点文件: /etc/nginx/conf.d/$config_file" "$BLUE"
        else
            print_color "警告: Nginx 检查或重载失败，请手动检查日志。" "$RED"
        fi
    else
        print_color "已跳过应用，仅生成文件: $config_file" "$YELLOW"
    fi
}

# =======================================================
# 模块五: CADDY 配置生成
# =======================================================

generate_caddy_security_and_performance() {
    cat << EOF
    # 安全和性能优化
    header {
        # 禁用版本显示 (Caddy默认不显示)
        # 常见安全头
        X-Frame-Options "SAMEORIGIN"
        X-Content-Type-Options "nosniff"
        X-XSS-Protection "1; mode=block"
    }
    
    # 启用 Gzip 压缩 (Caddy默认启用 Zstd/Gzip)
    # encode gzip
EOF
}

# Caddy 配置主生成器
generate_caddy_config() {
    print_color "--- 正在生成 Caddy 配置 ---" "$BLUE"
    config_file="${config_output_file}.caddyfile"
    main_caddyfile="/etc/caddy/Caddyfile"
    
    (
    echo "# Caddy 配置生成于 $(date)"
    echo "# ------------------------------------------------------------------"
    
    # 储存所有 Caddy 站点块的数组
    declare -a all_caddy_server_blocks=()
    
    # 1. 构造主域名/端口块
    
    # Caddy Server Name / Port Block
    caddy_server_line="$primary_domain"
    
    if [ "$is_https" == "true" ]; then
        if [[ "$use_standard_port" =~ ^[Yy]$ ]]; then
            # 443/80 端口，Caddy自动管理证书，无需配置证书行
            caddy_server_line="$caddy_server_line"
        else
            # 非标准 HTTPS 端口
            caddy_server_line="$caddy_server_line:$listen_port"
            if [ "$ssl_cert_path" != "Caddy_Auto" ]; then
                # Caddy 配置文件中使用 tls 即可
                caddy_tls_block=$(cat << EOF
    tls $ssl_cert_path $ssl_key_path
EOF
)
            fi
        fi
    else
        # 纯 HTTP 端口
        caddy_server_line="$caddy_server_line:$listen_port"
    fi

    # 包含子域名的 Caddyfile 顶行
    all_server_names="$caddy_server_line $(for mapping in "${PROXY_MAPPINGS[@]}"; do
        IFS='|' read -r type matcher backend set_host <<< "$mapping"
        if [ "$type" == "SUB_PROXY" ]; then 
            if [ "$is_https" == "true" ]; then
                echo "$matcher"
            else
                echo "$matcher:$listen_port"
            fi
        fi
    done)"

    caddy_main_block=$(cat << EOF
$all_server_names {
    # 全局安全/性能
    $(generate_caddy_security_and_performance)
EOF
)
    
    # 路径映射
    for mapping in "${PROXY_MAPPINGS[@]}"; do
        IFS='|' read -r type matcher backend_or_root set_host <<< "$mapping"

        if [ "$type" == "ROOT_STATIC" ]; then
            # 静态文件
            caddy_main_block+=$(cat << EOF
    
    # 根路径静态文件映射
    root * $backend_or_root
    file_server
EOF
)
        elif [ "$type" == "ROOT_PROXY" ] || [ "$type" == "PATH_PROXY" ]; then
            
            # Caddy 反代路径匹配器必须加 * 才能匹配子路径
            caddy_matcher="$matcher*"
            if [ "$type" == "ROOT_PROXY" ]; then
                caddy_matcher="*" # 根路径使用 *
            fi
            
            caddy_main_block+=$(cat << EOF

    # 路径反向代理: $matcher -> $backend_or_root
    reverse_proxy $caddy_matcher $backend_or_root {
EOF
)
            if [ "$set_host" == "Y" ]; then
                caddy_main_block+=$(cat << EOF
        # 设置 Host 请求头
        header_up Host {host}
EOF
)
            fi
            caddy_main_block+=$(cat << EOF
    }
EOF
)
        fi
    done

    # 添加自定义证书配置 (如果是非标准 443 端口)
    if [ -n "$caddy_tls_block" ]; then
        caddy_main_block+=$(echo "$caddy_tls_block")
    fi

    caddy_main_block+=$(cat << EOF
}
EOF
)
    all_caddy_server_blocks+=("$caddy_main_block")

    # 2. 写入配置
    for block in "${all_caddy_server_blocks[@]}"; do
        echo "$block"
    done
    echo "# ------------------------------------------------------------------"
    ) > "$config_file"

    print_color "✅ Caddy 配置已生成到文件: $config_file" "$GREEN"
    
    # 询问是否应用配置
    read -p "是否尝试将配置放入 /etc/caddy/sites/ 并重载 Caddy (需要 root 权限)? [y/N]: " apply_caddy
    if [[ "$apply_caddy" =~ ^[Yy]$ ]]; then
        if [ ! -d "/etc/caddy/sites" ]; then
            print_color "警告: 目标目录 /etc/caddy/sites 不存在，正在尝试创建..." "$YELLOW"
            if ! sudo mkdir -p /etc/caddy/sites; then
                print_color "错误: 无法创建 /etc/caddy/sites 目录，请检查权限。" "$RED"
                return
            fi
        fi
        
        sudo cp "$config_file" "/etc/caddy/sites/"
        
        # 检查主 Caddyfile 是否已经导入
        local import_line="import sites/*"
        if [ ! -f "$main_caddyfile" ]; then
             print_color "警告: 主 Caddyfile ($main_caddyfile) 不存在，正在创建并添加 import 行。" "$YELLOW"
             sudo echo "$import_line" > "$main_caddyfile"
        elif ! grep -q "$import_line" "$main_caddyfile"; then
            print_color "警告: 正在向主 Caddyfile ($main_caddyfile) 添加 import 行。" "$YELLOW"
            sudo echo "$import_line" >> "$main_caddyfile"
        fi
        
        print_color "正在重载 Caddy 服务..." "$YELLOW"
        # 使用 pkill -HUP caddy 或 caddy reload
        if pkill -HUP caddy || caddy reload --config "$main_caddyfile" > /dev/null 2>&1; then
            print_color "Caddy 配置已成功应用并重载！" "$GREEN"
            print_color "站点文件: /etc/caddy/sites/$config_file" "$BLUE"
            print_color "已 import 到: $main_caddyfile" "$BLUE"
        else
            print_color "警告: Caddy 重载失败，请手动检查日志" "$YELLOW"
        fi
    else
        print_color "已跳过应用，仅生成文件: $config_file" "$YELLOW"
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
                
                # 4.自定义命名
                get_filename_choice
                
                # 5. 生成配置
                if [ "$choice" == "1" ]; then
                    generate_nginx_config
                else
                    generate_caddy_config
                fi
                ;;\
            3)
                print_color "再见！" "$GREEN"; exit 0
                ;;\
            *)
                print_color "无效选择，请重新输入。" "$RED"
                ;;\
        esac
    done
}

# 运行主程序
main