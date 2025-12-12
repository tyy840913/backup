#!/bin/bash

# --- 脚本健壮性设置 ---
# -e: 任何命令执行失败时，立即退出
# -u: 使用未设置的变量时，报错并退出
# -o pipefail: 管道中任何命令失败，整个管道即失败
set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # 结束颜色

# --- 全局变量初始化 ---
# 核心配置
server_names=""
listen_port=80
ssl_enabled=false
ssl_cert=""
ssl_key=""
hsts_enabled=false
gzip_enabled=false
root_path=""

# 工作模式配置
WORK_MODE="" # static, proxy, mixed
PROXY_CONFIG_TYPE="" # path, subdomain
PROXY_RULES=() # 路径反代规则数组: "path|backend_url|proxy_set_host"
SUBDOMAIN_PROXIES=() # 子域名反代规则数组: "subdomain|backend_url"


# 打印带颜色的消息
print_color() {
    echo -e "${2}${1}${NC}"
}

# 显示标题
print_title() {
    echo "========================================="
    echo "    Web服务器配置生成器（V2.2 优化版）"
    echo "========================================="
    echo ""
}

# 显示菜单
show_menu() {
    print_title
    echo "请选择要生成的服务器配置:"
    echo "1. Nginx"
    echo "2. Caddy"
    echo "0. 退出"
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

# 验证文件是否存在（仅在输入不为空时执行）
validate_file_if_not_empty() {
    local file=$1
    if [[ -z "$file" ]]; then
        return 0 # 允许为空
    fi
    if [[ ! -f "$file" ]]; then
        print_color "错误: 文件 $file 不存在，请检查路径" "$RED"
        return 1
    fi
    return 0
}

# --- 获取工作模式和根路径 ---
get_work_mode() {
    local choice
    while true; do
        print_color "--- 工作模式选择 ---" "$CYAN"
        echo "请选择当前配置的工作模式:"
        echo "1. 仅静态文件服务 (Static Files Only)"
        echo "2. 仅反向代理 (Reverse Proxy Only)"
        echo "3. 混合模式 (Mixed Mode: 静态文件 + 路径反代)"
        read -p "请选择 [1-3]: " choice

        case "$choice" in
            1)
                WORK_MODE="static"
                print_color "已选择: 仅静态文件服务" "$GREEN"
                break
                ;;
            2)
                WORK_MODE="proxy"
                print_color "已选择: 仅反向代理" "$GREEN"
                break
                ;;
            3)
                WORK_MODE="mixed"
                print_color "已选择: 混合模式" "$GREEN"
                break
                ;;
            *)
                print_color "无效选择，请重试" "$RED"
                ;;
        esac
    done

    # Get root path if required
    if [[ "$WORK_MODE" == "static" || "$WORK_MODE" == "mixed" ]]; then
        while true; do
            read -e -p "请输入静态网站文件的根目录绝对路径 (例如: /var/www/html): " root_path
            # Check if directory exists (optional, but good practice)
            if [[ -d "$root_path" ]]; then
                print_color "静态文件根目录: $root_path" "$GREEN"
                break
            else
                print_color "警告: 路径 $root_path 不存在或不是目录。强烈建议使用存在的路径。" "$YELLOW"
                read -p "是否继续使用此路径? [y/N]: " continue_path
                if [[ "$continue_path" =~ ^[yY]$ ]]; then
                    break
                fi
            fi
        done
    else
        root_path="" # Clear if not used
    fi

    # Determine proxy configuration type if required
    if [[ "$WORK_MODE" == "proxy" || "$WORK_MODE" == "mixed" ]]; then
        local proxy_type_choice
        while true; do
            print_color "--- 反向代理规则类型 ---" "$CYAN"
            echo "请选择代理规则的定义方式:"
            echo "1. 基于路径的反向代理 (例如: /api/ -> backend)"
            echo "2. 基于子域名的反向代理 (例如: sub.domain.com -> backend)"
            read -p "请选择 [1-2]: " proxy_type_choice

            case "$proxy_type_choice" in
                1)
                    PROXY_CONFIG_TYPE="path"
                    print_color "已选择: 基于路径的反向代理" "$GREEN"
                    break
                    ;;
                2)
                    PROXY_CONFIG_TYPE="subdomain"
                    print_color "已选择: 基于子域名的反向代理" "$GREEN"
                    break
                    ;;
                *)
                    print_color "无效选择，请重试" "$RED"
                    ;;
            esac
        done
    else
        PROXY_CONFIG_TYPE="none"
    fi
    return 0
}

