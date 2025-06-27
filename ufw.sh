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
#   最终版本：2025.07.07
#
# ===============================================================

# ===================== 颜色定义 =====================
GREEN='\e[0;32m'
YELLOW='\e[0;33m'
RED='\e[0;31m'
BLUE='\e[0;34m'
NC='\e[0m' # 无颜色（重置颜色）

# ===================== 全局变量 =====================
USER_INPUT=""
STARTUP_MSG=""

# ===================== 权限与环境检查 =====================
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}❌ 错误: 请使用 root 权限运行此脚本 (例如: sudo bash $0)${NC}"
        exit 1
    fi
}

check_dependencies() {
    if ! command -v "ufw" &>/dev/null; then
        echo -e "${YELLOW}未找到 'ufw'，正在尝试安装...${NC}"
        apt-get update -qq && apt-get install -y ufw > /dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ 'ufw' 已成功安装${NC}"
        else
            echo -e "${RED}❌ 安装 'ufw' 失败。请手动执行 'sudo apt-get install ufw' 后重试。${NC}"
            exit 1
        fi
    fi
}

check_and_configure_ipv6() {
    local ufw_default_conf="/etc/default/ufw"
    if grep -q "^IPV6=yes" "$ufw_default_conf"; then
        return
    fi
    echo -e "${YELLOW}⚠️ 警告: 检测到 UFW 的 IPv6 支持未开启。${NC}"
    read -p "是否要自动修改配置以启用 IPv6 支持? [Y/n]: " confirm
    if [[ $confirm =~ ^[Yy]$ ]] || [ -z "$confirm" ]; then
        sed -i 's/^IPV6=no/IPV6=yes/' "$ufw_default_conf"
        echo -e "${GREEN}✅ 已启用 IPv6 支持。建议重载 UFW 以使配置生效。${NC}"
    fi
}

startup_check_and_apply() {
    local messages="\n${YELLOW}--- 启动环境自动检查与配置报告 ---${NC}"
    ufw allow 22/tcp comment "Auto-Setup-SSH" &>/dev/null || true
    ufw allow 80/tcp comment "Auto-Setup-HTTP" &>/dev/null || true
    ufw allow 443/tcp comment "Auto-Setup-HTTPS" &>/dev/null || true
    messages+="\n  ${GREEN}✓${NC} 已确保SSH/HTTP/HTTPS基础端口规则存在。"
    messages+="\n${YELLOW}------------------------------------------${NC}"
    STARTUP_MSG="$messages"
}

# ===================== 通用函数 =====================
# 核心函数: 支持ESC取消和退格键的 read
read_with_esc_cancel() {
    USER_INPUT=""
    local prompt="$1"
    local char
    echo -ne "$prompt"
    stty -echo
    trap 'stty echo' EXIT # 确保脚本退出时终端恢复正常
    while IFS= read -r -s -n 1 char; do
        case "$char" in
            $'\e') # ESC key
                stty echo; trap - EXIT; return 1
                ;;
            "") # Enter key
                stty echo; trap - EXIT; echo; return 0
                ;;
            $'\177') # Backspace key
                if [ -n "$USER_INPUT" ]; then
                    USER_INPUT="${USER_INPUT%?}"
                    echo -ne "\b \b"
                fi
                ;;
            *)
                USER_INPUT+="$char"
                echo -n "$char"
                ;;
        esac
    done
    stty echo; trap - EXIT
}

