#!/bin/bash

# =======================================================
# Web服务器配置生成器 (v2.1 个人黄金精简版)
# 核心原则：稳定、好用、不翻车、极简主义
# =======================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 全局变量
declare -a PROXY_MAPPINGS 
# 存储映射，格式: TYPE|MATCHER|BACKEND_URL/ROOT_PATH|SET_HOST_BOOL|CORS_BOOL
config_output_file=""  # 自定义输出文件名
server_type=""         # Nginx 或 Caddy

# 通用配置变量
domain_name=""
http_port=80
https_port=443
enable_ssl="n"

# 黄金精简配置默认值
enable_ipv6="y" 
enable_497_fix="y" # Nginx 497 错误自动跳转修复 (默认开启)


# 打印带颜色的消息 (重定向到 stderr 以防被变量捕获)
print_color() {
    echo -e "${2}${1}${NC}" >&2
}

# 显示标题
print_title() {
    echo "=================================================" >&2
    echo " Web服务器配置生成器 (v2.1 个人黄金精简版)" >&2
    echo "=================================================" >&2
    echo "" >&2
}

# 显示主菜单 (用于选择 Nginx 或 Caddy)
show_menu() {
    print_title
    echo "请选择要生成的服务器配置:"
    echo "1. Nginx (推荐：黄金精简版)"
    echo "2. Caddy (推荐：简洁优雅版)"
    echo "3. 退出"
    echo ""
}

# =======================================================
# 模块一: 输入与校验 (保留完整交互逻辑)
# =======================================================

