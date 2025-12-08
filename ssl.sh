#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置文件
CONFIG_DIR="$HOME/.acme_script"
CONFIG_FILE="$CONFIG_DIR/config"
ACME_DIR="$HOME/.acme.sh"
CERT_DIR="$CONFIG_DIR/certs"

# 初始化目录
init_directories() {
    mkdir -p "$CONFIG_DIR" "$CERT_DIR"
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "DEFAULT_CA=letsencrypt" > "$CONFIG_FILE"
        echo "DEFAULT_MODE=manual" >> "$CONFIG_FILE"
        echo "DEFAULT_KEY_LENGTH=ec-256" >> "$CONFIG_FILE"
    fi
}

# 检查并安装依赖
check_dependencies() {
    local dependencies=("curl" "socat" "openssl" "crontab" "idn")
    local missing=()
    
    echo -e "${BLUE}[*] 检查系统依赖...${NC}"
    
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -eq 0 ]; then
        echo -e "${GREEN}[✓] 所有依赖已安装${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}[!] 发现缺失依赖: ${missing[*]}${NC}"
    echo -e "${BLUE}[*] 尝试安装缺失依赖...${NC}"
    
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y "${missing[@]}" || {
            echo -e "${RED}[✗] 依赖安装失败${NC}"
            return 1
        }
    elif command -v yum &> /dev/null; then
        sudo yum install -y "${missing[@]}" || {
            echo -e "${RED}[✗] 依赖安装失败${NC}"
            return 1
        }
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y "${missing[@]}" || {
            echo -e "${RED}[✗] 依赖安装失败${NC}"
            return 1
        }
    else
        echo -e "${RED}[✗] 无法确定包管理器，请手动安装: ${missing[*]}${NC}"
        return 1
    fi
    
    echo -e "${GREEN}[✓] 依赖安装完成${NC}"
    return 0
}

# 安装acme.sh
install_acme() {
    echo -e "${BLUE}[*] 检查acme.sh安装...${NC}"
    
    if [ -f "$ACME_DIR/acme.sh" ]; then
        echo -e "${GREEN}[✓] acme.sh已安装${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}[!] acme.sh未安装，开始安装...${NC}"
    
    # 尝试官方安装
    echo -e "${BLUE}[*] 尝试官方安装...${NC}"
    if curl https://get.acme.sh | sh; then
        echo -e "${GREEN}[✓] acme.sh安装成功${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}[!] 官方安装失败，尝试GitHub安装...${NC}"
    
    # 尝试GitHub安装
    if git clone https://github.com/acmesh-official/acme.sh.git "$ACME_DIR"; then
        cd "$ACME_DIR" || return 1
        ./acme.sh --install \
            --home "$ACME_DIR" \
            --config-home "$CONFIG_DIR" \
            --cert-home "$CERT_DIR" || {
            echo -e "${RED}[✗] GitHub安装失败${NC}"
            return 1
        }
        echo -e "${GREEN}[✓] acme.sh安装成功${NC}"
        return 0
    fi
    
    echo -e "${RED}[✗] acme.sh安装失败${NC}"
    return 1
}

# 检查DNS记录
check_dns_record() {
    local domain="$1"
    local txt_record="$2"
    local max_attempts=60  # 5分钟，每5秒一次
    local attempt=1
    
    echo -e "${BLUE}[*] 开始检查DNS记录传播...${NC}"
    
    while [ $attempt -le $max_attempts ]; do
        echo -e "${YELLOW}[!] 尝试 $attempt/$max_attempts...${NC}"
        
        # 使用多个DNS服务器检查
        local dns_servers=("8.8.8.8" "1.1.1.1" "208.67.222.222" "8.8.4.4")
        local success=0
        
        for dns_server in "${dns_servers[@]}"; do
            if dig +short TXT "_acme-challenge.$domain" @"$dns_server" | grep -q "$txt_record"; then
                echo -e "${GREEN}[✓] DNS服务器 $dns_server 已生效${NC}"
                ((success++))
            fi
        done
        
        if [ $success -ge 2 ]; then
            echo -e "${GREEN}[✓] DNS记录已生效${NC}"
            return 0
        fi
        
        sleep 5
        ((attempt++))
    done
    
    echo -e "${RED}[✗] DNS记录检查超时${NC}"
    return 1
}

