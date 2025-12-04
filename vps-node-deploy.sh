#!/bin/bash
# 节点部署合集脚本

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
LINE_COLOR='\033[0;36m' # 分割线颜色
PURPLE='\033[0;35m' # 紫色

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此脚本需要root权限运行${NC}"
        exit 1
    fi
}

# 检查命令是否存在
check_command() {
    command -v "$1" &>/dev/null
}

# 安装命令
install_command() {
    local cmd=$1
    local pkg_name=${2:-$cmd}
    
    echo -e "${YELLOW}正在安装 $cmd...${NC}"
    
    if check_command apt; then
        apt update -y >/dev/null 2>&1
        apt install -y "$pkg_name" >/dev/null 2>&1
    elif check_command yum; then
        yum install -y "$pkg_name" >/dev/null 2>&1
    elif check_command dnf; then
        dnf install -y "$pkg_name" >/dev/null 2>&1
    elif check_command apk; then
        apk add "$pkg_name" >/dev/null 2>&1
    elif check_command pacman; then
        pacman -Syu --noconfirm "$pkg_name" >/dev/null 2>&1
    else
        return 1
    fi
}

# 初始安装 curl 和 wget
install_download_tools() {
    echo -e "${YELLOW}检查必要依赖...${NC}"
    
    # 检查 curl
    if ! check_command curl; then
        echo -e "${YELLOW}curl 未安装，正在安装...${NC}"
        install_command "curl"
        if ! check_command curl; then
            echo -e "${RED}curl 安装失败${NC}"
        else
            echo -e "${GREEN}curl 安装成功${NC}"
        fi
    else
        echo -e "${GREEN}curl 已安装${NC}"
    fi
    
    # 检查 wget
    if ! check_command wget; then
        echo -e "${YELLOW}wget 未安装，正在安装...${NC}"
        install_command "wget"
        if ! check_command wget; then
            echo -e "${RED}wget 安装失败${NC}"
        else
            echo -e "${GREEN}wget 安装成功${NC}"
        fi
    else
        echo -e "${GREEN}wget 已安装${NC}"
    fi
    
    echo ""
}

# 获取随机端口 (1024-65535)
get_random_port() {
    echo $((RANDOM % 64511 + 1024))
}

# 显示菜单
show_menu() {
    clear
    echo -e "${LINE_COLOR}========================================${NC}"
    echo -e "${YELLOW}          节点部署合集脚本${NC}"
    echo -e "${YELLOW}支持Ubuntu/Debian/CentOS/Alpine/Fedora${NC}"
    echo -e "${LINE_COLOR}========================================${NC}"
    echo ""
    echo -e "${PURPLE}====== Sing-box 多合一 ======${NC}"
    echo -e "${YELLOW}1. F佬Sing-box一键脚本${NC}"
    echo -e "${YELLOW}2. 老王Sing-box四合一${NC}"
    echo -e "${YELLOW}3. 勇哥Sing-box四合一${NC}"
    echo -e "${YELLOW}4. 233boy.sing-box一键脚本${NC}"
    echo ""
    echo -e "${PURPLE}========= Argo隧道 ==========${NC}"
    echo -e "${YELLOW}5. 老王Xray-2go一键脚本${NC}"
    echo -e "${YELLOW}6. F佬ArgoX一键脚本${NC}"
    echo -e "${YELLOW}7. Suoha一键Argo脚本${NC}"
    echo ""
    echo -e "${PURPLE}========= 单协议节点 =========${NC}"
    echo -e "${YELLOW}8. Hysteria2一键脚本${NC}"
    echo -e "${YELLOW}9. Juicity一键脚本${NC}"
    echo -e "${YELLOW}10. Tuic-v5一键脚本${NC}"
    echo -e "${YELLOW}11. Snell一键安装${NC}"
    echo -e "${YELLOW}12. Reality一键脚本${NC}"
    echo ""
    echo -e "${PURPLE}========== 面板工具 ==========${NC}"
    echo -e "${YELLOW}13. 新版X-UI面板${NC}"
    echo -e "${YELLOW}14. 伊朗版3X-UI面板${NC}"
    echo -e "${YELLOW}15. Sui面板(Sing-box面板)${NC}"
    echo ""
    echo -e "${PURPLE}========== 系统工具 ==========${NC}"
    echo -e "${GREEN}16. 系统清理 (清理垃圾文件)${NC}"
    echo -e "${RED}17. 一键DD (重装系统)${NC}"
    echo ""
    echo -e "${PURPLE}========== 其他代理 ==========${NC}"
    echo -e "${YELLOW}18. OpenVPN一键安装${NC}"
    echo -e "${YELLOW}19. Telegram代理(MTProto)${NC}"
    echo ""
    
    echo -e "${LINE_COLOR}========================================${NC}"
    echo -e "${RED}0. 退出脚本${NC}"
    echo -e "${LINE_COLOR}========================================${NC}"
}

