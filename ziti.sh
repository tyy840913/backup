#!/bin/bash

# 检查系统是否是中文环境
check_chinese_locale() {
    if [[ "$LANG" == *"zh_CN"* ]]; then
        echo "系统当前已经是中文环境。"
        return 0
    else
        echo "系统当前不是中文环境。"
        return 1
    fi
}

# 检查系统中文环境配置是否正常
check_chinese_locale_config() {
    if locale -a | grep -i "zh_CN" > /dev/null; then
        echo "系统已安装中文语言包。"
        return 0
    else
        echo "系统未安装中文语言包。"
        return 1
    fi
}

# 配置系统中文环境
configure_chinese_locale() {
    echo "正在配置系统中文环境..."

    # 检查系统发行版
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case $ID in
            alpine)
                echo "检测到 Alpine 系统。"
                apk add --no-cache langpacks-zh_CN
                echo "LANG=zh_CN.UTF-8" > /etc/profile.d/locale.sh
                ;;
            debian|ubuntu)
                echo "检测到 Debian/Ubuntu 系统。"
                apt-get update
                apt-get install -y language-pack-zh-hans
                update-locale LANG=zh_CN.UTF-8
                ;;
            centos|rhel)
                echo "检测到 CentOS/RHEL 系统。"
                yum install -y glibc-langpack-zh
                localectl set-locale LANG=zh_CN.UTF-8
                ;;
            fedora)
                echo "检测到 Fedora 系统。"
                dnf install -y glibc-langpack-zh
                localectl set-locale LANG=zh_CN.UTF-8
                ;;
            *)
                echo "不支持的发行版: $ID"
                exit 1
                ;;
        esac
    else
        echo "无法检测系统发行版。"
        exit 1
    fi

    echo "中文环境配置完成。"
}

# 主函数
main() {
    if check_chinese_locale; then
        if check_chinese_locale_config; then
            echo "系统中文环境配置正常。"
        else
            echo "系统中文环境配置不正常，正在重新配置..."
            configure_chinese_locale
        fi
    else
        if check_chinese_locale_config; then
            echo "系统已安装中文语言包，正在配置中文环境..."
            configure_chinese_locale
        else
            echo "系统未安装中文语言包，正在下载并配置中文环境..."
            configure_chinese_locale
        fi
    fi

    echo "所有操作已完成。"
}

# 执行主函数
main