# --- 路径反代规则收集（迭代使用） ---
get_path_based_proxies() {
    print_color "--- 添加路径反向代理规则 ---" "$CYAN"

    local proxy_path
    local backend_url
    local proxy_set_host="true"
    local set_host_choice

    while true; do
        read -e -p "请输入要代理的路径 (例如: /api/ 或 /): " proxy_path
        if [[ -z "$proxy_path" ]]; then
            print_color "路径不能为空" "$RED"
        else
            break
        fi
    done

    read -e -p "请输入后端服务地址 (例如: http://127.0.0.1:8080): " backend_url

    read -p "是否设置 Proxy Header 'Host' 为原始域名 (通常用于后端验证SSL/多租户，默认: Y)? [Y/n]: " set_host_choice
    if [[ "$set_host_choice" =~ ^[nN]$ ]]; then
        proxy_set_host="false"
    fi

    # 存储规则到全局数组: PROXY_RULES
    PROXY_RULES+=("${proxy_path}|${backend_url}|${proxy_set_host}")
    print_color "已添加规则: $proxy_path -> $backend_url (设置Host: $proxy_set_host)" "$GREEN"
    return 0
}

# --- 子域名反代规则收集（迭代使用） ---
get_subdomain_based_proxies() {
    print_color "--- 添加子域名反向代理规则 ---" "$CYAN"

    local subdomain
    local backend_url

    while true; do
        read -e -p "请输入子域名 (例如: api.example.com): " subdomain
        if [[ -z "$subdomain" ]]; then
            print_color "子域名不能为空" "$RED"
        else
            break
        fi
    done

    read -e -p "请输入后端服务地址 (例如: http://127.0.0.1:8080): " backend_url

    # 存储规则到全局数组: SUBDOMAIN_PROXIES
    SUBDOMAIN_PROXIES+=("${subdomain}|${backend_url}")
    print_color "已添加子域名规则: $subdomain -> $backend_url" "$GREEN"
    return 0
}

