#!/bin/bash

# =======================================================
# Web服务器配置生成器 (v1.1.1 终极 Lite 完美版 - 个人服务器最优解)
# 目标: 配置行数 40-60 行, 保留核心功能, 修复所有已知瑕疵.
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
enable_ssl=true        # SSL 默认启用

# 打印带颜色的消息 (重定向到 stderr 以防被变量捕获)
print_color() {
    echo -e "${2}${1}${NC}" >&2
}

# 显示标题
print_title() {
    echo "============================================" >&2
    echo " Web服务器配置生成器 (v1.1.1 终极 Lite 完美版)" >&2
    echo "============================================" >&2
    echo "" >&2
}

# 显示主菜单 (用于选择 Nginx 或 Caddy)
show_menu() {
    print_title
    echo "请选择要生成的服务器配置:"
    echo "1. Nginx (精简配置)"
    echo "2. Caddy (精简配置)"
    echo "3. 退出"
    echo ""
}

# =======================================================
# 模块一: 输入与校验
# =======================================================

# 获取所有通用配置
get_generic_config() {
    # 域名
    while true; do
        read -p "$(print_color '1. 请输入主域名 (例如: example.com): ' "$YELLOW")" domain_name
        if [[ -z "$domain_name" ]]; then
            print_color "域名不能为空！" "$RED"
        else
            server_name="$domain_name"
            break
        fi
    done
    
    # 启用 SSL 询问 (新功能：支持灵活配置)
    read -p "$(print_color '2. 是否启用 HTTPS/SSL? (Y/n - 强烈推荐): ' "$YELLOW")" enable_ssl_choice
    if [[ "$enable_ssl_choice" =~ ^[Nn]$ ]]; then
        enable_ssl=false
    else
        enable_ssl=true
    fi
    
    if [ "$enable_ssl" = true ]; then
        # SSL 证书路径
        while true; do
            read -p "$(print_color '  -> 证书文件路径 (fullchain.pem): ' "$YELLOW")" ssl_cert_path
            if [[ -z "$ssl_cert_path" ]]; then
                print_color "证书路径不能为空！" "$RED"
            else
                ssl_certificate_path="$ssl_cert_path"
                break
            fi
        done

        # SSL 密钥路径
        while true; do
            read -p "$(print_color '  -> 私钥文件路径 (privkey.key): ' "$YELLOW")" ssl_key_path
            if [[ -z "$ssl_key_path" ]]; then
                print_color "私钥路径不能为空！" "$RED"
            else
                ssl_certificate_key_path="$ssl_key_path"
                break
            fi
        done
    fi
    
    # 是否需要静态文件配置 (仅 Nginx 需要)
    if [ "$choice" == "1" ]; then
        read -p "$(print_color '3. Nginx 是否包含静态文件缓存配置? (y/N): ' "$YELLOW")" include_static_cache_choice
        if [[ "$include_static_cache_choice" =~ ^[Yy]$ ]]; then
            include_static_cache=true
        else
            include_static_cache=false
        fi
    fi
}

# 获取反向代理映射
get_proxy_mappings() {
    PROXY_MAPPINGS=() # 清空数组
    print_color "=== 映射配置开始 (路径/子域名反代) ===" "$BLUE"
    
    # 根路径配置 (强制配置)
    while true; do
        read -p "$(print_color '1. 请输入根路径 (/) 的后端地址 (例如: http://127.0.0.1:8080): ' "$YELLOW")" root_backend
        if [[ -z "$root_backend" ]]; then
            print_color "根路径后端地址不能为空！" "$RED"
        else
            PROXY_MAPPINGS+=("PROXY|/|$root_backend|true") # 根路径强制开启 Host
            break
        fi
    done
    
    # 额外的路径/子域名反代 (可选)
    while true; do
        read -p "$(print_color '2. 是否添加额外的路径/子域名反代? (y/N): ' "$YELLOW")" add_more
        if [[ "$add_more" =~ ^[Yy]$ ]]; then
            local matcher=""
            local backend_url=""
            
            read -p "$(print_color '请输入匹配器 (路径: /api): ' "$YELLOW")" matcher
            read -p "$(print_color '请输入后端地址 (例如: http://127.0.0.1:8081): ' "$YELLOW")" backend_url
            
            if [[ -n "$matcher" && -n "$backend_url" ]]; then
                PROXY_MAPPINGS+=("PROXY|$matcher|$backend_url|true")
            else
                print_color "匹配器和后端地址不能为空，跳过此条配置。" "$RED"
            fi
        else
            break
        fi
    done
    
    print_color "=== 映射配置结束 ===" "$BLUE"
}

# 获取文件名 (Fix 3: 优化默认文件名)
get_filename_choice() {
    local default_name
    if [ "$choice" == "1" ]; then
        default_name="${server_name}.conf"
    else
        default_name="Caddyfile" # Caddy 官方推荐文件名
    fi
    
    read -p "$(print_color "请输入配置文件名 (默认: ${default_name}): " "$YELLOW")" config_name
    if [[ -z "$config_name" ]]; then
        config_output_file="$default_name"
        print_color "使用默认文件名: ${config_output_file}" "$BLUE"
    else
        config_output_file="$config_name"
    fi
}