# 注册证书颁发机构
register_ca() {
    local ca="$1"
    local email="$2"
    
    case "$ca" in
        "letsencrypt")
            "$ACME_DIR/acme.sh" --register-account -m "$email" \
                --server letsencrypt || return 1
            ;;
        "zerossl")
            echo -e "${YELLOW}[!] ZeroSSL需要EAB凭证${NC}"
            read -p "请输入EAB Key ID: " eab_kid
            read -p "请输入EAB HMAC Key: " eab_hmac
            
            "$ACME_DIR/acme.sh" --register-account -m "$email" \
                --server zerossl \
                --eab-kid "$eab_kid" \
                --eab-hmac-key "$eab_hmac" || return 1
            ;;
        "buypass")
            "$ACME_DIR/acme.sh" --register-account -m "$email" \
                --server buypass || return 1
            ;;
        *)
            echo -e "${RED}[✗] 不支持的CA: $ca${NC}"
            return 1
            ;;
    esac
    
    echo -e "${GREEN}[✓] $ca 注册成功${NC}"
    return 0
}

# 申请证书
issue_certificate() {
    local domain="$1"
    local ca="$2"
    local mode="$3"
    local keylength="$4"
    local email="$5"
    
    echo -e "${BLUE}[*] 开始申请证书: $domain${NC}"
    
    # 检查是否已注册
    if [ "$ca" != "letsencrypt" ]; then
        if ! "$ACME_DIR/acme.sh" --list-accounts | grep -q "$email"; then
            echo -e "${YELLOW}[!] 需要注册到 $ca${NC}"
            register_ca "$ca" "$email" || return 1
        fi
    fi
    
    # 申请证书
    if [ "$mode" = "manual" ]; then
        echo -e "${YELLOW}[!] 使用手动DNS验证模式${NC}"
        
        # 申请并获取TXT记录
        local output
        output=$("$ACME_DIR/acme.sh" --issue \
            --domain "$domain" \
            --server "$ca" \
            --dns \
            --keylength "$keylength" \
            --dnssleep 0 2>&1)
        
        # 提取TXT记录
        local txt_record
        txt_record=$(echo "$output" | grep -oP 'TXT value: \K[^"]+' | head -1)
        
        if [ -z "$txt_record" ]; then
            txt_record=$(echo "$output" | grep -oP 'TXT=\K[^ ]+' | head -1)
        fi
        
        if [ -z "$txt_record" ]; then
            echo -e "${RED}[✗] 无法提取TXT记录${NC}"
            return 1
        fi
        
        echo -e "${GREEN}[✓] 请添加DNS TXT记录:${NC}"
        echo -e "${BLUE}主机名: _acme-challenge.$domain${NC}"
        echo -e "${BLUE}记录值: $txt_record${NC}"
        echo -e "${YELLOW}添加完成后按回车键继续...${NC}"
        read -r
        
        # 检查DNS记录
        check_dns_record "$domain" "$txt_record" || return 1
        
        # 完成证书申请
        if "$ACME_DIR/acme.sh" --renew --domain "$domain" --force; then
            echo -e "${GREEN}[✓] 证书申请成功${NC}"
            return 0
        else
            echo -e "${RED}[✗] 证书申请失败${NC}"
            return 1
        fi
    else
        # API自动验证
        echo -e "${YELLOW}[!] 使用API自动验证${NC}"
        
        # 选择DNS API
        echo "选择DNS服务商："
        echo "1) Cloudflare"
        echo "2) Aliyun"
        echo "3) DNSPod"
        echo "4) CloudXNS"
        echo "5) GoDaddy"
        echo "6) Namecheap"
        read -p "请选择(1-6): " dns_choice
        
        case $dns_choice in
            1) dns_api="dns_cf" ;;
            2) dns_api="dns_ali" ;;
            3) dns_api="dns_dp" ;;
            4) dns_api="dns_cx" ;;
            5) dns_api="dns_gd" ;;
            6) dns_api="dns_nc" ;;
            *) echo -e "${RED}[✗] 无效选择${NC}"; return 1 ;;
        esac
        
        # 设置API凭证
        read -p "请输入API Key: " api_key
        read -p "请输入API Secret: " api_secret
        
        export "${dns_api#dns_}_Key"="$api_key"
        export "${dns_api#dns_}_Secret"="$api_secret"
        
        # 申请证书
        if "$ACME_DIR/acme.sh" --issue \
            --domain "$domain" \
            --server "$ca" \
            --dns "$dns_api" \
            --keylength "$keylength"; then
            echo -e "${GREEN}[✓] 证书申请成功${NC}"
            return 0
        else
            echo -e "${RED}[✗] 证书申请失败${NC}"
            return 1
        fi
    fi
}

