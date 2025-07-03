#!/bin/bash

# 脚本名称: setup_chinese_env.sh
# 描述: 检查并安装中文字体 (fonts-wqy-zenhei) 并配置系统 locale 为 zh_CN.UTF-8。
# 用法: 以root权限运行此脚本。

# 检查是否以root用户运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误: 此脚本需要root权限才能运行。请使用 'sudo' 执行。"
    exit 1
fi

Auto_set_fonts() {
    echo "--- 开始配置中文字体和中文环境 ---"

    local FONT_PKG="fonts-wqy-zenhei"

    # 检查字体包是否已安装
    echo "  - 检查字体包: $FONT_PKG"
    if dpkg -s "$FONT_PKG" &>/dev/null; then
        echo "  - ✅ 字体包 ($FONT_PKG) 已安装。"
    else
        echo "  - 准备安装字体包: $FONT_PKG"
        # 简化输出，重定向 apt 的冗余信息
        if apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq "$FONT_PKG" >/dev/null 2>&1; then
            echo "  - ✅ 字体包安装成功。"
        else
            echo "  - ⚠️ 字体安装失败，可能影响中文显示。请尝试手动执行 'sudo apt-get install -y $FONT_PKG'"
        fi
    fi

    local OS=""
    if grep -qi 'ubuntu' /etc/os-release; then OS="ubuntu"; fi
    if grep -qi 'debian' /etc/os-release; then OS="debian"; fi

    echo "  - 检测操作系统类型: $OS"
    if [ -z "$OS" ]; then
        echo "  - ⚠️ 无法识别的操作系统类型，可能影响中文环境配置。"
    fi
    
    # 检查 locale 是否已配置为 zh_CN.UTF-8
    echo "  - 检查中文环境 (zh_CN.UTF-8) 配置..."
    if grep -q "LANG=zh_CN.UTF-8" /etc/default/locale 2>/dev/null; then
        echo "  - ✅ 中文环境 (zh_CN.UTF-8) 已配置。"
    else
        echo "  - 正在配置中文环境..."
        if [[ "$OS" == "ubuntu" ]]; then
            echo "    - 尝试安装 Ubuntu 中文语言包..."
            if apt-get install -y -qq language-pack-zh-hans >/dev/null 2>&1; then
                echo "    - ✅ Ubuntu 中文语言包安装成功。"
            else
                echo "    - ⚠️ Ubuntu 中文语言包安装失败，请手动检查网络或源。"
            fi
        elif [[ "$OS" == "debian" ]]; then
            echo "    - 尝试安装 locales 包 (Debian)..."
            if apt-get install -y -qq locales >/dev/null 2>&1; then
                echo "    - ✅ locales 包安装成功。"
                # 取消注释 zh_CN.UTF-8
                echo "    - 取消注释 /etc/locale.gen 中的 zh_CN.UTF-8..."
                if sed -i '/^# *zh_CN.UTF-8 UTF-8/s/^# *//' /etc/locale.gen; then
                    echo "    - ✅ zh_CN.UTF-8 已在 /etc/locale.gen 中启用。"
                else
                    echo "    - ⚠️ 无法修改 /etc/locale.gen，请手动检查文件权限或内容。"
                fi

                echo "    - 正在生成 locale..."
                if locale-gen >/dev/null 2>&1; then
                    echo "    - ✅ locale 生成成功。"
                else
                    echo "    - ⚠️ 执行 locale-gen 失败，请手动执行 'sudo locale-gen'。"
                fi
            else
                echo "    - ⚠️ Debian 安装 locales 包失败，请手动检查网络或源。"
            fi
        fi

        # 仅在 /etc/default/locale 中不存在时才添加
        echo "    - 正在更新 /etc/default/locale..."
        if ! grep -q "LANG=zh_CN.UTF-8" /etc/default/locale; then
            echo 'LANG=zh_CN.UTF-8' >> /etc/default/locale
            echo "    - ✅ LANG=zh_CN.UTF-8 已添加到 /etc/default/locale。"
        else
            echo "    - ⚠️ LANG=zh_CN.UTF-8 已存在于 /etc/default/locale，跳过添加。"
        fi
        
        # 立即设置环境变量，以便当前会话生效
        export LANG=zh_CN.UTF-8
        echo "  - ✅ 中文环境设置成功。部分更改可能需要您**重新登录或重启**系统才能完全生效。"
    fi

    echo "  - 刷新字体缓存..."
    if fc-cache -fv > /dev/null 2>&1; then
        echo "  - ✅ 字体缓存刷新完成。"
    else
        echo "  - ⚠️ 字体缓存刷新失败，请尝试手动执行 'fc-cache -fv'。"
    fi
    echo "-------------------------------------"
    echo "脚本执行完毕。"
}

# 调用主函数
Auto_set_fonts
