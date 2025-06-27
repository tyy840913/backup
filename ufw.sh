#!/bin/bash
# set -e：当命令返回非零状态时，立即退出脚本
# set -o pipefail：如果管道中任一命令失败，整个管道失败
set -e
set -o pipefail

# ===============================================================
#
#   UFW 防火墙管理工具 (增强中文版)
#   适用系统：Debian / Ubuntu
#
#   作者：Gemini AI & User Collaboration
#   最终版本：2025.07.05
#
# ===============================================================

# ===================== 颜色定义 =====================
GREEN='\e[0;32m'
YELLOW='\e[0;33m'
RED='\e[0;31m'
BLUE='\e[0;34m'
NC='\e[0m' # 无颜色（重置颜色）

# ===================== 全局变量 =====================
# 用于存储自定义 read 函数的返回结果
USER_INPUT=""
# 用于存储启动提示信息
STARTUP_MSG=""

# ===================== 权限与环境检查 =====================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}❌ 错误: 请使用 root 权限运行此脚本 (例如: sudo bash $0)${NC}"
        exit 1
    fi
}

check_dependencies() {
    local dependencies=("ufw")
    echo -e "${YELLOW}🔍 正在检查所需工具...${NC}"
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${YELLOW}未找到 '$cmd'，正在尝试自动安装...${NC}"
            apt-get update -qq && apt-get install -y "$cmd" > /dev/null
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✅ '$cmd' 已成功安装${NC}"
            else
                echo -e "${RED}❌ 安装 '$cmd' 失败。请手动执行 'sudo apt-get install ufw' 后重试。${NC}"
                exit 1
            fi
        fi
    done
    echo -e "${GREEN}✅ 所有依赖项均已满足。${NC}"
}

check_and_configure_ipv6() {
    local ufw_default_conf="/etc/default/ufw"
    if grep -q "^IPV6=yes" "$ufw_default_conf"; then
        return
    fi

    echo -e "${YELLOW}⚠️ 警告: 检测到 UFW 的 IPv6 支持未开启 (IPV6=no)。${NC}"
    read -p "是否要自动修改配置以启用 IPv6 支持? [Y/n]: " confirm
    if [[ $confirm =~ ^[Yy]$ ]] || [ -z "$confirm" ]; then
        sed -i 's/^IPV6=no/IPV6=yes/' "$ufw_default_conf"
        echo -e "${GREEN}✅ 已启用 IPv6 支持。建议重载 UFW 以使配置生效。${NC}"
    fi
}

startup_check_and_apply() {
    local messages="\n${YELLOW}--- 启动环境自动检查与配置报告 ---${NC}"
    local changes_made=false

    local common_ports=("22/tcp" "80/tcp" "443/tcp")
    local port_names=("SSH" "HTTP" "HTTPS")
    for i in "${!common_ports[@]}"; do
        local port=${common_ports[$i]}
        local name=${port_names[$i]}
        if ufw status | grep -qw "$port" | grep -q 'ALLOW'; then
            messages+="\n  ${YELLOW}✓${NC} 常用端口规则已存在: $name ($port)"
        else
            ufw allow "$port" comment "Auto-Setup-$name"
            changes_made=true
            messages+="\n  ${GREEN}✓${NC} 已自动开放常用端口: $name ($port)"
        fi
    done

    local lan_ranges=("192.168.0.0/16" "10.0.0.0/8" "172.16.0.0/12")
    for lan in "${lan_ranges[@]}"; do
        if ufw status | grep -qE "ALLOW.*from $lan"; then
            messages+="\n  ${YELLOW}✓${NC} 内网访问规则已存在: $lan"
        else
            ufw allow from "$lan" to any comment "Auto-Setup-LAN"
            changes_made=true
            messages+="\n  ${GREEN}✓${NC} 已自动开放内网访问: $lan"
        fi
    done

    if [ "$changes_made" = true ]; then
        messages+="\n\n  ${GREEN}提示: 已自动添加缺失的基础规则。${NC}"
    else
        messages+="\n\n  ${GREEN}提示: 您的关键规则配置完整。${NC}"
    fi

    messages+="\n${YELLOW}------------------------------------------${NC}"
    STARTUP_MSG="$messages"
}

