#!/bin/bash

# ============================================================
#  Docker 安装与配置脚本
#  功能：安装 Docker CE + Docker Compose v2 | 配置镜像加速
#  支持：Ubuntu / Debian / CentOS / RHEL / Fedora
# ============================================================

R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; B='\033[1;34m'; C='\033[1;36m'; N='\033[0m'
GH_PROXY="https://git.woskee.nyc.mn/"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${R}需要 root 权限${N}"
        exit 1
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS="${ID,,}"
        echo -e "${G}系统：${PRETTY_NAME:-$ID}${N}"
    else
        echo -e "${R}无法检测操作系统${N}"
        exit 1
    fi
    case "$OS" in
        ubuntu|debian|centos|rhel|fedora|almalinux|rocky|alpine) ;;
        *) echo -e "${R}不支持的发行版：$OS${N}"; exit 1 ;;
    esac
}

install_dependencies() {
    echo -e "${B}--- 检查依赖 ---${N}"
    if command -v curl &>/dev/null; then
        echo -e "${G}✔ curl 已安装${N}"
        return 0
    fi
    echo "安装 curl..."
    case "$OS" in
        ubuntu|debian) apt-get update -qq && apt-get install -y curl ;;
        centos|rhel|almalinux|rocky) yum install -y curl ;;
        fedora) dnf install -y curl ;;
        alpine) apk add curl ;;
    esac
    echo -e "${G}依赖安装完成${N}"
}

install_docker() {
    echo -e "\n${B}--- 安装 Docker CE ---${N}"
    if command -v docker &>/dev/null; then
        echo -e "${Y}Docker 已安装，版本：$(docker --version 2>/dev/null)${N}"
        if ! pgrep dockerd &>/dev/null; then
            echo "启动 Docker 服务..."
            systemctl start docker 2>/dev/null || service docker start 2>/dev/null
        fi
        return 0
    fi
    echo "从官方源安装 Docker CE（使用镜像加速）..."
    if curl -fsSL "${GH_PROXY}https://get.docker.com" | sh -s -- --mirror Aliyun; then
        echo -e "${G}Docker CE 安装成功${N}"
        systemctl enable docker && systemctl start docker
    else
        echo -e "${R}官方脚本安装失败，尝试从系统源安装...${N}"
        case "$OS" in
            ubuntu|debian)
                apt-get install -y docker.io
                systemctl enable docker && systemctl start docker
                ;;
            centos|rhel|almalinux|rocky)
                yum install -y docker 2>/dev/null || yum install -y moby-engine 2>/dev/null || {
                    echo -e "${R}系统源无 Docker 包，请手动安装${N}"
                    return 1
                }
                systemctl enable docker && systemctl start docker
                ;;
            fedora)
                dnf install -y moby-engine 2>/dev/null || dnf install -y docker 2>/dev/null || {
                    echo -e "${R}系统源无 Docker 包，请手动安装${N}"
                    return 1
                }
                systemctl enable docker && systemctl start docker
                ;;
            alpine)
                apk add docker
                rc-update add docker boot
                service docker start
                ;;
        esac
    fi
}