# --- 关键修改：主配置收集函数 (get_web_config) ---
get_web_config() {
    # 每次运行时重置配置
    server_names=""
    listen_port=80
    ssl_enabled=false
    ssl_cert=""
    ssl_key=""
    hsts_enabled=false
    gzip_enabled=false
    root_path=""
    WORK_MODE=""
    PROXY_CONFIG_TYPE=""
    PROXY_RULES=()
    SUBDOMAIN_PROXIES=()

    print_color "--- 基础配置 ---" "$CYAN"

    # 1. 端口选择
    local port_choice
    local non_std_port
    local ssl_choice_non_std
    
    while true; do
        read -p "是否使用标准端口 (HTTP: 80, HTTPS: 443)? [Y/n]: " port_choice
        if [[ "$port_choice" =~ ^[nN]$ ]]; then
            # 非标准端口
            while true; do
                read -p "请输入非标准监听端口 (例如: 8080): " non_std_port
                if validate_port "$non_std_port"; then
                    listen_port="$non_std_port"
                    
                    # 询问是否启用 HTTPS/SSL
                    read -p "非标准端口 $listen_port 是否启用 HTTPS/SSL? [y/N]: " ssl_choice_non_std
                    if [[ "$ssl_choice_non_std" =~ ^[yY]$ ]]; then
                        ssl_enabled=true
                        print_color "已选择非标准端口 $listen_port，启用 HTTPS/SSL (Nginx将使用497跳转)。" "$GREEN"
                    else
                        ssl_enabled=false
                        print_color "已选择非标准端口 $listen_port，使用 HTTP。" "$GREEN"
                    fi
                    break 2 # 跳出内外循环
                fi
            done
        elif [[ "$port_choice" =~ ^[yY]$ || "$port_choice" == "" ]]; then
            # 标准端口
            read -p "是否启用 HTTPS/SSL? (标准端口，将使用 80 重定向至 443) [y/N]: " ssl_choice
            if [[ "$ssl_choice" =~ ^[yY]$ ]]; then
                ssl_enabled=true
                listen_port=443 # 主监听端口为 443
                print_color "已选择标准端口 80 和 443，启用 HTTPS。" "$GREEN"
            else
                ssl_enabled=false
                listen_port=80
                print_color "已选择标准端口 80，使用 HTTP。" "$GREEN"
            fi
            break
        else
            print_color "无效选择，请重试" "$RED"
        fi
    done
    
    # 2. 域名输入
    read -e -p "请输入域名 (多个用空格分隔): " server_names
    if [[ -z "$server_names" ]]; then
        print_color "域名不能为空" "$RED"
        return 1
    fi

    # 3. SSL/TLS 配置（仅在启用了 SSL 时询问证书）
    if "$ssl_enabled"; then
        print_color "--- SSL/TLS 证书配置 (允许留空，但配置可能无法工作) ---" "$CYAN"
        
        while true; do
            read -e -p "请输入 SSL 证书文件绝对路径 (.crt/.pem) [留空]: " ssl_cert
            if validate_file_if_not_empty "$ssl_cert"; then
                break
            fi
        done
        
        while true; do
            read -e -p "请输入 SSL 密钥文件绝对路径 (.key) [留空]: " ssl_key
            if validate_file_if_not_empty "$ssl_key"; then
                break
            fi
        done
        
        if [[ -z "$ssl_cert" || -z "$ssl_key" ]]; then
            print_color "警告: 您启用了 SSL，但证书或密钥路径为空。生成的配置无法启动 HTTPS 服务，请务必手动补全。" "$YELLOW"
        fi

        read -p "是否启用 HSTS 强制安全连接? [y/N]: " hsts_choice
        if [[ "$hsts_choice" =~ ^[yY]$ ]]; then
            hsts_enabled=true
        fi
    fi

    # 4. Gzip
    read -p "是否启用 Gzip 压缩? [Y/n]: " gzip_choice
    if [[ "$gzip_choice" =~ ^[nN]$ ]]; then
        gzip_enabled=false
    else
        gzip_enabled=true
    fi
    
    # 5. --- 获取工作模式和根路径 ---
    get_work_mode || return 1

    # 6. --- 迭代代理逻辑 ---
    if [[ "$WORK_MODE" == "proxy" || "$WORK_MODE" == "mixed" ]]; then
        if [[ "$PROXY_CONFIG_TYPE" == "path" ]]; then
            while true; do
                get_path_based_proxies
                
                read -e -p "是否继续添加下一个基于路径的反向代理? [Y/n]: " cont
                if [[ ! "$cont" =~ ^[yY]$ && "$cont" != "" ]]; then
                    break
                fi
            done
        elif [[ "$PROXY_CONFIG_TYPE" == "subdomain" ]]; then
            while true; do
                get_subdomain_based_proxies
                
                read -e -p "是否继续添加下一个基于子域名的反向代理? [Y/n]: " cont
                if [[ ! "$cont" =~ ^[yY]$ && "$cont" != "" ]]; then
                    break
                fi
            done
        fi
    fi

    print_color "配置信息收集完成。" "$GREEN"
    return 0
}

