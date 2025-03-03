#!/bin/ash
sleep_duration=0.3

echo "▌[1/8] 系统环境检测..." && sleep $sleep_duration
# 检测系统类型
if [ -f /etc/alpine-release ]; then
    DISTRO="alpine"
elif [ -f /etc/debian_version ]; then
    DISTRO="debian"
else
    echo "❌ 不支持的系统类型" >&2
    exit 1
fi

echo "▌[2/8] 语言环境检查..." && sleep $sleep_duration
if [ -z "$LANG" ]; then
    echo "⚠️ 未检测到语言环境设置"
    NEED_INSTALL=1
else
    echo "✅ 当前语言环境: $LANG"
    if echo "$LANG" | grep -q 'zh_CN'; then
        echo "✔ 中文环境已配置"
        exit 0
    else
        echo "⚠️ 当前为非中文环境"
        NEED_INSTALL=1
    fi
fi

if [ "$NEED_INSTALL" -eq 1 ]; then
    case $DISTRO in
        alpine)
            echo "▌[3/8] Alpine系统配置准备..." && sleep $sleep_duration
            GLIBC_PKGS=(
                "https://add.woskee.nyc.mn/github.com/sgerrand/alpine-pkg-glibc/releases/download/2.35-r0/glibc-2.35-r0.apk"
                "https://add.woskee.nyc.mn/github.com/sgerrand/alpine-pkg-glibc/releases/download/2.35-r0/glibc-bin-2.35-r0.apk"
                "https://add.woskee.nyc.mn/github.com/sgerrand/alpine-pkg-glibc/releases/download/2.35-r0/glibc-i18n-2.35-r0.apk"
            )
            
            echo "▌[4/8] 安装依赖组件..." && sleep $sleep_duration
            apk add --no-cache wget ca-certificates || {
                echo "❌ 基础依赖安装失败" >&2
                exit 2
            }

            echo "▌[5/8] 下载Glibc组件..." && sleep $sleep_duration
            mkdir -p /tmp/glibc-install
            for pkg in "${GLIBC_PKGS[@]}"; do
                wget -P /tmp/glibc-install "$pkg" || {
                    echo "❌ 组件下载失败: $pkg" >&2
                    exit 3
                }
            done

            echo "▌[6/8] 安装本地化包..." && sleep $sleep_duration
            apk add --allow-untrusted /tmp/glibc-install/*.apk || {
                echo "❌ Glibc安装失败" >&2
                exit 4
            }

            echo "▌[7/8] 生成中文环境..." && sleep $sleep_duration
            /usr/glibc-compat/bin/localedef -i zh_CN -f UTF-8 zh_CN.UTF-8 || {
                echo "❌ 本地化生成失败" >&2
                exit 5
            }
            ;;

        debian)
            echo "▌[3/8] Debian系统配置中..." && sleep $sleep_duration
            apt-get update && apt-get install -y locales language-pack-zh-hans || {
                echo "❌ 依赖安装失败" >&2
                exit 2
            }
            ;;
    esac

    echo "▌[8/8] 永久环境配置..." && sleep $sleep_duration
    echo "export LANG=zh_CN.UTF-8" > /etc/profile.d/lang.sh
    echo "export LANGUAGE=zh_CN:zh:en_US:en" >> /etc/profile.d/lang.sh
    source /etc/profile.d/lang.sh

    echo "✅ 配置完成，建议重启系统使设置完全生效"
    echo "🔄 当前临时环境测试:"
    locale -a | grep zh_CN
else
    echo "✅ 环境配置检查正常，无需修改"
fi