# =======================================================
# 模块二: Nginx 配置生成 (v1.1.1 终极 Lite 完美版)
# =======================================================

# 精简版 SSL/TLS 配置 (删除 OCSP、session 缓存，简化 ciphers)
generate_nginx_ssl_config() {
    cat << EOF
    # SSL/TLS 基础配置 (v1.1 Lite 精简版)
    ssl_certificate $ssl_certificate_path;
    ssl_certificate_key $ssl_certificate_key_path;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5; # 简化为够用且兼容性最好的配置
    ssl_prefer_server_ciphers on;
EOF
}

# HTTP 到 HTTPS 重定向 (Fix 1: 简化 497 处理并添加注释)
generate_nginx_http_to_https_redirect() {
    local redirect_logic=""
    if [ "$enable_ssl" = true ]; then
        # 启用 SSL 时，添加 301 重定向和 497 修复
        redirect_logic=$(cat << EOF
    # 核心功能: HTTP 强制跳转 HTTPS
    # 修复 1: 497 处理（非标端口访问必备）
    error_page 497 https://\$host\$request_uri; 

    location / {
        # 核心功能: 301 跳转到 HTTPS
        return 301 https://\$host\$request_uri;
    }
EOF
)
    else
        # 未启用 SSL 时，该块用于代理，不应该有 301/497 逻辑
        redirect_logic=$(cat << EOF
    # 注意: SSL 未启用，此 HTTP 80 块将直接用于反向代理。
    # 如果需要强制跳转 HTTPS, 请在 443 块启用后，取消注释以下行:
    # error_page 497 https://\$host\$request_uri; 
    # location / {
    #     return 301 https://\$host\$request_uri;
    # }
EOF
)
    fi

    cat << EOF
server {
    # 监听 IPv4 和 IPv6 80 端口
    listen 80;
    listen [::]:80;
    server_name $server_name;
    
$redirect_logic
}

EOF
}

# 精简版静态文件配置
generate_nginx_static_file_config() {
    cat << EOF
    # 静态资源缓存配置 (v1.1 Lite 精简版)
    # 简化匹配: 仅常用静态资源
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff2?|ttf|eot)$ {
        # 30天缓存 (个人项目更新频繁, 30天够用)
        expires 30d;
        add_header Cache-Control "public";
        try_files \$uri =404;
    }

EOF
}