# 检查是否是有效的域名
is_valid_domain() {
    local domain=$1
    if [[ "$domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ && "$domain" =~ \. ]]; then
        return 0
    else
        return 1
    fi
}

# 获取域名配置
get_domain_config() {
    while true; do
        read -e -p "请输入主域名 (例如: example.com)，留空则使用 IP: " domain_input
        if [[ -z "$domain_input" ]]; then
            domain_name="_" # 使用 Nginx 默认的匹配符
            print_color "已使用 IP 或通配符匹配 (server_name _)。" "$YELLOW"
            break
        elif is_valid_domain "$domain_input"; then
            read -e -p "是否包含 www 子域名 (www.$domain_input)？ [Y/n]: " include_www
            include_www=${include_www:-y}
            if [[ "$include_www" =~ ^[Yy]$ ]]; then
                domain_name="$domain_input www.$domain_input"
            else
                domain_name="$domain_input"
            fi
            break
        else
            print_color "域名格式无效，请重新输入或留空使用 IP。" "$RED"
        fi
    done
}

# 获取端口配置
get_port_config() {
    while true; do
        read -e -p "请输入 HTTP 监听端口 (默认 80): " port_80_input
        http_port=${port_80_input:-80}
        if [[ "$http_port" =~ ^[0-9]+$ && "$http_port" -gt 0 && "$http_port" -le 65535 ]]; then
            break
        else
            print_color "端口号无效，请输入 1-65535 之间的数字。" "$RED"
        fi
    done

    while true; do
        read -e -p "请输入 HTTPS 监听端口 (默认 443): " port_443_input
        https_port=${port_443_input:-443}
        if [[ "$https_port" =~ ^[0-9]+$ && "$https_port" -gt 0 && "$https_port" -le 65535 ]]; then
            if [ "$https_port" -eq "$http_port" ]; then
                print_color "HTTPS 端口不能与 HTTP 端口相同，请重新输入。" "$RED"
            else
                break
            fi
        else
            print_color "端口号无效，请输入 1-65535 之间的数字。" "$RED"
        fi
    done
}

# 获取 SSL 配置
get_ssl_config() {
    while true; do
        read -e -p "是否启用 SSL/HTTPS？ (推荐) [Y/n]: " ssl_choice
        ssl_choice=${ssl_choice:-y}
        if [[ "$ssl_choice" =~ ^[Yy]$ ]]; then
            enable_ssl="y"
            break
        elif [[ "$ssl_choice" =~ ^[Nn]$ ]]; then
            enable_ssl="n"
            break
        else
            print_color "无效输入，请重新输入 Y 或 N。" "$RED"
        fi
    done
}

# 获取通用配置 (按照清单进行精简和修改)
get_generic_config() {
    get_domain_config
    get_port_config
    get_ssl_config
    
    # [清单修改] IPv6 监听：修改询问，默认值设为 Y
    read -e -p "是否启用 IPv6 监听？([::]:port) [Y/n]: " ipv6_choice
    enable_ipv6=${ipv6_choice:-y}
    
    # [清单删除] HSTS, OCSP, 超严格密码套件：移除所有相关询问
    # [清单删除] 静态文件缓存：移除询问

    print_color "已完成基本配置。注意：本版本已自动采用个人黄金精简安全配置。" "$YELLOW"
}

# =======================================================
# 模块二: 映射配置 (Proxy / Root) (保留完整交互逻辑)
# =======================================================

# 添加一个反向代理或静态根目录映射
add_proxy_mapping() {
    local matcher=""
    local backend=""
    local type=""
    local set_host_header="y" # proxy_set_header Host $host 默认开启
    local enable_cors="n"     # CORS 默认关闭

    print_color "--- 添加新的映射配置 ---" "$BLUE"

    # 1. 选择匹配器类型
    while true; do
        echo "请选择匹配器/映射类型:"
        echo "1. 根路径映射 (/) -> 静态目录或默认反代"
        echo "2. 路径前缀映射 (/api, /admin) -> 反向代理"
        echo "3. 退出映射配置"
        read -e -p "请选择 [1-3]: " mapping_type_choice

        case $mapping_type_choice in
            1)
                type="ROOT"
                matcher="/"
                break
                ;;
            2)
                type="PATH"
                while true; do
                    read -e -p "请输入路径前缀 (例如: /api, /admin/): " matcher_input
                    if [[ -z "$matcher_input" ]]; then
                        print_color "路径前缀不能为空，请重新输入。" "$RED"
                        continue
                    elif [[ "$matcher_input" != /* ]]; then
                        matcher="/$matcher_input"
                    else
                        matcher="$matcher_input"
                    fi
                    
                    local is_duplicate=0
                    for map in "${PROXY_MAPPINGS[@]}"; do
                        if [[ "$map" == *\|"$matcher"\|* ]]; then
                            is_duplicate=1
                            break
                        fi
                    done

                    if [ "$is_duplicate" -eq 1 ]; then
                        print_color "错误: 路径 $matcher 已经存在，请选择其他路径。" "$RED"
                    else
                        break
                    fi
                done
                break
                ;;
            3)
                return 1 # 退出添加
                ;;
            *)
                print_color "无效选择，请重新输入。" "$RED"
                ;;
        esac
    done

    # 2. 根据类型获取后端或根目录
    if [ "$type" == "ROOT" ]; then
        echo "根路径 (/) 可以是静态文件目录，也可以是默认反向代理地址。"
        while true; do
            read -e -p "请输入静态文件目录 (例如: /var/www/html) 或反向代理地址 (例如: http://127.0.0.1:8080): " backend_input
            if [ -n "$backend_input" ]; then
                backend="$backend_input"
                
                if [[ "$backend" =~ ^http://.* ]] || [[ "$backend" =~ ^https://.* ]]; then
                    type="PROXY" 
                    read -e -p "是否为该反代启用 CORS 跨域支持？[y/N]: " cors_choice
                    enable_cors=${cors_choice:-n}
                else
                    type="ROOT"
                fi

                break
            else
                print_color "输入不能为空。" "$RED"
            fi
        done
    elif [ "$type" == "PATH" ]; then
        while true; do
            read -e -p "请输入反向代理目标地址 (例如: http://127.0.0.1:8081): " backend_input
            if [[ "$backend_input" =~ ^http://.* ]] || [[ "$backend_input" =~ ^https://.* ]]; then
                backend="$backend_input"
                type="PROXY_PATH"
                read -e -p "是否为该反代启用 CORS 跨域支持？[y/N]: " cors_choice
                enable_cors=${cors_choice:-n}
                break
            else
                print_color "反向代理地址必须以 http:// 或 https:// 开头。" "$RED"
            fi
        done
    fi

    # 3. 存储映射
    PROXY_MAPPINGS+=("$type|$matcher|$backend|$set_host_header|$enable_cors")
    print_color "映射已添加: $type $matcher -> $backend (CORS: $enable_cors)" "$GREEN"
    echo ""
    return 0
}

# 获取所有映射配置
get_proxy_mappings() {
    print_color "--- 映射配置 ---" "$YELLOW"
    print_color "您需要配置静态文件服务、反向代理（例如：将 /api 转发到后端服务）或两者。" "$YELLOW"
    echo ""

    # 1. 至少添加一个根路径配置
    if [ ${#PROXY_MAPPINGS[@]} -eq 0 ]; then
        print_color "注意：您必须首先配置根路径 (/) 的映射。" "$YELLOW"
        while true; do
            read -e -p "请配置根路径 (/)：输入静态目录或反代地址 (默认: http://127.0.0.1:8080): " root_backend
            root_backend=${root_backend:-http://127.0.0.1:8080}
            
            if [[ "$root_backend" =~ ^http://.* ]] || [[ "$root_backend" =~ ^https://.* ]]; then
                # 根路径代理默认开启 CORS 询问
                read -e -p "是否为该反代启用 CORS 跨域支持？[y/N]: " cors_choice
                enable_cors=${cors_choice:-n}
                PROXY_MAPPINGS+=("PROXY|/|$root_backend|y|$enable_cors")
                print_color "根路径 (/) 已配置为反向代理到 $root_backend" "$GREEN"
            else
                # 根路径静态文件，不需要 CORS
                PROXY_MAPPINGS+=("ROOT|/|$root_backend|y|n")
                print_color "根路径 (/) 已配置为静态文件目录 $root_backend" "$GREEN"
            fi
            break
        done
    fi

    # 2. 循环添加其他映射
    while true; do
        add_proxy_mapping || break
    done
}

# 获取最终文件名
get_filename_choice() {
    local default_filename=$(echo "$domain_name" | cut -d ' ' -f 1)
    read -e -p "请输入配置输出文件名 (默认: $default_filename.conf): " filename_input
    config_output_file="${filename_input:-$default_filename.conf}"
}

# =======================================================
# 模块三: Nginx 配置生成 (个人黄金精简版)
# =======================================================

generate_nginx_config() {
    local config_content=""
    local primary_domain=$(echo "$domain_name" | cut -d ' ' -f 1)

    print_color "--- 正在生成 Nginx 黄金精简配置 ---" "$BLUE"
    
    # 1. HTTP 跳转块 (如果启用了 SSL)
    if [ "$enable_ssl" == "y" ]; then
        config_content+="# 自动将 HTTP($http_port) 流量永久重定向到 HTTPS($https_port)\n"
        config_content+="server {\n"
        config_content+="    listen $http_port;\n"
        if [[ "$enable_ipv6" =~ ^[Yy]$ ]]; then
            config_content+="    listen [::]:$http_port;\n"
        fi
        config_content+="    server_name $domain_name;\n\n"
        config_content+="    # 永久重定向\n"
        config_content+="    return 301 https://\$host:$https_port\$request_uri;\n"
        config_content+="}\n\n"
    fi

    # 2. HTTPS/HTTP 主配置块
    config_content+="server {\n"
    
    # 监听配置
    if [ "$enable_ssl" == "y" ]; then
        config_content+="    # HTTPS 监听\n"
        config_content+="    listen $https_port ssl http2;\n"
        if [[ "$enable_ipv6" =~ ^[Yy]$ ]]; then
            config_content+="    listen [::]:$https_port ssl http2;\n"
        fi
        config_content+="\n"
        
        # 497 错误自动修复（当 HTTPS 端口不是 443 时，497 错误是救命神器）
        if [ "$https_port" != "443" ] && [ "$enable_497_fix" == "y" ]; then
            config_content+="    # [黄金精简] 修复非 443 端口的 497 错误\n"
            config_content+="    error_page 497 https://\$host:\$server_port\$request_uri;\n\n"
        fi

        # SSL 证书和协议配置 (写死 Let's Encrypt 默认路径)
        config_content+="    # SSL 证书 (Let's Encrypt 默认路径)\n"
        config_content+="    ssl_certificate     /etc/letsencrypt/live/$primary_domain/fullchain.pem;\n"
        config_content+="    ssl_certificate_key /etc/letsencrypt/live/$primary_domain/privkey.pem;\n"
        config_content+="    ssl_protocols       TLSv1.2 TLSv1.3;\n\n"
        
        # [清单修改] 密码套件 (黄金精简版：稳定兼容，HIGH:!aNULL:!MD5)
        config_content+="    # [黄金精简] 密码套件 (HIGH:!aNULL:!MD5，兼容性高)\n"
        config_content+="    ssl_ciphers         HIGH:!aNULL:!MD5;\n\n"
        
        # [清单删除] OCSP Stapling 和 Session Cache 彻底删除
        
    else
        # 纯 HTTP 监听
        config_content+="    # HTTP 监听\n"
        config_content+="    listen $http_port;\n"
        if [[ "$enable_ipv6" =~ ^[Yy]$ ]]; then
            config_content+="    listen [::]:$http_port;\n"
        fi
        config_content+="\n"
    fi
    
    config_content+="    server_name $domain_name;\n\n"

    # [清单保留] GZIP 压缩 (默认开启，节省流量)
    config_content+="    # Gzip 压缩 (默认开启)\n"
    config_content+="    gzip on;\n"
    config_content+="    gzip_vary on;\n"
    config_content+="    gzip_min_length 1024;\n"
    config_content+="    gzip_proxied expired no-cache no-store private auth;\n"
    config_content+="    gzip_types text/plain text/css application/json application/javascript application/x-javascript text/xml application/xml application/xml+rss text/javascript;\n\n"

    # [清单保留+精简] 安全头 (只保留最有用的两个)
    config_content+="    # [黄金精简] 极简安全头\n"
    config_content+="    add_header X-Content-Type-Options nosniff always;\n"
    config_content+="    add_header Referrer-Policy \"strict-origin-when-cross-origin\" always;\n\n"
    # [清单删除] X-Frame-Options 彻底删除

    # 3. 映射块
    for map in "${PROXY_MAPPINGS[@]}"; do
        IFS='|' read -r type matcher backend set_host_header enable_cors <<< "$map"

        if [ "$type" == "PROXY" ] || [ "$type" == "PROXY_PATH" ]; then
            # 反向代理配置
            config_content+="    # 反向代理: $matcher -> $backend\n"
            config_content+="    location $matcher {\n"
            config_content+="        proxy_pass $backend;\n"
            
            # [清单保留] 必需头 (Host $host 永远默认开)
            config_content+="        # 必需头\n"
            config_content+="        proxy_set_header Host \$host;\n"
            config_content+="        proxy_set_header X-Real-IP \$remote_addr;\n"
            config_content+="        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;\n"
            config_content+="        proxy_set_header X-Forwarded-Proto \$scheme;\n\n"
            
            # [清单保留] WebSocket 必需头 (所有 proxy_pass 默认加上)
            config_content+="        # WebSocket 必需头\n"
            config_content+="        proxy_set_header Upgrade \$http_upgrade;\n"
            config_content+="        proxy_set_header Connection \"upgrade\";\n\n"
            
            # CORS 支持 (根据用户选择添加)
            if [[ "$enable_cors" =~ ^[Yy]$ ]]; then
                 config_content+="        # CORS 跨域支持\n"
                 config_content+="        if (\$request_method = 'OPTIONS') {\n"
                 config_content+="            add_header 'Access-Control-Allow-Origin' '*';\n"
                 config_content+="            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, PUT, DELETE';\n"
                 config_content+="            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';\n"
                 config_content+="            add_header 'Access-Control-Max-Age' 1728000;\n"
                 config_content+="            add_header 'Content-Type' 'text/plain; charset=utf-8';\n"
                 config_content+="            add_header 'Content-Length' 0;\n"
                 config_content+="            return 204;\n"
                 config_content+="        }\n"
                 config_content+="        add_header 'Access-Control-Allow-Origin' '*';\n"
                 config_content+="        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, PUT, DELETE';\n"
                 config_content+="        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range';\n\n"
            fi
            
            config_content+="    }\n\n"
            
        elif [ "$type" == "ROOT" ]; then
            # 静态文件配置 
            config_content+="    # 静态文件/根目录: $matcher -> $backend\n"
            config_content+="    location $matcher {\n"
            config_content+="        root $backend;\n"
            config_content+="        index index.html index.htm;\n"
            # [清单删除] 彻底删除静态文件长缓存 location 块
            config_content+="        try_files \$uri \$uri/ =404;\n"
            config_content+="    }\n\n"
        fi
    done
    
    config_content+="}\n"

    # 4. 写入文件
    echo -e "$config_content" > "$config_output_file"
    print_color "Nginx 配置已生成到文件: $config_output_file" "$GREEN"
    print_color "请检查配置内容并确保 Let's Encrypt 证书路径正确！" "$YELLOW"
    
    # 5. 自动安装/重载 (默认开启)
    handle_nginx_installation "$config_output_file"
}


# =======================================================
# 模块四: Caddy 配置生成 (个人黄金精简版)
# =======================================================

generate_caddy_config() {
    local config_content=""
    local primary_domain=$(echo "$domain_name" | cut -d ' ' -f 1)
    
    # Caddy 使用 {domain} 匹配所有 server_name
    local caddy_domain_list=$(echo "$domain_name" | sed 's/ / /g') # 保持空格分隔

    print_color "--- 正在生成 Caddy 简洁优雅配置 ---" "$BLUE"

    config_content+="{}\n\n" 
    
    if [ "$enable_ssl" == "y" ]; then
        config_content+="# Caddy 自动配置 Let's Encrypt/ZeroSSL 证书\n"
        config_content+="$caddy_domain_list {\n"
        
        # 自动重定向 HTTP 到 HTTPS (Caddy 默认行为)
        if [ "$https_port" != "443" ] || [ "$http_port" != "80" ]; then
            config_content+="  # 监听非默认端口\n"
            config_content+="  # Caddy 将自动重定向 http://$http_port 到 https://$https_port\n"
            config_content+="  @http_match expression {http_scheme} == \"http\" and {host} in $caddy_domain_list\n"
            config_content+="  handle @http_match {\n"
            config_content+="      redir https://{host}:$https_port{uri} permanent\n"
            config_content+="  }\n\n"
        fi

    else
        # 纯 HTTP
        config_content+="# 纯 HTTP 配置\n"
        config_content+="$caddy_domain_list:$http_port {\n"
    fi
    
    # [清单删除] 移除 Caddy 的 zstd 压缩询问和配置
    config_content+="  # 压缩 (Caddy 默认开启 gzip/zstd，无需手动配置)\n"

    # [清单保留+精简] 极简安全头
    config_content+="  # [黄金精简] 极简安全头\n"
    config_content+="  header {\n"
    config_content+="    Referrer-Policy strict-origin-when-cross-origin\n"
    # [清单删除] X-Frame-Options 彻底删除
    config_content+="  }\n\n"

    # 映射块
    for map in "${PROXY_MAPPINGS[@]}"; do
        IFS='|' read -r type matcher backend set_host_header enable_cors <<< "$map"

        if [ "$type" == "PROXY" ] || [ "$type" == "PROXY_PATH" ]; then
            # 反向代理配置
            config_content+="  # 反向代理: $matcher -> $backend\n"
            config_content+="  route $matcher {\n"
            
            # CORS 支持 (根据用户选择添加)
            if [[ "$enable_cors" =~ ^[Yy]$ ]]; then
                 config_content+="    # CORS 跨域支持\n"
                 config_content+="    header {\n"
                 config_content+="      Access-Control-Allow-Origin *\n"
                 config_content+="      Access-Control-Allow-Methods \"GET, POST, OPTIONS, PUT, DELETE\"\n"
                 config_content+="      Access-Control-Allow-Headers \"DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range\"\n"
                 config_content+="      Access-Control-Max-Age 1728000\n"
                 config_content+="      if {method} == \"OPTIONS\" {\n"
                 config_content+="        status 204\n"
                 config_content+="        close\n"
                 config_content+="      }\n"
                 config_content+="    }\n"
            fi
            
            config_content+="    reverse_proxy $backend {\n"
            # [清单保留] Host 头默认开启 (Caddy 默认行为，此处明确写出)
            config_content+="      # Host 头默认开启 proxy_set_header Host \$host\n"
            config_content+="      header_up Host {host}\n"
            # [清单保留] WebSocket Caddy 默认支持
            config_content+="    }\n"
            config_content+="  }\n\n"
            
        elif [ "$type" == "ROOT" ]; then
            # 静态文件配置 (Caddy 默认无长缓存)
            config_content+="  # 静态文件/根目录: $matcher -> $backend\n"
            config_content+="  root * $backend\n"
            config_content+="  file_server\n\n"
        fi
    done
    
    config_content+="}\n"

    # 4. 写入文件
    echo -e "$config_content" > "$config_output_file"
    print_color "Caddy 配置已生成到文件: $config_output_file" "$GREEN"
    
    # 5. 校验 (Caddy 不进行自动安装，仅进行校验)
    handle_caddy_installation "$config_output_file"
}

# =======================================================
# 模块五: 安装与校验 (Nginx / Caddy)
# =======================================================

# Nginx 安装/校验/重载
handle_nginx_installation() {
    local config_file=$1
    
    # [清单修改] 自动安装/重载默认开启
    local install_choice="y"

    if [[ "$install_choice" =~ ^[Yy]$ ]]; then
        print_color "--- Nginx 自动安装/重载 (默认开启) ---" "$YELLOW"
        if [ -d "/etc/nginx/sites-enabled" ]; then
            
            # 1. 复制文件
            if sudo cp "$config_file" "/etc/nginx/sites-available/$config_output_file"; then
                print_color "配置已复制到 /etc/nginx/sites-available/$config_output_file" "$GREEN"
                # 2. 创建软链接
                if sudo ln -sf "/etc/nginx/sites-available/$config_output_file" "/etc/nginx/sites-enabled/"; then
                    print_color "已在 sites-enabled 中创建软链接。" "$GREEN"
                    
                    # 3. 校验配置
                    if sudo nginx -t; then
                        print_color "Nginx 配置验证成功！正在重载..." "$GREEN"
                        # 4. 重载服务
                        if sudo systemctl reload nginx; then
                            print_color "Nginx 服务重载成功！新配置已生效。" "$GREEN"
                        else
                            print_color "警告: Nginx 服务重载失败，请手动检查日志！" "$RED"
                        fi
                    else
                        print_color "错误: Nginx 配置验证失败，请手动检查 /etc/nginx/sites-available/$config_output_file 中的错误！" "$RED"
                    fi
                else
                    print_color "错误: 无法创建 sites-enabled 软链接，请检查权限。" "$RED"
                fi
            else
                print_color "错误: 无法复制配置到 sites-available，请检查权限。" "$RED"
            fi
        else
            print_color "警告: 找不到 /etc/nginx/sites-enabled 目录，跳过自动安装。" "$YELLOW"
        fi
    fi
}

# Caddy 校验 (保留原始脚本的 Caddy 校验逻辑)
handle_caddy_installation() {
    local config_file=$1
    
    print_color "--- Caddy 配置校验提示 ---" "$BLUE"
    
    if command -v caddy &> /dev/null; then
        print_color "请将 $config_file 的内容追加到您的 Caddyfile 中，然后手动执行 'sudo caddy validate' 和 'sudo systemctl reload caddy'。" "$YELLOW"
    else
        print_color "警告: Caddy 命令未找到，跳过配置校验。" "$YELLOW"
    fi
}


# 主程序 (保留原始脚本的主程序逻辑)
main() {
    while true; do
        
        # 1. 服务器类型选择 (Nginx/Caddy) - 放在最前面
        show_menu
        read -p "请选择 [1-3]: " choice

        case $choice in
            1)
                server_type="Nginx"
                # 2. 获取所有通用配置 (端口、SSL、IPv6、域名) - 已精简
                get_generic_config
                
                # 3. 获取所有映射配置 (根路径、路径/子域名反代)
                get_proxy_mappings
                
                # 4.自定义命名
                get_filename_choice
                
                # 5. 生成配置并尝试安装
                generate_nginx_config
                ;;
            2)
                server_type="Caddy"
                # 2. 获取所有通用配置 (端口、SSL、IPv6、域名) - 已精简
                get_generic_config
                
                # 3. 获取所有映射配置 (根路径、路径/子域名反代)
                get_proxy_mappings
                
                # 4.自定义命名
                get_filename_choice
                
                # 5. 生成配置并提示校验
                generate_caddy_config
                ;;
            3)
                print_color "再见！" "$GREEN"; exit 0
                ;;
            *)
                print_color "无效选择，请重新输入。" "$RED"
                ;;
        esac

        # 清空映射配置以备下次运行
        PROXY_MAPPINGS=()
        config_output_file=""
        echo ""
    done
}

# 运行主程序
main