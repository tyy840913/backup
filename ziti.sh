#!/bin/bash

# 功能：自动检测并安装中文字体，配置系统显示支持
# 支持系统：Debian/Ubuntu/CentOS/Alpine

# 检查中文字体是否已安装
check_chinese_font() {
    if command -v fc-list &>/dev/null; then
        if fc-list :lang=zh | grep -q -E "WenQuanYi|Microsoft|Droid|Noto|文泉驿|宋体"; then
            echo "检测到已安装中文字体"
            return 0
        else
            echo "未检测到中文字体"
            return 1
        fi
    else
        echo "字体工具未安装，开始安装fontconfig..."
        install_font_tools
        return 1
    fi
}

# 安装字体工具
install_font_tools() {
    if [[ -f /etc/alpine-release ]]; then
        apk add fontconfig mkfontscale --no-cache
    elif command -v apt &>/dev/null; then
        apt update && apt install -y fontconfig
    elif command -v yum &>/dev/null; then
        yum install -y fontconfig mkfontscale
    fi
}

# 安装中文字体包
install_chinese_font() {
    echo "开始安装中文字体..."
    
    if [[ -f /etc/alpine-release ]]; then
        apk add font-droid-nonlatin --no-cache
        FONT_DIR="/usr/share/fonts/droid-nonlatin"
    elif command -v apt &>/dev/null; then
        apt install -y fonts-wqy-zenhei fonts-wqy-microhei xfonts-wqy
        FONT_DIR="/usr/share/fonts/truetype/wqy"
    elif command -v yum &>/dev/null; then
        yum install -y wqy* fontconfig
        FONT_DIR="/usr/share/fonts/wqy-zenhei"
    fi

    # 更新字体缓存
    fc-cache -fv &>/dev/null
}

# 配置字体环境
configure_font() {
    # 设置系统语言环境
    export LANG="zh_CN.UTF-8"
    
    # 生成字体索引（针对自定义字体目录）
    if [[ -n $FONT_DIR ]]; then
        mkfontscale "$FONT_DIR"
        mkfontdir "$FONT_DIR"
    fi
    
    # Alpine系统特殊处理
    if [[ -f /etc/alpine-release ]]; then
        apk add --no-cache ttf-freefont ttf-droid
        /usr/glibc-compat/bin/localedef -i zh_CN -f UTF-8 zh_CN.UTF-8
    fi
}

# 主执行流程
main() {
    if check_chinese_font; then
        echo "✅ 系统已安装中文字体"
    else
        install_chinese_font
        configure_font
    fi

    # 验证字体显示
    echo "正在验证字体显示..."
    echo -e "\e[1;32m我有一只美羊羊\e[0m"
    
    # 最终检查
    if fc-list :lang=zh | grep -q "Droid Sans Fallback"; then
        echo "✅ 中文字体配置完成"
    else
        echo "❌ 配置失败，请手动检查"
        exit 1
    fi
}

# 执行主函数
main