# 系统清理功能
system_clean() {
    echo -e "${YELLOW}正在执行系统清理...${NC}"
    echo -e "${YELLOW}警告: 此操作将清理系统垃圾文件和日志，建议先备份重要数据！${NC}"
    echo ""
    
    # 确认执行
    read -p "是否继续? [y/N]: " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}已取消清理操作${NC}"
        return
    fi
    
    echo -e "${YELLOW}1. 清理APT/YUM/DNF缓存...${NC}"
    if check_command apt; then
        apt clean
        apt autoclean
        apt autoremove -y
    elif check_command yum; then
        yum clean all
        yum autoremove -y
    elif check_command dnf; then
        dnf clean all
        dnf autoremove -y
    fi
    
    echo -e "${YELLOW}2. 清理系统日志文件 (保留最近7天)...${NC}"
    find /var/log -name "*.log" -type f -mtime +7 -delete 2>/dev/null || true
    find /var/log -name "*.gz" -type f -delete 2>/dev/null || true
    journalctl --vacuum-time=7d 2>/dev/null || true
    
    echo -e "${YELLOW}3. 清理临时文件...${NC}"
    rm -rf /tmp/* 2>/dev/null || true
    rm -rf /var/tmp/* 2>/dev/null || true
    
    echo -e "${YELLOW}4. 清理Docker相关垃圾 (如果已安装)...${NC}"
    if check_command docker; then
        docker system prune -f 2>/dev/null || true
    fi
    
    echo -e "${YELLOW}5. 清理旧的Linux内核 (仅Debian/Ubuntu)...${NC}"
    if check_command apt; then
        apt autoremove --purge -y 2>/dev/null || true
    fi
    
    echo -e "${GREEN}系统清理完成！${NC}"
    
    # 显示清理结果
    echo ""
    echo -e "${YELLOW}当前磁盘使用情况:${NC}"
    df -h /
}

# 一键DD功能 - 使用指定的bin456789/reinstall脚本
system_dd() {
    echo -e "${RED}⚠️ ⚠️ ⚠️  警告: 一键DD将重新安装系统，会删除所有数据！⚠️ ⚠️ ⚠️${NC}"
    echo -e "${RED}请确保已备份所有重要数据！${NC}"
    echo -e "${RED}此操作不可逆，VPS上的所有数据将被永久删除！${NC}"
    echo ""
    
    # 确认执行
    read -p "是否继续? [输入'yes'确认，其他任意键取消]: " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo -e "${YELLOW}已取消DD操作${NC}"
        return
    fi
    
    echo -e "${YELLOW}正在下载bin456789/reinstall一键重装脚本...${NC}"
    echo -e "${YELLOW}脚本地址: https://github.com/bin456789/reinstall${NC}"
    echo ""
    
    # 执行指定的DD脚本
    if curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh || wget -O reinstall.sh https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh; then
        chmod +x reinstall.sh
        echo -e "${GREEN}脚本下载成功！${NC}"
        echo ""
        echo -e "${YELLOW}使用方法:${NC}"
        echo -e "  1. 直接运行: ${GREEN}./reinstall.sh${NC}"
        echo -e "  2. 查看帮助: ${GREEN}./reinstall.sh -h${NC}"
        echo -e "  3. 快速安装Debian 12: ${GREEN}./reinstall.sh debian 12${NC}"
        echo -e "  4. 快速安装alpine 3.22: ${GREEN}./reinstall.sh alpine 3.22${NC}"
        echo -e "  5. 快速安装Ubuntu 22.04: ${GREEN}./reinstall.sh ubuntu 22.04${NC}"
        echo ""
        echo -e "${YELLOW}正在启动DD脚本...${NC}"
        bash reinstall.sh
    else
        echo -e "${RED}脚本下载失败，请检查网络连接！${NC}"
    fi
}

# 执行选择
execute_choice() {
    local choice=$1
    
    case $choice in
        1)
            echo -e "${YELLOW}执行F佬Sing-box一键脚本...${NC}"
            bash <(curl -Ls https://raw.githubusercontent.com/fscarmen/sing-box/main/sing-box.sh)
            ;;
        2)
            echo -e "${YELLOW}执行老王Sing-box四合一脚本...${NC}"
            bash <(curl -Ls https://raw.githubusercontent.com/eooce/sing-box/main/sing-box.sh)
            ;;
        3)
            echo -e "${YELLOW}执行勇哥Sing-box四合一脚本...${NC}"
            bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh)
            ;;
        4)
            echo -e "${YELLOW}执行233boy.sing-box一键脚本...${NC}"
            bash <(wget -qO- -o- https://github.com/233boy/sing-box/raw/main/install.sh)
            ;;
        5)
            echo -e "${YELLOW}执行老王Xray-2go一键脚本...${NC}"
            bash <(curl -Ls https://github.com/eooce/xray-2go/raw/main/xray_2go.sh)
            ;;
        6)
            echo -e "${YELLOW}执行F佬ArgoX一键脚本...${NC}"
            bash <(wget -qO- https://raw.githubusercontent.com/fscarmen/argox/main/argox.sh)
            ;;
        7)
            echo -e "${YELLOW}执行Suoha一键Argo脚本...${NC}"
            bash <(curl -Ls https://www.baipiao.eu.org/suoha.sh)
            ;;
        8)
            echo -e "${YELLOW}执行Hysteria2一键脚本...${NC}"
            echo ""
            echo -e "${YELLOW}请输入端口号(直接回车使用随机端口): ${NC}\c"
            read port
            
            if [[ -z "$port" ]]; then
                port=$(get_random_port)
                echo -e "${YELLOW}使用随机端口: $port${NC}"
            fi
            
            if [ -f "/etc/alpine-release" ]; then
                SERVER_PORT=$port bash -c "$(curl -L https://raw.githubusercontent.com/eooce/scripts/master/containers-shell/hy2.sh)"
            else
                HY2_PORT=$port bash -c "$(curl -L https://raw.githubusercontent.com/eooce/scripts/master/Hysteria2.sh)"
            fi
            ;;
        9)
            echo -e "${YELLOW}执行Juicity一键脚本...${NC}"
            bash <(curl -Ls https://raw.githubusercontent.com/eooce/scripts/master/juicity.sh)
            ;;
        10)
            echo -e "${YELLOW}执行Tuic-v5一键脚本...${NC}"
            bash -c "$(curl -L https://raw.githubusercontent.com/eooce/scripts/master/tuic.sh)"
            ;;
        11)
            echo -e "${YELLOW}执行Snell一键安装...${NC}"
            wget -O snell.sh --no-check-certificate https://git.io/Snell.sh
            chmod +x snell.sh
            ./snell.sh
            ;;
        12)
            echo -e "${YELLOW}执行Reality一键脚本...${NC}"
            echo ""
            echo -e "${YELLOW}请输入端口号(直接回车使用随机端口): ${NC}\c"
            read port
            
            if [[ -z "$port" ]]; then
                port=$(get_random_port)
                echo -e "${YELLOW}使用随机端口: $port${NC}"
            fi
            
            if [ -f "/etc/alpine-release" ]; then
                PORT=$port bash -c "$(curl -L https://raw.githubusercontent.com/eooce/scripts/master/test.sh)"
            else
                PORT=$port bash -c "$(curl -L https://raw.githubusercontent.com/eooce/xray-reality/master/reality.sh)"
            fi
            ;;
        13)
            echo -e "${YELLOW}执行新版X-UI面板安装...${NC}"
            bash <(curl -Ls https://raw.githubusercontent.com/slobys/x-ui/main/install.sh)
            ;;
        14)
            echo -e "${YELLOW}执行伊朗版3X-UI面板安装...${NC}"
            bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh)
            ;;
        15)
            echo -e "${YELLOW}执行Sui面板安装...${NC}"
            bash <(curl -Ls https://raw.githubusercontent.com/Misaka-blog/s-ui/master/install.sh)
            ;;
        16)
            system_clean
            ;;
        17)
            system_dd
            ;;
        18)
            echo -e "${YELLOW}执行OpenVPN一键安装...${NC}"
            wget https://git.io/vpn -O openvpn-install.sh
            chmod +x openvpn-install.sh
            bash openvpn-install.sh
            ;;
        19)
            echo -e "${YELLOW}执行Telegram代理(MTProto)安装...${NC}"
            echo ""
            echo -e "${YELLOW}请输入端口号(直接回车使用随机端口): ${NC}\c"
            read port
            
            if [[ -z "$port" ]]; then
                port=$(get_random_port)
                echo -e "${YELLOW}使用随机端口: $port${NC}"
            fi
            
            PORT=$port bash <(curl -Ls https://raw.githubusercontent.com/eooce/scripts/master/mtp.sh)
            ;;
        0)
            echo -e "${GREEN}退出脚本${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选择，请重新输入${NC}"
            sleep 2
            return 1
            ;;
    esac
    
    return 0
}

# 主函数
main() {
    check_root
    
    # 安装必要依赖
    install_download_tools
    
    # 检查是否至少有一个下载工具
    if ! check_command curl && ! check_command wget; then
        echo -e "${RED}错误: 无法安装 curl 或 wget，请手动安装后再运行本脚本${NC}"
        exit 1
    fi
    
    # 主循环
    while true; do
        show_menu
        echo -e "${YELLOW}请输入你的选择 [0-19]: ${NC}\c"
        read choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if [[ $choice -ge 0 && $choice -le 19 ]]; then
                execute_choice $choice
                if [ $? -eq 0 ]; then
                    echo ""
                    echo -e "${YELLOW}按任意键返回菜单...${NC}"
                    read -n 1 -s
                fi
            else
                echo -e "${RED}请输入 0-19 之间的数字${NC}"
                sleep 2
            fi
        else
            echo -e "${RED}请输入数字${NC}"
            sleep 2
        fi
    done
}

# 运行主函数
main
