#!/bin/bash

# PVE LXC容器创建脚本 
# 功能：交互式创建LXC容器，使用菜单选择而非手动输入

echo "=== PVE LXC容器创建脚本 ==="
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取容器ID（自动递增）
get_next_ctid() {
    local ctids=$(pct list | awk 'NR>1 {print $1}')
    local next_id=100
    for ctid in $ctids; do
        if [ $ctid -ge $next_id ]; then
            next_id=$((ctid + 1))
        fi
    done
    echo $next_id
}

# 自动获取网关IP
get_gateway() {
    local gateway=$(ip route | grep default | awk '{print $3}')
    if [ -z "$gateway" ]; then
        echo "无法自动获取网关IP，请手动输入："
        read -p "网关IP: " gateway
    fi
    echo "$gateway"
}

# 获取用户输入 - 容器名（验证：不能有空格）
read_container_name() {
    echo ""
    echo -e "${YELLOW}=== 基本配置 ===${NC}"
    read -p "请输入容器名: " container_name
    while true; do
        # 检查是否为空
        if [ -z "$container_name" ]; then
            echo -e "${RED}容器名不能为空${NC}"
            read -p "请输入容器名: " container_name
            continue
        fi
        # 检查是否包含空格
        if [[ "$container_name" =~ [[:space:]] ]]; then
            echo -e "${RED}容器名不能包含空格${NC}"
            read -p "请输入容器名: " container_name
            continue
        fi
        break
    done
}

