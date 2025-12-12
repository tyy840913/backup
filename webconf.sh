#!/bin/bash

# =======================================================
# Web服务器配置生成器 (v1.0.1 权威生产版 - 极致精简配置)
# 修复了 Line 15 和 Line 48 的空格错误，并新增了配置生成功能。
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
config_output_file="" # 自定义输出文件名

# 打印带颜色的消息 (重定向到 stderr 以防被变量捕获)
print_color() {
    echo -e "${2}${1}${NC}" >&2
}

# 显示标题
print_title() {
    echo "==========================================" >&2
    echo " Web服务器配置生成器 (v1.0.1 极致精简版)" >&2
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
    # 修正 Line 48 的非标准空格错误 (if 语句行首现在使用标准空格)
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
            echo "检测到域名，请选择后端协议:" >&2
            echo "1. HTTP" >&2
            echo "2. HTTPS" >&2
            read -p "请选择 [1-2]: " protocol_choice
            protocol_choice=${protocol_choice:-1}
            [ "$protocol_choice" == "2" ] && backend_url="https://${backend_host}:${backend_port}" || backend_url="http://${backend_host}:${backend_port}"
        else
            print_color "错误: Host格式无效" "$RED"
            continue
        fi
        break
    done
    
    # 确保只有最终结果进入标准输出
    echo "$backend_url"
}

# 自动复制Nginx配置文件 (保留逻辑)
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

# 获取通用配置 (端口、SSL)
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
                
                # >>> 优化部分: 将菜单改为 [Y/n] 提示 <<<
                read -e -p "是否启用 HTTPS/SSL (使用 $custom_port 端口)? [Y/n]: " enable_ssl_choice
                enable_ssl_choice=${enable_ssl_choice:-y} # 默认启用
                
                if [[ ! "$enable_ssl_choice" =~ ^[Nn] ]]; then
                    http_port=""; https_port=$custom_port
                    # 只有自定义端口非 443 时，才需要 497 处理 (逻辑保留)
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
        print_color "=== SSL证书配置 ===" "$BLUE"
        read -p "SSL证书路径 (默认: /etc/ssl/certs/fullchain.pem): " ssl_cert
        [ -z "$ssl_cert" ] && ssl_cert="/etc/ssl/certs/fullchain.pem"
        read -p "SSL私钥路径 (默认: /etc/ssl/private/privkey.key): " ssl_key
        [ -z "$ssl_key" ] && ssl_key="/etc/ssl/private/privkey.key"
    fi
    # 4. 高级配置精简：已删除所有 HSTS/OCSP/Gzip/缓存 的用户交互
    echo "" >&2
}

# 获取用户自定义文件名
get_filename_choice() {
    local default_name=""
    if [ "$choice" == "1" ]; then
        default_name="nginx_${server_names%% *}.conf"
    else
        default_name="caddy_${server_names%% *}.caddyfile"
    fi

    print_color "=== 文件命名 ===" "$BLUE"
    read -e -p "请输入配置文件名称 (默认: $default_name): " custom_name
    config_output_file=${custom_name:-$default_name}
    
    # Nginx 自动补 .conf
    if [ "$choice" == "1" ] && [[ ! "$config_output_file" =~ \.conf$ ]]; then
        config_output_file="${config_output_file}.conf"
    fi
    
    print_color "配置文件将保存为: $config_output_file" "$GREEN"
}

# 获取反代和静态映射配置 (此模块保留所有逻辑)
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
# 模块二: 配置生成 (Nginx)
# =======================================================

