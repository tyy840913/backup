#!/bin/bash
# 增强版中文支持脚本（修复字体检测/循环目录/自动修复）
# 支持Alpine/Debian/Ubuntu/CentOS

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

detect_distro() {
    if [ -f /etc/alpine-release ]; then
        echo "alpine"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    elif [ -f /etc/redhat-release ]; then
        echo "redhat"
    else
        echo -e "${RED}不支持的发行版${NC}" >&2
        exit 1
    fi
}

check_chinese_font() {
    # 确保fontconfig可用
    if ! command -v fc-list &> /dev/null; then
        case $1 in
            alpine) apk add fontconfig ;;
            debian) apt install -y fontconfig ;;
            redhat) yum install -y fontconfig ;;
        esac
    fi

    # 检测字体存在性
    local font_installed=0
    if fc-list :lang=zh | grep -qiE "Noto|CJK|WenQuanYi"; then
        font_installed=1
    fi

    # 验证显示能力
    local test_str=$(echo -e '\xe4\xbd\xa0\xe5\xa5\xbd' 2>/dev/null)
    if [ "$test_str" = "你好" ]; then
        return 0
    else
        # 当字体存在但显示异常时特殊处理
        [ $font_installed -eq 1 ] && return 2 || return 1
    fi
}

install_zh() {
    case $1 in
        alpine)
            echo -e "${GREEN}[Alpine] 安装基础组件...${NC}"
            apk update
            
            GLIBC_VER="2.34-r0"
            GLIBC_PKGS=(
                "glibc-${GLIBC_VER}.apk"
                "glibc-bin-${GLIBC_VER}.apk"
                "glibc-i18n-${GLIBC_VER}.apk"
            )

            curl -sSL -o /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub
            for pkg in "${GLIBC_PKGS[@]}"; do
                curl -sSLO "https://add.woskee.nyc.mn/github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VER}/${pkg}"
                apk add --force-overwrite "./${pkg}"
                rm -f "./${pkg}"
            done

            echo -e "${GREEN}配置中文locale...${NC}"
            /usr/glibc-compat/bin/localedef -i zh_CN -f UTF-8 zh_CN.UTF-8
            echo 'export LANG=zh_CN.UTF-8' > /etc/profile.d/lang.sh
            source /etc/profile.d/lang.sh

            echo -e "${GREEN}安装中文字体...${NC}"
            apk add font-noto-cjk --no-cache
            ;;

        debian)
            echo -e "${GREEN}[Debian/Ubuntu] 安装中文支持...${NC}"
            apt update
            apt install -y locales language-pack-zh-hans fonts-noto-cjk
            sed -i '/zh_CN.UTF-8/s/^# //g' /etc/locale.gen
            locale-gen zh_CN.UTF-8
            echo 'LANG=zh_CN.UTF-8' > /etc/default/locale
            ;;

        redhat)
            echo -e "${GREEN}[CentOS/RHEL] 安装中文支持...${NC}"
            yum install -y glibc-langpack-zh google-noto-cjk-fonts
            localedef -c -f UTF-8 -i zh_CN zh_CN.utf8
            echo 'LANG=zh_CN.UTF-8' > /etc/locale.conf
            ;;
    esac

    echo -e "${GREEN}优化字体缓存...${NC}"
    find /usr/share/fonts -type d -exec touch {} \;  # 修复循环目录警告
    fc-cache -fv

    # 二次验证
    if ! check_chinese_font $1; then
        echo -e "${RED}检测到问题，尝试修复...${NC}"
        case $1 in
            alpine) apk fix font-noto-cjk ;;
            debian) apt install --reinstall -y fonts-noto-cjk ;;
            redhat) yum reinstall -y google-noto-cjk-fonts ;;
        esac
        fc-cache -fv
        check_chinese_font $1 || {
            echo -e "${RED}修复失败，请手动检查：${NC}"
            echo "1. 运行 fc-list :lang=zh 检查字体"
            echo "2. 检查 /etc/locale.conf 或 /etc/default/locale"
            echo "3. 尝试手动设置：export LANG=zh_CN.UTF-8"
            exit 1
        }
    fi
}

# 主流程
DISTRO=$(detect_distro)

if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}请使用root权限执行!${NC}" >&2
    exit 1
fi

install_zh $DISTRO

echo -e "\n${GREEN}验证通过! 请执行以下操作：${NC}"
echo "1. 新终端测试: echo -e '\xe4\xbd\xa0\xe5\xa5\xbd'"
echo "2. GUI程序需重启生效"
echo "3. 查看当前字体: fc-match sans-serif:lang=zh"
