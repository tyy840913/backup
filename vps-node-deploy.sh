#!/bin/bash
# 节点部署合集脚本

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
LINE_COLOR='\033[0;36m' # 分割线颜色
PURPLE='\033[0;35m' # 紫色
CYAN='\033[0;36m' # 青色

# --- 核心系统数据库 (2025年12月更新) ---
declare -a DD_SYSTEM_DB=(
    # --- KVM/完整系统部分 ---
    "Debian 13 (trixie)|kvm|debian 13"         # 注意：需要核实reinstall.sh是否支持debian 13参数
    "Debian 12 (bookworm)|kvm|debian 12"
    "Debian 11 (bullseye)|kvm|debian 11"
    "Debian 10 (buster)|kvm|debian 10"
    "Ubuntu 24.04 LTS (Noble Numbat)|kvm|ubuntu 24.04"
    "Ubuntu 22.04 LTS (Jammy Jellyfish)|kvm|ubuntu 22.04"
    "Ubuntu 20.04 LTS (Focal Fossa)|kvm|ubuntu 20.04"
    "CentOS Stream 10|kvm|centos 10"           # 注意：需要核实reinstall.sh是否支持centos 10参数
    "CentOS Stream 9|kvm|centos 9"
    "CentOS Stream 8|kvm|centos 8"
    "Rocky Linux 9|kvm|rocky 9"
    "Rocky Linux 8|kvm|rocky 8"
    "AlmaLinux 9|kvm|alma 9"
    "AlmaLinux 8|kvm|alma 8"
    "Fedora 41|kvm|fedora 41"
    "Fedora 40|kvm|fedora 40"
    "Fedora 39|kvm|fedora 39"
    "Alpine Linux 3.23|kvm|alpine 3.23"        # 注意：需要核实reinstall.sh是否支持alpine 3.23参数
    "Alpine Linux 3.22|kvm|alpine 3.22"
    "Alpine Linux 3.21|kvm|alpine 3.21"
    "Alpine Linux 3.20|kvm|alpine 3.20"
    "Arch Linux|kvm|arch"
    "OpenSUSE Tumbleweed|kvm|opensuse-tumbleweed"
    # 注意：已移除所有LXC容器相关条目
)

# --- 基础工具函数 ---
check_root() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}错误: 此脚本需要root权限运行${NC}" && exit 1
}

check_command() { command -v "$1" &>/dev/null; }

install_command() {
    local cmd=$1 pkg_name=${2:-$cmd}
    echo -e "${YELLOW}正在安装 $cmd...${NC}"
    if check_command apt; then apt update -y >/dev/null 2>&1 && apt install -y "$pkg_name" >/dev/null 2>&1
    elif check_command yum; then yum install -y "$pkg_name" >/dev/null 2>&1
    elif check_command dnf; then dnf install -y "$pkg_name" >/dev/null 2>&1
    elif check_command apk; then apk add "$pkg_name" >/dev/null 2>&1
    elif check_command pacman; then pacman -Syu --noconfirm "$pkg_name" >/dev/null 2>&1
    else return 1; fi
}

install_download_tools() {
    echo -e "${YELLOW}检查必要依赖...${NC}"
    for tool in curl wget; do
        if ! check_command "$tool"; then
            echo -e "${YELLOW}$tool 未安装，正在安装...${NC}"
            install_command "$tool" && echo -e "${GREEN}$tool 安装成功${NC}" || echo -e "${RED}$tool 安装失败${NC}"
        else echo -e "${GREEN}$tool 已安装${NC}"; fi
    done
    echo ""
}

get_random_port() { echo $((RANDOM % 64511 + 1024)); }