# 获取用户输入 - 密码
read_password() {
    while true; do
        read -s -p "请输入root密码: " password
        echo ""
        if [ ${#password} -lt 6 ]; then
            echo -e "${RED}密码长度至少为6位${NC}"
            continue
        fi
        
        read -s -p "确认密码: " password_confirm
        echo ""
        
        if [ "$password" = "$password_confirm" ]; then
            break
        else
            echo -e "${RED}两次密码输入不一致${NC}"
        fi
    done
}

# 选择模板
select_template() {
    echo ""
    echo -e "${YELLOW}=== 模板选择 ===${NC}"
    
    local templates=()
    while IFS= read -r line; do
        # 提取模板路径（只取第一列，去掉大小信息）
        local template_path=$(echo "$line" | awk '{print $1}')
        if [[ $template_path =~ local:vztmpl/(.+) ]]; then
            templates+=("${BASH_REMATCH[1]}")
        fi
    done < <(pveam list local 2>/dev/null)
    
    if [ ${#templates[@]} -eq 0 ]; then
        echo -e "${RED}错误：未找到已下载的模板${NC}"
        exit 1
    fi
    
    PS3="请选择模板编号: "
    select template in "${templates[@]}"; do
        if [ -n "$template" ]; then
            template="local:vztmpl/$template"
            break
        else
            echo -e "${RED}无效选择${NC}"
        fi
    done
}

# 选择网络配置
select_network() {
    echo ""
    echo -e "${YELLOW}=== 网络配置 ===${NC}"
    
    # 自动获取网关
    gateway=$(get_gateway)
    echo -e "${GREEN}自动检测到网关IP: $gateway${NC}"
    
    read -p "请输入IP地址最后一段 (1-254): " ip_last_octet
    while [[ ! $ip_last_octet =~ ^[0-9]+$ ]] || [ $ip_last_octet -lt 1 ] || [ $ip_last_octet -gt 254 ]; do
        echo -e "${RED}请输入1-254之间的数字${NC}"
        read -p "请输入IP地址最后一段 (1-254): " ip_last_octet
    done
    
    echo "完整IP地址: 192.168.1.$ip_last_octet"
}

# 选择资源配置
select_resources() {
    echo ""
    echo -e "${YELLOW}=== 资源配置 ===${NC}"
    
    # CPU核心选择（竖排显示）- 放在最前面，2的倍数
    echo "请选择CPU核心数："
    echo "1) 2 核"
    echo "2) 4 核"
    echo "3) 6 核"
    echo "4) 8 核"
    echo "5) 自定义"
    PS3="请输入选项: "
    while true; do
        read -p "$PS3" cpu_choice
        case $cpu_choice in
            1) cores=2; break ;;
            2) cores=4; break ;;
            3) cores=6; break ;;
            4) cores=8; break ;;
            5)
                read -p "请输入CPU核心数: " cores
                while [[ ! $cores =~ ^[0-9]+$ ]] || [ $cores -lt 1 ]; do
                    echo -e "${RED}请输入有效的正整数${NC}"
                    read -p "请输入CPU核心数: " cores
                done
                break ;;
            *)
                echo -e "${RED}无效选择，请输入 1-5${NC}"
                ;;
        esac
    done
    
    # 内存选择（竖排显示）
    echo ""
    echo "请选择内存大小："
    echo "1) 512MB"
    echo "2) 1024MB"
    echo "3) 2048MB"
    echo "4) 4096MB"
    echo "5) 8192MB"
    echo "6) 自定义"
    PS3="请输入选项: "
    while true; do
        read -p "$PS3" memory_choice
        case $memory_choice in
            1) memory=512; break ;;
            2) memory=1024; break ;;
            3) memory=2048; break ;;
            4) memory=4096; break ;;
            5) memory=8192; break ;;
            6)
                read -p "请输入内存大小(MB): " memory
                while [[ ! $memory =~ ^[0-9]+$ ]]; do
                    echo -e "${RED}请输入有效的数字${NC}"
                    read -p "请输入内存大小(MB): " memory
                done
                break ;;
            *)
                echo -e "${RED}无效选择，请输入 1-6${NC}"
                ;;
        esac
    done
    
    # Swap选择（竖排显示）- 在内存和硬盘之间
    echo ""
    echo "请选择Swap大小："
    echo "1) 512MB"
    echo "2) 1024MB"
    echo "3) 2048MB"
    echo "4) 4096MB"
    echo "5) 8192MB"
    echo "6) 自定义"
    echo "0) 禁用Swap"
    PS3="请输入选项: "
    while true; do
        read -p "$PS3" swap_choice
        case $swap_choice in
            1) swap=512; break ;;
            2) swap=1024; break ;;
            3) swap=2048; break ;;
            4) swap=4096; break ;;
            5) swap=8192; break ;;
            6)
                read -p "请输入Swap大小(MB): " swap
                while [[ ! $swap =~ ^[0-9]+$ ]]; do
                    echo -e "${RED}请输入有效的数字${NC}"
                    read -p "请输入Swap大小(MB): " swap
                done
                break ;;
            0) swap=0; break ;;
            *)
                echo -e "${RED}无效选择，请输入 0-6${NC}"
                ;;
        esac
    done
    
    # 硬盘选择（竖排显示）
    echo ""
    echo "请选择硬盘大小："
    echo "1) 2GB"
    echo "2) 4GB"
    echo "3) 8GB"
    echo "4) 16GB"
    echo "5) 32GB"
    echo "6) 自定义"
    PS3="请输入选项: "
    while true; do
        read -p "$PS3" disk_choice
        case $disk_choice in
            1) disk_size=2; break ;;
            2) disk_size=4; break ;;
            3) disk_size=8; break ;;
            4) disk_size=16; break ;;
            5) disk_size=32; break ;;
            6)
                read -p "请输入硬盘大小(GB): " disk_size
                while [[ ! $disk_size =~ ^[0-9]+$ ]]; do
                    echo -e "${RED}请输入有效的数字${NC}"
                    read -p "请输入硬盘大小(GB): " disk_size
                done
                break ;;
            *)
                echo -e "${RED}无效选择，请输入 1-6${NC}"
                ;;
        esac
    done
}

# 选择安全配置（带默认值提示）
select_security() {
    echo ""
    echo -e "${YELLOW}=== 安全配置 ===${NC}"
    
    # 特权模式（默认特权）
    echo "请选择特权模式："
    echo "1) 特权容器"
    echo "2) 非特权容器"
    PS3="特权模式 (默认: 1): "
    while true; do
        read -p "$PS3" privileged_choice
        case $privileged_choice in
            ""|"1")
                unprivileged=0
                echo -e "${GREEN}已选择：特权容器${NC}"
                break
                ;;
            2)
                unprivileged=1
                echo -e "${GREEN}已选择：非特权容器${NC}"
                break
                ;;
            *)
                echo -e "${RED}无效选择，请输入 1 或 2${NC}"
                ;;
        esac
    done
    
    # 防火墙（默认禁用）
    echo ""
    echo "请选择防火墙："
    echo "1) 禁用"
    echo "2) 启用"
    PS3="防火墙 (默认: 1): "
    while true; do
        read -p "$PS3" firewall_choice
        case $firewall_choice in
            ""|"1")
                firewall=0
                echo -e "${GREEN}已选择：禁用${NC}"
                break
                ;;
            2)
                firewall=1
                echo -e "${GREEN}已选择：启用${NC}"
                break
                ;;
            *)
                echo -e "${RED}无效选择，请输入 1 或 2${NC}"
                ;;
        esac
    done
}