# --- Nginx 配置生成 ---
generate_nginx_config() {
    local config_file="nginx_$(echo "$server_names" | awk '{print $1}' | tr -cd '[:alnum:]_-')_$(date +%Y%m%d_%H%M%S).conf"
    print_color "--- 正在生成 Nginx 配置 ---" "$CYAN"

    # HTTP 重定向块 (如果启用了 SSL 且使用的是标准端口 443)
    if "$ssl_enabled" && [ "$listen_port" -eq 443 ]; then
        echo "server {" > "$config_file"
        echo "    listen 80;" >> "$config_file"
        echo "    server_name $server_names;" >> "$config_file"
        echo "    # 自动重定向到 HTTPS 443 端口" >> "$config_file"
        echo "    return 301 https://\$host\$request_uri;" >> "$config_file"
        echo "}" >> "$config_file"
        echo "" >> "$config_file"
    fi

    # HTTPS/HTTP 主配置块
    echo "server {" >> "$config_file"
    
    if "$ssl_enabled"; then
        echo "    # HTTPS 监听: $listen_port" >> "$config_file"
        echo "    listen $listen_port ssl http2;" >> "$config_file"
        echo "    server_name $server_names;" >> "$config_file"

        # NEW: 497 错误重定向 (仅在非标准 HTTPS 端口下需要)
        if [ "$listen_port" -ne 443 ]; then
            echo "    # Nginx 497 错误强制重定向 (适用于非标准端口)" >> "$config_file"
            echo "    error_page 497 =301 https://\$host:$listen_port\$request_uri;" >> "$config_file"
        fi
        
        # 证书配置 (仅当路径不为空时写入)
        if [[ -n "$ssl_cert" && -n "$ssl_key" ]]; then
            echo "    ssl_certificate \"$ssl_cert\";" >> "$config_file"
            echo "    ssl_certificate_key \"$ssl_key\";" >> "$config_file"
            echo "    ssl_session_cache shared:SSL:10m;" >> "$config_file"
            echo "    ssl_session_timeout 10m;" >> "$config_file"
            echo "    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';" >> "$config_file"
            echo "    ssl_prefer_server_ciphers on;" >> "$config_file"
            echo "    ssl_protocols TLSv1.2 TLSv1.3;" >> "$config_file"
        else
            echo "    # 警告: 证书路径为空，此 SSL 块可能无法正常工作。" >> "$config_file"
        fi

        if "$hsts_enabled"; then
            echo "    # 启用 HSTS (半年)" >> "$config_file"
            echo "    add_header Strict-Transport-Security \"max-age=15768000; includeSubDomains\" always;" >> "$config_file"
        fi
    else
        echo "    # HTTP 监听: $listen_port" >> "$config_file"
        echo "    listen $listen_port;" >> "$config_file"
        echo "    server_name $server_names;" >> "$config_file"
    fi

    # Gzip 配置
    if "$gzip_enabled"; then
        echo "    # Gzip 压缩配置" >> "$config_file"
        echo "    gzip on;" >> "$config_file"
        echo "    gzip_min_length 1k;" >> "$config_file"
        echo "    gzip_comp_level 5;" >> "$config_file"
        echo "    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;" >> "$config_file"
    fi

    # 1. 静态文件配置 (仅静态/混合模式)
    if [[ "$WORK_MODE" == "static" || "$WORK_MODE" == "mixed" ]]; then
        echo "    # 静态文件根目录" >> "$config_file"
        echo "    root \"$root_path\";" >> "$config_file"
        echo "    index index.html index.htm;" >> "$config_file"

        # 仅在纯静态模式下，默认location处理所有请求
        if [[ "$WORK_MODE" == "static" ]]; then
            echo "    location / {" >> "$config_file"
            echo "        try_files \$uri \$uri/ =404;" >> "$config_file"
            echo "    }" >> "$config_file"
        fi
    fi

    # 2. 路径反代配置 (纯反代/混合模式)
    if [[ "$WORK_MODE" == "proxy" || "$WORK_MODE" == "mixed" ]]; then
        # 遍历所有路径反代规则
        for rule in "${PROXY_RULES[@]}"; do
            IFS='|' read -r proxy_path backend_url proxy_set_host <<< "$rule"
            echo "    # 反向代理: $proxy_path -> $backend_url" >> "$config_file"
            echo "    location \"$proxy_path\" {" >> "$config_file"
            echo "        proxy_pass \"$backend_url\";" >> "$config_file"
            echo "        proxy_redirect off;" >> "$config_file"
            echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$config_file"
            echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" >> "$config_file"
            
            if [[ "$proxy_set_host" == "true" ]]; then
                echo "        proxy_set_header Host \$http_host;" >> "$config_file"
            fi
            
            # 解决Websocket支持
            echo "        proxy_http_version 1.1;" >> "$config_file"
            echo "        proxy_set_header Upgrade \$http_upgrade;" >> "$config_file"
            echo "        proxy_set_header Connection \"upgrade\";" >> "$config_file"
            echo "    }" >> "$config_file"
        done
        
        # 混合模式下的根路径处理：未匹配到代理路径的请求转发到静态文件
        if [[ "$WORK_MODE" == "mixed" ]]; then
            echo "    # 根路径处理：未匹配到代理的请求，转发到静态文件" >> "$config_file"
            echo "    location / {" >> "$config_file"
            echo "        try_files \$uri \$uri/ =404;" >> "$config_file"
            echo "    }" >> "$config_file"
        elif [[ "$WORK_MODE" == "proxy" && ${#PROXY_RULES[@]} -eq 0 ]]; then
             print_color "警告：纯反代模式下未检测到任何代理规则，生成的 Nginx 配置将不包含任何 location 块！" "$YELLOW"
        fi
    fi

    echo "}" >> "$config_file"

    # 3. 子域名反代配置 (每个子域名独立 server 块)
    if [[ "$PROXY_CONFIG_TYPE" == "subdomain" ]]; then
        print_color "注意: 子域名反代将生成独立的 Server 块。" "$YELLOW"
        for rule in "${SUBDOMAIN_PROXIES[@]}"; do
            IFS='|' read -r subdomain backend_url <<< "$rule"
            echo "" >> "$config_file"
            echo "server {" >> "$config_file"
            
            if "$ssl_enabled"; then
                echo "    listen $listen_port ssl http2;" >> "$config_file"
                if [[ -n "$ssl_cert" && -n "$ssl_key" ]]; then
                    echo "    ssl_certificate \"$ssl_cert\";" >> "$config_file"
                    echo "    ssl_certificate_key \"$ssl_key\";" >> "$config_file"
                fi
            else
                echo "    listen $listen_port;" >> "$config_file"
            fi
            
            echo "    server_name $subdomain;" >> "$config_file"
            echo "    # 子域名代理: $subdomain -> $backend_url" >> "$config_file"
            echo "    location / {" >> "$config_file"
            echo "        proxy_pass \"$backend_url\";" >> "$config_file"
            echo "        proxy_set_header Host \$host;" >> "$config_file"
            echo "        # ... 其他反代设置 (略) ... " >> "$config_file"
            echo "    }" >> "$config_file"
            echo "}" >> "$config_file"
        done
    fi


    print_color "Nginx 配置生成成功: $config_file" "$GREEN"
    echo ""
    print_color "--- Nginx 使用示例 ---" "$YELLOW"
    echo "1. 将配置文件复制到 Nginx 配置目录:"
    echo "   cp \"$config_file\" /etc/nginx/conf.d/"
    echo "2. 检查配置语法:"
    echo "   nginx -t"
    echo "3. 重载 Nginx 服务:"
    echo "   systemctl reload nginx"
    echo ""
}

# --- Caddy 配置生成 ---
generate_caddy_config() {
    local config_file="caddy_$(echo "$server_names" | awk '{print $1}' | tr -cd '[:alnum:]_-')_$(date +%Y%m%d_%H%M%S).Caddyfile"
    print_color "--- 正在生成 Caddyfile 配置 ---" "$CYAN"

    # Caddyfile 头部 (主域名)
    local address
    local http_address
    
    # 确定 Caddy 监听地址
    if "$ssl_enabled"; then
        address="$server_names:$listen_port"
        http_address="$server_names:80" # Caddy 默认会自动处理 80 到 HTTPS 的跳转
    elif [ "$listen_port" -eq 80 ]; then
        address="$server_names"
    else
        # 非标准 HTTP 端口
        address="http://$server_names:$listen_port"
    fi
    
    echo "$address {" > "$config_file"

    # Caddy SSL/TLS 证书配置 (手动模式)
    if "$ssl_enabled"; then
        if [[ -n "$ssl_cert" && -n "$ssl_key" ]]; then
            echo "    # 手动指定证书" >> "$config_file"
            echo "    tls \"$ssl_cert\" \"$ssl_key\"" >> "$config_file"
        elif [ "$listen_port" -eq 443 ]; then
             echo "    # Caddy 将尝试自动申请证书 (如果使用标准端口 443)" >> "$config_file"
             # 保持默认行为，如果证书为空，Caddy会尝试ACME
             echo "    tls" >> "$config_file"
        fi
        
        # Caddy 会自动处理重定向，不需要像 Nginx 那样添加 497 错误页
    fi

    # Gzip 配置 (Caddy 默认使用 encode gzip zstd)
    if "$gzip_enabled"; then
        echo "    # 启用 Gzip/Zstd 压缩" >> "$config_file"
        echo "    encode gzip zstd" >> "$config_file"
    fi

    # HSTS 配置
    if "$hsts_enabled"; then
        echo "    # 启用 HSTS" >> "$config_file"
        echo "    header Strict-Transport-Security \"max-age=31536000; includeSubDomains\"" >> "$config_file"
    fi

    # 1. 静态文件配置 (仅静态/混合模式) - 放在最前面作为默认
    if [[ "$WORK_MODE" == "static" || "$WORK_MODE" == "mixed" ]]; then
        echo "    # 静态文件配置" >> "$config_file"
        echo "    root * \"$root_path\"" >> "$config_file"
        echo "    file_server" >> "$config_file"
    fi

    # 2. 路径反代配置 (纯反代/混合模式)
    if [[ "$WORK_MODE" == "proxy" || "$WORK_MODE" == "mixed" ]]; then
        for rule in "${PROXY_RULES[@]}"; do
            IFS='|' read -r proxy_path backend_url proxy_set_host <<< "$rule"
            echo "    # 反向代理: $proxy_path -> $backend_url" >> "$config_file"
            # Caddy 的 route 优先级高，且路径匹配更灵活
            echo "    route \"$proxy_path\"* {" >> "$config_file"
            echo "        reverse_proxy \"$backend_url\"" >> "$config_file"
            
            if [[ "$proxy_set_host" == "true" ]]; then
                echo "        header_up Host {http.request.host}" >> "$config_file"
            fi
            echo "    }" >> "$config_file"
        done
        
        # 纯反代模式下，如果用户没有添加路径规则，则默认将根路径 / 代理
        if [[ "$WORK_MODE" == "proxy" && ${#PROXY_RULES[@]} -eq 0 ]]; then
             print_color "警告：纯反代模式下未检测到路径规则，默认将所有流量代理到用户输入中的第一个后端地址。" "$YELLOW"
             echo "    # 纯反代模式下，默认代理所有流量" >> "$config_file"
             echo "    reverse_proxy # 请手动在此处填写默认后端地址，例如: http://127.0.0.1:8080" >> "$config_file"
        fi
    fi

    echo "}" >> "$config_file"

    # 3. 子域名反代配置 (每个子域名独立 Server 块)
    if [[ "$PROXY_CONFIG_TYPE" == "subdomain" ]]; then
        print_color "注意: 子域名反代将生成独立的 Server 块。" "$YELLOW"
        for rule in "${SUBDOMAIN_PROXIES[@]}"; do
            IFS='|' read -r subdomain backend_url <<< "$rule"
            echo "" >> "$config_file"
            echo "$subdomain {" >> "$config_file"
            
            if "$ssl_enabled" && [[ -n "$ssl_cert" && -n "$ssl_key" ]]; then
                echo "    tls \"$ssl_cert\" \"$ssl_key\"" >> "$config_file"
            fi
            
            echo "    # 子域名代理: $subdomain -> $backend_url" >> "$config_file"
            echo "    reverse_proxy \"$backend_url\"" >> "$config_file"
            echo "}" >> "$config_file"
        done
    fi

    print_color "Caddyfile 配置生成成功: $config_file" "$GREEN"
    echo ""
    print_color "--- Caddy 使用示例 ---" "$YELLOW"
    echo "1. 将配置追加到 Caddyfile:"
    echo "   cat \"$config_file\" | tee -a /etc/caddy/Caddyfile"
    echo "2. 配置验证:"
    echo "   caddy validate --config /etc/caddy/Caddyfile"
    echo "3. 重载服务:"
    echo "   systemctl reload caddy"
    echo ""
}

# 主程序
main() {
    while true; do
        show_menu
        local choice
        read -p "请选择 [0-2]: " choice

        case "$choice" in
            0)
                print_color "再见！" "$GREEN"
                exit 0
                ;;
            1)
                if get_web_config; then
                    generate_nginx_config
                fi
                ;;
            2)
                if get_web_config; then
                    generate_caddy_config
                fi
                ;;
            *)
                print_color "无效选择，请重试" "$RED"
                ;;
        esac

        echo ""
        while true; do
            local cont
            read -e -p "是否继续生成其他配置? [Y/n/0退出]: " cont
            case "$cont" in
                0)
                    print_color "再见！" "$GREEN"
                    exit 0
                    ;;
                ""|y|Y)
                    break  # 继续
                    ;;
                n|N)
                    print_color "再见！" "$GREEN"
                    exit 0
                    ;;
                *)
                    print_color "无效选择，请重试" "$RED"
                    ;;
            esac
        done
    done
}

# 运行主程序
main