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
ROOT_ACTION="" # 根路径处理: "404" 或 "proxy|backend_url|set_host"


# 打印带颜色的消息
print_color() {
    echo -e "${2}${1}${NC}"
}

# 显示标题
print_title() {
    echo "========================================="
    echo "    Web服务器配置生成器（V2.8 修复版）"
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

# 后端地址标准化：如果只输入端口号，默认使用 http://127.0.0.1:
normalize_backend_url() {
    local url=$1
    if [[ "$url" =~ ^[0-9]+$ ]]; then
        # 仅是端口号
        echo "http://127.0.0.1:$url"
    elif [[ "$url" =~ ^:[0-9]+$ ]]; then
        # 仅是 :端口号
        echo "http://127.0.0.1$url"
    elif [[ ! "$url" =~ ^https?:// ]]; then
        # 缺少协议，默认添加 http://
        echo "http://$url"
    else
        echo "$url"
    fi
}

# 路径标准化：只保证有前导斜杠，不强制添加尾部斜杠，解决路径匹配文件和目录的冲突。
normalize_proxy_path() {
    local path=$1
    
    # 1. 移除首尾可能的多余引号
    path=$(echo "$path" | sed -e 's/^"//' -e 's/"$//')

    # 2. 确保有前导斜杠
    if [[ ! "$path" =~ ^/ ]]; then
        path="/$path"
    fi

    # 3. 不强制添加尾部斜杠 (保留用户选择的灵活性)
    
    echo "$path"
}

# --- 获取工作模式和根路径 ---
get_work_mode() {
    local choice
    # 重置 root_path
    root_path=""

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
            
            # Fatal Error 3 修复：必须有 root
            if [[ -z "$root_path" ]]; then
                print_color "根目录不能为空，请重新输入。" "$RED"
                continue
            fi

            if [[ -d "$root_path" ]]; then
                print_color "静态文件根目录: $root_path" "$GREEN"
                break
            else
                print_color "警告: 路径 $root_path 不存在或不是目录。强烈建议使用存在的路径。" "$YELLOW"
                read -p "是否继续使用此路径? [Y/n]: " continue_path
                if [[ "$continue_path" =~ ^[nN]$ ]]; then
                    continue
                else
                    break
                fi
            fi
        done
    # 纯反代模式下，root_path 留空，Nginx 生成时会给一个安全默认值
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

    local raw_proxy_path
    local proxy_path # This will be the normalized path
    local raw_backend_url
    local backend_url
    local proxy_set_host="true"
    local set_host_choice

    while true; do
        read -e -p "请输入要代理的路径 (例如: api, /admin, 或带通配符 /data/*): " raw_proxy_path
        if [[ -z "$raw_proxy_path" ]]; then
            print_color "路径不能为空" "$RED"
        else
            proxy_path=$(normalize_proxy_path "$raw_proxy_path") # Call the new normalization function
            break
        fi
    done

    read -e -p "请输入后端服务地址 (例如: http://127.0.0.1:8080 或只输入端口 8080): " raw_backend_url
    backend_url=$(normalize_backend_url "$raw_backend_url")

    # 默认 Y
    read -p "是否设置 Proxy Header 'Host' 为原始域名 (默认: Y)? [Y/n]: " set_host_choice
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
    local raw_backend_url
    local backend_url

    while true; do
        read -e -p "请输入子域名 (例如: api.example.com): " subdomain
        if [[ -z "$subdomain" ]]; then
            print_color "子域名不能为空" "$RED"
        else
            break
        fi
    done

    read -e -p "请输入后端服务地址 (例如: http://127.0.0.1:8080 或只输入端口 8080): " raw_backend_url
    backend_url=$(normalize_backend_url "$raw_backend_url")

    # 存储规则到全局数组: SUBDOMAIN_PROXIES
    SUBDOMAIN_PROXIES+=("${subdomain}|${backend_url}")
    print_color "已添加子域名规则: $subdomain -> $backend_url" "$GREEN"
    return 0
}

# --- 主配置收集函数 (get_web_config) ---
get_web_config() {
    # 每次运行时重置配置
    server_names=""
    listen_port=80
    ssl_enabled=false
    ssl_cert=""
    ssl_key=""
    hsts_enabled=false
    gzip_enabled=false
    root_path="" # 保持 root_path 清空，让 get_work_mode 处理

    WORK_MODE=""
    PROXY_CONFIG_TYPE=""
    PROXY_RULES=()
    SUBDOMAIN_PROXIES=()
    ROOT_ACTION=""

    print_color "--- 基础配置 ---" "$CYAN"

    # 1. 端口选择
    local port_choice
    local non_std_port
    local ssl_choice_std

    while true; do
        read -p "是否使用标准端口 (HTTP: 80, HTTPS: 443)? [Y/n]: " port_choice
        if [[ "$port_choice" =~ ^[nN]$ ]]; then
            # 非标准端口
            while true; do
                read -p "请输入非标准监听端口 (例如: 8080): " non_std_port
                if validate_port "$non_std_port"; then
                    listen_port="$non_std_port"
                    
                    # 询问是否启用 HTTPS/SSL (默认 Y)
                    read -p "非标准端口 $listen_port 是否启用 HTTPS/SSL? [Y/n]: " ssl_choice_non_std
                    if [[ "$ssl_choice_non_std" =~ ^[yY]$ || "$ssl_choice_non_std" == "" ]]; then
                        ssl_enabled=true
                        print_color "已选择非标准端口 $listen_port，启用 HTTPS/SSL。" "$GREEN"
                    else
                        ssl_enabled=false
                        print_color "已选择非标准端口 $listen_port，使用 HTTP。" "$GREEN"
                    fi
                    break 2 # 跳出内外循环
                fi
            done
        elif [[ "$port_choice" =~ ^[yY]$ || "$port_choice" == "" ]]; then
            # 标准端口
            # 询问是否启用 HTTPS/SSL (默认 Y)
            read -p "是否启用 HTTPS/SSL? (标准端口，将使用 80 重定向至 443) [Y/n]: " ssl_choice_std
            if [[ "$ssl_choice_std" =~ ^[yY]$ || "$ssl_choice_std" == "" ]]; then
                ssl_enabled=true
                listen_port=443 # 主监听端口为 443
                print_color "已选择标准端口 80 和 443，启用 HTTPS (将使用301重定向)。" "$GREEN"
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
        print_color "--- SSL/TLS 证书配置 (支持手动填写/自签证书) ---" "$CYAN"
        
        # Fatal Error 2 修复：即使为空，也允许继续，但需要提供默认占位符
        read -e -p "请输入 SSL 证书文件绝对路径 (.crt/.pem) [留空，将使用默认占位]: " ssl_cert
        read -e -p "请输入 SSL 密钥文件绝对路径 (.key) [留空，将使用默认占位]: " ssl_key
        
        if [[ -z "$ssl_cert" || -z "$ssl_key" ]]; then
            print_color "警告: 证书或密钥路径为空。配置中将使用默认占位符，请在部署前务必手动修改！" "$YELLOW"
        fi

        # 默认 Y
        read -p "是否启用 HSTS 强制安全连接? [Y/n]: " hsts_choice
        if [[ ! "$hsts_choice" =~ ^[nN]$ ]]; then
            hsts_enabled=true
        fi
    fi

    # 4. Gzip (默认 Y)
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
                
                # 默认 Y
                read -e -p "是否继续添加下一个基于路径的反向代理? [Y/n]: " cont
                if [[ "$cont" =~ ^[nN]$ ]]; then
                    break
                fi
            done
        elif [[ "$PROXY_CONFIG_TYPE" == "subdomain" ]]; then
            while true; do
                get_subdomain_based_proxies
                
                # 默认 Y
                read -e -p "是否继续添加下一个基于子域名的反向代理? [Y/n]: " cont
                if [[ "$cont" =~ ^[nN]$ ]]; then
                    break
                fi
            done
        fi

        # 7. --- 根路径 '/' 处理 (适用于路径反代/混合模式) ---
        print_color "--- 根路径 '/' 处理 ---" "$CYAN"
        local root_choice
        local raw_root_backend_url
        local root_backend_url
        local root_set_host="true"
        local root_set_host_choice

        while true; do
            echo "根路径 '/' 如何处理 (如果路径反代中未明确包含 '/')?"
            echo "1. 返回 404 错误 (不响应)"
            echo "2. 反向代理到特定后端"
            # 如果是混合模式，提供第三个选项
            if [[ "$WORK_MODE" == "mixed" ]]; then
                echo "3. 服务静态文件 (Root: $root_path)"
            fi
            read -p "请选择 [1-3, 纯反代模式只有 1-2]: " root_choice
            
            case "$root_choice" in
                1)
                    ROOT_ACTION="404"
                    print_color "已选择: 根路径 '/' 返回 404" "$GREEN"
                    break
                    ;;
                2)
                    read -e -p "请输入根路径 '/' 对应的后端服务地址 (例如: http://127.0.0.1:3000 或只输入端口 3000): " raw_root_backend_url
                    root_backend_url=$(normalize_backend_url "$raw_root_backend_url")

                    # 默认 Y
                    read -p "是否设置根路径 Proxy Header 'Host' 为原始域名? [Y/n]: " root_set_host_choice
                    if [[ "$root_set_host_choice" =~ ^[nN]$ ]]; then
                        root_set_host="false"
                    fi
                    ROOT_ACTION="proxy|${root_backend_url}|${root_set_host}"
                    print_color "已选择: 根路径 '/' 反向代理至 $root_backend_url" "$GREEN"
                    break
                    ;;
                3)
                    if [[ "$WORK_MODE" == "mixed" ]]; then
                        ROOT_ACTION="static"
                        print_color "已选择: 根路径 '/' 服务静态文件" "$GREEN"
                        break
                    else
                        print_color "无效选择，请重试" "$RED"
                    fi
                    ;;
                *)
                    print_color "无效选择，请重试" "$RED"
                    ;;
            esac
        done
    elif [[ "$WORK_MODE" == "static" ]]; then
        ROOT_ACTION="static" # 纯静态模式下，根路径默认服务静态文件
    fi

    print_color "配置信息收集完成。" "$GREEN"
    return 0
}

