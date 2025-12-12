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
    echo "    Web服务器配置生成器（V2.0 重构版）"
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

# 验证文件是否存在
validate_file() {
    local file=$1
    if [[ ! -f "$file" ]]; then
        print_color "错误: 文件 $file 不存在，请检查路径" "$RED"
        return 1
    fi
    return 0
}

# --- 新增：获取工作模式和根路径 ---
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

# --- 修改：路径反代规则收集（迭代使用） ---
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

# --- 修改：子域名反代规则收集（迭代使用） ---
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

# --- 修改：主配置收集函数 (get_web_config) ---
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
    while true; do
        read -p "是否使用标准端口 (HTTP: 80, HTTPS: 443)? [Y/n]: " port_choice
        if [[ "$port_choice" =~ ^[nN]$ ]]; then
            read -p "请输入非标准监听端口 (例如: 8080): " non_std_port
            if validate_port "$non_std_port"; then
                listen_port="$non_std_port"
                break
            fi
        elif [[ "$port_choice" =~ ^[yY]$ || "$port_choice" == "" ]]; then
            listen_port=80
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

    # 3. SSL/TLS 配置
    local ssl_choice
    read -p "是否启用 HTTPS/SSL? [y/N]: " ssl_choice
    if [[ "$ssl_choice" =~ ^[yY]$ ]]; then
        ssl_enabled=true
        listen_port=443 # 默认使用443
        if [[ "$port_choice" =~ ^[nN]$ ]]; then
            read -p "HTTPS非标准监听端口 (例如: 8443): " non_std_port
            if validate_port "$non_std_port"; then
                listen_port="$non_std_port"
            fi
        fi

        while true; do
            read -e -p "请输入 SSL 证书文件绝对路径 (.crt/.pem): " ssl_cert
            if validate_file "$ssl_cert"; then
                break
            fi
        done
        while true; do
            read -e -p "请输入 SSL 密钥文件绝对路径 (.key): " ssl_key
            if validate_file "$ssl_key"; then
                break
            fi
        done

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
    
    # 5. --- NEW: 获取工作模式和根路径 ---
    get_work_mode || return 1

    # 6. --- NEW: 迭代代理逻辑 ---
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