# 证书申请子菜单
cert_issue_menu() {
    echo -e "\n${BLUE}=== 证书申请 ===${NC}"
    
    read -p "请输入域名: " domain
    if [ -z "$domain" ]; then
        echo -e "${RED}[✗] 域名不能为空${NC}"
        return 1
    fi
    
    # 选择CA
    echo "选择证书颁发机构："
    echo "1) Let's Encrypt (默认)"
    echo "2) ZeroSSL (需要注册)"
    echo "3) BuyPass"
    read -p "请选择(1-3): " ca_choice
    
    case $ca_choice in
        1|"") ca="letsencrypt" ;;
        2) ca="zerossl" ;;
        3) ca="buypass" ;;
        *) echo -e "${RED}[✗] 无效选择${NC}"; return 1 ;;
    esac
    
    # 选择验证模式
    echo "选择验证模式："
    echo "1) 手动DNS验证 (默认)"
    echo "2) DNS API自动验证"
    read -p "请选择(1-2): " mode_choice
    
    case $mode_choice in
        1|"") mode="manual" ;;
        2) mode="api" ;;
        *) echo -e "${RED}[✗] 无效选择${NC}"; return 1 ;;
    esac
    
    # 选择密钥类型
    echo "选择密钥类型："
    echo "1) RSA 2048"
    echo "2) ECC 256 (默认)"
    echo "3) ECC 384"
    read -p "请选择(1-3): " key_choice
    
    case $key_choice in
        1) keylength="2048" ;;
        2|"") keylength="ec-256" ;;
        3) keylength="ec-384" ;;
        *) echo -e "${RED}[✗] 无效选择${NC}"; return 1 ;;
    esac
    
    read -p "请输入邮箱地址: " email
    if [ -z "$email" ]; then
        echo -e "${RED}[✗] 邮箱不能为空${NC}"
        return 1
    fi
    
    # 执行证书申请
    issue_certificate "$domain" "$ca" "$mode" "$keylength" "$email"
    
    if [ $? -eq 0 ]; then
        # 自动安装证书
        read -p "证书申请成功，是否立即安装？(y/n): " install_now
        if [[ $install_now =~ ^[Yy]$ ]]; then
            install_certificate_menu "$domain"
        fi
    fi
}

