#!/bin/bash
# 支持中文显示的通用安装脚本（适用Alpine/Debian/Ubuntu/CentOS）
# 需要以root权限运行

# 定义颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # 恢复默认

# 检测发行版类型
if [ -f /etc/alpine-release ]; then
    DISTRO="alpine"
elif [ -f /etc/debian_version ]; then
    DISTRO="debian"
elif [ -f /etc/redhat-release ]; then
    DISTRO="redhat"
else
    echo -e "${RED}不支持的发行版${NC}"
    exit 1
fi

# 安装基础依赖
install_zh() {
    case $DISTRO in
        "alpine")
            echo -e "${GREEN}配置Alpine系统中文支持...${NC}"
            apk update
            
            # 安装glibc兼容层（关键步骤）
            GLIBC_VER="2.34-r0"
            GLIBC_PKGS=(
                "glibc-${GLIBC_VER}.apk"
                "glibc-bin-${GLIBC_VER}.apk"
                "glibc-i18n-${GLIBC_VER}.apk"
            )
            
            # 下载公钥和软件包（使用国内镜像）
            curl -sSL -o /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub
            for pkg in "${GLIBC_PKGS[@]}"; do
                curl -sSL -O "https://add.woskee.nyc.mn/github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VER}/${pkg}"
                apk add --force-overwrite "./${pkg}"
                rm -f "./${pkg}"
            done
            
            # 生成中文locale
            /usr/glibc-compat/bin/localedef -i zh_CN -f UTF-8 zh_CN.UTF-8
            echo 'export LANG=zh_CN.UTF-8' >> /etc/profile.d/lang.sh
            source /etc/profile.d/lang.sh
            
            # 安装中文字体
            apk add font-noto-cjk ttf-dejavu
            ;;
            
        "debian")
            echo -e "${GREEN}配置Debian/Ubuntu中文支持...${NC}"
            apt update
            apt install -y locales language-pack-zh-hans fonts-noto-cjk
            sed -i '/zh_CN.UTF-8/s/^# //g' /etc/locale.gen
            locale-gen
            echo 'LANG=zh_CN.UTF-8' > /etc/default/locale
            ;;
            
        "redhat")
            echo -e "${GREEN}配置CentOS/RHEL中文支持...${NC}"
            yum install -y glibc-langpack-zh google-noto-cjk-fonts
            localedef -c -f UTF-8 -i zh_CN zh_CN.utf8
            echo 'LANG=zh_CN.UTF-8' > /etc/locale.conf
            ;;
    esac
    
    # 通用配置
    echo -e "${GREEN}更新字体缓存...${NC}"
    fc-cache -fv
}

# 执行安装
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}请使用root权限运行此脚本！${NC}"
    exit 1
else
    install_zh
    echo -e "${GREEN}安装完成！请执行以下操作：${NC}"
    echo "1. 重启终端会话"
    echo "2. 测试中文显示：echo -e '\xe4\xbd\xa0\xe5\xa5\xbd' 应显示'你好'"
    echo "3. 如需永久生效，请重启系统"
fi