# ===================== 通用函数 =====================
# 核心函数: 支持ESC取消和退格键的 read
# 调用方法: read_with_esc_cancel "提示语: "; local ret=$?
# 成功时 ret=0, USER_INPUT 存储结果; 取消时 ret=1
read_with_esc_cancel() {
    USER_INPUT=""
    local prompt="$1"
    local char
    
    echo -ne "$prompt"
    
    # stty -echo anlamsız karakterlerin ekranda görünmesini engeller.
    # stty echo ise normale döndürür.
    stty -echo
    while IFS= read -r -s -n 1 char; do
        if [[ $char == $'\e' ]]; then # ESC key
            stty echo
            return 1 
        fi
        if [[ $char == "" ]]; then # Enter key
            stty echo
            echo
            return 0
        fi
        if [[ $char == $'\177' || $char == $'\b' ]]; then # Backspace key
            if [ -n "$USER_INPUT" ]; then
                USER_INPUT="${USER_INPUT%?}"
                echo -ne "\b \b"
            fi
        else
            USER_INPUT+="$char"
            echo -n "$char"
        fi
    done
    stty echo
}

pause() {
    echo
    read -s -n 1 -r -p "按任意键继续..."
    echo -ne "\r\033[K" # 清除提示行
}

# ===================== 防火墙状态显示 =====================
show_simple_status() {
    if ufw status | grep -q "Status: active"; then
        echo -e "当前状态: ${GREEN}● 启用 (Active)${NC}"
    else
        echo -e "当前状态: ${RED}● 关闭 (Inactive)${NC}"
    fi
}

show_detailed_status() {
    clear
    echo -e "\n${BLUE}---------- 当前详细防火墙状态与规则 ----------${NC}"
    ufw status verbose
    echo -e "${BLUE}----------------------------------------------${NC}\n"
}

# ===================== 启用 / 关闭防火墙 =====================
enable_firewall() {
    clear
    if ufw status | grep -q "Status: active"; then
        echo -e "${YELLOW}⚠️ 防火墙已经是 [启用] 状态。${NC}"
    else
        read -p "您确定要启用防火墙吗? (y/n): " confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            if ! ufw status | grep -q '22/tcp.*ALLOW'; then
                echo -e "${YELLOW}⚠️ 为防止失联，将自动放行 SSH (22/tcp) 端口...${NC}"
                ufw allow 22/tcp comment "Fallback-SSH-Enable"
            fi
            ufw enable
            echo -e "${GREEN}✅ 防火墙已成功启用。${NC}"
        else
            echo -e "${RED}❌ 操作已取消。${NC}"
        fi
    fi
}

disable_firewall() {
    clear
    if ufw status | grep -q "Status: inactive"; then
        echo -e "${YELLOW}⚠️ 防火墙已经是 [关闭] 状态。${NC}"
    else
        read -p "警告：关闭防火墙会使服务器暴露在风险中。您确定要关闭吗? (y/n): " confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            ufw disable
            echo -e "${GREEN}✅ 防火墙已成功关闭。${NC}"
        else
            echo -e "${RED}❌ 操作已取消。${NC}"
        fi
    fi
}

