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

# 完全卸载中文字体及配置
uninstall_chinese_font() {
    echo "⚠️ 开始卸载现有中文字体及配置..."
    
    # 通用字体文件清理
    find /usr/share/fonts/ \( -name "*.ttf" -o -name "*.ttc" \) \
        -exec echo "删除字体文件: {}" \; \
        -exec rm -f {} \;
    
    # 各发行版包管理器卸载
    if [[ -f /etc/alpine-release ]]; then
        apk del font-droid-nonlatin --no-cache 2>/dev/null
    elif command -v apt &>/dev/null; then
        apt purge -y fonts-wqy-* xfonts-wqy fonts-arphic-* 2>/dev/null
    elif command -v yum &>/dev/null; then
        yum remove -y wqy* fonts-chinese 2>/dev/null
    fi
    
    # 清理用户级字体 (参考)
    rm -rf ~/.local/share/fonts/*chinese* 
    rm -rf ~/.fonts/*chinese*
    
    # 恢复字体配置文件 (参考)
    sed -i '/chinese/d' /etc/fonts/fonts.conf 2>/dev/null
    sed -i '/自定义中文字体/d' /etc/fonts/fonts.conf 2>/dev/null
    
    # 重置语言环境 (参考)
    sed -i '/LANG=zh_CN/d' /etc/environment
    sed -i '/LANG=zh_CN/d' /etc/profile.d/locale.sh
    
    # 强制刷新缓存
    fc-cache -fv >/dev/null
    echo "✅ 字体卸载完成，缓存已重置"
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
        # 添加用户交互逻辑
        read -p "是否需要重新安装中文字体？(y/N)" reinstall
        if [[ $reinstall =~ [yY] ]]; then
            uninstall_chinese_font
            install_chinese_font
            configure_font
        fi
    else
        install_chinese_font
        configure_font
    fi
}

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
