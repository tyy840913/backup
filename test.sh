#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # 结束颜色

# 打印带颜色的消息
print_color() {
    echo -e "${2}${1}${NC}"
}

# 显示标题
print_title() {
    echo "========================================"
    echo "    Web服务器配置生成器（增强版）"
    echo "========================================"
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

# 输入验证函数：端口
validate_port() {
    local port=$1
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        print_color "错误: 端口号必须是1-65535之间的数字" "$RED"
        return 1
    fi
    return 0
}

# 验证IPv4格式
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
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

# 验证路径格式
validate_path() {
    local path=$1
    if [[ $path =~ ^\/[a-zA-Z0-9_\-\.\/]*$ ]]; then
        return 0
    else
        return 1
    fi
}

# 获取后端配置
get_backend_config() {
    local backend_type=$1
    
    case $backend_type in
        "single")
            get_single_backend_config
            ;;
        "multi")
            get_multi_backend_config
            ;;
    esac
}

# 获取单后端配置
get_single_backend_config() {
    while true; do
        read -p "请输入后端服务地址 (IP、域名或带端口的地址，如 127.0.0.1:8080): " backend_input

        if [ -z "$backend_input" ]; then
            print_color "错误: 后端地址不能为空" "$RED"
            continue
        fi

        # 检查是否包含端口
        if [[ $backend_input =~ :[0-9]+$ ]]; then
            backend_host=$(echo "$backend_input" | awk -F: '{print $1}')
            backend_port=$(echo "$backend_input" | awk -F: '{print $2}')
        else
            backend_host="$backend_input"
            backend_port="80"
        fi

        # 验证输入的是IP还是域名
        if validate_ip "$backend_host" || validate_domain "$backend_host"; then
            # 询问协议
            echo "请选择后端协议:"
            echo "1. HTTP (默认)"
            echo "2. HTTPS"
            read -p "请选择 [1-2]: " protocol_choice
            protocol_choice=${protocol_choice:-1}
            case $protocol_choice in
                2)
                    backend_url="https://${backend_host}:${backend_port}"
                    ;;
                *)
                    backend_url="http://${backend_host}:${backend_port}"
                    ;;
            esac
            break
        else
            print_color "错误: 请输入有效的 IP 地址或域名" "$RED"
        fi
    done

    read -p "请输入代理路径 (例如: /api/, 留空为 /): " proxy_path_input
    if [ -z "$proxy_path_input" ]; then
        proxy_path="/"
    else
        # 确保路径以/开头
        if [[ ! "$proxy_path_input" =~ ^/ ]]; then
            proxy_path_input="/$proxy_path_input"
        fi
        proxy_path="$proxy_path_input"
    fi

    read -e -p "是否传递 Host 头? [Y/n]: " pass_host
    pass_host=${pass_host:-y}
    if [[ ! "$pass_host" =~ ^[Nn] ]]; then
        proxy_set_host=true
    else
        proxy_set_host=false
    fi
}

# 获取多后端配置
get_multi_backend_config() {
    multi_backends=()
    
    echo ""
    print_color "=== 根域名处理配置 ===" "$PURPLE"
    echo "请选择根域名的处理方式:"
    echo "1. 返回 404 (不处理根路径)"
    echo "2. 代理到特定后端"
    echo "3. 服务静态文件"
    read -p "请选择 [1-3]: " root_choice
    
    case $root_choice in
        2)
            echo "配置根域名代理后端..."
            get_single_backend_config
            multi_backends+=("root:$proxy_path:$backend_url:$proxy_set_host")
            ;;
        3)
            read -p "请输入静态文件根目录 (默认: /var/www/html): " static_root
            static_root=${static_root:-/var/www/html}
            multi_backends+=("root:static:$static_root")
            ;;
        *)
            multi_backends+=("root:404")
            print_color "根路径将返回 404" "$YELLOW"
            ;;
    esac
    
    echo ""
    print_color "=== 多后端代理配置 ===" "$PURPLE"
    echo "请选择多后端代理类型:"
    echo "1. 路径代理 (如 /api/* 代理到不同后端)"
    echo "2. 子域名代理 (如 api.domain.com 代理到不同后端)"
    read -p "请选择 [1-2]: " multi_type_choice
    
    if [ $multi_type_choice -eq 1 ]; then
        get_path_based_proxies
    else
        get_subdomain_based_proxies
    fi
}

# 获取基于路径的代理配置
get_path_based_proxies() {
    while true; do
        echo ""
        print_color "添加路径代理规则" "$CYAN"
        read -p "请输入代理路径 (如 /api/, 输入 'done' 结束): " path_input
        
        if [ "$path_input" = "done" ]; then
            break
        fi
        
        if [ -z "$path_input" ]; then
            print_color "路径不能为空" "$RED"
            continue
        fi
        
        # 确保路径以/开头
        if [[ ! "$path_input" =~ ^/ ]]; then
            path_input="/$path_input"
        fi
        
        # 获取后端配置
        get_single_backend_config
        multi