# ===================== 自定义访问规则管理 =====================
custom_rule_manager() {
    while true; do
        clear
        echo -e "${BLUE}---------- 当前规则列表 (带编号) ----------${NC}"
        ufw status numbered
        echo -e "${BLUE}------------------------------------------${NC}"
        echo -e "\n${YELLOW}自定义访问规则管理 (在任何输入时按 ESC 可取消):${NC}"
        echo -e "  1) 允许特定 IP/IP段 访问"
        echo -e "  2) 开放端口 (多个用${RED}空格${NC}分隔)"
        echo -e "  3) 封禁/拒绝 IP 或 端口"
        echo -e "  4) 删除规则 (输入编号)"
        echo -e "\n  ${BLUE}0) 返回主菜单${NC}"
        read -p "请选择一个操作 [0-4]: " opt
        
        if [[ "$opt" == "0" ]]; then return; fi
        
        case $opt in
            1) # 允许 IP
                read_with_esc_cancel "请输入要允许的 IP/IP段: "; local ret=$?
                if [ $ret -ne 0 ]; then echo -e "\n${RED}❌ 操作已取消。${NC}"; pause; continue; fi
                local ip=$USER_INPUT
                
                read_with_esc_cancel "请输入端口 (留空则所有端口): "; ret=$?
                if [ $ret -ne 0 ]; then echo -e "\n${RED}❌ 操作已取消。${NC}"; pause; continue; fi
                local port=$USER_INPUT

                read -p "请输入协议 [tcp|udp|both] (默认为 both): " proto
                proto=${proto:-both}

                if [ -z "$port" ]; then
                    ufw allow from "$ip" comment "Custom-IP-Allow"
                    echo -e "${GREEN}✅ 已允许来自 [$ip] 的所有协议访问。${NC}"
                else
                    if [[ "$proto" =~ ^(tcp|both)$ ]]; then ufw allow proto tcp from "$ip" to any port "$port" comment "Custom-TCP-Port-Allow"; echo -e "${GREEN}✅ TCP: 已允许来自 [$ip] 访问端口 [$port]。${NC}"; fi
                    if [[ "$proto" =~ ^(udp|both)$ ]]; then ufw allow proto udp from "$ip" to any port "$port" comment "Custom-UDP-Port-Allow"; echo -e "${GREEN}✅ UDP: 已允许来自 [$ip] 访问端口 [$port]。${NC}"; fi
                fi
                pause
                ;;
            2) # 开放端口
                read_with_esc_cancel "请输入要开放的端口(多个用${RED}空格${NC}分隔): "; local ret=$?
                if [ $ret -ne 0 ]; then echo -e "\n${RED}❌ 操作已取消。${NC}"; pause; continue; fi
                local ports_array=($USER_INPUT) # Shell自动按空格分割
                
                read -p "请输入协议 [tcp|udp|both] (默认为 both): " proto
                proto=${proto:-both}
                
                for port in "${ports_array[@]}"; do
                    if [[ "$proto" =~ ^(tcp|both)$ ]]; then ufw allow "$port"/tcp comment "Custom-TCP-Port-Allow"; echo -e "${GREEN}✅ TCP 端口 [$port] 已开放。${NC}"; fi
                    if [[ "$proto" =~ ^(udp|both)$ ]]; then ufw allow "$port"/udp comment "Custom-UDP-Port-Allow"; echo -e "${GREEN}✅ UDP 端口 [$port] 已开放。${NC}"; fi
                done
                pause
                ;;
            3) # 封禁
                read -p "您想封禁 IP 还是 Port? [ip/port]: " block_type
                if [[ "$block_type" == "ip" ]]; then
                    read_with_esc_cancel "请输入要封禁的 IP 地址: "; local ret=$?
                    if [ $ret -ne 0 ]; then echo -e "\n${RED}❌ 操作已取消。${NC}"; pause; continue; fi
                    ufw deny from "$USER_INPUT" to any comment "Custom-IP-Deny"
                    echo -e "${GREEN}✅ 来自 [$USER_INPUT] 的所有访问已被拒绝。${NC}"
                elif [[ "$block_type" == "port" ]]; then
                    read_with_esc_cancel "请输入要封禁的端口(多个用${RED}空格${NC}分隔): "; local ret=$?
                    if [ $ret -ne 0 ]; then echo -e "\n${RED}❌ 操作已取消。${NC}"; pause; continue; fi
                    local ports_array=($USER_INPUT)
                    
                    read -p "协议类型 [tcp|udp|both] (默认为 both): " proto
                    proto=${proto:-both}
                    for port in "${ports_array[@]}"; do
                       if [[ "$proto" =~ ^(tcp|both)$ ]]; then ufw deny "$port"/tcp comment "Custom-Port-Deny"; echo -e "${GREEN}✅ TCP 端口 [$port] 已被拒绝访问。${NC}"; fi
                       if [[ "$proto" =~ ^(udp|both)$ ]]; then ufw deny "$port"/udp comment "Custom-Port-Deny"; echo -e "${GREEN}✅ UDP 端口 [$port] 已被拒绝访问。${NC}"; fi
                    done
                else
                    echo -e "${RED}❌ 无效的选择。${NC}"
                fi
                pause
                ;;
            4) # 删除规则
                read_with_esc_cancel "请输入要删除的规则【编号】: "; local ret=$?
                if [ $ret -ne 0 ]; then echo -e "\n${RED}❌ 操作已取消。${NC}"; pause; continue; fi
                local rule_num=$USER_INPUT
                if ! [[ "$rule_num" =~ ^[0-9]+$ ]]; then
                    echo -e "${RED}❌ 错误: 请输入有效的规则编号。${NC}"
                else
                    read -p "您确定要删除规则【#$rule_num】吗? (y/n): " confirm
                    if [[ $confirm =~ ^[Yy]$ ]]; then
                        ufw --force delete "$rule_num"
                        echo -e "${GREEN}✅ 规则 #${rule_num} 已成功删除。${NC}"
                    else
                        echo -e "${RED}❌ 操作已取消。${NC}"
                    fi
                fi
                pause
                ;;
            *)
                echo -e "${RED}无效的输入。${NC}"; pause ;;
        esac
    done
}