# 证书续期
renew_certificate() {
    echo -e "\n${BLUE}=== 证书续期 ===${NC}"
    
    # 列出所有证书
    local certs=()
    local index=1
    
    for cert in "$CERT_DIR"/*; do
        if [ -d "$cert" ]; then
            cert_name=$(basename "$cert")
            certs+=("$cert_name")
            echo "$index) $cert_name"
            ((index++))
        fi
    done
    
    if [ ${#certs[@]} -eq 0 ]; then
        echo -e "${YELLOW}[!] 没有找到证书${NC}"
        return 1
    fi
    
    read -p "请选择要续期的证书序号: " cert_index
    if ! [[ "$cert_index" =~ ^[0-9]+$ ]] || [ "$cert_index" -lt 1 ] || [ "$cert_index" -gt ${#certs[@]} ]; then
        echo -e "${RED}[✗] 无效的序号${NC}"
        return 1
    fi
    
    local domain="${certs[$((cert_index-1))]}"
    
    echo -e "${BLUE}[*] 续期证书: $domain${NC}"
    
    # 检查原验证方式
    local cert_info="$CERT_DIR/$domain/$domain.conf"
    if [ -f "$cert_info" ]; then
        local original_mode=$(grep "Le_DNSSleep" "$cert_info")
        if [ -n "$original_mode" ] && [ "$original_mode" = "Le_DNSSleep='0'" ]; then
            echo -e "${YELLOW}[!] 检测到手动DNS验证模式${NC}"
            echo "请确保DNS记录已正确设置"
            read -p "按回车键开始续期..."
        fi
    fi
    
    # 执行续期
    if "$ACME_DIR/acme.sh" --renew --domain "$domain" --force; then
        echo -e "${GREEN}[✓] 证书续期成功${NC}"
        return 0
    else
        echo -e "${RED}[✗] 证书续期失败${NC}"
        return 1
    fi
}

# 删除证书
delete_certificate() {
    echo -e "\n${BLUE}=== 删除证书 ===${NC}"
    
    # 列出所有证书
    local certs=()
    local index=1
    
    for cert in "$CERT_DIR"/*; do
        if [ -d "$cert" ]; then
            cert_name=$(basename "$cert")
            certs+=("$cert_name")
            echo "$index) $cert_name"
            ((index++))
        fi
    done
    
    if [ ${#certs[@]} -eq 0 ]; then
        echo -e "${YELLOW}[!] 没有找到证书${NC}"
        return 1
    fi
    
    read -p "请选择要删除的证书序号: " cert_index
    if ! [[ "$cert_index" =~ ^[0-9]+$ ]] || [ "$cert_index" -lt 1 ] || [ "$cert_index" -gt ${#certs[@]} ]; then
        echo -e "${RED}[✗] 无效的序号${NC}"
        return 1
    fi
    
    local domain="${certs[$((cert_index-1))]}"
    
    read -p "确定要删除证书 $domain 吗？(y/n): " confirm
    if ! [[ $confirm =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}[!] 取消删除${NC}"
        return 0
    fi
    
    # 删除证书
    if "$ACME_DIR/acme.sh" --remove --domain "$domain"; then
        # 清理残留文件
        rm -rf "$CERT_DIR/$domain"
        echo -e "${GREEN}[✓] 证书删除成功${NC}"
        return 0
    else
        echo -e "${RED}[✗] 证书删除失败${NC}"
        return 1
    fi
}

# 列出证书
list_certificates() {
    echo -e "\n${BLUE}=== 证书列表 ===${NC}"
    
    local certs=()
    local index=1
    
    for cert in "$CERT_DIR"/*; do
        if [ -d "$cert" ]; then
            cert_name=$(basename "$cert")
            certs+=("$cert_name")
            
            # 获取证书信息
            local cert_file="$cert/$cert_name.cer"
            if [ -f "$cert_file" ]; then
                local expiry_date
                expiry_date=$(openssl x509 -enddate -noout -in "$cert_file" 2>/dev/null | cut -d= -f2)
                echo "$index) $cert_name - 到期时间: $expiry_date"
            else
                echo "$index) $cert_name"
            fi
            ((index++))
        fi
    done
    
    if [ ${#certs[@]} -eq 0 ]; then
        echo -e "${YELLOW}[!] 没有找到证书${NC}"
    fi
}

# 安装证书到Web服务
install_certificate_menu() {
    local domain="$1"
    
    if [ -z "$domain" ]; then
        echo -e "\n${BLUE}=== 安装证书 ===${NC}"
        
        # 列出证书供选择
        local certs=()
        local index=1
        
        for cert in "$CERT_DIR"/*; do
            if [ -d "$cert" ]; then
                cert_name=$(basename "$cert")
                certs+=("$cert_name")
                echo "$index) $cert_name"
                ((index++))
            fi
        done
        
        if [ ${#certs[@]} -eq 0 ]; then
            echo -e "${YELLOW}[!] 没有找到证书${NC}"
            return 1
        fi
        
        read -p "请选择要安装的证书序号: " cert_index
        if ! [[ "$cert_index" =~ ^[0-9]+$ ]] || [ "$cert_index" -lt 1 ] || [ "$cert_index" -gt ${#certs[@]} ]; then
            echo -e "${RED}[✗] 无效的序号${NC}"
            return 1
        fi
        
        domain="${certs[$((cert_index-1))]}"
    fi
    
    echo -e "\n${BLUE}安装证书: $domain${NC}"
    echo "选择Web服务："
    echo "1) Nginx"
    echo "2) Apache"
    echo "3) X-UI"
    echo "4) Caddy"
    echo "5) Haproxy"
    echo "6) Trojan"
    echo "7) V2Ray"
    echo "8) 自定义路径"
    read -p "请选择(1-8): " service_choice
    
    local cert_path="$CERT_DIR/$domain/$domain.cer"
    local key_path="$CERT_DIR/$domain/$domain.key"
    local ca_path="$CERT_DIR/$domain/ca.cer"
    
    if [ ! -f "$cert_path" ] || [ ! -f "$key_path" ]; then
        echo -e "${RED}[✗] 证书文件不存在${NC}"
        return 1
    fi
    
    case $service_choice in
        1) # Nginx
            local nginx_conf="/etc/nginx/conf.d/$domain.conf"
            if [ ! -f "$nginx_conf" ]; then
                nginx_conf="/etc/nginx/sites-available/$domain"
            fi
            
            if [ ! -f "$nginx_conf" ]; then
                read -p "请输入Nginx配置文件路径: " nginx_conf
            fi
            
            if [ -f "$nginx_conf" ]; then
                # 备份原配置
                cp "$nginx_conf" "$nginx_conf.bak"
                
                # 更新证书路径
                sed -i "s|ssl_certificate .*|ssl_certificate $cert_path;|" "$nginx_conf"
                sed -i "s|ssl_certificate_key .*|ssl_certificate_key $key_path;|" "$nginx_conf"
                
                echo -e "${GREEN}[✓] Nginx配置已更新${NC}"
                echo -e "${YELLOW}[!] 请执行: nginx -t && systemctl reload nginx${NC}"
            else
                echo -e "${YELLOW}[!] Nginx配置文件不存在，证书文件位置:${NC}"
                echo "证书: $cert_path"
                echo "私钥: $key_path"
            fi
            ;;
            
        2) # Apache
            local apache_conf="/etc/apache2/sites-available/$domain.conf"
            if [ ! -f "$apache_conf" ]; then
                apache_conf="/etc/httpd/conf.d/$domain.conf"
            fi
            
            if [ ! -f "$apache_conf" ]; then
                read -p "请输入Apache配置文件路径: " apache_conf
            fi
            
            if [ -f "$apache_conf" ]; then
                # 备份原配置
                cp "$apache_conf" "$apache_conf.bak"
                
                # 更新证书路径
                sed -i "s|SSLCertificateFile .*|SSLCertificateFile $cert_path|" "$apache_conf"
                sed -i "s|SSLCertificateKeyFile .*|SSLCertificateKeyFile $key_path|" "$apache_conf"
                
                if [ -f "$ca_path" ]; then
                    sed -i "s|SSLCertificateChainFile .*|SSLCertificateChainFile $ca_path|" "$apache_conf"
                fi
                
                echo -e "${GREEN}[✓] Apache配置已更新${NC}"
                echo -e "${YELLOW}[!] 请执行: apachectl configtest && systemctl reload apache2${NC}"
            else
                echo -e "${YELLOW}[!] Apache配置文件不存在，证书文件位置:${NC}"
                echo "证书: $cert_path"
                echo "私钥: $key_path"
            fi
            ;;
            
        3) # X-UI
            local xui_config="/etc/x-ui/config.json"
            if [ ! -f "$xui_config" ]; then
                xui_config="/usr/local/x-ui/config.json"
            fi
            
            if [ ! -f "$xui_config" ]; then
                read -p "请输入X-UI配置文件路径: " xui_config
            fi
            
            if [ -f "$xui_config" ]; then
                # 备份原配置
                cp "$xui_config" "$xui_config.bak"
                
                # 读取证书内容
                local cert_content
                cert_content=$(sed ':a;N;$!ba;s/\n/\\n/g' "$cert_path")
                local key_content
                key_content=$(sed ':a;N;$!ba;s/\n/\\n/g' "$key_path")
                
                # 更新JSON配置
                python3 -c "
import json
with open('$xui_config', 'r') as f:
    config = json.load(f)
if 'inbounds' in config:
    for inbound in config['inbounds']:
        if 'streamSettings' in inbound and 'security' in inbound['streamSettings']:
            if inbound['streamSettings']['security'] == 'tls':
                inbound['streamSettings']['tlsSettings'] = inbound['streamSettings'].get('tlsSettings', {})
                inbound['streamSettings']['tlsSettings']['certificates'] = [{
                    'certificateFile': '$cert_path',
                    'keyFile': '$key_path'
                }]
with open('$xui_config', 'w') as f:
    json.dump(config, f, indent=2)
" 2>/dev/null || {
                    echo -e "${YELLOW}[!] Python不可用，手动更新X-UI配置:${NC}"
                    echo "证书: $cert_path"
                    echo "私钥: $key_path"
                }
                
                echo -e "${GREEN}[✓] X-UI配置已更新${NC}"
                echo -e "${YELLOW}[!] 请重启X-UI服务${NC}"
            else
                echo -e "${YELLOW}[!] X-UI配置文件不存在，证书文件位置:${NC}"
                echo "证书: $cert_path"
                echo "私钥: $key_path"
            fi
            ;;
            
        4) # Caddy
            local caddyfile="/etc/caddy/Caddyfile"
            if [ ! -f "$caddyfile" ]; then
                caddyfile="/usr/local/etc/caddy/Caddyfile"
            fi
            
            if [ ! -f "$caddyfile" ]; then
                read -p "请输入Caddyfile路径: " caddyfile
            fi
            
            if [ -f "$caddyfile" ]; then
                echo -e "${YELLOW}[!] Caddy通常自动管理证书，如需手动配置:${NC}"
                echo "将以下内容添加到Caddyfile:"
                echo "$domain {"
                echo "    tls $cert_path $key_path"
                echo "    ...其他配置..."
                echo "}"
            fi
            ;;
            
        5) # Haproxy
            local haproxy_cfg="/etc/haproxy/haproxy.cfg"
            if [ ! -f "$haproxy_cfg" ]; then
                read -p "请输入HAProxy配置文件路径: " haproxy_cfg
            fi
            
            if [ -f "$haproxy_cfg" ]; then
                # 合并证书链
                local combined_cert="/etc/haproxy/certs/$domain.pem"
                mkdir -p /etc/haproxy/certs
                cat "$cert_path" "$ca_path" 2>/dev/null > "$combined_cert"
                
                echo -e "${GREEN}[✓] HAProxy证书已合并到: $combined_cert${NC}"
                echo -e "${YELLOW}[!] 在配置中添加: bind :443 ssl crt $combined_cert${NC}"
            fi
            ;;
            
        6) # Trojan
            local trojan_config="/etc/trojan/config.json"
            if [ ! -f "$trojan_config" ]; then
                read -p "请输入Trojan配置文件路径: " trojan_config
            fi
            
            if [ -f "$trojan_config" ]; then
                cp "$trojan_config" "$trojan_config.bak"
                
                # 更新Trojan配置
                sed -i "s|\"cert\":.*|\"cert\": \"$cert_path\",|" "$trojan_config"
                sed -i "s|\"key\":.*|\"key\": \"$key_path\",|" "$trojan_config"
                
                echo -e "${GREEN}[✓] Trojan配置已更新${NC}"
                echo -e "${YELLOW}[!] 请重启Trojan服务${NC}"
            fi
            ;;
            
        7) # V2Ray
            local v2ray_config="/etc/v2ray/config.json"
            if [ ! -f "$v2ray_config" ]; then
                v2ray_config="/usr/local/etc/v2ray/config.json"
            fi
            
            if [ ! -f "$v2ray_config" ]; then
                read -p "请输入V2Ray配置文件路径: " v2ray_config
            fi
            
            if [ -f "$v2ray_config" ]; then
                cp "$v2ray_config" "$v2ray_config.bak"
                
                # 更新V2Ray配置
                python3 -c "
import json
with open('$v2ray_config', 'r') as f:
    config = json.load(f)
for inbound in config.get('inbounds', []):
    if 'streamSettings' in inbound and 'security' in inbound['streamSettings']:
        if inbound['streamSettings']['security'] == 'tls':
            inbound['streamSettings']['tlsSettings'] = inbound['streamSettings'].get('tlsSettings', {})
            inbound['streamSettings']['tlsSettings']['certificates'] = [{
                'certificateFile': '$cert_path',
                'keyFile': '$key_path'
            }]
with open('$v2ray_config', 'w') as f:
    json.dump(config, f, indent=2)
" 2>/dev/null || {
                    echo -e "${YELLOW}[!] Python不可用，手动更新V2Ray配置:${NC}"
                    echo "证书: $cert_path"
                    echo "私钥: $key_path"
                }
                
                echo -e "${GREEN}[✓] V2Ray配置已更新${NC}"
                echo -e "${YELLOW}[!] 请重启V2Ray服务${NC}"
            fi
            ;;
            
        8) # 自定义路径
            echo -e "${GREEN}[✓] 证书文件位置:${NC}"
            echo "完整证书链: $cert_path"
            echo "私钥文件: $key_path"
            if [ -f "$ca_path" ]; then
                echo "CA证书: $ca_path"
            fi
            
            read -p "请输入目标证书路径: " target_cert
            read -p "请输入目标私钥路径: " target_key
            
            if [ -n "$target_cert" ]; then
                cp "$cert_path" "$target_cert"
                echo -e "${GREEN}[✓] 证书复制到: $target_cert${NC}"
            fi
            
            if [ -n "$target_key" ]; then
                cp "$key_path" "$target_key"
                echo -e "${GREEN}[✓] 私钥复制到: $target_key${NC}"
            fi
            ;;
            
        *)
            echo -e "${RED}[✗] 无效的选择${NC}"
            return 1
            ;;
    esac
    
    return 0
}

# 重新安装acme.sh
reinstall_acme() {
    echo -e "\n${BLUE}=== 重新安装acme.sh ===${NC}"
    
    read -p "确定要重新安装acme.sh吗？(y/n): " confirm
    if ! [[ $confirm =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}[!] 取消重新安装${NC}"
        return 0
    fi
    
    # 备份证书
    echo -e "${BLUE}[*] 备份证书...${NC}"
    local backup_dir="/tmp/acme_backup_$(date +%s)"
    mkdir -p "$backup_dir"
    cp -r "$CERT_DIR" "$backup_dir/certs"
    cp -r "$CONFIG_DIR" "$backup_dir/config"
    
    # 卸载旧版本
    echo -e "${BLUE}[*] 卸载旧版本...${NC}"
    if [ -f "$ACME_DIR/acme.sh" ]; then
        "$ACME_DIR/acme.sh" --uninstall || true
    fi
    rm -rf "$ACME_DIR"
    
    # 重新安装
    echo -e "${BLUE}[*] 重新安装...${NC}"
    if install_acme; then
        # 恢复备份
        echo -e "${BLUE}[*] 恢复证书...${NC}"
        cp -r "$backup_dir/certs"/* "$CERT_DIR/" 2>/dev/null || true
        cp -r "$backup_dir/config"/* "$CONFIG_DIR/" 2>/dev/null || true
        
        echo -e "${GREEN}[✓] acme.sh重新安装完成${NC}"
        rm -rf "$backup_dir"
        return 0
    else
        echo -e "${RED}[✗] 重新安装失败${NC}"
        echo -e "${YELLOW}[!] 备份文件保存在: $backup_dir${NC}"
        return 1
    fi
}

# 主菜单
main_menu() {
    while true; do
        echo -e "\n${BLUE}=== ACME证书管理脚本 ===${NC}"
        echo "1) 申请证书"
        echo "2) 证书续期"
        echo "3) 删除证书"
        echo "4) 列出证书"
        echo "5) 安装证书到Web服务"
        echo "6) 重新安装acme.sh"
        echo "0) 退出"
        
        read -p "请选择操作(0-6): " choice
        
        case $choice in
            1) cert_issue_menu ;;
            2) renew_certificate ;;
            3) delete_certificate ;;
            4) list_certificates ;;
            5) install_certificate_menu ;;
            6) reinstall_acme ;;
            0) 
                echo -e "${GREEN}再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}[✗] 无效的选择${NC}"
                ;;
        esac
        
        echo -e "\n${YELLOW}按回车键继续...${NC}"
        read -r
    done
}

# 主程序
main() {
    # 检查root权限
    if [ "$EUID" -eq 0 ]; then
        echo -e "${YELLOW}[!] 不建议使用root用户运行，建议使用普通用户${NC}"
        read -p "是否继续？(y/n): " continue_as_root
        if ! [[ $continue_as_root =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    # 初始化
    init_directories
    
    # 检查依赖
    if ! check_dependencies; then
        echo -e "${RED}[✗] 依赖检查失败，请手动安装缺失的依赖${NC}"
        exit 1
    fi
    
    # 安装acme.sh
    if ! install_acme; then
        echo -e "${RED}[✗] acme.sh安装失败${NC}"
        exit 1
    fi
    
    # 设置alias
    alias acme.sh="$ACME_DIR/acme.sh"
    
    # 显示主菜单
    main_menu
}

# 运行主程序
main