# --- 虚拟化环境检测 ---
detect_virt_env() {
    local virt_type="unknown"
    if check_command systemd-detect-virt; then
        if systemd-detect-virt --container &>/dev/null; then
            virt_type=$(systemd-detect-virt --container 2>/dev/null)
            [[ "$virt_type" == "none" ]] && virt_type="unknown"
        elif systemd-detect-virt --vm &>/dev/null; then
            virt_type=$(systemd-detect-virt --vm 2>/dev/null)
        fi
    fi
    if [[ "$virt_type" == "unknown" ]]; then
        if [ -f /.dockerenv ]; then virt_type="docker"
        elif [ -f /proc/1/environ ] && grep -q "container=lxc" /proc/1/environ; then virt_type="lxc"
        elif [ -d /proc/vz ] && [ ! -d /proc/bc ]; then virt_type="openvz"
        elif grep -q "hypervisor" /proc/cpuinfo; then virt_type="kvm"; fi
    fi
    case "$virt_type" in
        qemu|xen|vmware|microsoft|oracle|bochs|uml|parallels|zvm) echo "kvm" ;;
        lxc|openvz|docker|systemd-nspawn|lxc-libvirt|rkt) echo "lxc" ;;
        *) echo "kvm" ;;
    esac
}

# --- 系统清理功能 ---
system_clean() {
    echo -e "${YELLOW}正在执行系统清理...${NC}"
    echo -e "${YELLOW}警告: 此操作将清理系统垃圾文件和日志，建议先备份重要数据！${NC}"
    echo "" && read -p "是否继续? [y/N]: " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && echo -e "${YELLOW}已取消清理操作${NC}" && return
    
    echo -e "${YELLOW}1. 清理APT/YUM/DNF缓存...${NC}"
    if check_command apt; then apt clean && apt autoclean && apt autoremove -y
    elif check_command yum; then yum clean all && yum autoremove -y
    elif check_command dnf; then dnf clean all && dnf autoremove -y; fi
    
    echo -e "${YELLOW}2. 清理系统日志文件 (保留最近7天)...${NC}"
    find /var/log -name "*.log" -type f -mtime +7 -delete 2>/dev/null || true
    find /var/log -name "*.gz" -type f -delete 2>/dev/null || true
    journalctl --vacuum-time=7d 2>/dev/null || true
    
    echo -e "${YELLOW}3. 清理临时文件...${NC}"
    rm -rf /tmp/* 2>/dev/null || true
    rm -rf /var/tmp/* 2>/dev/null || true
    
    echo -e "${YELLOW}4. 清理Docker相关垃圾 (如果已安装)...${NC}"
    check_command docker && docker system prune -f 2>/dev/null || true
    
    echo -e "${YELLOW}5. 清理旧的Linux内核 (仅Debian/Ubuntu)...${NC}"
    check_command apt && apt autoremove --purge -y 2>/dev/null || true
    
    echo -e "${GREEN}系统清理完成！${NC}\n" && df -h /
}

# --- DD系统重装核心模块 ---
system_dd() {
    echo -e "${RED}⚠️ ⚠️ ⚠️  警告: 一键DD将重新安装系统，会删除所有数据！⚠️ ⚠️ ⚠️${NC}"
    echo -e "${RED}请确保已备份所有重要数据！${NC}\n"
    read -p "是否继续? [输入'yes'确认]: " confirm
    [[ "$confirm" != "yes" ]] && echo -e "${YELLOW}已取消DD操作${NC}" && return
    
    local env_type=$(detect_virt_env)
    echo -e "${YELLOW}检测到当前环境: ${GREEN}${env_type}${NC}\n"
    
    # 检查是否支持DD操作（仅支持KVM/完整系统）
    if [[ "$env_type" != "kvm" ]]; then
        echo -e "${RED}❌ 不支持的环境类型❌${NC}"
        echo -e "${YELLOW}当前脚本仅支持 KVM/完整系统 环境下的DD重装${NC}"
        echo -e "${YELLOW}检测到您当前运行在 ${RED}${env_type}${YELLOW} 环境下${NC}"
        echo -e "${YELLOW}此环境不支持使用bin456789/reinstall脚本进行DD重装${NC}"
        return
    fi
    
    show_dd_menu "$env_type"
}

show_dd_menu() {
    local env_type=$1
    clear && echo -e "${LINE_COLOR}========================================${NC}"
    echo -e "${PURPLE}          KVM/完整系统 DD菜单${NC}"
    echo -e "${YELLOW}使用: bin456789/reinstall 脚本${NC}"
    echo -e "${LINE_COLOR}========================================${NC}\n"
    
    local script_file="reinstall.sh"
    local download_url="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"
    
    echo -e "${YELLOW}正在下载DD脚本...${NC}"
    if curl -O "$download_url" || wget -O "$script_file" "$download_url"; then
        chmod +x "$script_file" && echo -e "${GREEN}DD脚本下载成功！${NC}\n"
    else 
        echo -e "${RED}脚本下载失败，请检查网络连接！${NC}" 
        return
    fi
    
    # 计算系统数量
    local system_count=0
    for sys_info in "${DD_SYSTEM_DB[@]}"; do
        IFS='|' read -r display_name sys_type cmd_param <<< "$sys_info"
        [[ "$sys_type" == "$env_type" ]] && ((system_count++))
    done
    
    # 计算数字对齐的位数
    local total_options=$((system_count + 2))  # 系统选项 + 自定义 + 返回
    local max_digits=1
    [[ $total_options -ge 10 ]] && max_digits=2
    [[ $total_options -ge 100 ]] && max_digits=3
    
    # 显示菜单选项
    local option_num=1
    declare -a valid_options=() valid_display_names=()
    
    for sys_info in "${DD_SYSTEM_DB[@]}"; do
        IFS='|' read -r display_name sys_type cmd_param <<< "$sys_info"
        if [[ "$sys_type" == "$env_type" ]]; then
            printf "  \033[1;33m%${max_digits}d.\033[0m \033[1;33m%s\033[0m\n" "$option_num" "$display_name"
            valid_options+=("$cmd_param")
            valid_display_names+=("$display_name")
            ((option_num++))
        fi
    done
    
    local custom_num=$option_num
    local return_num=$((option_num + 1))
    
    # 使用同样的对齐方式显示自定义选项和返回选项
    printf "  \033[1;32m%${max_digits}d.\033[0m \033[1;32m%s\033[0m\n" "$custom_num" "自定义安装命令"
    printf "  \033[1;31m%${max_digits}d.\033[0m \033[1;31m%s\033[0m\n" "$return_num" "返回主菜单"
    
    echo -e "\n${LINE_COLOR}========================================${NC}"
    echo -e "${YELLOW}请输入你的选择 [1-${return_num}]: ${NC}\c" && read dd_choice

    # 处理空输入（直接按回车）
    if [[ -z "$dd_choice" ]]; then
        echo -e "${YELLOW}已取消选择，返回主菜单...${NC}"
        return
    fi

    if ! [[ "$dd_choice" =~ ^[0-9]+$ ]] || [ "$dd_choice" -lt 1 ] || [ "$dd_choice" -gt "$return_num" ]; then
        echo -e "${RED}无效选择${NC}" && sleep 1 && return
    fi

    if [ "$dd_choice" -eq "$return_num" ]; then
        echo -e "${YELLOW}返回主菜单...${NC}" && return
    elif [ "$dd_choice" -eq "$custom_num" ]; then
        echo -e "${YELLOW}自定义安装命令${NC}\n"
        echo -e "格式: ${GREEN}./reinstall.sh <系统> <版本> [参数]${NC}"
        echo -e "示例: ./reinstall.sh debian 12 --mirror aliyun"
        echo -e "更多参数请参考: ${CYAN}https://github.com/bin456789/reinstall${NC}"
        echo -e "${YELLOW}请输入完整的安装命令:${NC}" && read -e custom_cmd
        echo -e "${RED}开始执行DD安装，即将删除所有数据！${NC}" && sleep 3
        eval "./$script_file $custom_cmd"
    else
        local idx=$((dd_choice - 1))
        local cmd_param="${valid_options[$idx]}" name="${valid_display_names[$idx]}"
        echo -e "${YELLOW}正在安装 $name...${NC}"
        echo -e "${RED}开始执行DD安装，即将删除所有数据！${NC}" && sleep 3
        ./reinstall.sh $cmd_param
    fi
}

# --- 主菜单与执行函数 ---
show_menu() {
    clear && echo -e "${LINE_COLOR}========================================${NC}"
    echo -e "${YELLOW}               节点部署合集脚本${NC}"
    echo -e "${LINE_COLOR}========================================${NC}"
    
    local menu_groups=(
        "====== Sing-box 多合一 =====" "1|F佬Sing-box一键脚本" "2|老王Sing-box四合一" "3|勇哥Sing-box四合一" "4|233boy.sing-box一键脚本"
        "========= WARP 脚本 ========" "5|fscarmen WARP脚本" "6|P3TERX WARP脚本" "7|WARP-GO脚本" "8|MISAKA WARP脚本"
        "========= Argo隧道 =========" "9|老王Xray-2go一键脚本" "10|F佬ArgoX一键脚本" "11|Suoha一键Argo脚本"
        "========= 单协议节点 =======" "12|Hysteria2一键脚本" "13|Juicity一键脚本" "14|Tuic-v5一键脚本" "15|Snell一键安装" "16|Reality一键脚本" "17|ShadowTLS一键脚本"
        "========== 面板工具 ========" "18|新版X-UI面板" "19|伊朗版3X-UI面板" "20|Sui面板(Sing-box面板)"
        "========= 系统性能优化 ======" "21|BBR加速脚本" "GREEN|22|系统清理 (清理垃圾文件)" "RED|23|一键DD (重装系统)"
        "========== 监控与探针 =======" "24|哪吒监控面板+探针"
        "========== 网络与检测 =======" "25|DNS流媒体解锁脚本" "26|流媒体解锁检测工具" "27|证书自动续签脚本" "28|网络测速与Bench测试"
        "========== 开发环境 ========" "29|Docker全家桶安装" "30|Python环境配置" "31|Node.js环境部署"
        "========== 其他代理 ========" "32|OpenVPN一键安装" "33|Telegram代理(MTProto)"
    )
    
    for item in "${menu_groups[@]}"; do
        if [[ "$item" == *=* ]]; then
            # 处理分组标题行
            printf "  \033[0;35m%s\033[0m\n" "$item"
        elif [[ "$item" == *"|"* ]]; then
            # 处理带颜色标记的菜单项 (如 "GREEN|18|系统清理")
            IFS='|' read -r color_part number_part desc_part <<< "$item"
            if [[ "$color_part" =~ ^(GREEN|RED|YELLOW)$ ]]; then
                # 有颜色标记的格式: "颜色|数字|描述"
                color_code=""
                case "$color_part" in
                    "YELLOW") color_code="33" ;;
                    "GREEN") color_code="32" ;;
                    "RED") color_code="31" ;;
                esac
                printf "  \033[1;33m%2d.\033[0m \033[1;%sm%s\033[0m\n" "$number_part" "$color_code" "$desc_part"
            else
                # 普通菜单项格式: "数字|描述" (如 "1|F佬Sing-box一键脚本")
                printf "  \033[1;33m%2d.\033[0m \033[1;33m%s\033[0m\n" "$color_part" "$number_part"
            fi
        else
            # 处理普通数字格式 (这里应该不会执行，保留以防万一)
            printf "  \033[1;33m%s\033[0m\n" "$item"
        fi
    done
    
    echo -e "\n${LINE_COLOR}========================================${NC}"
    echo -e "${RED} 0. 退出脚本${NC}"
    echo -e "${LINE_COLOR}========================================${NC}"
}

execute_choice() {
    case $1 in
        1) echo -e "${YELLOW}执行F佬Sing-box一键脚本...${NC}"; bash <(curl -Ls https://raw.githubusercontent.com/fscarmen/sing-box/main/sing-box.sh) ;;
        2) echo -e "${YELLOW}执行老王Sing-box四合一脚本...${NC}"; bash <(curl -Ls https://raw.githubusercontent.com/eooce/sing-box/main/sing-box.sh) ;;
        3) echo -e "${YELLOW}执行勇哥Sing-box四合一脚本...${NC}"; bash <(curl -Ls https://raw.githubusercontent.com/yonggekkk/sing-box-yg/main/sb.sh) ;;
        4) echo -e "${YELLOW}执行233boy.sing-box一键脚本...${NC}"; bash <(wget -qO- -o- https://github.com/233boy/sing-box/raw/main/install.sh) ;;
        5) echo -e "${YELLOW}执行fscarmen WARP脚本...${NC}"; wget -N https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh && bash menu.sh ;;
        6) echo -e "${YELLOW}执行P3TERX WARP脚本...${NC}"; bash <(curl -fsSL git.io/warp.sh) menu ;;
        7) echo -e "${YELLOW}执行WARP-GO脚本...${NC}"; wget -N https://raw.githubusercontent.com/fscarmen/warp/main/warp-go.sh && bash warp-go.sh ;;
        8) echo -e "${YELLOW}执行MISAKA WARP脚本...${NC}"; wget -N https://gitlab.com/Misaka-blog/warp-script/-/raw/main/warp.sh && bash warp.sh ;;
        9) echo -e "${YELLOW}执行老王Xray-2go一键脚本...${NC}"; bash <(curl -Ls https://github.com/eooce/xray-2go/raw/main/xray_2go.sh) ;;
        10) echo -e "${YELLOW}执行F佬ArgoX一键脚本...${NC}"; bash <(wget -qO- https://raw.githubusercontent.com/fscarmen/argox/main/argox.sh) ;;
        11) echo -e "${YELLOW}执行Suoha一键Argo脚本...${NC}"; bash <(curl -Ls https://www.baipiao.eu.org/suoha.sh) ;;
        12) echo -e "${YELLOW}执行Hysteria2一键脚本...${NC}"; [ -f "/etc/alpine-release" ] && bash -c "$(curl -L https://raw.githubusercontent.com/eooce/scripts/master/containers-shell/hy2.sh)" || bash -c "$(curl -L https://raw.githubusercontent.com/eooce/scripts/master/Hysteria2.sh)" ;;
        13) echo -e "${YELLOW}执行Juicity一键脚本...${NC}"; bash <(curl -Ls https://raw.githubusercontent.com/eooce/scripts/master/juicity.sh) ;;
        14) echo -e "${YELLOW}执行Tuic-v5一键脚本...${NC}"; bash -c "$(curl -L https://raw.githubusercontent.com/eooce/scripts/master/tuic.sh)" ;;
        15) echo -e "${YELLOW}执行Snell一键安装...${NC}"; wget -O snell.sh --no-check-certificate https://git.io/Snell.sh && chmod +x snell.sh && ./snell.sh ;;
        16) echo -e "${YELLOW}执行Reality一键脚本...${NC}"; [ -f "/etc/alpine-release" ] && bash -c "$(curl -L https://raw.githubusercontent.com/eooce/scripts/master/test.sh)" || bash -c "$(curl -L https://raw.githubusercontent.com/eooce/xray-reality/master/reality.sh)" ;;
        17) echo -e "${YELLOW}执行ShadowTLS一键脚本...${NC}"; bash <(curl -Ls https://raw.githubusercontent.com/eooce/scripts/master/shadowtls.sh) ;;
        18) echo -e "${YELLOW}执行新版X-UI面板安装...${NC}"; bash <(curl -Ls https://raw.githubusercontent.com/slobys/x-ui/main/install.sh) ;;
        19) echo -e "${YELLOW}执行伊朗版3X-UI面板安装...${NC}"; bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) ;;
        20) echo -e "${YELLOW}执行Sui面板安装...${NC}"; bash <(curl -Ls https://raw.githubusercontent.com/Misaka-blog/s-ui/master/install.sh) ;;
        21) echo -e "${YELLOW}执行BBR加速脚本...${NC}"; bash <(curl -Lso- https://git.io/kernel.sh) ;;
        22) system_clean ;;
        23) system_dd ;;
        24) echo -e "${YELLOW}执行哪吒监控面板+探针...${NC}"; bash <(curl -Ls https://raw.githubusercontent.com/naiba/nezha/master/script/install.sh) ;;
        25) echo -e "${YELLOW}执行DNS流媒体解锁脚本...${NC}"; wget -N https://raw.githubusercontent.com/fscarmen/warp/main/warp.sh && chmod +x warp.sh && ./warp.sh menu ;;
        26) echo -e "${YELLOW}执行流媒体解锁检测工具...${NC}"; bash <(curl -L -s https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh) ;;
        27) echo -e "${YELLOW}执行证书自动续签脚本...${NC}"; curl https://get.acme.sh | sh ;;
        28) echo -e "${YELLOW}执行网络测速与Bench测试...${NC}"; wget -qO- bench.sh | bash ;;
        29) echo -e "${YELLOW}执行Docker全家桶安装...${NC}"; curl -fsSL https://get.docker.com | bash && curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && chmod +x /usr/local/bin/docker-compose ;;
        30) echo -e "${YELLOW}执行Python环境配置...${NC}"; bash <(curl -Ls https://raw.githubusercontent.com/eooce/scripts/master/python_setup.sh) ;;
        31) echo -e "${YELLOW}执行Node.js环境部署...${NC}"; bash <(curl -Ls https://raw.githubusercontent.com/eooce/scripts/master/nodejs_setup.sh) ;;
        32) echo -e "${YELLOW}执行OpenVPN一键安装...${NC}"; wget https://git.io/vpn -O openvpn-install.sh && chmod +x openvpn-install.sh && bash openvpn-install.sh ;;
        33) echo -e "${YELLOW}执行Telegram代理(MTProto)...${NC}"; bash <(curl -Ls https://raw.githubusercontent.com/eooce/scripts/master/mtp.sh) ;;
        0) echo -e "${GREEN}退出脚本${NC}"; exit 0 ;;
        *) echo -e "${RED}无效选择，请重新输入${NC}"; sleep 2; return 1 ;;
    esac
    return 0
}

# --- 主函数 ---
main() {
    check_root
    install_download_tools
    if ! check_command curl && ! check_command wget; then
        echo -e "${RED}错误: 无法安装 curl 或 wget，请手动安装后再运行本脚本${NC}"
        exit 1
    fi
    while true; do
        show_menu
        echo -e "${YELLOW}请输入你的选择 [0-30]: ${NC}\c" && read choice
        
        # 处理空输入（直接按回车）
        if [[ -z "$choice" ]]; then
            echo -e "${YELLOW}已取消选择，返回菜单...${NC}" && sleep 1
            continue
        fi
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 0 && $choice -le 33 ]]; then
            execute_choice $choice
            # 如果选择的是退出(0)，则直接退出，否则显示返回提示
            if [[ $choice -eq 0 ]]; then
                echo -e "${GREEN}退出脚本${NC}"
                exit 0
            else
                echo -e "\n${YELLOW}按任意键返回主菜单...${NC}" && read -n 1 -s
            fi
        else
            echo -e "${RED}请输入0-30之间的数字${NC}"; sleep 2
        fi
    done
}

main