# --- 修改：Nginx 配置生成 ---
generate_nginx_config() {
    local config_file="nginx_$(echo "$server_names" | awk '{print $1}' | tr -cd '[:alnum:]_-')_$(date +%Y%m%d_%H%M%S).conf"
    print_color "--- 正在生成 Nginx 配置 ---" "$CYAN"

    # HTTP 重定向块 (如果启用了 SSL)
    if "$ssl_enabled"; then
        echo "server {" > "$config_file"
        echo "    listen 80;" >> "$config_file"
        echo "    server_name $server_names;" >> "$config_file"
        echo "    return 301 https://\$host:\$server_port\$request_uri;" >> "$config_file"
        echo "}" >> "$config_file"
        echo "" >> "$config_file"
    fi

    # HTTPS/HTTP 主配置块
    echo "server {" >> "$config_file"
    if "$ssl_enabled"; then
        echo "    # HTTPS 监听" >> "$config_file"
        echo "    listen $listen_port ssl http2;" >> "$config_file"
        echo "    server_name $server_names;" >> "$config_file"
        
        echo "    ssl_certificate \"$ssl_cert\";" >> "$config_file"
        echo "    ssl_certificate_key \"$ssl_key\";" >> "$config_file"
        echo "    ssl_session_cache shared:SSL:10m;" >> "$config_file"
        echo "    ssl_session_timeout 10m;" >> "$config_file"
        echo "    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';" >> "$config_file"
        echo "    ssl_prefer_server_ciphers on;" >> "$config_file"
        echo "    ssl_protocols TLSv1.2 TLSv1.3;" >> "$config_file"

        if "$hsts_enabled"; then
            echo "    # 启用 HSTS (半年)" >> "$config_file"
            echo "    add_header Strict-Transport-Security \"max-age=15768000; includeSubDomains\" always;" >> "$config_file"
        fi
    else
        echo "    # HTTP 监听" >> "$config_file"
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

        # 仅在混合模式下，默认location不做处理，留给后面代理
        if [[ "$WORK_MODE" == "static" ]]; then
            echo "    location / {" >> "$config_file"
            echo "        try_files \$uri \$uri/ =404;" >> "$config_file"
            echo "    }" >> "$config_file"
        fi
    fi

    # 2. 路径反代配置 (纯反代/混合模式)
    if [[ "$WORK_MODE" == "proxy" || "$WORK_MODE" == "mixed" ]]; then
        # 如果是纯反代模式，或者混合模式但没有定义特定路径代理，则使用根路径代理
        if [[ "$WORK_MODE" == "proxy" && ${#PROXY_RULES[@]} -eq 0 ]]; then
             # 纯反代但没有特定路径规则，默认代理根目录
             PROXY_RULES+=("/|${server_names}|true") # 默认代理所有流量，这里backend_url可以是任意值，但逻辑上必须有一个根代理
             # 强制要求用户至少有一个路径代理，否则配置逻辑不完整。
             # 为简化，如果用户选了纯反代，但在迭代中没有添加任何规则，此处会产生一个空配置，所以保持原逻辑，在纯反代时，/ 路径是必须被代理的。
             # 但由于我们要求用户迭代添加，所以理论上PROXY_RULES应该不会空。
             print_color "警告：纯反代模式下未检测到路径规则，请确保至少添加了 '/' 路径代理。" "$YELLOW"
        fi

        for rule in "${PROXY_RULES[@]}"; do
            IFS='|' read -r proxy_path backend_url proxy_set_host <<< "$rule"
            echo "    # 反向代理: $proxy_path -> $backend_url" >> "$config_file"
            echo "    location $proxy_path {" >> "$config_file"
            echo "        proxy_pass $backend_url;" >> "$config_file"
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
        elif [[ "$WORK_MODE" == "proxy" && ${#PROXY_RULES[@]} -gt 0 ]]; then
            # 纯反代模式下，如果根路径没有被代理，需要提供一个默认的 404
            # 考虑到用户已经迭代添加了规则，这个分支比较复杂，通常纯反代要么代理 / ，要么所有未匹配都返回 404
            # 为了安全，未匹配到的路径直接返回404，不暴露服务器信息
            :
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
            echo "    listen $listen_port;" >> "$config_file"
            if "$ssl_enabled"; then
                echo "    listen $listen_port ssl http2;" >> "$config_file"
            fi
            echo "    server_name $subdomain;" >> "$config_file"
            echo "    # 子域名代理: $subdomain -> $backend_url" >> "$config_file"
            echo "    location / {" >> "$config_file"
            echo "        proxy_pass $backend_url;" >> "$config_file"
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

# --- 修改：Caddy 配置生成 ---
generate_caddy_config() {
    local config_file="caddy_$(echo "$server_names" | awk '{print $1}' | tr -cd '[:alnum:]_-')_$(date +%Y%m%d_%H%M%S).Caddyfile"
    print_color "--- 正在生成 Caddyfile 配置 ---" "$CYAN"

    # Caddyfile 头部 (主域名)
    local address
    if "$ssl_enabled"; then
        address="$server_names:$listen_port"
    elif [ "$listen_port" -eq 80 ]; then
        address="$server_names"
    else
        address="$server_names:$listen_port"
    fi
    echo "$address {" > "$config_file"

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
            echo "    route $proxy_path/* {" >> "$config_file"
            echo "        reverse_proxy $backend_url" >> "$config_file"
            
            if [[ "$proxy_set_host" == "true" ]]; then
                echo "        header_up Host {http.request.host}" >> "$config_file"
            fi
            echo "    }" >> "$config_file"
        done
        
        # 纯反代模式下，如果根路径没有被代理，则代理根路径。
        if [[ "$WORK_MODE" == "proxy" && ${#PROXY_RULES[@]} -eq 0 ]]; then
             print_color "警告：纯反代模式下未检测到路径规则，默认将根路径 '/' 代理到第一个后端地址。" "$YELLOW"
             read -e -p "请输入默认后端服务地址 (例如: http://127.0.0.1:8080): " default_backend_url
             echo "    # 纯反代模式下，默认代理所有流量" >> "$config_file"
             echo "    reverse_proxy $default_backend_url" >> "$config_file"
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
            echo "    # 子域名代理: $subdomain -> $backend_url" >> "$config_file"
            echo "    reverse_proxy $backend_url" >> "$config_file"
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