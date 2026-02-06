#!/bin/bash

# PVE LXC容器创建脚本 - 简化版
# 功能：快速创建LXC容器，最少交互

echo "=== PVE LXC容器快速创建脚本 ==="
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 固定配置
CORES=4
MEMORY=2048
SWAP=512
DISK_SIZE=4
UNPRIVILEGED=0  # 特权容器
FIREWALL=0      # 禁用防火墙

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

# 输入容器名（不能有空格）
read_container_name() {
    echo -e "${YELLOW}=== 基本配置 ===${NC}"
    read -p "请输入容器名: " container_name
    while true; do
        if [ -z "$container_name" ]; then
            echo -e "${RED}容器名不能为空${NC}"
            read -p "请输入容器名: " container_name
            continue
        fi
        if [[ "$container_name" =~ [[:space:]] ]]; then
            echo -e "${RED}容器名不能包含空格${NC}"
            read -p "请输入容器名: " container_name
            continue
        fi
        break
    done
}

# 输入密码
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
        local template_path=$(echo "$line" | awk '{print $1}')
        if [[ $template_path =~ local:vztmpl/(.+) ]]; then
            templates+=("${BASH_REMATCH[1]}")
        fi
    done < <(pveam list local 2>/dev/null)
    
    if [ ${#templates[@]} -eq 0 ]; then
        echo -e "${RED}错误：未找到已下载的模板${NC}"
        echo "请先下载模板："
        echo "  pveam update"
        echo "  pveam download local debian-12-standard_12.7-1_amd64.tar.zst"
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

# 输入IP地址
read_ip() {
    echo ""
    echo -e "${YELLOW}=== 网络配置 ===${NC}"
    gateway=$(get_gateway)
    echo -e "${GREEN}自动检测到网关IP: $gateway${NC}"
    
    read -p "请输入IP地址最后一段 (1-254): " ip_last_octet
    while [[ ! $ip_last_octet =~ ^[0-9]+$ ]] || [ $ip_last_octet -lt 1 ] || [ $ip_last_octet -gt 254 ]; do
        echo -e "${RED}请输入1-254之间的数字${NC}"
        read -p "请输入IP地址最后一段 (1-254): " ip_last_octet
    done
    
    echo "完整IP地址: 192.168.1.$ip_last_octet"
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
    echo -e "CPU核心:     ${CORES} 核"
    echo -e "内存:        ${MEMORY}MB"
    echo -e "Swap:        ${SWAP}MB"
    echo -e "硬盘:        ${DISK_SIZE}GB"
    echo -e "特权模式:    特权"
    echo -e "防火墙:      禁用"
    echo -e "特性:        keyctl, nesting, fuse, nfs, cifs"
    echo "----------------------------------------"
}

# 创建容器
create_container() {
    echo ""
    echo -e "${YELLOW}正在创建容器...${NC}"
    
    pct create "$ctid" "$template" \
        --hostname "$container_name" \
        --memory "$MEMORY" \
        --swap "$SWAP" \
        --cores "$CORES" \
        --net0 "name=eth0,bridge=vmbr0,firewall=$FIREWALL,gw=$gateway,ip=192.168.1.$ip_last_octet/24,type=veth" \
        --rootfs "local-lvm:${DISK_SIZE}" \
        --unprivileged "$UNPRIVILEGED" \
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
        echo ""
        echo "常用命令："
        echo "  pct status $ctid          # 查看状态"
        echo "  pct enter $ctid            # 进入容器"
        echo "  pct config $ctid           # 查看配置"
    else
        echo ""
        echo -e "${RED}容器创建失败${NC}"
        exit 1
    fi
}

# 主程序
main() {
    ctid=$(get_next_ctid)
    
    read_container_name
    read_password
    select_template
    read_ip
    show_summary
    
    echo ""
    read -p "确认创建容器？(y/n，默认为y): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "操作已取消"
        exit 0
    fi
    
    create_container
}

main