# 智能暂停函数，返回1代表ESC被按下
pause() {
    echo
    read -s -n 1 -r -p "按任意键继续，或按 [ESC] 键返回上一级..." key
    echo -ne "\r\033[K"
    if [[ $key == $'\e' ]]; then
        return 1
    fi
    return 0
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

# ===================== 启用 / 关闭 / 重置防火墙 =====================
enable_firewall() {
    clear
    if ufw status | grep -q "Status: active"; then
        echo -e "${YELLOW}⚠️ 防火墙已经是 [启用] 状态。${NC}"
    else
        read -p "您确定要启用防火墙吗? (y/n): " confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
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

# ===================== 自定义访问规则管理 =====================
custom_rule_manager() {
    while true; do
        clear
        echo -e "${BLUE}---------- 当前规则列表 (带编号) ----------${NC}"; ufw status numbered; echo -e "${BLUE}------------------------------------------${NC}"
        echo -e "\n${YELLOW}自定义访问规则管理 (在任何输入时按 ESC 可返回此菜单):${NC}"
        echo -e "  1) 允许特定 IP/IP段 访问"
        echo -e "  2) 开放端口 (多个用${RED}空格${NC}分隔)"
        echo -e "  3) 封禁/拒绝 IP 或 端口"
        echo -e "  4) 删除规则 (输入编号)"
        echo -e "\n  ${BLUE}0) 返回主菜单${NC}"
        read -p "请选择一个操作 [0-4]: " opt
        
        if [[ "$opt" == "0" ]]; then
            return
        fi
        
        case $opt in
            1) # 允许 IP
                read_with_esc_cancel "请输入要允许的 IP/IP段: "; local ret=$?
                if [ $ret -ne 0 ]; then echo -e "\n${RED}操作取消。${NC}"; sleep 1; continue; fi
                local ip=$USER_INPUT
                
                read_with_esc_cancel "请输入端口 (留空则所有): "; ret=$?
                if [ $ret -ne 0 ]; then echo -e "\n${RED}操作取消。${NC}"; sleep 1; continue; fi
                local port=$USER_INPUT
                
                read -p "协议 [tcp|udp|both] (默认 both): " proto
                proto=${proto:-both}

                if [ -z "$port" ]; then
                    ufw allow from "$ip"
                    echo -e "${GREEN}✅ 已添加规则：允许来自 [$ip] 的所有访问。${NC}"
                else
                    if [[ "$proto" =~ ^(tcp|both)$ ]]; then ufw allow proto tcp from "$ip" to any port "$port"; fi
                    if [[ "$proto" =~ ^(udp|both)$ ]]; then ufw allow proto udp from "$ip" to any port "$port"; fi
                    echo -e "${GREEN}✅ 已添加规则：允许来自 [$ip] 访问端口 [$port]。${NC}"
                fi
                if ! pause; then return; fi
                ;;
            2) # 开放端口
                read_with_esc_cancel "请输入要开放的端口(多个用${RED}空格${NC}分隔): "; local ret=$?
                if [ $ret -ne 0 ]; then echo -e "\n${RED}操作取消。${NC}"; sleep 1; continue; fi
                local ports_array=($USER_INPUT)
                
                read -p "协议 [tcp|udp|both] (默认 both): " proto
                proto=${proto:-both}
                
                for p in "${ports_array[@]}"; do
                    if [[ "$proto" =~ ^(tcp|both)$ ]]; then ufw allow "$p"/tcp; fi
                    if [[ "$proto" =~ ^(udp|both)$ ]]; then ufw allow "$p"/udp; fi
                    echo -e "${GREEN}✅ 端口 [$p] 已开放。${NC}"
                done
                if ! pause; then return; fi
                ;;
            3) # 封禁
                read -p "您想封禁 IP 还是 Port? [ip/port]: " block_type
                if [[ "$block_type" == "ip" ]]; then
                    read_with_esc_cancel "请输入要封禁的 IP 地址: "; ret=$?
                    if [ $ret -ne 0 ]; then echo -e "\n${RED}操作取消。${NC}"; sleep 1; continue; fi
                    ufw deny from "$USER_INPUT"
                    echo -e "${GREEN}✅ IP [$USER_INPUT] 已封禁。${NC}"
                elif [[ "$block_type" == "port" ]]; then
                    read_with_esc_cancel "请输入要封禁的端口(多个用${RED}空格${NC}分隔): "; ret=$?
                    if [ $ret -ne 0 ]; then echo -e "\n${RED}操作取消。${NC}"; sleep 1; continue; fi
                    local ports_array=($USER_INPUT)
                    read -p "协议 [tcp|udp|both] (默认 both): " proto
                    proto=${proto:-both}
                    for p in "${ports_array[@]}"; do
                        if [[ "$proto" =~ ^(tcp|both)$ ]]; then ufw deny "$p"/tcp; fi
                        if [[ "$proto" =~ ^(udp|both)$ ]]; then ufw deny "$p"/udp; fi
                        echo -e "${GREEN}✅ 端口 [$p] 已封禁。${NC}"
                    done
                else
                    echo -e "${RED}❌ 无效的选择。${NC}"
                fi
                if ! pause; then return; fi
                ;;
            4) # 删除规则
                read_with_esc_cancel "请输入要删除的规则【编号】: "; local ret=$?
                if [ $ret -ne 0 ]; then echo -e "\n${RED}操作取消。${NC}"; sleep 1; continue; fi
                local rule_num=$USER_INPUT
                
                read -p "您确定要删除规则【#$rule_num】吗? (y/n): " confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
                    ufw --force delete "$rule_num"
                    echo -e "${GREEN}✅ 规则 #${rule_num} 已删除。${NC}"
                else
                    echo -e "${RED}❌ 操作已取消。${NC}"
                fi
                if ! pause; then return; fi
                ;;
            *)
                echo -e "${RED}无效输入。${NC}"; if ! pause; then return; fi ;;
        esac
    done
}