configure_docker() {
    local DAEMON_JSON="/etc/docker/daemon.json"
    local CONFIG_CHANGED=0

    echo -e "\n${B}--- 配置 Docker 镜像加速 ---${N}"
    mkdir -p "$(dirname "$DAEMON_JSON")"

    local MIRRORS='["https://docker.xuanyuan.me","https://docker.1ms.run","https://docker.woskee.nyc.mn","https://docker.wosken.dpdns.org","https://docker.luxxk.dpdns.org","https://docker.woskee.dpdns.org"]'

    if grep -q "registry-mirrors" "$DAEMON_JSON" 2>/dev/null; then
        echo -e "${Y}检测到已有镜像加速配置，跳过${N}"
    else
        if command -v python3 &>/dev/null; then
            python3 -c "
import json
try:
    with open('$DAEMON_JSON') as f:
        cfg = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    cfg = {}
cfg['registry-mirrors'] = $MIRRORS
cfg['live-restore'] = True
with open('$DAEMON_JSON', 'w') as f:
    json.dump(cfg, f, indent=2)
" && CONFIG_CHANGED=1 && echo -e "${G}已配置镜像加速${N}"
        else
            cat > "$DAEMON_JSON" <<EOF
{
  "registry-mirrors": $MIRRORS,
  "live-restore": true
}
EOF
            CONFIG_CHANGED=1
            echo -e "${G}已创建 daemon.json${N}"
        fi
    fi

    # systemd 代理（可选）
    if [[ "$OS" != alpine ]]; then
        local PROXY_DIR="/etc/systemd/system/docker.service.d"
        if [[ ! -f "$PROXY_DIR/http-proxy.conf" ]]; then
            echo -e "\n${Y}是否配置 Docker systemd 代理？(y/N)${N}"
            read -r input
            if [[ "$input" =~ ^[Yy]$ ]]; then
                mkdir -p "$PROXY_DIR"
                cat > "$PROXY_DIR/http-proxy.conf" <<EOF
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:7890"
Environment="HTTPS_PROXY=http://127.0.0.1:7890"
Environment="NO_PROXY=localhost,127.0.0.1,docker.xuanyuan.me,docker.1ms.run,.nyc.mn,.dpdns.org"
Environment="http_proxy=http://127.0.0.1:7890"
Environment="https_proxy=http://127.0.0.1:7890"
Environment="no_proxy=localhost,127.0.0.1,docker.xuanyuan.me,docker.1ms.run,.nyc.mn,.dpdns.org"
EOF
                CONFIG_CHANGED=1
                echo -e "${G}代理配置已写入${N}"
            fi
        fi
    fi

    if [[ $CONFIG_CHANGED -eq 1 ]]; then
        echo "重启 Docker 服务..."
        systemctl daemon-reload && systemctl restart docker && echo -e "${G}Docker 已重启${N}"
    else
        echo -e "${G}配置无变化，无需重启${N}"
    fi
}

verify_docker() {
    echo -e "\n${B}--- 验证安装 ---${N}"
    docker --version 2>/dev/null && echo -e "${G}✔ Docker 可用${N}" || echo -e "${R}✖ Docker 不可用${N}"
    docker compose version 2>/dev/null && echo -e "${G}✔ Docker Compose v2 可用${N}" || {
        echo -e "${R}✖ Docker Compose v2 未找到${N}"
        echo "尝试安装 Docker Compose 插件..."
        local PLUGIN_DIR="/usr/local/lib/docker/cli-plugins"
        mkdir -p "$PLUGIN_DIR"
        local VERSION=$(curl -s "${GH_PROXY}https://api.github.com/repos/docker/compose/releases/latest" | grep '"tag_name":' | cut -d'"' -f4)
        [[ -n "$VERSION" ]] && curl -L "${GH_PROXY}https://github.com/docker/compose/releases/download/${VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o "$PLUGIN_DIR/docker-compose" && chmod +x "$PLUGIN_DIR/docker-compose" && echo -e "${G}Docker Compose $VERSION 安装完成${N}"
    }

    echo -e "\n${C}镜像加速器：${N}"
    docker info 2>/dev/null | awk '/Registry Mirrors:/{flag=1; next} /^$/{flag=0} flag{sub(/^[ \t]+/,""); print}'
    echo -e "\n${C}代理配置：${N}"
    docker info 2>/dev/null | awk '/HTTP Proxy:|HTTPS Proxy:|No Proxy:/{sub(/^[ \t]+/,""); print}'
}

main() {
    check_root
    detect_os
    install_dependencies
    install_docker
    configure_docker
    verify_docker
    echo -e "\n${G}Docker 安装配置完成${N}"
}

main "$@"