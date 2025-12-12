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
root_path="" # 默认使用 /var/www/html 或 /usr/share/nginx/html，用户可覆盖

# 工作模式配置
WORK_MODE="" # static, proxy, mixed
PROXY_CONFIG_TYPE="" # path, subdomain
PROXY_RULES=() # 路径反代规则数组: "path|backend_url|proxy_set_host"
SUBDOMAIN_PROXIES=() # 子域名反代规则数组: "subdomain|backend_url|proxy_set_host"
ROOT_ACTION="" # 根路径处理: "404", "static", 或 "proxy|backend_url|set_host"


# 打印带颜色的消息
print_color() {
    echo -e "${2}${1}${NC}"
}

# 显示标题
print_title() {
    echo "========================================="
    echo " Web服务器配置生成器（v3.0 逻辑一致性版）"
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
# 这是确保所有代理配置一致性的关键函数
normalize_backend_url() {
    local url=$1
    if [[ "$url" =~ ^[0-9]+$ ]]; then
        # 仅是端口号 -> 默认使用本机 HTTP
        echo "http://127.0.0.1:$url"
    elif [[ "$url" =~ ^:[0-9]+$ ]]; then
        # 仅是 :端口号 -> 默认使用本机 HTTP
        echo "http://127.0.0.1$url"
    elif [[ ! "$url" =~ ^https?:// ]]; then
        # 缺少协议，默认添加 http://
        echo "http://$url"
    else
        echo "$url"
    fi
}

# 路径标准化：只保证有前导斜杠，不强制添加尾部斜杠
normalize_proxy_path() {
    local path=$1
    
    # 1. 移除首尾可能的多余引号
    path=$(echo "$path" | sed -e 's/^"//' -e 's/"$//')

    # 2. 确保有前导斜杠
    if [[ ! "$path" =~ ^/ ]]; then
        path="/$path"
    fi
    
    echo "$path"
}

# --- 获取工作模式和根路径 ---
get_work_mode() {
    local choice
    local default_root="/var/www/html" # 默认规范的静态文件路径
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

    # Get root path if required (使用 /var/www/html 作为默认)
    if [[ "$WORK_MODE" == "static" || "$WORK_MODE" == "mixed" ]]; then
        while true; do
            read -e -p "请输入静态网站文件的根目录绝对路径 (默认: $default_root): " root_path_input
            
            # 使用默认值或用户输入的值
            if [[ -z "$root_path_input" ]]; then
                root_path="$default_root"
            else
                root_path="$root_path_input"
            fi

            # 仅打印警告，不强制退出
            if [[ ! -d "$root_path" ]]; then
                print_color "警告: 路径 $root_path 不存在或不是目录。建议使用存在的路径。" "$YELLOW"
                read -p "是否继续使用此路径? [Y/n]: " continue_path
                if [[ "$continue_path" =~ ^[nN]$ ]]; then
                    continue
                else
                    break
                fi
            else
                print_color "静态文件根目录: $root_path" "$GREEN"
                break
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
            echo "2. 基于子域名的反向代理 (例如: api.domain.com -> backend)"
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
            proxy_path=$(normalize_proxy_path "$raw_proxy_path") # 调用路径标准化函数
            break
        fi
    done

    # 关键：使用 normalize_backend_url 确保端口输入自动解析到 http://127.0.0.1:
    read -e -p "请输入后端服务地址 (例如: http://127.0.0.1:8080 或只输入端口 8080): " raw_backend_url
    backend_url=$(normalize_backend_url "$raw_backend_url")

    # Host Header 一致性配置
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
    local proxy_set_host="true"
    local set_host_choice # 确保所有代理类型都有一致的配置选项

    while true; do
        # 明确要求 FQDN 域名
        read -e -p "请输入子域名 (必须是完整域名, 例如: api.example.com): " subdomain
        if [[ -z "$subdomain" ]]; then
            print_color "子域名不能为空" "$RED"
        # 简单检查是否包含 . (避免输入裸词如 api)
        elif [[ ! "$subdomain" =~ \. ]]; then
             print_color "警告: 建议输入完整域名 (FQDN)，例如 api.example.com" "$YELLOW"
        fi
        
        if [[ -n "$subdomain" ]]; then
            break
        fi
    done

    # 关键：使用 normalize_backend_url 确保端口输入自动解析到 http://127.0.0.1:
    read -e -p "请输入后端服务地址 (例如: http://127.0.0.1:8080 或只输入端口 8080): " raw_backend_url
    backend_url=$(normalize_backend_url "$raw_backend_url")
    
    # Host Header 一致性配置 (与路径代理一致)
    read -p "是否设置 Proxy Header 'Host' 为原始域名 (默认: Y)? [Y/n]: " set_host_choice
    if [[ "$set_host_choice" =~ ^[nN]$ ]]; then
        proxy_set_host="false"
    fi


    # 存储规则到全局数组: SUBDOMAIN_PROXIES
    SUBDOMAIN_PROXIES+=("${subdomain}|${backend_url}|${proxy_set_host}")
    print_color "已添加子域名规则: $subdomain -> $backend_url (设置Host: $proxy_set_host)" "$GREEN"
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
    root_path="" 

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
        # 默认 Y
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
            # 标准端口 (默认 Y)
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
    local server_names_input
    # 允许留空，并给出提示
    read -e -p "请输入域名 (多个用空格分隔) [留空，将使用 'localhost']: " server_names_input
    
    # 如果用户输入为空，使用 localhost
    if [[ -z "$server_names_input" ]]; then
        server_names="localhost"
        print_color "已选择默认域名: localhost" "$YELLOW"
    else
        # 如果用户输入了域名，也添加 localhost，并确保唯一性
        server_names="$server_names_input localhost"
        # 使用 AWK 确保 server_names 中的域名是唯一的 (以防用户自己输入 localhost)
        server_names=$(echo "$server_names" | tr ' ' '\n' | awk '!a[$0]++' | tr '\n' ' ' | sed 's/ $//')
        print_color "域名: $server_names" "$GREEN"
    fi


    # 3. SSL/TLS 配置（仅在启用了 SSL 时询问证书）
    if "$ssl_enabled"; then
        print_color "--- SSL/TLS 证书配置 (支持手动填写/自签证书) ---" "$CYAN"
        
        # 即使为空，也允许继续，但需要提供默认占位符
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
                    # 关键：使用 normalize_backend_url 确保端口输入自动解析到 http://127.0.0.1:
                    read -e -p "请输入根路径 '/' 对应的后端服务地址 (例如: http://127.0.0.1:3000 或只输入端口 3000): " raw_root_backend_url
                    root_backend_url=$(normalize_backend_url "$raw_root_backend_url")

                    # Host Header 一致性配置
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
    # 使用第一个域名/localhost作为文件名
    local config_file="nginx_$(echo "$server_names" | awk '{print $1}' | tr -cd '[:alnum:]_-')_$(date +%Y%m%d_%H%M%S).conf"
    print_color "--- 正在生成 Nginx 配置 ---" "$CYAN"

    # --- 确定最终 root 路径（避免 root "" 错误） ---
    # Nginx 默认的安全路径，如果 root_path (用户输入/默认值) 为空，则使用此路径
    local final_root_path="/usr/share/nginx/html" 
    if [[ -n "$root_path" ]]; then
        final_root_path="$root_path" # 使用用户输入或 /var/www/html 默认值
    fi
    
    # 定义统一的代理通用配置块 (实现通用配置一致性)
    local nginx_proxy_common_headers
    nginx_proxy_common_headers=$(cat <<EOF
        proxy_redirect off;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
EOF
)

    # HTTP 重定向块 (仅在启用了 SSL 且使用的是标准端口 443 时生成 301 重定向)
    if "$ssl_enabled" && [ "$listen_port" -eq 443 ]; then
        echo "server {" > "$config_file"
        echo "    listen 80;" >> "$config_file"
        # 80 端口必须匹配真实域名才能跳转
        echo "    server_name $server_names;" >> "$config_file" 
        echo "    # 标准端口(80)重定向到 HTTPS (443)" >> "$config_file"
        echo "    return 301 https://\$server_name\$request_uri;" >> "$config_file" 
        echo "}" >> "$config_file"
        echo "" >> "$config_file"
    fi

    # HTTPS/HTTP 主配置块
    echo "server {" >> "$config_file"
    
    if "$ssl_enabled"; then
        echo "    # HTTPS 监听: $listen_port" >> "$config_file"
        echo "    listen $listen_port ssl http2;" >> "$config_file"
        echo "    server_name $server_names;" >> "$config_file"

        # 497 错误重定向 (非标准 SSL 端口的 HTTP 请求强制 301 跳转到 HTTPS)
        if [ "$listen_port" -ne 443 ]; then
            echo "    # Nginx 497 错误处理: 强制重定向到 HTTPS (非标准 SSL 端口)" >> "$config_file"
            echo "    error_page 497 https://\$host:\$server_port\$request_uri;" >> "$config_file"
        fi
        
        # SSL 证书配置
        echo "    # --- SSL 证书配置 (支持自签证书) ---" >> "$config_file"
        if [[ -z "$ssl_cert" || -z "$ssl_key" ]]; then
            echo "    # !!! 警告: 证书或密钥路径为空。配置中将使用默认占位符，请在部署前务必手动修改！" >> "$config_file"
            echo "    ssl_certificate     /etc/ssl/certs/nginx-default.crt;" >> "$config_file"
            echo "    ssl_certificate_key /etc/ssl/private/nginx-default.key;" >> "$config_file"
        else
            echo "    ssl_certificate     $ssl_cert;" >> "$config_file"
            echo "    ssl_certificate_key $ssl_key;" >> "$config_file"
        fi

        echo "    ssl_session_cache shared:SSL:10m;" >> "$config_file"
        echo "    ssl_session_timeout 10m;" >> "$config_file"
        
        # 2025 年标准 SSL 最佳实践
        echo "    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';" >> "$config_file"
        echo "    ssl_prefer_server_ciphers off;" >> "$config_file" # 现代最佳实践
        echo "    ssl_protocols TLSv1.2 TLSv1.3;" >> "$config_file"
        echo "    # --- SSL 证书配置结束 ---" >> "$config_file"

        # HSTS 加上 always
        if "$hsts_enabled"; then
            echo "    # 启用 HSTS 强制安全连接 (半年), 确保 always" >> "$config_file"
            echo "    add_header Strict-Transport-Security \"max-age=15768000; includeSubDomains\" always;" >> "$config_file"
        fi
    else
        echo "    # HTTP 监听: $listen_port" >> "$config_file"
        echo "    listen $listen_port;" >> "$config_file"
        echo "    server_name $server_names;" >> "$config_file"
    fi
    
    # 添加通用安全 Header
    echo "    # 推荐安全 Header" >> "$config_file"
    echo "    add_header X-Frame-Options SAMEORIGIN;" >> "$config_file"
    echo "    add_header X-Content-Type-Options nosniff;" >> "$config_file"
    echo "    add_header X-XSS-Protection \"1; mode=block\";" >> "$config_file"

    # Gzip 配置 (去重优化)
    if "$gzip_enabled"; then
        echo "    # Gzip 压缩配置 (已优化类型列表)" >> "$config_file"
        echo "    gzip on;" >> "$config_file"
        echo "    gzip_min_length 1k;" >> "$config_file"
        echo "    gzip_comp_level 5;" >> "$config_file"
        echo "    gzip_types text/plain text/css application/json application/javascript text/xml application/xml+rss image/svg+xml;" >> "$config_file"
    fi

    # 根目录配置 (为 location 块提供环境)
    echo "    # 服务器根目录 (为静态文件和 location 块提供 context)" >> "$config_file"
    echo "    root $final_root_path;" >> "$config_file"
    echo "    index index.html index.htm;" >> "$config_file"

    # --- 静态资源超长缓存（性能优化） ---
    echo "    # 静态资源长缓存（性能优化: 1 年缓存）" >> "$config_file"
    echo "    location ~* \\.(?:jpg|jpeg|png|gif|ico|svg|woff2?|ttf|eot|css|js)\$ {" >> "$config_file"
    echo "        expires 1y;" >> "$config_file" 
    echo "        add_header Cache-Control \"public, immutable\";" >> "$config_file"
    echo "        access_log off;" >> "$config_file" # 不记录静态文件访问日志
    echo "    }" >> "$config_file"
    echo "" >> "$config_file"


    # --- 路径反代配置 (优先级最高) ---
    if [[ "$PROXY_CONFIG_TYPE" == "path" ]]; then
        # 遍历所有路径反代规则
        for rule in "${PROXY_RULES[@]}"; do
            IFS='|' read -r proxy_path backend_url proxy_set_host <<< "$rule"
            
            # 使用 "^~"（前缀最长匹配）确保代理规则的优先级高于 location /
            echo "    # 反向代理: $proxy_path -> $backend_url (Host: $proxy_set_host)" >> "$config_file"
            echo "    location ^~ $proxy_path {" >> "$config_file" 
            
            # 统一使用不带斜杠的 proxy_pass
            echo "        proxy_pass $backend_url;" >> "$config_file" 
            
            # 插入通用配置
            echo "$nginx_proxy_common_headers" | while IFS= read -r line; do
                echo "    $line" >> "$config_file"
            done
            
            # Host Header 根据用户选择配置
            if [[ "$proxy_set_host" == "true" ]]; then
                echo "        proxy_set_header Host \$host;" >> "$config_file"
            fi
            
            echo "    }" >> "$config_file"
        done
    fi

    # --- 根路径 '/' 特殊处理 (处理根路径精确匹配) ---
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
            echo "    # 根路径 '/' 反向代理: / -> $root_backend_url (Host: $root_set_host, 精确匹配)" >> "$config_file"
            echo "    location = / {" >> "$config_file"
            
            # proxy_pass 移除引号
            echo "        proxy_pass $root_backend_url;" >> "$config_file"
            
            # 插入通用配置
            echo "$nginx_proxy_common_headers" | while IFS= read -r line; do
                echo "    $line" >> "$config_file"
            done

            # Host Header 根据用户选择配置
            if [[ "$root_set_host" == "true" ]]; then
                echo "        proxy_set_header Host \$host;" >> "$config_file"
            fi
            
            echo "    }" >> "$config_file"
        fi
    fi

    # --- 默认/兜底处理 (location /) ---
    echo "    # 默认/兜底处理: location / (处理未匹配的子路径)" >> "$config_file"
    echo "    location / {" >> "$config_file"
    
    if [[ "$WORK_MODE" == "static" || "$WORK_MODE" == "mixed" ]]; then
        echo "        # 静态/混合模式下，处理未匹配到的静态文件" >> "$config_file"
        echo "        try_files \$uri \$uri/ =404;" >> "$config_file"
    elif [[ "$WORK_MODE" == "proxy" ]]; then
        # 纯反代模式下，未被 location ^~ 明确捕获的流量，全部代理到根路径的后端 (如果根路径选择是代理)
        if [[ "$ROOT_ACTION" =~ ^proxy\| ]]; then
            IFS='|' read -r _ root_backend_url root_set_host <<< "$ROOT_ACTION"
            echo "        # 纯反代模式：未被 location ^~ 明确捕获的流量，全部代理到根路径的后端" >> "$config_file"
            echo "        proxy_pass $root_backend_url;" >> "$config_file"
            
            # 插入通用配置
            echo "$nginx_proxy_common_headers" | while IFS= read -r line; do
                echo "    $line" >> "$config_file"
            done

            # Host Header 根据用户选择配置
            if [[ "$root_set_host" == "true" ]]; then
                echo "        proxy_set_header Host \$host;" >> "$config_file"
            fi
            
        else
            # 如果 ROOT_ACTION 是 404 (或未配置)，则兜底 404
            echo "        # 纯反代模式，未匹配到任何显式 location 规则，返回 404" >> "$config_file"
            echo "        return 404;" >> "$config_file"
        fi
    fi
    echo "    }" >> "$config_file"
    
    echo "}" >> "$config_file"

    # --- 子域名反代配置 (每个子域名独立 server 块) ---
    if [[ "$PROXY_CONFIG_TYPE" == "subdomain" ]]; then
        print_color "注意: 子域名反代将生成独立的 Server 块，它们使用与主域名相同的端口和 SSL/HSTS 设置。" "$YELLOW"
        for rule in "${SUBDOMAIN_PROXIES[@]}"; do
            IFS='|' read -r subdomain backend_url proxy_set_host <<< "$rule" # <-- 读取 Host 配置
            echo "" >> "$config_file"
            echo "server {" >> "$config_file"
            
            if "$ssl_enabled"; then
                echo "    listen $listen_port ssl http2;" >> "$config_file"
                echo "    server_name $subdomain;" >> "$config_file"
                
                # 统一 SSL 证书配置 (与主块一致)
                if [[ -z "$ssl_cert" || -z "$ssl_key" ]]; then
                    echo "    ssl_certificate     /etc/ssl/certs/nginx-default.crt;" >> "$config_file"
                    echo "    ssl_certificate_key /etc/ssl/private/nginx-default.key;" >> "$config_file"
                else
                    echo "    ssl_certificate     $ssl_cert;" >> "$config_file"
                    echo "    ssl_certificate_key $ssl_key;" >> "$config_file"
                fi
                # 子域名也应用 HSTS (与主块一致)
                if "$hsts_enabled"; then
                    echo "    add_header Strict-Transport-Security \"max-age=15768000; includeSubDomains\" always;" >> "$config_file"
                fi
            else
                echo "    listen $listen_port;" >> "$config_file"
                echo "    server_name $subdomain;" >> "$config_file"
            fi
            
            # 纯反代模式，设置默认 root 避免 Nginx 报错
            echo "    root $final_root_path;" >> "$config_file"

            echo "    # 子域名代理: $subdomain -> $backend_url (Host: $proxy_set_host)" >> "$config_file"
            echo "    location / {" >> "$config_file"
            # 统一 proxy_pass
            echo "        proxy_pass $backend_url;" >> "$config_file"

            # 插入通用配置 (保持一致性)
            echo "$nginx_proxy_common_headers" | while IFS= read -r line; do
                echo "    $line" >> "$config_file"
            done
            
            # Host Header 根据用户选择配置 (保持一致性)
            if [[ "$proxy_set_host" == "true" ]]; then
                echo "        proxy_set_header Host \$host;" >> "$config_file" 
            fi
            
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
    # 使用第一个域名/localhost作为文件名
    local config_file="caddy_$(echo "$server_names" | awk '{print $1}' | tr -cd '[:alnum:]_-')_$(date +%Y%m%d_%H%M%S).Caddyfile"
    print_color "--- 正在生成 Caddyfile 配置 ---" "$CYAN"
    
    # 确定最终 root 路径
    local final_root_path="/usr/share/nginx/html" 
    if [[ -n "$root_path" ]]; then
        final_root_path="$root_path"
    fi
    
    # Caddy 不允许 server_names 后面有空格，所以将空格替换为逗号，并在末尾添加端口
    local caddy_address=""
    if [ "$listen_port" -eq 80 ] && ! "$ssl_enabled"; then
        # 80 端口 HTTP
        caddy_address=$(echo "$server_names" | tr ' ' ',')
    else
        # 其他端口或 HTTPS，需要显式添加 :port
        caddy_address=$(echo "$server_names" | tr ' ' ',')":$listen_port"
    fi
    
    echo "$caddy_address {" > "$config_file"

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
        echo "    # Caddy 会自动处理 80 -> HTTPS 的重定向" >> "$config_file"
        echo "    # --- SSL 证书配置结束 ---" >> "$config_file"
    fi

    # Gzip 配置 (Caddy 默认使用 encode gzip zstd)
    if "$gzip_enabled"; then
        echo "    # 启用 Gzip/Zstd 压缩" >> "$config_file"
        echo "    encode gzip zstd" >> "$config_file"
    fi

    # HSTS 配置
    if "$hsts_enabled"; then
        echo "    # 启用 HSTS (一年)" >> "$config_file"
        echo "    header Strict-Transport-Security \"max-age=31536000; includeSubDomains\"" >> "$config_file"
    fi
    
    # 添加通用安全 Header
    echo "    # 推荐安全 Header" >> "$config_file"
    echo "    header X-Frame-Options SAMEORIGIN" >> "$config_file"
    echo "    header X-Content-Type-Options nosniff" >> "$config_file"
    echo "    header X-XSS-Protection \"1; mode=block\"" >> "$config_file"

    # --- 静态文件配置 (仅静态/混合模式) ---
    if [[ "$WORK_MODE" == "static" || "$WORK_MODE" == "mixed" ]]; then
        echo "    # 静态文件配置" >> "$config_file"
        echo "    root * $final_root_path" >> "$config_file"
        # 静态资源缓存时间 1 年 (31536000s)
        echo "    header Cache-Control \"public, max-age=31536000, immutable\"" >> "$config_file" 
        echo "    file_server" >> "$config_file"
    fi

    # --- 2. 路径反代配置 (优先级高) ---
    if [[ "$PROXY_CONFIG_TYPE" == "path" ]]; then
        for rule in "${PROXY_RULES[@]}"; do
            IFS='|' read -r proxy_path backend_url proxy_set_host <<< "$rule"
            echo "    # 反向代理: $proxy_path -> $backend_url (Host: $proxy_set_host)" >> "$config_file"
            
            # 使用 route 确保精确路径控制，并利用 URI 匹配
            echo "    route $proxy_path $proxy_path/* {" >> "$config_file"
            echo "        reverse_proxy $backend_url" >> "$config_file"
            
            # Host Header 根据用户选择配置 (一致性)
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
            : # 静态文件已由 file_server 模块处理
        elif [[ "$ROOT_ACTION" =~ ^proxy\| ]]; then
            IFS='|' read -r _ root_backend_url root_set_host <<< "$ROOT_ACTION"
            echo "    route / {" >> "$config_file"
            
            if [[ "$WORK_MODE" == "proxy" ]]; then
                # 纯反代模式：所有未被捕获的流量全部代理到根路径的后端
                echo "        reverse_proxy /* $root_backend_url" >> "$config_file" 
            else
                 echo "        reverse_proxy $root_backend_url" >> "$config_file"
            fi
            
            # Host Header 根据用户选择配置 (一致性)
            if [[ "$root_set_host" == "true" ]]; then
                echo "        header_up Host {http.request.host}" >> "$config_file"
            fi
            echo "    }" >> "$config_file"
        fi
    fi
    
    echo "}" >> "$config_file"

    # --- 4. 子域名反代配置 (每个子域名独立 Server 块) ---
    if [[ "$PROXY_CONFIG_TYPE" == "subdomain" ]]; then
        print_color "注意: 子域名反代将生成独立的 Server 块，使用与主域名相同的端口和 SSL/HSTS 设置。" "$YELLOW"
        for rule in "${SUBDOMAIN_PROXIES[@]}"; do
            IFS='|' read -r subdomain backend_url proxy_set_host <<< "$rule" # <-- 读取 Host 配置
            echo "" >> "$config_file"
            
            local subdomain_address
            # Caddy 子域名代理不需要包含 localhost
            if [ "$listen_port" -eq 80 ] && ! "$ssl_enabled"; then
                subdomain_address="$subdomain"
            else
                subdomain_address="$subdomain:$listen_port"
            fi
            
            echo "$subdomain_address {" >> "$config_file"
            
            if "$ssl_enabled"; then
                 if [[ -n "$ssl_cert" && -n "$ssl_key" ]]; then
                    echo "    tls $ssl_cert $ssl_key" >> "$config_file"
                else
                    echo "    tls internal"
                fi
                 if "$hsts_enabled"; then
                    echo "    header Strict-Transport-Security \"max-age=31536000; includeSubDomains\"" >> "$config_file"
                fi
            fi
            
            # 纯反代模式，设置默认 root 避免 Caddy 报错
            echo "    root * $final_root_path" >> "$config_file"

            echo "    # 子域名代理: $subdomain -> $backend_url (Host: $proxy_set_host)" >> "$config_file"
            echo "    reverse_proxy $backend_url" >> "$config_file"
            
            # Host Header 根据用户选择配置 (一致性)
            if [[ "$proxy_set_host" == "true" ]]; then
                echo "    header_up Host {http.request.host}" >> "$config_file" 
            fi
            
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
        # 确保 read -p 捕获输入
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
            # 增加提示清晰度
            read -e -p "是否继续生成其他配置? [Y/n/0退出]: " cont
            
            # 如果 cont 为空，默认视为 Y (继续)
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