# ===================== 日志与备份管理 (格式化) =====================
manage_logs_menu() {
    while true; do
        clear
        echo -e "${YELLOW}--- 日志管理 ---${NC}"
        echo -e "  1) 设置日志级别\n  2) 查看最近日志\n  3) 实时监控日志\n\n  ${BLUE}0) 返回主菜单${NC}"
        read -p "请选择 [0-3]: " opt
        case $opt in
            1)
                read -p "输入级别 [low|medium|high|full|off]: " lv
                ufw logging "$lv"
                echo -e "${GREEN}✅ 日志级别已设为: $lv${NC}"
                if ! pause; then return; fi
                ;;
            2)
                echo -e "\n${YELLOW}--- 最近 50行 UFW 日志 ---${NC}"
                if [ -f "/var/log/ufw.log" ]; then
                    tail -n 50 /var/log/ufw.log
                else
                    echo -e "${RED}日志文件不存在。${NC}"
                fi
                if ! pause; then return; fi
                ;;
            3)
                echo -e "\n${YELLOW}--- 实时监控 (按 Ctrl+C 退出) ---${NC}"
                if [ -f "/var/log/ufw.log" ]; then
                    tail -f /var/log/ufw.log
                else
                    echo -e "${RED}日志文件不存在。${NC}"; if ! pause; then return; fi
                fi
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效输入。${NC}"; if ! pause; then return; fi
                ;;
        esac
    done
}

manage_backup_menu() {
    while true; do
        clear
        echo -e "${YELLOW}--- 备份与恢复 ---${NC}"
        echo -e "  1) 导出规则\n  2) 导入规则\n\n  ${BLUE}0) 返回主菜单${NC}"
        read -p "请选择 [0-2]: " opt
        case $opt in
            1)
                local f="/root/ufw-backup-$(date +%Y%m%d).tar.gz"
                read -p "输入备份路径 (默认: $f): " p
                p=${p:-$f}
                if tar -czf "$p" /etc/ufw /lib/ufw/user*.rules &>/dev/null; then
                    echo -e "${GREEN}✅ 规则已导出到: $p${NC}"
                else
                    echo -e "${RED}❌ 导出失败。${NC}"
                fi
                if ! pause; then return; fi
                ;;
            2)
                read -p "输入要导入的备份文件路径: " f
                if [ -f "$f" ]; then
                    read -p "警告：将覆盖现有规则，继续? (y/n): " c
                    if [[ $c =~ ^[Yy]$ ]]; then
                        if tar -xzf "$f" -C /; then
                            echo -e "${GREEN}✅ 配置已导入。${NC}"
                            read -p "立即重载防火墙? (y/n): " r
                            if [[ $r =~ ^[Yy]$ ]]; then
                                ufw reload
                                echo -e "${GREEN}✅ 防火墙已重载。${NC}"
                            fi
                        else
                            echo -e "${RED}❌ 导入失败。${NC}"
                        fi
                    fi
                else
                    echo -e "${RED}❌ 文件不存在。${NC}"
                fi
                if ! pause; then return; fi
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效输入。${NC}"; if ! pause; then return; fi
                ;;
        esac
    done
}

# ===================== 主菜单 =====================
main_menu() {
    while true; do
        clear
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║${NC}              🛡️  ${YELLOW}UFW 防火墙管理器 v2025.07.07${NC}              ${GREEN}║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
        
        show_simple_status
        if [ -n "$STARTUP_MSG" ]; then
            echo -e "$STARTUP_MSG"
            STARTUP_MSG=""
        fi
        
        echo -e "\n${YELLOW}--- 基本操作 ---${NC}"
        echo -e "  1) 启用防火墙"
        echo -e "  2) 关闭防火墙"
        echo -e "  3) 查看详细状态"
        echo -e "  4) 重置防火墙"
        
        echo -e "\n${YELLOW}--- 高级功能 ---${NC}"
        echo -e "  5) 管理防火墙规则"
        echo -e "  6) 日志管理"
        echo -e "  7) 备份与恢复"
        
        echo -e "\n${YELLOW}--------------------------------------------------------------${NC}"
        echo -e "  ${BLUE}0) 退出脚本${NC}"
        
        read -p "请输入您的选择 [0-7]: " choice
        
        case $choice in
            1) enable_firewall; pause || continue ;;
            2) disable_firewall; pause || continue ;;
            3) show_detailed_status; pause || continue ;;
            4) reset_firewall; pause || continue ;;
            5) custom_rule_manager ;;
            6) manage_logs_menu ;;
            7) manage_backup_menu ;;
            0) echo -e "\n${GREEN}感谢使用，再见！${NC}"; exit 0 ;;
            *) echo -e "${RED}无效的输入。${NC}"; pause || continue ;;
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