generate_nginx_config() {
    local output=""
    local default_host=$(echo "$server_names" | awk '{print $1}')
    local proxy_headers=""

    # 基础性能和安全头部
    proxy_headers="
    proxy_set_header Host \$http_host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    "

    output+="# Nginx Configuration Generated by Script v1.0.1\n"
    output+="# Generated for: $server_names\n\n"

    # 1. HTTP 80/Custom Port Block (Redirect or Plain HTTP)
    if [ -n "$http_port" ]; then
        output+="server {\n"
        output+="    listen $http_port;\n"
        output+="    server_name $server_names;\n\n"
        
        if $enable_301_redirect && [ -n "$https_port" ]; then
            output+="    # HTTP 强制跳转 HTTPS\n"
            output+="    return 301 https://\$host\$request_uri;\n"
        else
            output+="    # HTTP Block: Apply Mappings\n"
            # 根路径静态或代理映射 (仅当未启用重定向时)
            local root_mapping=${PROXY_MAPPINGS[0]}
            local type=$(echo "$root_mapping" | cut -d'|' -f1)
            local target=$(echo "$root_mapping" | cut -d'|' -f3)

            output+="    location / {\n"
            if [ "$type" == "ROOT_STATIC" ]; then
                output+="        root $target;\n"
                output+="        index index.html index.htm;\n"
            else # ROOT_PROXY
                output+="        proxy_pass $target;\n"
                output+="        # 默认使用代理头部\n"
                output+="        $proxy_headers"
            fi
            output+="    }\n"
        fi
        output+="}\n\n"
    fi

    # 2. HTTPS Main Block
    if [ -n "$https_port" ]; then
        output+="server {\n"
        output+="    listen $https_port ssl http2;\n"
        output+="    server_name $server_names;\n\n"

        output+="    # SSL Configuration\n"
        output+="    ssl_certificate $ssl_cert;\n"
        output+="    ssl_certificate_key $ssl_key;\n"
        output+="    ssl_session_timeout 1d;\n"
        output+="    ssl_protocols TLSv1.2 TLSv1.3;\n"
        output+="    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384';\n"
        output+="    ssl_prefer_server_ciphers on;\n\n"

        # Nginx 497 Error Handling (for non-443 ports)
        if $need_497; then
            output+="    # 修复非443端口的497错误\n"
            output+="    error_page 497 =301 https://\$host:\$server_port\$request_uri;\n\n"
        fi

        # 3. Mappings (Iterate through PROXY_MAPPINGS)
        for mapping in "${PROXY_MAPPINGS[@]}"; do
            local type=$(echo "$mapping" | cut -d'|' -f1)
            local matcher=$(echo "$mapping" | cut -d'|' -f2)
            local target=$(echo "$mapping" | cut -d'|' -f3)
            local set_host=$(echo "$mapping" | cut -d'|' -f4)

            # 根路径映射 (已在HTTP block中处理，这里是HTTPS block的主体)
            if [ "$type" == "ROOT_STATIC" ]; then
                output+="    location / {\n"
                output+="        root $target;\n"
                output+="        index index.html index.htm;\n"
                output+="        try_files \$uri \$uri/ =404;\n"
                output+="    }\n"
            elif [ "$type" == "ROOT_PROXY" ]; then
                output+="    location / {\n"
                output+="        proxy_pass $target;\n"
                if [ "$set_host" == "true" ]; then
                    output+="        $proxy_headers"
                fi
                output+="    }\n"
            
            # 路径反向代理 (例如: /api)
            elif [ "$type" == "PATH_PROXY" ]; then
                # 使用 ^~ 前缀匹配，确保优先于其他正则或通用匹配
                output+="    location $matcher {\n"
                output+="        # 路径反代 $matcher -> $target\n"
                output+="        proxy_pass $target;\n"
                if [ "$set_host" == "true" ]; then
                    output+="        $proxy_headers"
                fi
                output+="    }\n"

            # 子域名反向代理 (Nginx需要额外配置一个server block，但这里只处理当前配置的 server_names)
            # 子域名配置在主 server block 不适用，需要用户手动创建新的 server block
            # 脚本只支持当前 server_names 的配置
            elif [ "$type" == "SUBDOMAIN_PROXY" ]; then
                # 如果子域名是通配符，它将匹配到当前 server_name (如: *.domain.com)
                if [[ "$server_names" =~ \* ]] || [[ "$matcher" == "*" ]]; then
                    output+="\n    # WARNING: 此脚本只生成一个 server block。\n"
                    output+="# 通配符子域名映射 $matcher.$default_host -> $target 无法在此块中实现。\n"
                    output+="# 您可能需要在不同的 server {} 块中配置子域名。\n"
                    output+="    # 建议使用 CaddyFile 实现更简单的多域名/子域名配置。\n"
                fi
            fi
        done
        
        output+="\n"
        output+="# 404 Error page\n"
        output+='    error_page 404 /404.html;\n'
        output+="}\n"
    fi

    # 输出到文件
    echo -e "$output" > "$config_output_file"
    print_color "Nginx配置已生成到: $config_output_file" "$GREEN"
    copy_nginx_config "$config_output_file"
}