# 反向代理配置 (保留核心头、WebSocket)
generate_nginx_proxy_config() {
    local config_block=""
    
    # 遍历所有映射
    for mapping in "${PROXY_MAPPINGS[@]}"; do
        IFS='|' read -r type matcher backend_url set_host <<< "$mapping"
        
        # 路径匹配 (Nginx 路径匹配)
        if [[ "$matcher" == /* ]]; then
            
            # 如果是根路径，且 SSL 未启用，则跳过重定向块的 location /，直接在 80 块进行代理
            if [ "$matcher" == "/" ] && [ "$enable_ssl" = false ]; then
                # 如果 SSL 未启用，根路径代理将在 80 块内，此处跳过生成独立的 location /
                continue 
            fi

            # 如果是路径匹配
            config_block+=$(cat << EOF
    location $matcher {
        # 核心功能: 反向代理 (不带尾 /, 路径完整传递)
        proxy_pass $backend_url;
        
        # 核心功能: WebSocket 完整头
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # 核心功能: 真实 IP 和 Host 传递
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

EOF
)
        fi
    done
    
    echo "$config_block"
}


# Nginx 主生成函数
generate_nginx_config() {
    local config_file="$config_output_file"
    
    # --- 1. HTTP 块 (重定向或直接代理) ---
    # 如果 SSL 未启用，则 HTTP 块必须包含根路径代理逻辑
    if [ "$enable_ssl" = false ]; then
        # 生成 HTTP 80 块并包含根路径代理
        cat << EOF > "$config_file"
server {
    # 监听 IPv4 和 IPv6 80 端口
    listen 80;
    listen [::]:80;
    server_name $server_name;
    
    # SSL 未启用，此块作为主要代理块
    
EOF
        
        # 静态文件配置 (可选)
        if [ "$include_static_cache" = true ]; then
            generate_nginx_static_file_config >> "$config_file"
        fi

        # 根路径代理 (来自 PROXY_MAPPINGS 的根路径配置)
        for mapping in "${PROXY_MAPPINGS[@]}"; do
            IFS='|' read -r type matcher backend_url set_host <<< "$mapping"
            if [ "$matcher" == "/" ]; then
                cat << EOF >> "$config_file"
    location / {
        # 核心功能: 反向代理 (不带尾 /, 路径完整传递)
        proxy_pass $backend_url;
        
        # 核心功能: WebSocket 完整头
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # 核心功能: 真实 IP 和 Host 传递
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

EOF
            fi
        done

        # 额外的路径代理
        generate_nginx_proxy_config >> "$config_file"
        
        echo "}" >> "$config_file"
        
    else
        # --- 1. HTTP 块 (重定向) ---
        generate_nginx_http_to_https_redirect > "$config_file"
        
        # --- 2. HTTPS 块 ---
        cat << EOF >> "$config_file"
server {
    # 核心功能: 保留 IPv4/IPv6 监听
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $server_name;
    
EOF
        
        # 3. SSL/TLS 配置 (精简版)
        generate_nginx_ssl_config >> "$config_file"
        
        # 4. 安全头 (精简版)
        cat << EOF >> "$config_file"

    # 安全头 (v1.1 Lite 精简版)
    # 保留基础安全: HSTS (仅 max-age) 和 MIME 嗅探防护
    add_header Strict-Transport-Security "max-age=31536000" always; # 移除 includeSubDomains 和 preload
    add_header X-Content-Type-Options nosniff always; # 保留
    # 移除 X-Frame-Options 和 X-XSS-Protection
    
EOF
        
        # 5. 静态文件配置 (可选)
        if [ "$include_static_cache" = true ]; then
            generate_nginx_static_file_config >> "$config_file"
        fi
        
        # 6. 反向代理配置
        generate_nginx_proxy_config >> "$config_file"
        
        # 7. HTTPS 块结束
        echo "}" >> "$config_file"
    fi
    
    print_color "Nginx 精简配置文件已生成到: $config_file" "$GREEN"
    
    # 部署提示
    if [ -f "$config_file" ]; then
        print_color "--- 文件内容预览 (前 45 行) ---" "$BLUE"
        cat "$config_file" | head -n 45 
        print_color "--------------------" "$BLUE"
        print_color "请将此配置放置到 Nginx 的 conf.d 目录，并确保证书路径正确。" "$YELLOW"
    fi
}


# =======================================================
# 模块三: Caddy 配置生成 (v1.1.1 终极 Lite 完美版)
# =======================================================

# Caddy 主生成函数
generate_caddy_config() {
    local config_file="$config_output_file"
    
    # 1. 块开始 (Caddy 自动处理 80/443 和 SSL/HSTS)
    cat << EOF > "$config_file"
# Caddyfile (v1.1.1 终极 Lite 完美版)
# Caddy 自动处理 HTTP 到 HTTPS 的重定向、497 错误和 SSL 证书。
# 核心功能: 保留 IPv4/IPv6
$server_name {
    
    # 核心功能: 真实 IP 和 Host 传递 (全局设置)
    # Fix 1: 将 headers 提升至站点块根部，使 reverse_proxy 更加简洁 (Caddy 最佳实践)
    header_up Host {host}
    header_up X-Real-IP {remote_host}
    # Caddy 默认支持 WebSocket 和 X-Forwarded-Proto/For
    
EOF
    
    # 2. 反向代理配置 (Fix 1: 全部使用简洁的单行语法)
    for mapping in "${PROXY_MAPPINGS[@]}"; do
        IFS='|' read -r type matcher backend_url set_host <<< "$mapping"
        
        # 路径匹配 (根路径 / 或 /path)
        if [[ "$matcher" == /* ]]; then
            
            # Caddy 路径匹配，使用简洁的 /path* 语法
            local caddy_matcher="${matcher}"
            if [ "$matcher" != "/" ]; then
                caddy_matcher="${matcher}*"
            fi

            echo "    # 路径反代: $matcher" >> "$config_file"
            echo "    reverse_proxy $caddy_matcher $backend_url" >> "$config_file" 
        fi
    done

    
    # 3. 安全头 (精简版)
    cat << EOF >> "$config_file"

    # 安全头 (v1.1 Lite 精简版)
    header {
        # 移除 encode gzip zstd (Caddy 默认开启)
        # 保留基础安全: HSTS (仅 max-age) 和 MIME 嗅探防护
        Strict-Transport-Security max-age=31536000 # 移除 includeSubDomains 和 preload
        X-Content-Type-Options nosniff
    }

}
EOF

    # 4. 部署提示
    print_color "Caddyfile 精简配置文件已生成到: $config_file" "$GREEN"
    if [ -f "$config_file" ]; then
        print_color "--- 文件内容预览 (前 20 行) ---" "$BLUE"
        cat "$config_file" | head -n 20 
        print_color "--------------------" "$BLUE"
        print_color "请将此内容粘贴到您的 Caddyfile 中，并手动重载 Caddy 服务。" "$YELLOW"
    fi
}


# =======================================================
# 模块四: 主程序
# =======================================================

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
                    # 只有在启用 SSL 时才检查 Caddyfile 路径
                    if [ "$enable_ssl" = true ]; then
                        # Caddy 自动生成和管理证书，不需要输入路径
                        generate_caddy_config
                    else
                        print_color "Caddy 官方强烈推荐使用其自动 HTTPS 功能，手动禁用 SSL 会失去 Caddy 的核心优势。" "$RED"
                        print_color "已跳过生成 Caddy 配置。" "$YELLOW"
                    fi
                fi
                ;;\
            3)
                print_color "再见！" "$GREEN"; exit 0
                ;;\
            *)\
                print_color "无效选择，请重新输入。" "$RED"\
                ;;\
        esac
        echo ""
    done
}

# 执行主程序
main