# 显示配置摘要
show_summary() {
    echo ""
    echo -e "${GREEN}=== 配置摘要 ===${NC}"
    echo "----------------------------------------"
    echo -e "容器ID:      $ctid"
    echo -e "容器名:      $container_name"
    echo -e "模板:        ${template#local:vztmpl/}"
    echo -e "IP地址:      192.168.1.$ip_last_octet/24"
    echo -e "网关:        $gateway"
    echo -e "CPU核心:     ${cores} 核"
    echo -e "内存:        ${memory}MB"
    echo -e "Swap:        $([ $swap -gt 0 ] && echo "${swap}MB" || echo "禁用")"
    echo -e "硬盘:        ${disk_size}GB"
    echo -e "特权模式:    $([ $unprivileged -eq 0 ] && echo "特权" || echo "非特权")"
    echo -e "防火墙:      $([ $firewall -eq 1 ] && echo "启用" || echo "禁用")"
    echo -e "特性:        keyctl, nesting, fuse, nfs, cifs"
    echo -e "IPv6:        SLAAC（无状态自动配置）"
    echo "----------------------------------------"
}

# 创建容器
create_container() {
    echo ""
    echo -e "${YELLOW}正在创建容器...${NC}"
    
    # 直接执行 pct create 命令，包含所有参数
    pct create "$ctid" "$template" \
        --hostname "$container_name" \
        --memory "$memory" \
        --swap "$swap" \
        --cores "$cores" \
        --net0 "name=eth0,bridge=vmbr0,firewall=$firewall,gw=$gateway,ip=192.168.1.$ip_last_octet/24,type=veth" \
        --rootfs "local-lvm:${disk_size}" \
        --unprivileged "$unprivileged" \
        --features "keyctl=1,nesting=1,fuse=1,mount=nfs;cifs" \
        --ostype debian \
        --password "$password" \
        --start 1 \
        --onboot 1
    
    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}容器创建成功！${NC}"
        echo "容器ID: $ctid"
        echo "容器名: $container_name"
        echo "IP地址: 192.168.1.$ip_last_octet"
        echo -e "特权模式: $([ $unprivileged -eq 0 ] && echo "特权" || echo "非特权")"
        echo ""
        echo -e "${GREEN}已启用的功能特性：${NC}"
        echo "  - keyctl:   密钥管理支持"
        echo "  - nesting:  嵌套容器支持"
        echo "  - fuse:     FUSE文件系统支持"
        echo "  - nfs:      NFS文件系统支持 (通过mount参数)"
        echo "  - cifs:     SMB/CIFS文件系统支持 (通过mount参数)"
        echo ""
        echo -e "${GREEN}IPv6 SLAAC配置说明：${NC}"
        echo "容器将通过SLAAC自动获取IPv6地址"
        echo "如需检查IPv6地址，请执行："
        echo "  pct enter $ctid"
        echo "  ip -6 addr"
        echo ""
        echo "如需查看容器状态，请使用: pct status $ctid"
        echo "如需查看容器配置，请使用: pct config $ctid"
    else
        echo ""
        echo -e "${RED}容器创建失败，请检查配置后重试${NC}"
        exit 1
    fi
}

# 主程序
main() {
    # 获取容器ID
    ctid=$(get_next_ctid)
    
    # 收集用户输入
    read_container_name
    read_password
    select_template
    select_network
    select_resources
    select_security
    
    # 显示摘要
    show_summary
    
    # 确认创建（空输入默认为创建）
    echo ""
    read -p "确认创建容器？(y/n): " confirm
    # 空输入、y、Y 都确认创建，只有 n/N 才取消
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "操作已取消"
        exit 0
    fi
    
    # 创建容器
    create_container
}

# 运行主程序
main