# ===================== 日志管理 (子菜单) =====================
manage_logs_menu() {
    while true; do
        clear
        echo -e "${YELLOW}--- 日志管理 ---${NC}"
        echo -e "  1) 设置日志级别 (low, medium, high, full, off)"
        echo -e "  2) 查看最近 50 条日志"
        echo -e "  3) 实时监控日志"
        echo -e "\n  ${BLUE}0) 返回主菜单${NC}"
        read -p "请选择一个操作 [0-3]: " log_opt
        case $log_opt in
            1)
                read -p "请输入日志级别 [low|medium|high|full|off]: " level
                if [[ "$level" =~ ^(low|medium|high|full|off)$ ]]; then
                    ufw logging "$level"
                    echo -e "${GREEN}✅ 日志级别已设置为: $level${NC}"
                else
                    echo -e "${RED}❌ 无效的级别。${NC}"
                fi
                pause
                ;;
            2)
                echo -e "\n${YELLOW}--- 最近 50 行 UFW 日志 ---${NC}"
                if [ -f "/var/log/ufw.log" ]; then
                    tail -n 50 /var/log/ufw.log
                else
                    echo -e "${RED}日志文件不存在。${NC}"
                fi
                echo -e "${YELLOW}----------------------------${NC}"
                pause
                ;;
            3)
                echo -e "\n${YELLOW}--- 实时监控 UFW 日志 (按 Ctrl+C 退出) ---${NC}"
                if [ -f "/var/log/ufw.log" ]; then
                    tail -f /var/log/ufw.log
                else
                    echo -e "${RED}日志文件不存在。${NC}"
                    pause
                fi
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效的输入。${NC}"
                pause
                ;;
        esac
    done
}

