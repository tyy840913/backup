#!/bin/bash

# =======================================================
# Web服务器配置生成器 (v1.0.1 - 个人精简版)
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
# 打印带颜色的消息 (重定向到 stderr 以防被变量捕获)
print_color() {
    echo -e "${2}${1}${NC}" >&2
}

# 显示标题
print_title() {
    echo "==========================================" >&2
    echo " Web服务器配置生成器 (v1.0.1 个人精简版)" >&2
    echo "==========================================" >&2
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
            read -e -p "检测到域名，是否使用 HTTPS 协议? [Y/n]: " protocol_choice
            protocol_choice=${protocol_choice:-y}
            if [[ "$protocol_choice" =~ ^[Yy] ]]; then
                backend_url="https://${backend_host}:${backend_port}"
            else
                backend_url="http://${backend_host}:${backend_port}"
            fi
        else
            print_color "错误: Host格式无效" "$RED"
            continue
        fi
        break
    done
    
    # 确保只有最终结果进入标准输出
    echo "$backend_url"
}

copy_nginx_config() {
    local config_file=$1
    echo ""
    print_color "=== Nginx配置安装 ===" "$BLUE"
    read -e -p "是否将配置文件复制到Nginx目录并启用? [Y/n]: " install_choice
    install_choice=${install_choice:-y}
    if [[ ! "$install_choice" =~ ^[Nn] ]]; then
        if [ -d "/etc/nginx/sites-available" ] && [ -d "/etc/nginx/sites-enabled" ]; then
            # 1. 先测试当前配置文件语法
            print_color "正在测试配置文件语法..." "$YELLOW"
            if nginx -t -c "$config_file"; then
                print_color "配置文件语法测试成功！" "$GREEN"
                
                # 2. 复制文件
                cp "$config_file" "/etc/nginx/sites-available/"
                
                # 3. 创建软链接
                ln -sf "/etc/nginx/sites-available/$config_file" "/etc/nginx/sites-enabled/"
                
                # 4. 自动重载（不重启）
                print_color "正在重载Nginx配置..." "$YELLOW"
                if pkill -HUP nginx || nginx -s reload; then
                    print_color "Nginx配置已重载完成！" "$GREEN"
                else
                    print_color "警告: 重载失败，但配置文件已安装" "$YELLOW"
                fi
            else
                print_color "错误: 配置文件语法测试失败，请检查配置！" "$RED"
            fi
        else
            print_color "错误: Nginx目录不存在" "$RED"
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

    echo "" >&2
    print_color "=== Web服务通用配置 ===" "$BLUE"

    # 1. 端口模式选择 
    while true; do
        echo "请选择端口配置模式:" >&2
        echo "1. 标准 (80/443，启用HTTP->HTTPS重定向)" >&2
        echo "2. 自定义" >&2
        read -p "请选择 [1-2]: " port_mode
        case $port_mode in
            1) http_port=80; https_port=443; enable_301_redirect=true; break ;;
            2)
                read -p "请输入监听端口 (例如: 8080): " custom_port
                if ! validate_port "$custom_port"; then print_color "错误: 端口无效" "$RED"; continue; fi
                
                read -e -p "是否为此自定义端口启用 HTTPS (SSL)? [Y/n]: " enable_ssl_choice
                enable_ssl_choice=${enable_ssl_choice:-y}
                
                if [[ ! "$enable_ssl_choice" =~ ^[Nn] ]]; then
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
        
        # 优先尝试的 ACME 客户端默认目录
        local priority_dirs=("$HOME/.acme.sh" "/etc/letsencrypt/live")
        
        ssl_cert=""
        ssl_key=""
        
        while true; do
            # 阶段1: 优先尝试 ACME 默认目录
            if [ -z "$ssl_cert" ]; then
                local primary_domain="${server_names%% *}"  # 主域名用于匹配
                local found_domain_dir=false
                
                for base_dir in "${priority_dirs[@]}"; do
                    if [ -d "$base_dir" ]; then
                        print_color "优先检查 ACME 目录: $base_dir" "$YELLOW"
                        
                        # 通配匹配域名目录 (支持额外字符，如 woskee.dynv6.net_ecc)
                        local matched_dirs=("$base_dir"/*"$primary_domain"*)
                        if [ -d "${matched_dirs[0]}" ] && [ "${matched_dirs[0]}" != "$base_dir/*$primary_domain*" ]; then
                            local domain_dir
                            if [ ${#matched_dirs[@]} -eq 1 ]; then
                                domain_dir="${matched_dirs[0]}"
                            else
                                echo "找到多个匹配的域名目录:" >&2
                                select domain_dir in "${matched_dirs[@]}"; do
                                    if [ -n "$domain_dir" ]; then break; fi
                                done
                            fi
                            
                            print_color "使用域名目录: $domain_dir" "$GREEN"
                            found_domain_dir=true
                            
                            # 自动找证书链
                            for cert_file in fullchain.pem chain.pem cert.pem certificate.pem; do
                                if [ -f "$domain_dir/$cert_file" ]; then
                                    ssl_cert="$domain_dir/$cert_file"
                                    print_color "自动选择证书链: $ssl_cert" "$GREEN"
                                    break
                                fi
                            done
                            
                            # 自动找私钥
                            for key_file in privkey.pem key.pem private.pem; do
                                candidate="$domain_dir/$key_file"
                                if [ -f "$candidate" ] && [ "$candidate" != "$ssl_cert" ]; then
                                    ssl_key="$candidate"
                                    print_color "自动选择私钥: $ssl_key" "$GREEN"
                                    break
                                fi
                            done
                            
                            if [ -z "$ssl_cert" ] || [ -z "$ssl_key" ]; then
                                print_color "自动未找到完整证书/私钥，列出 $domain_dir 下可用文件供手动选择" "$YELLOW"
                                ls -1 "$domain_dir"/*.pem "$domain_dir"/*.crt "$domain_dir"/*.key 2>/dev/null || true
                                
                                read -p "请输入证书路径: " ssl_cert
                                read -p "请输入私钥路径: " ssl_key
                            fi
                            
                            break  # 已找到目录，跳出优先目录循环
                        fi
                    fi
                done
                
                if [ "$found_domain_dir" = true ]; then
                    # 找到后确认
                    echo "" >&2
                    print_color "ACME 自动配置完成：" "$GREEN"
                    echo "证书: $ssl_cert" >&2
                    echo "私钥: $ssl_key" >&2
                    read -e -p "是否使用以上配置？ [Y/n]: " confirm
                    confirm=${confirm:-y}
                    if [[ "$confirm" =~ ^[Yy] ]]; then
                        break
                    else
                        ssl_cert=""
                        ssl_key=""
                        print_color "重新开始配置..." "$YELLOW"
                    fi
                fi
            fi
            
            # 阶段2: 如果优先目录没找到，或用户拒绝，询问自定义根目录
            if [ -z "$ssl_cert" ]; then
                read -p "请输入证书根目录 (留空手动输入路径): " cert_root_dir
                
                if [ -z "$cert_root_dir" ]; then
                    # 手动输入
                    read -p "SSL证书路径 (默认: /etc/ssl/certs/fullchain.pem): " ssl_cert
                    [ -z "$ssl_cert" ] && ssl_cert="/etc/ssl/certs/fullchain.pem"
                    read -p "SSL私钥路径 (默认: /etc/ssl/private/privkey.key): " ssl_key
                    [ -z "$ssl_key" ] && ssl_key="/etc/ssl/private/privkey.key"
                    break
                fi
                
                if [ ! -d "$cert_root_dir" ]; then
                    print_color "错误: 目录 $cert_root_dir 不存在" "$RED"
                    continue
                fi
                
                # 自定义目录下同样用通配查找域名子目录（可选增强）
                local primary_domain="${server_names%% *}"
                local matched_dirs=("$cert_root_dir"/*"$primary_domain"*)
                local domain_dir
                if [ -d "${matched_dirs[0]}" ] && [ "${matched_dirs[0]}" != "$cert_root_dir/*$primary_domain*" ]; then
                    if [ ${#matched_dirs[@]} -eq 1 ]; then
                        domain_dir="${matched_dirs[0]}"
                    else
                        echo "找到多个匹配目录:" >&2
                        select domain_dir in "${matched_dirs[@]}"; do
                            if [ -n "$domain_dir" ]; then break; fi
                        done
                    fi
                    print_color "使用目录: $domain_dir" "$GREEN"
                else
                    print_color "未找到匹配域名子目录，直接在根目录 $cert_root_dir 中查找" "$YELLOW"
                    domain_dir="$cert_root_dir"
                fi
                
                # 自动优先证书链 + 私钥
                for cert_file in fullchain.pem chain.pem cert.pem certificate.pem; do
                    if [ -f "$domain_dir/$cert_file" ]; then
                        ssl_cert="$domain_dir/$cert_file"
                        print_color "自动选择证书链: $ssl_cert" "$GREEN"
                        break
                    fi
                done
                
                for key_file in privkey.pem key.pem private.key privkey.key; do
                    candidate="$domain_dir/$key_file"
                    if [ -f "$candidate" ] && [ "$candidate" != "$ssl_cert" ]; then
                        ssl_key="$candidate"
                        print_color "自动选择私钥: $ssl_key" "$GREEN"
                        break
                    fi
                done
                
                if [ -z "$ssl_cert" ] || [ -z "$ssl_key" ]; then
                    print_color "自动未找到，列出可用文件:" "$YELLOW"
                    ls -1 "$domain_dir"/*.pem "$domain_dir"/*.crt "$domain_dir"/*.key "$domain_dir"/*.cer 2>/dev/null || true
                    read -p "请输入证书路径: " ssl_cert
                    read -p "请输入私钥路径: " ssl_key
                fi
                
                # 确认
                echo "" >&2
                echo "证书: $ssl_cert" >&2
                echo "私钥: $ssl_key" >&2
                read -e -p "确认使用？ [Y/n]: " confirm
                confirm=${confirm:-y}
                if [[ "$confirm" =~ ^[Yy] ]; then
                    break
                fi
            fi
        done
        
        # 简单存在性检查
        if [ ! -f "$ssl_cert" ]; then print_color "警告: 证书文件不存在 $ssl_cert" "$YELLOW"; fi
        if [ ! -f "$ssl_key" ]; then print_color "警告: 私钥文件不存在 $ssl_key" "$YELLOW"; fi
        
        print_color "最终SSL配置: 证书 $ssl_cert   私钥 $ssl_key" "$BLUE"
    fi
}

# 获取用户自定义文件名 → 改为固定目录 + 自动路径
get_filename_choice() {
    local default_name=""
    local site_dir="/etc/caddy/sites"

    if [ "$choice" == "1" ]; then
        default_name="nginx_${server_names%% *}.conf"
        print_color "=== 文件命名 ===" "$BLUE"
        read -e -p "请输入Nginx配置文件名称 (默认: $default_name): " custom_name
        config_output_file=${custom_name:-$default_name}
        if [[ ! "$config_output_file" =~ \.conf$ ]]; then
            config_output_file="${config_output_file}.conf"
        fi
    else
        # Caddy：强制存到 /etc/caddy/sites/ 目录
        default_name="${server_names%% *}.caddyfile"
        print_color "=== Caddy站点文件命名 ===" "$BLUE"
        read -e -p "请输入站点文件名 (默认: $default_name，将保存到 $site_dir/): " custom_name
        config_output_file=${custom_name:-$default_name}
        
        # 确保目录存在
        mkdir -p "$site_dir"
        
        # 完整路径
        config_output_file="$site_dir/$config_output_file"
    fi
    
    print_color "配置文件将保存为: $config_output_file" "$GREEN"
}

# 获取反代和静态映射配置
get_proxy_mappings() {
    PROXY_MAPPINGS=() # 清空旧映射
    
    print_color "=== 映射配置 (根路径 '/') ===" "$BLUE"
    
    # 1. 根路径 (Default) 强制配置 
    while true; do
        echo "请定义主域名根路径 '/' 的默认行为:" >&2
        echo "1. 静态网站" >&2
        echo "2. 全站反向代理" >&2
        read -p "请选择 [1-2]: " root_mode
        
        if [ "$root_mode" == "1" ]; then
            read -p "请输入网站根目录 (默认: /var/www/html): " root_path
            [ -z "$root_path" ] && root_path="/var/www/html"
            PROXY_MAPPINGS+=("ROOT_STATIC|/|$root_path|false")
            break
        elif [ "$root_mode" == "2" ]; then
            print_color "--- 全站反代目标 ---" "$YELLOW"
            # get_backend_info 只输出 URL
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
        
        echo "请选择要添加的映射类型:" >&2
        echo "1. 路径反向代理 (例如: /api -> 127.0.0.1:9001)" >&2
        echo "2. 子域名反向代理 (例如: api.domain.com -> 127.0.0.1:9002)" >&2
        echo "3. 完成配置并生成" >&2
        read -p "请选择 [1-3]: " map_type
        
        if [ "$map_type" == "3" ]; then break; fi
        
        if [ "$map_type" == "1" ]; then
            while true; do
                read -p "请输入路径 (例如: api): " path_input
                local path_matcher=$(normalize_path "$path_input")
                # 检查是否是根路径，根路径已在上面配置
                if [[ "$path_matcher" == "/" ]]; then
                    print_color "错误: 根路径 '/' 已在上面配置。请使用子路径。" "$RED"
                else
                    # 路径反代匹配器：不带末尾斜杠，以匹配 /api 和 /api/ 
                    # Nginx proxy_pass 不带末尾斜杠，实现路径完整传递
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
        config+="\n    # 通用 SSL/TLS 配置 (适用于所有 HTTPS 监听块 - 单文件输出需要重复)\n"
        config+="    ssl_certificate $ssl_cert;\n"
        config+="    ssl_certificate_key $ssl_key;\n"
        config+="    ssl_protocols TLSv1.2 TLSv1.3;\n"
    fi
    echo -e "$config"
}

# Nginx 通用安全/性能头和Gzip配置生成
generate_nginx_security_and_performance() {
    local config=""
    config+="\n    # 通用安全/性能头配置\n"
    config+="    add_header X-Frame-Options \"SAMEORIGIN\" always;\n"
    config+="    add_header X-Content-Type-Options nosniff always;\n"
    echo -e "$config\n"
}

# =======================================================
# 模块三: Caddy 通用配置生成
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
    config+="        X-Content-Type-Options nosniff\n"
    config+="    }\n"

    echo -e "$config"
}


# =======================================================
# 模块四: 主配置生成器 (专注于反代/静态逻辑关系)
# =======================================================

# 生成Nginx配置 
generate_nginx_config() {
    local config_file="$config_output_file"  # 使用自定义文件名

    echo "# Nginx配置文件 - 生成于 $(date)" > "$config_file"
    echo "# 版本: v1.0.1 权威生产版" >> "$config_file"
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
            [ "$need_497" = true ] && echo "    # 497 错误重定向到 \$host:\$server_port" >> "$config_file"
            [ "$need_497" = true ] && echo "    error_page 497 =301 https://\$host:\$server_port\$request_uri;" >> "$config_file"
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
        
        local root_mode_found=false
        
        for mapping in "${PROXY_MAPPINGS[@]}"; do
            # Use more explicit variable names for clarity in this complex mapping structure
            IFS='|' read -r m_type m_matcher m_target m_flag <<< "$mapping"
            
            # 路径反代/根路径/静态配置 只在 主域名 server block (MAIN) 中处理
            if [ "$block_type" == "MAIN" ]; then
                
                # 静态网站根目录配置 (ROOT_STATIC)
                if [ "$m_type" == "ROOT_STATIC" ]; then
                    if [ "$root_mode_found" = false ]; then
                        local root_path=$m_target
                        
                        echo "    # 静态网站根目录配置" >> "$config_file"
                        echo "    root $root_path;" >> "$config_file" 
                        echo "    index index.html index.htm;" >> "$config_file"
                        
                        # 静态文件服务和缓存逻辑
                        echo "    location / {" >> "$config_file"
                        echo "        try_files \$uri \$uri/ =404;" >> "$config_file"
                        echo "    }" >> "$config_file"
            
                        root_mode_found=true
                    fi
                fi
                
                # 全站反代 (ROOT_PROXY)
                if [ "$m_type" == "ROOT_PROXY" ]; then
                    if [ "$root_mode_found" = false ]; then
                        local set_host=$m_flag
                        local backend_url=$m_target
                        echo "    location / {" >> "$config_file"
                        echo "        # 根路径全站反向代理" >> "$config_file"
                        echo "        proxy_pass $backend_url;" >> "$config_file" 
                        [ "$set_host" = "true" ] && echo "        proxy_set_header Host \$host;" >> "$config_file"
                        echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$config_file"
                        echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" >> "$config_file"
                        echo "        proxy_set_header X-Forwarded-Proto \$scheme;" >> "$config_file"
                        echo "    }" >> "$config_file"
                        root_mode_found=true
                    fi
                fi

                # 路径反代 (PATH_PROXY)
                if [ "$m_type" == "PATH_PROXY" ]; then
                    local set_host=$m_flag
                    local backend_url=$m_target
                    
                    echo "    location ${m_matcher} {" >> "$config_file"
                    echo "        # 路径反向代理: Nginx 不带末尾斜杠，实现路径完整传递" >> "$config_file"
                    echo "        proxy_pass $backend_url;" >> "$config_file" # <<< FIX: proxy_pass 永远不带末尾斜杠
                    [ "$set_host" = "true" ] && echo "        proxy_set_header Host \$host;" >> "$config_file"
                    echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$config_file"
                    echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" >> "$config_file"
                    echo "        proxy_set_header X-Forwarded-Proto \$scheme;" >> "$config_file"
                    echo "    }" >> "$config_file"
                fi
            fi
            
            # 子域名反代 只在 子域名 server block (SUB) 中处理
            if [ "$block_type" == "SUB" ] && [ "$m_type" == "SUBDOMAIN_PROXY" ]; then
                local set_host=$m_flag
                local backend_url=$m_target
                echo "    location / {" >> "$config_file" 
                echo "        # 子域名全站反向代理" >> "$config_file"
                echo "        proxy_pass $backend_url;" >> "$config_file" 
                [ "$set_host" = "true" ] && echo "        proxy_set_header Host \$host;" >> "$config_file"
                echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$config_file"
                echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" >> "$config_file"
                echo "        proxy_set_header X-Forwarded-Proto \$scheme;" >> "$config_file" 
                echo "    }" >> "$config_file"
                break 
            fi
        done
        
        echo "}" >> "$config_file"
        echo "" >> "$config_file"
    done
    
    print_color "Nginx配置文件已生成: $config_file" "$GREEN"
    copy_nginx_config "$config_file"
}

# 生成Caddy配置 
generate_caddy_config() {
    local config_file="$config_output_file"  # 使用自定义文件名

    echo "# Caddy配置文件 - 生成于 $(date)" > "$config_file"
    echo "# 版本: v1.0.1 权威生产版" >> "$config_file"
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
        
        # 处理非标准 HTTPS 端口
        local listener_addr="$block_server_names"
        if [ -n "$https_port" ] && [ "$https_port" -ne 443 ]; then
            listener_addr="${block_server_names}:${https_port}"
        fi

        echo "$listener_addr {" >> "$config_file"
        
        # 插入通用 安全/性能 配置
        echo -e "$COMMON_SEC_PERF_CONFIG" >> "$config_file"
        
        # --- 映射列表 (反代逻辑关系) ---
        for mapping in "${PROXY_MAPPINGS[@]}"; do
            IFS='|' read -r m_type m_matcher m_target m_flag <<< "$mapping"
            
            if [ "$block_type" == "MAIN" ]; then
                # 静态根目录
                if [ "$m_type" == "ROOT_STATIC" ]; then
                    local root_path=$m_target
                    echo "    root * $root_path" >> "$config_file"
                    echo "    file_server" >> "$config_file"
                    
                # 全站代理或路径代理
                elif [ "$m_type" == "ROOT_PROXY" ] || [ "$m_type" == "PATH_PROXY" ]; then
                    local set_host=$m_flag
                    local path_match=$m_matcher
                    local backend_url=$m_target
                    
                    # Caddy路径反代修正：/path* 是正确写法 (V1.0.1 权威修正)
                    local caddy_matcher="${path_match}*"
                    [ "$path_match" == "/" ] && caddy_matcher="/" # 根路径匹配器仍为 /
                    
                    echo "    # 反向代理: ${caddy_matcher} 到 $backend_url" >> "$config_file"
                    echo "    reverse_proxy ${caddy_matcher} $backend_url {" >> "$config_file"
                    [ "$set_host" = "true" ] && echo "        header_up Host {host}" >> "$config_file"
                    echo "        header_up X-Real-IP {remote_host} # V1.0.1 统一新增" >> "$config_file"
                    echo "        header_up X-Forwarded-Proto {scheme}" >> "$config_file" 
                    echo "    }" >> "$config_file"
                fi
            
            elif [ "$block_type" == "SUB" ] && [ "$m_type" == "SUBDOMAIN_PROXY" ]; then
                 local sub_domain=$(echo "$block_server_names" | awk '{print $1}')
                 if [[ "$m_matcher" == "*" ]] || [[ "$sub_domain" == "$m_matcher."* ]]; then
                    local set_host=$m_flag
                    local backend_url=$m_target
                    echo "    # 子域名全站反向代理到 $backend_url" >> "$config_file"
                    echo "    reverse_proxy $backend_url {" >> "$config_file"
                    [ "$set_host" = "true" ] && echo "        header_up Host {host}" >> "$config_file"
                    echo "        header_up X-Real-IP {remote_host} # V1.0.1 统一新增" >> "$config_file"
                    echo "        header_up X-Forwarded-Proto {scheme}" >> "$config_file" 
                    echo "    }" >> "$config_file"
                    break
                 fi
            fi
        done
        
        echo "}" >> "$config_file"
        echo "" >> "$config_file"
    done
    
    print_color "Caddy配置文件已生成: $config_file" "$GREEN"

    # === Caddy 生产级安装逻辑：独立文件 + import ===
    read -e -p "是否将此站点配置应用到Caddy（创建独立文件 + 添加 import）? [Y/n]: " install_choice
    install_choice=${install_choice:-y}
    if [[ ! "$install_choice" =~ ^[Nn] ]]; then
        local main_caddyfile="/etc/caddy/Caddyfile"
        local import_line="import $config_file"

        # 1. 验证生成的配置是否正确
        print_color "正在验证生成的站点配置..." "$YELLOW"
        if caddy validate --config "$config_file" > /dev/null 2>&1; then
            print_color "站点配置文件验证通过！" "$GREEN"
        else
            print_color "错误: 站点配置文件验证失败，请检查生成内容！" "$RED"
            return 1
        fi

        # 2. 检查主 Caddyfile 是否存在
        if [ ! -f "$main_caddyfile" ]; then
            print_color "警告: 主 Caddyfile 不存在 ($main_caddyfile)，尝试创建基本文件..." "$YELLOW"
            mkdir -p "/etc/caddy"
            echo "# 主 Caddyfile - 自动生成" | tee "$main_caddyfile" > /dev/null
            echo "# 请将全局配置（如 admin、logging）放在这里" | tee -a "$main_caddyfile" > /dev/null
            echo "" | tee -a "$main_caddyfile" > /dev/null
        fi

        # 3. 检查是否已存在完全相同的 import 行
        local import_line="import $config_file"

        escaped_basename=$(basename "$config_file" | sed 's/[.[\*^$()+?{|]/\\&/g')
        escaped_fullpath=$(printf '%s' "$config_file" | sed 's/[.[\*^$()+?{|]/\\&/g')

        if grep -qE "^\s*import\s.*${escaped_basename}\s*$" "$main_caddyfile" 2>/dev/null || \
           grep -qE "^\s*import\s.*${escaped_fullpath}\s*$" "$main_caddyfile" 2>/dev/null; then
            print_color "检测到已包含该站点 import，跳过添加" "$YELLOW"
        else
            print_color "正在向主 Caddyfile 添加 import..." "$YELLOW"
            if [ -s "$main_caddyfile" ]; then
                echo "" | tee -a "$main_caddyfile" > /dev/null
            fi
            echo "$import_line" | tee -a "$main_caddyfile" > /dev/null
            print_color "已成功添加 import 行" "$GREEN"
        fi

        # 4. 重载 Caddy 服务
        print_color "正在重载 Caddy 服务..." "$YELLOW"
        if pkill -HUP caddy || caddy reload --config "$main_caddyfile" > /dev/null 2>&1; then
            print_color "Caddy 配置已成功应用并重载！" "$GREEN"
            print_color "站点文件: $config_file" "$BLUE"
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