# --- Nginx 配置生成 ---
generate_nginx_config() {
    local config_file="nginx_$(echo "$server_names" | awk '{print $1}' | tr -cd '[:alnum:]_-')_$(date +%Y%m%d_%H%M%S).conf"
    print_color "--- 正在生成 Nginx 配置 ---" "$CYAN"

    # --- 致命错误 3 修复：确定最终 root 路径（避免 root "" 错误） ---
    local final_root_path="/usr/share/nginx/html" # Nginx 默认的安全路径
    if [[ -n "$root_path" ]]; then
        final_root_path="$root_path" # 使用用户输入的路径
    fi
    
    # HTTP 重定向块 (仅在启用了 SSL 且使用的是标准端口 443 时生成 301 重定向)
    if "$ssl_enabled" && [ "$listen_port" -eq 443 ]; then
        echo "server {" > "$config_file"
        echo "    listen 80;" >> "$config_file"
        echo "    server_name $server_names;" >> "$config_file"
        echo "    # 标准端口(80)重定向到 HTTPS (443)" >> "$config_file"
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

        # --- 致命错误 1 修复：497 错误重定向 (移除 =301，使用 $server_port) ---
        if [ "$listen_port" -ne 443 ]; then
            echo "    # Nginx 497 错误强制重定向 (非标准 SSL 端口的 HTTP 请求强制 301 跳转到 HTTPS)" >> "$config_file"
            echo "    error_page 497 https://\$host:\$server_port\$request_uri;" >> "$config_file"
        fi
        
        # --- 致命错误 2 修复：SSL 证书配置 (不能使用空字符串 "" ) ---
        echo "    # --- SSL 证书配置 (支持自签证书) ---" >> "$config_file"
        if [[ -z "$ssl_cert" || -z "$ssl_key" ]]; then
            echo "    # !!! 警告: 证书或密钥路径为空。请手动修改以下两行！" >> "$config_file"
            echo "    ssl_certificate     /etc/ssl/certs/nginx-default.crt;" >> "$config_file"
            echo "    ssl_certificate_key /etc/ssl/private/nginx-default.key;" >> "$config_file"
        else
            echo "    ssl_certificate     $ssl_cert;" >> "$config_file"
            echo "    ssl_certificate_key $ssl_key;" >> "$config_file"
        fi

        echo "    ssl_session_cache shared:SSL:10m;" >> "$config_file"
        echo "    ssl_session_timeout 10m;" >> "$config_file"
        
        # --- 隐患修复：ssl_prefer_server_ciphers 改为 off (现代最佳实践) ---
        echo "    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';" >> "$config_file"
        echo "    ssl_prefer_server_ciphers off;" >> "$config_file"
        echo "    ssl_protocols TLSv1.2 TLSv1.3;" >> "$config_file"
        echo "    # --- SSL 证书配置结束 ---" >> "$config_file"

        # --- 隐患修复：HSTS 加上 always ---
        if "$hsts_enabled"; then
            echo "    # 启用 HSTS (半年), 确保 always" >> "$config_file"
            echo "    add_header Strict-Transport-Security \"max-age=15768000; includeSubDomains\" always;" >> "$config_file"
        fi
    else
        echo "    # HTTP 监听: $listen_port" >> "$config_file"
        echo "    listen $listen_port;" >> "$config_file"
        echo "    server_name $server_names;" >> "$config_file"
    fi
    
    # --- 隐患修复：添加通用安全 Header ---
    echo "    # 推荐安全 Header" >> "$config_file"
    echo "    add_header X-Frame-Options SAMEORIGIN;" >> "$config_file"
    echo "    add_header X-Content-Type-Options nosniff;" >> "$config_file"
    echo "    add_header X-XSS-Protection \"1; mode=block\";" >> "$config_file"

    # Gzip 配置
    if "$gzip_enabled"; then
        echo "    # Gzip 压缩配置" >> "$config_file"
        echo "    gzip on;" >> "$config_file"
        echo "    gzip_min_length 1k;" >> "$config_file"
        echo "    gzip_comp_level 5;" >> "$config_file"
        echo "    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;" >> "$config_file"
    fi

    # --- 3. 根目录配置 (为 location 块提供环境) ---
    echo "    # 服务器根目录 (为静态文件和 location 块提供 context)" >> "$config_file"
    echo "    root $final_root_path;" >> "$config_file"
    echo "    index index.html index.htm;" >> "$config_file"

    # --- 2. 路径反代配置 (优先级最高) ---
    if [[ "$PROXY_CONFIG_TYPE" == "path" ]]; then
        # 遍历所有路径反代规则
        for rule in "${PROXY_RULES[@]}"; do
            IFS='|' read -r proxy_path backend_url proxy_set_host <<< "$rule"
            
            # 使用 "^~"（前缀最长匹配）确保代理规则的优先级高于 location /
            echo "    # 反向代理: $proxy_path (前缀最长匹配 ^~)" >> "$config_file"
            # 移除 location 路径周围的引号，更符合 Nginx 习惯
            echo "    location ^~ $proxy_path {" >> "$config_file" 
            
            # --- 隐患修复：proxy_pass 移除引号 (Nginx 不需要引号) ---
            if [[ "$proxy_path" =~ \*$ ]]; then
                 # 示例: location /data/* { proxy_pass http://backend; }
                 echo "        proxy_pass $backend_url;" >> "$config_file"
            elif [[ ! "$proxy_path" =~ /$ ]]; then
                # /api 这样的路径，使用 $request_uri 确保完整路径发送
                echo "        # Nginx 默认行为：proxy_pass 值无 / 则不剥离前缀，有 / 则剥离前缀。" >> "$config_file"
                echo "        proxy_pass $backend_url\$request_uri;" >> "$config_file"
            else
                # proxy_path 以 / 结尾，例如 /api/
                echo "        proxy_pass $backend_url;" >> "$config_file"
            fi
            
            echo "        proxy_redirect off;" >> "$config_file"
            echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$config_file"
            echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" >> "$config_file"
            # --- 隐患修复：添加 X-Forwarded-Proto (解决后端识别协议问题) ---
            echo "        proxy_set_header X-Forwarded-Proto \$scheme;" >> "$config_file"
            
            if [[ "$proxy_set_host" == "true" ]]; then
                # 隐患修复：使用 $host (比 $http_host 更健壮)
                echo "        proxy_set_header Host \$host;" >> "$config_file"
            fi
            
            echo "        proxy_http_version 1.1;" >> "$config_file"
            echo "        proxy_set_header Upgrade \$http_upgrade;" >> "$config_file"
            echo "        proxy_set_header Connection \"upgrade\";" >> "$config_file"
            echo "    }" >> "$config_file"
        done
    fi

    # --- 3. 根路径 '/' 特殊处理 (处理根路径精确匹配) ---
    if [[ "$WORK_MODE" != "static" && -n "$ROOT_ACTION" ]]; then
        if [[ "$ROOT_ACTION" == "404" ]]; then
            echo "    # 根路径 '/' 返回 404 (精确匹配)" >> "$config_file"
            echo "    location = / {" >> "$config_file"
            echo "        return 404;" >> "$config_file"
            echo "    }" >> "$config_file"
        elif [[ "$ROOT_ACTION" == "static" ]]; then
            echo "    # 根路径 '/' 服务静态文件 (精确匹配)" >> "$config_file"
            echo "    location = / {" >> "$config_file"
            echo "        try_files \$uri \$uri/ =404;" >> "$config_file"
            echo "    }" >> "$config_file"
        elif [[ "$ROOT_ACTION" =~ ^proxy\| ]]; then
            IFS='|' read -r _ root_backend_url root_set_host <<< "$ROOT_ACTION"
            echo "    # 根路径 '/' 反向代理: / -> $root_backend_url (精确匹配)" >> "$config_file"
            echo "    location = / {" >> "$config_file"
            
            # --- 隐患修复：proxy_pass 移除引号 ---
            echo "        proxy_pass $root_backend_url;" >> "$config_file"
            
            echo "        proxy_redirect off;" >> "$config_file"
            echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$config_file"
            echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" >> "$config_file"
            # --- 隐患修复：添加 X-Forwarded-Proto ---
            echo "        proxy_set_header X-Forwarded-Proto \$scheme;" >> "$config_file"

            if [[ "$root_set_host" == "true" ]]; then
                # 隐患修复：使用 $host
                echo "        proxy_set_header Host \$host;" >> "$config_file"
            fi
            
            echo "        proxy_http_version 1.1;" >> "$config_file"
            echo "        proxy_set_header Upgrade \$http_upgrade;" >> "$config_file"
            echo "        proxy_set_header Connection \"upgrade\";" >> "$config_file"
            echo "    }" >> "$config_file"
        fi
    fi

    # --- 4. 默认/兜底处理 (location /) ---
    echo "    # 默认/兜底处理: location / (处理未匹配的子路径)" >> "$config_file"
    echo "    location / {" >> "$config_file"
    
    if [[ "$WORK_MODE" == "static" || "$WORK_MODE" == "mixed" ]]; then
        echo "        # 混合模式或纯静态模式下，处理未匹配到的静态文件" >> "$config_file"
        echo "        try_files \$uri \$uri/ =404;" >> "$config_file"
    elif [[ "$WORK_MODE" == "proxy" ]]; then
        # 纯反代模式下，默认 location / 返回 404 (代理逻辑应在精确匹配的 location 中处理)
        echo "        # 纯反代模式，未匹配到任何显式 location 规则，返回 404" >> "$config_file"
        echo "        return 404;" >> "$config_file"
    fi
    echo "    }" >> "$config_file"
    
    echo "}" >> "$config_file"

    # --- 5. 子域名反代配置 (每个子域名独立 server 块) ---
    if [[ "$PROXY_CONFIG_TYPE" == "subdomain" ]]; then
        print_color "注意: 子域名反代将生成独立的 Server 块，它们使用与主域名相同的端口和 SSL 证书设置。" "$YELLOW"
        for rule in "${SUBDOMAIN_PROXIES[@]}"; do
            IFS='|' read -r subdomain backend_url <<< "$rule"
            echo "" >> "$config_file"
            echo "server {" >> "$config_file"
            
            if "$ssl_enabled"; then
                echo "    listen $listen_port ssl http2;" >> "$config_file"
                echo "    server_name $subdomain;" >> "$config_file"
                
                # 使用主配置中的证书路径逻辑
                if [[ -z "$ssl_cert" || -z "$ssl_key" ]]; then
                    echo "    ssl_certificate     /etc/ssl/certs/nginx-default.crt;" >> "$config_file"
                    echo "    ssl_certificate_key /etc/ssl/private/nginx-default.key;" >> "$config_file"
                else
                    echo "    ssl_certificate     $ssl_cert;" >> "$config_file"
                    echo "    ssl_certificate_key $ssl_key;" >> "$config_file"
                fi
            else
                echo "    listen $listen_port;" >> "$config_file"
                echo "    server_name $subdomain;" >> "$config_file"
            fi
            
            # 纯反代模式，设置默认 root 避免 Nginx 报错
            echo "    root $final_root_path;" >> "$config_file"

            echo "    # 子域名代理: $subdomain -> $backend_url" >> "$config_file"
            echo "    location / {" >> "$config_file"
            # --- 隐患修复：proxy_pass 移除引号 ---
            echo "        proxy_pass $backend_url;" >> "$config_file"

            echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$config_file"
            echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" >> "$config_file"
            # --- 隐患修复：添加 X-Forwarded-Proto ---
            echo "        proxy_set_header X-Forwarded-Proto \$scheme;" >> "$config_file"
            
            echo "        proxy_set_header Host \$host;" >> "$config_file" # 子域名代理默认设置 Host
            echo "    }" >> "$config_file"
            echo "}" >> "$config_file"
        done
    fi


    print_color "Nginx 配置生成成功: $config_file" "$GREEN"
    echo ""
    print_color "--- Nginx 使用示例 ---" "$YELLOW"
    echo "1. 将配置文件复制到 Nginx 配置目录:"
    echo "   cp \"$config_file\" /etc/nginx/conf.d/"
    echo "2. 检查配置语法 (必须通过):"
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
    
    # 确定 Caddy 监听地址
    if "$ssl_enabled"; then
        # Caddy 会自动处理非标准 HTTPS 端口的证书和重定向
        address="$server_names:$listen_port"
    elif [ "$listen_port" -eq 80 ]; then
        address="$server_names"
    else
        # 非标准 HTTP 端口
        address="http://$server_names:$listen_port"
    fi
    
    echo "$address {" > "$config_file"

    # Caddy SSL/TLS 证书配置 (手动模式)
    if "$ssl_enabled"; then
        echo "    # --- SSL 证书配置 (支持自签/内置/外部) ---" >> "$config_file"
        if [[ -n "$ssl_cert" && -n "$ssl_key" ]]; then
            echo "    # 使用用户提供的证书路径" >> "$config_file"
            echo "    tls $ssl_cert $ssl_key" >> "$config_file"
        else
            echo "    # 证书路径为空，使用 Caddy 内置的证书管理 (自签或ACME)" >> "$config_file"
            if [ "$listen_port" -eq 443 ]; then
                 echo "    tls" # 标准 443 端口，默认启用ACME (Let's Encrypt)
            else
                 echo "    tls internal" # 非标准端口，默认使用内部自签名
            fi
        fi
        echo "    # --- SSL 证书配置结束 ---" >> "$config_file"

        # 如果是标准端口 443，Caddy 会自动设置 80 -> 443 重定向。
        # 如果是非标准端口，Caddy 会自动处理 HTTP 到 HTTPS 的跳转。
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
    
    # 隐患修复：添加通用安全 Header
    echo "    # 推荐安全 Header" >> "$config_file"
    echo "    header X-Frame-Options SAMEORIGIN" >> "$config_file"
    echo "    header X-Content-Type-Options nosniff" >> "$config_file"
    echo "    header X-XSS-Protection \"1; mode=block\"" >> "$config_file"

    # --- 1. 静态文件配置 (仅静态/混合模式) ---
    if [[ "$WORK_MODE" == "static" || "$WORK_MODE" == "mixed" ]]; then
        echo "    # 静态文件配置" >> "$config_file"
        echo "    root * $root_path" >> "$config_file"
        echo "    file_server" >> "$config_file"
    fi

    # --- 2. 路径反代配置 (优先级高) ---
    if [[ "$PROXY_CONFIG_TYPE" == "path" ]]; then
        for rule in "${PROXY_RULES[@]}"; do
            IFS='|' read -r proxy_path backend_url proxy_set_host <<< "$rule"
            echo "    # 反向代理: $proxy_path -> $backend_url" >> "$config_file"
            # Caddy 使用 handle 确保精确匹配，并使用 * 来匹配所有子路径
            echo "    handle $proxy_path $proxy_path/* {" >> "$config_file"
            echo "        reverse_proxy $backend_url" >> "$config_file"
            
            if [[ "$proxy_set_host" == "true" ]]; then
                echo "        header_up Host {http.request.host}" >> "$config_file"
            fi
            # Caddy 自动添加 X-Forwarded-Proto, X-Real-IP 等标准头
            echo "    }" >> "$config_file"
        done
    fi

    # --- 3. 根路径 '/' 特殊处理 (处理根路径精确匹配) ---
    if [[ "$WORK_MODE" != "static" && -n "$ROOT_ACTION" ]]; then
        echo "    # 根路径 '/' 精确匹配处理" >> "$config_file"
        if [[ "$ROOT_ACTION" == "404" ]]; then
            echo "    route / {" >> "$config_file"
            echo "        respond 404" >> "$config_file"
            echo "    }" >> "$config_file"
        elif [[ "$ROOT_ACTION" == "static" ]]; then
            echo "    route / {" >> "$config_file"
            echo "        file_server" >> "$config_file"
            echo "    }" >> "$config_file"
        elif [[ "$ROOT_ACTION" =~ ^proxy\| ]]; then
            IFS='|' read -r _ root_backend_url root_set_host <<< "$ROOT_ACTION"
            echo "    route / {" >> "$config_file"
            echo "        reverse_proxy $root_backend_url" >> "$config_file"
            
            if [[ "$root_set_host" == "true" ]]; then
                echo "        header_up Host {http.request.host}" >> "$config_file"
            fi
            echo "    }" >> "$config_file"
        fi
    fi
    
    echo "}" >> "$config_file"

    # --- 4. 子域名反代配置 (每个子域名独立 Server 块) ---
    if [[ "$PROXY_CONFIG_TYPE" == "subdomain" ]]; then
        print_color "注意: 子域名反代将生成独立的 Server 块，使用与主域名相同的端口和 SSL 证书设置。" "$YELLOW"
        for rule in "${SUBDOMAIN_PROXIES[@]}"; do
            IFS='|' read -r subdomain backend_url <<< "$rule"
            echo "" >> "$config_file"
            echo "$subdomain {" >> "$config_file"
            
            if "$ssl_enabled"; then
                 if [[ -n "$ssl_cert" && -n "$ssl_key" ]]; then
                    echo "    tls $ssl_cert $ssl_key" >> "$config_file"
                else
                    echo "    tls internal"
                fi
            fi
            
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
        # 确保 choice 变量在 read 之前被声明
        choice="" 
        read -p "请选择 [0-2]: " choice

        # 确保 choice 不为空，如果为空，使用一个无效值
        if [ -z "$choice" ]; then
            choice="-1"
        fi

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
            cont=""
            read -e -p "是否继续生成其他配置? [Y/n/0退出]: " cont
            
            # 如果 cont 为空，默认视为 Y
            if [ -z "$cont" ]; then
                cont="Y"
            fi

            case "$cont" in
                0)
                    print_color "再见！" "$GREEN"
                    exit 0
                    ;;
                y|Y)
                    break  # 继续
                    ;;
                n|N)
                    print_color "再见！" "$GREEN"
                    exit 0
                    ;;\
                *)\
                    print_color "无效选择，请重试" "$RED"
                    ;;
            esac
        done
    done
}

# 运行主程序
main