# ===================== 备份与恢复 (子菜单) =====================
manage_backup_menu() {
    while true; do
        clear
        echo -e "${YELLOW}--- 备份与恢复 ---${NC}"
        echo -e "  1) 导出 (备份) 当前所有UFW规则"
        echo -e "  2) 导入 (恢复) UFW规则"
        echo -e "\n  ${BLUE}0) 返回主菜单${NC}"
        read -p "请选择一个操作 [0-2]: " backup_opt
        case $backup_opt in
            1)
                local default_path="/root/ufw-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
                read -p "请输入备份文件保存路径 (默认为 ${default_path}): " custom_path
                local file_path=${custom_path:-$default_path}
                
                if tar -czf "$file_path" /etc/ufw /lib/ufw/user*.rules &>/dev/null; then
                    echo -e "${GREEN}✅ 规则已成功导出到: $file_path${NC}"
                else
                    echo -e "${RED}❌ 导出失败。请检查路径和权限。${NC}"
                fi
                pause
                ;;
            2)
                read -p "请输入要导入的备份文件路径: " file
                if [ -f "$file" ]; then
                    read -p "警告：这将覆盖所有现有规则，是否继续? (y/n): " confirm
                    if [[ $confirm =~ ^[Yy]$ ]]; then
                        if tar -xzf "$file" -C /; then
                            echo -e "${GREEN}✅ 配置已成功导入。${NC}"
                            read -p "是否立即重载防火墙以使新规则生效? (y/n): " reload_confirm
                            if [[ $reload_confirm =~ ^[Yy]$ ]]; then
                                ufw reload
                                echo -e "${GREEN}✅ 防火墙已重载。${NC}"
                            fi
                        else
                             echo -e "${RED}❌ 导入失败。文件可能已损坏或权限不足。${NC}"
                        fi
                    fi
                else
                    echo -e "${RED}❌ 文件 '$file' 不存在。${NC}"
                fi
                pause
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效的输入。${NC}"
                pause
                ;;
        esac
    done
}

# ===================== 重置规则 =====================
reset_firewall() {
    clear
    read -p "警告：此操作将删除所有规则并恢复到默认状态。确定要重置吗? (y/n): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        ufw reset
        echo -e "${GREEN}✅ 防火墙已重置。${NC}"
    else
        echo -e "${RED}❌ 操作已取消。${NC}"
    fi
}

# ===================== 主菜单 =====================
main_menu() {
    while true; do
        clear
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║${NC}              🛡️  ${YELLOW}UFW 防火墙管理器 v2025.07.05${NC}              ${GREEN}║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
        
        show_simple_status
        if [ -n "$STARTUP_MSG" ]; then
            echo -e "$STARTUP_MSG"
            STARTUP_MSG=""
        fi
        
        echo -e "\n${YELLOW}--- 基本操作 & 状态 ---${NC}"
        echo -e "  1) 启用防火墙"
        echo -e "  2) 关闭防火墙"
        echo -e "  3) 查看详细状态与规则列表"
        echo -e "  4) 重置防火墙 (清空所有规则)"
        
        echo -e "\n${YELLOW}--- 规则与高级功能 ---${NC}"
        echo -e "  5) 管理防火墙规则"
        echo -e "  6) 日志管理"
        echo -e "  7) 备份与恢复"
        
        echo -e "\n${YELLOW}--------------------------------------------------------------${NC}"
        echo -e "  ${BLUE}0) 退出脚本${NC}"
        
        read -p "请输入您的选择 [0-7]: " choice
        
        case $choice in
            1) enable_firewall; pause ;;
            2) disable_firewall; pause ;;
            3) show_detailed_status; pause ;;
            4) reset_firewall; pause ;;
            5) custom_rule_manager ;;
            6) manage_logs_menu ;;
            7) manage_backup_menu ;;
            0) echo -e "\n${GREEN}感谢使用，再见！${NC}"; exit 0 ;;
            *) echo -e "${RED}无效的输入。${NC}"; pause ;;
        esac
    done
}

# ===================== 主程序入口 =====================
clear
check_root
check_dependencies
check_and_configure_ipv6
startup_check_and_apply
main_menu
