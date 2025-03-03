#!/bin/bash

# 颜色定义
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # 重置颜色

# 系统检测函数
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    elif type lsb_release >/dev/null 2>&1; then
        OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
        VER=$(lsb_release -sr)
    else
        OS=$(uname -s)
        VER=$(uname -r)
    fi
}

# 步骤输出函数
step_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    sleep 0.5
}

step_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    sleep 0.5
}

step_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" 
    sleep 0.5
}

step_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    sleep 0.5
}

# 主逻辑
main() {
    clear
    step_info "开始检测系统环境..."
    detect_os
    
    # 步骤1：检查当前语言环境[1,3](@ref)
    step_info "检查当前语言环境..."
    if locale | grep -q "LANG=zh_CN"; then
        step_success "当前已是中文环境"
        exit 0
    else
        step_warning "当前非中文环境"
    fi
    
    # 步骤2：验证locale配置[2,3](@ref)
    step_info "检查locale配置..."
    if grep -q "zh_CN.UTF-8" /etc/locale.gen; then
        step_success "已存在中文locale配置"
    else
        step_warning "缺少中文locale配置"
        case $OS in
            ubuntu|debian)
                sudo sed -i 's/# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
                ;;
            centos|rhel)
                sudo localedef -c -f UTF-8 -i zh_CN zh_CN.UTF-8
                ;;
            fedora)
                sudo dnf install glibc-langpack-zh -y
                ;;
        esac
        sudo locale-gen && step_success "生成中文locale"
    fi
    
    # 步骤3：尝试修复环境[4,5](@ref)
    step_info "尝试自动修复..."
    case $OS in
        ubuntu|debian)
            sudo update-locale LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8
            ;;
        centos|rhel|fedora)
            sudo localectl set-locale LANG=zh_CN.UTF-8
            ;;
    esac
    if [ $? -eq 0 ]; then
        step_success "环境变量设置成功"
    else
        step_error "自动修复失败，尝试安装语言包"
    fi
    
    # 步骤4：安装语言包[3,5](@ref)
    step_info "开始安装中文语言包..."
    case $OS in
        ubuntu|debian)
            sudo apt-get update && sudo apt-get install -y language-pack-zh-hans
            ;;
        centos|rhel)
            sudo yum groupinstall -y "Chinese Support"
            ;;
        fedora)
            sudo dnf install -y glibc-langpack-zh
            ;;
        *)
            step_error "不支持的发行版"
            exit 1
            ;;
    esac
    
    # 最终配置[1,3](@ref)
    step_info "应用最终配置..."
    sudo cp /etc/locale.conf /etc/locale.conf.bak 2>/dev/null
    echo 'LANG="zh_CN.UTF-8"' | sudo tee /etc/locale.conf >/dev/null
    source /etc/profile.d/lang.sh 2>/dev/null
    
    step_success "配置完成，建议重启系统"
}

# 执行主函数
main