# =======================================================
# 模块二: 配置生成 (Caddy)
# =======================================================

generate_caddy_config() {
    local output=""
    local server_name_list=""
    
    # 构造 Caddyfile 的域名/端口头
    if [ -n "$https_port" ]; then
        # Caddy默认启用HTTPS，除非指定为:http或非标准端口
        if [ "$https_port" == "443" ]; then
            server_name_list="$server_names"
        else
            server_name_list="$server_names:$https_port {\n    tls $ssl_cert $ssl_key"
        fi
    elif [ -n "$http_port" ]; then
        server_name_list="$server_names:$http_port {\n"
    fi

    output+="# Caddyfile Configuration Generated by Script v1.0.1\n"
    output+="# Generated for: $server_names\n\n"
    output+="$server_name_list\n\n"

    # 1. 自动重定向 (Caddy自动处理 80 -> 443，无需手动配置)
    if [ -n "$https_port" ] && $enable_301_redirect; then
        output+="\treduce_caddy_redirects\n"
    fi

    # 2. Mappings (Caddyfile Logic)
    for mapping in "${PROXY_MAPPINGS[@]}"; do
        local type=$(echo "$mapping" | cut -d'|' -f1)
        local matcher=$(echo "$mapping" | cut -d'|' -f2)
        local target=$(echo "$mapping" | cut -d'|' -f3)
        local set_host=$(echo "$mapping" | cut -d'|' -f4)

        if [ "$type" == "ROOT_STATIC" ]; then
            output+="\t# Root Static Site\n"
            output+="\troot * $target\n"
            output+="\tfile_server\n\n"
        elif [ "$type" == "ROOT_PROXY" ]; then
            output+="\t# Full Site Reverse Proxy\n"
            output+="\treverse_proxy $target {\n"
            if [ "$set_host" == "true" ]; then
                output+="\t\theader_up Host {host}\n" # Caddy默认传Host头
            fi
            output+="\t}\n"
        elif [ "$type" == "PATH_PROXY" ]; then
            output+="\t# Path Reverse Proxy $matcher\n"
            output+="\t$matcher reverse_proxy $target {\n"
            if [ "$set_host" == "true" ]; then
                output+="\t\theader_up Host {host}\n"
            fi
            output+="\t}\n"
        elif [ "$type" == "SUBDOMAIN_PROXY" ]; then
            # Caddy 子域名需要在独立的 block 中，这里只打印提示
            output+="\t# WARNING: 子域名/通配符映射 ($matcher) 需要在独立的 Caddyfile block 中配置。\n"
        fi
    done
    
    output+="\n}"

    # 输出到文件
    echo -e "$output" > "$config_output_file"
    print_color "Caddyfile 配置已生成到: $config_output_file" "$GREEN"
    print_color "请运行 'caddy fmt $config_output_file' 格式化，并运行 'caddy run' 启动服务。" "$YELLOW"
}

# 主程序 (已优化流程)
main() {
    while true; do
        
        # 1. 服务器类型选择 (Nginx/Caddy) - 放在最前面
        show_menu
        read -p "请选择 [1-3]: " choice

        case $choice in
            1 | 2)
                # 2. 获取所有通用配置 (端口、SSL)
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

# 运行主程序
main
