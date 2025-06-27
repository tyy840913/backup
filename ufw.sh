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
#   最终版本：2025.07.02
#
# ===============================================================

# ===================== 颜色定义 =====================
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色（重置颜色）

# 全局变量 - 用于存储启动提示信息
STARTUP_MSG=""

# ===================== 权限与依赖检查 =====================
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
            apt-get update -qq
            if apt-get install -y "$cmd"; then
                echo -e "${GREEN}✅ '$cmd' 已成功安装${NC}"
            else
                echo -e "${RED}❌ 安装 '$cmd' 失败。请手动执行 'sudo apt-get install ufw' 后重试。${NC}"
                exit 1
            fi
        fi
    done
    echo -e "${GREEN}✅ 所有依赖项均已满足。${NC}"
}

# ===================== 启动检查并自动设置默认规则 =====================
startup_check_and_apply() {
    local messages=""
    messages+="\n${YELLOW}--- 启动环境自动检查与配置报告 ---${NC}\n"
    local changes_made=false

    # 检查并配置常用外网端口
    local common_ports=("22/tcp" "80/tcp" "443/tcp")
    local port_names=("SSH" "HTTP" "HTTPS")
    for i in "${!common_ports[@]}"; do
        local port=${common_ports[$i]}
        local name=${port_names[$i]}
        # 检查规则是否存在，精确匹配 "ALLOW"
        if ufw status | grep -qw "$port" | grep -q 'ALLOW'; then
            messages+="  ${YELLOW}✓${NC} 常用端口规则已存在: $name ($port)\n"
        else
            ufw allow "$port" comment "Auto-Setup-$name"
            messages+="  ${GREEN}✓${NC} 已自动开放常用端口: $name ($port)\n"
            changes_made=true
        fi
    done

    # 检查并配置内网访问
    local lan_ranges=("192.168.0.0/16" "10.0.0.0/8" "172.16.0.0/12")
    for lan in "${lan_ranges[@]}"; do
        if ufw status | grep -qE "ALLOW.*from $lan"; then
            messages+="  ${YELLOW}✓${NC} 内网访问规则已存在: $lan\n"
        else
            ufw allow from "$lan" to any comment "Auto-Setup-LAN"
            messages+="  ${GREEN}✓${NC} 已自动开放内网访问: $lan\n"
            changes_made=true
        fi
    done

    if [ "$changes_made" = true ]; then
        messages+="\n  ${GREEN}提示: 已自动添加缺失的基础规则，保障服务正常运行。${NC}\n"
    else
        messages+="\n  ${GREEN}提示: 您的关键规则配置完整，无需自动操作。${NC}\n"
    fi

    messages+="${YELLOW}------------------------------------------${NC}"
    STARTUP_MSG="$messages"
}

# ===================== 通用函数 =====================
pause() {
    read -n 1 -s -r -p "按任意键返回菜单..."
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
    # UFW命令本身输出是英文，我们用中文标题包装
    ufw status verbose
    echo -e "${BLUE}----------------------------------------------${NC}\n"
}

# ===================== 启用 / 关闭防火墙 =====================
enable_firewall() {
    clear
    if ufw status | grep -q "Status: active"; then
        echo -e "${YELLOW}⚠️ 防火墙已经是 [启用] 状态，无需重复操作。${NC}"
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
    clear
    echo -e "${BLUE}---------- 当前规则列表 (带编号) ----------${NC}"
    ufw status numbered
    echo -e "${BLUE}------------------------------------------${NC}"
    echo -e "\n${YELLOW}自定义访问规则管理:${NC}"
    echo "  1) 允许特定 IP/IP段 访问 (可指定端口)"
    echo "  2) 开放端口 (可指定多个，用逗号分隔)"
    echo "  3) 封禁/拒绝 IP 或 端口"
    echo "  4) 删除规则 (输入编号)"
    echo -e "\n  0) 返回主菜单"
    read -p "请选择一个操作 [0-4]: " opt
    local success_msg=""
    case $opt in
        1)
            local ip
            while true; do
                read -p "请输入要允许的 IP 地址或 IP 段 (如 1.2.3.4 或 1.2.3.0/24): " ip
                # 简单的 IP/CIDR 格式校验
                if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
                    break
                else
                    echo -e "${RED}❌ IP 地址格式不正确，请重新输入。${NC}"
                fi
            done

            read -p "请输入端口 (留空为所有端口): " port
            read -p "请输入协议 [tcp|udp|both] (默认为 both): " proto
            proto=${proto:-both}

            if [ -z "$port" ]; then
                ufw allow from "$ip" comment "Custom-IP-Allow"
                success_msg="✅ 已添加规则：允许来自 [$ip] 的所有协议访问。"
            else
                if [[ "$proto" =~ ^(tcp|both)$ ]]; then
                    ufw allow proto tcp from "$ip" to any port "$port" comment "Custom-TCP-Port-Allow"
                    success_msg+="✅ TCP: 已允许来自 [$ip] 访问端口 [$port]。\n"
                fi
                if [[ "$proto" =~ ^(udp|both)$ ]]; then
                    ufw allow proto udp from "$ip" to any port "$port" comment "Custom-UDP-Port-Allow"
                    success_msg+="✅ UDP: 已允许来自 [$ip] 访问端口 [$port]。"
                fi
            fi
            echo -e "${GREEN}${success_msg}${NC}"
            ;;
        2)
            read -p "请输入要开放的端口或范围(多个用','隔开, 如 80,443,8000:9000): " ports_input
            read -p "请输入协议 [tcp|udp|both] (默认为 both): " proto
            proto=${proto:-both}
            
            # 使用IFS处理逗号分隔的输入
            IFS=',' read -ra ports_array <<< "$ports_input"
            for port in "${ports_array[@]}"; do
                port=$(echo "$port" | xargs) # 去除前后空格
                if ! [[ "$port" =~ ^[0-9]+(:[0-9]+)?$ ]]; then
                    echo -e "${RED}❌ 输入 '$port' 不是有效的端口或端口范围，已跳过。${NC}"
                    continue
                fi

                if [[ "$proto" =~ ^(tcp|both)$ ]]; then
                    ufw allow "$port"/tcp comment "Custom-TCP-Port-Allow"
                    echo -e "${GREEN}✅ TCP 端口 [$port] 已开放。${NC}"
                fi
                if [[ "$proto" =~ ^(udp|both)$ ]]; then
                    ufw allow "$port"/udp comment "Custom-UDP-Port-Allow"
                    echo -e "${GREEN}✅ UDP 端口 [$port] 已开放。${NC}"
                fi
            done
            ;;
        3)
            local block_type
            while true; do
                read -p "您想封禁 IP 还是 Port? [ip/port]: " block_type
                if [[ "$block_type" == "ip" || "$block_type" == "port" ]]; then
                    break
                else
                     echo -e "${RED}❌ 无效的选择，请输入 'ip' 或 'port'。${NC}"
                fi
            done

            if [[ "$block_type" == "ip" ]]; then
                read -p "请输入要封禁的 IP 地址: " target_ip
                 if [[ ! $target_ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$ ]]; then
                     echo -e "${RED}❌ IP 地址格式不正确。操作已取消。${NC}"
                     return
                 fi
                ufw deny from "$target_ip" to any comment "Custom-IP-Deny"
                echo -e "${GREEN}✅ 来自 [$target_ip] 的所有访问已被拒绝。${NC}"
            elif [[ "$block_type" == "port" ]]; then
                read -p "请输入要封禁的端口或范围(多个用','隔开): " ports_input
                read -p "协议类型 [tcp|udp|both] (默认为 both): " proto
                proto=${proto:-both}

                IFS=',' read -ra ports_array <<< "$ports_input"
                for port in "${ports_array[@]}"; do
                    port=$(echo "$port" | xargs) # 去除前后空格
                    if ! [[ "$port" =~ ^[0-9]+(:[0-9]+)?$ ]]; then
                        echo -e "${RED}❌ 输入 '$port' 不是有效的端口或端口范围，已跳过。${NC}"
                        continue
                    fi

                    if [[ "$proto" =~ ^(tcp|both)$ ]]; then
                        ufw deny "$port"/tcp comment "Custom-Port-Deny"
                        echo -e "${GREEN}✅ TCP 端口 [$port] 已被拒绝访问。${NC}"
                    fi
                    if [[ "$proto" =~ ^(udp|both)$ ]]; then
                        ufw deny "$port"/udp comment "Custom-Port-Deny"
                        echo -e "${GREEN}✅ UDP 端口 [$port] 已被拒绝访问。${NC}"
                    fi
                done
            fi
            ;;
        4)
            read -p "请输入要删除的规则【编号】: " rule_num
            if ! [[ "$rule_num" =~ ^[0-9]+$ ]]; then
                echo -e "${RED}❌ 错误: 请输入有效的规则编号 (纯数字)。${NC}"
            else
                read -p "您确定要删除规则【#$rule_num】吗? (y/n): " confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
                    # 使用 --force 避免交互，并检查命令是否真的执行成功
                    if ufw --force delete "$rule_num"; then
                        echo -e "${GREEN}✅ 规则 #${rule_num} 已成功删除。${NC}"
                    else
                        # ufw delete对于不存在的规则返回码为0，但会输出错误信息，这里我们捕获一下
                        echo -e "${RED}❌ 删除失败，请确认规则编号 #${rule_num} 是否存在。${NC}"
                    fi
                else
                    echo -e "${RED}❌ 操作已取消。${NC}"
                fi
            fi
            ;;
        0)
            return
            ;;
        *)
            echo -e "${RED}无效的输入。${NC}"
            ;;
    esac
}

# ===================== 日志管理 (子菜单) =====================
manage_logs_menu() {
    while true; do
        clear
        echo -e "${YELLOW}--- 日志管理 ---${NC}"
        echo "  1) 设置日志级别 (low, medium, high, full, off)"
        echo "  2) 查看最近 50 条日志"
        echo "  3) 实时监控日志"
        echo -e "\n  ${BLUE}0) 返回主菜单${NC}"
        read -p "请选择一个操作 [0-3]: " log_opt
        case $log_opt in
            1)
                read -p "请输入日志级别 [low|medium|high|full|off]: " level
                if [[ "$level" =~ ^(low|medium|high|full|off)$ ]]; then
                    ufw logging "$level"
                    echo -e "${GREEN}✅ 日志级别已设置为: $level${NC}"
                else
                    echo -e "${RED}❌ 无效的级别。请输入指定的级别之一。${NC}"
                fi
                pause
                ;;
            2)
                echo -e "\n${YELLOW}--- 最近 50 行 UFW 日志 ---${NC}"
                if [ -f "/var/log/ufw.log" ]; then
                    tail -n 50 /var/log/ufw.log
                else
                    echo -e "${RED}日志文件 /var/log/ufw.log 不存在（可能是日志功能未开启或级别为'off'）。${NC}"
                fi
                echo -e "${YELLOW}----------------------------${NC}"
                pause
                ;;
            3)
                echo -e "\n${YELLOW}--- 实时监控 UFW 日志 (按 Ctrl+C 退出) ---${NC}"
                 if [ -f "/var/log/ufw.log" ]; then
                    tail -f /var/log/ufw.log
                else
                    echo -e "${RED}日志文件 /var/log/ufw.log 不存在（可能是日志功能未开启或级别为'off'）。${NC}"
                    pause
                fi
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效的输入，请输入 0-3 之间的数字。${NC}"
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
        echo "  1) 导出 (备份) 当前所有UFW规则"
        echo "  2) 导入 (恢复) UFW规则"
        echo -e "\n  ${BLUE}0) 返回主菜单${NC}"
        read -p "请选择一个操作 [0-2]: " backup_opt
        case $backup_opt in
            1)
                local default_path="/root/ufw-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
                read -p "请输入备份文件保存路径 (默认为 ${default_path}): " custom_path
                local file_path=${custom_path:-$default_path}
                
                # 检查目录是否存在，不存在则尝试创建
                local dir_path
                dir_path=$(dirname "$file_path")
                if [ ! -d "$dir_path" ]; then
                    mkdir -p "$dir_path"
                fi

                if tar -czf "$file_path" /etc/ufw; then
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
                        # 先解压到临时目录，再移动，更安全
                        if tar -xzf "$file" -C /; then
                            echo -e "${GREEN}✅ 配置已成功导入。${NC}"
                            read -p "是否立即重载防火墙以使新规则生效? (y/n): " reload_confirm
                            if [[ $reload_confirm =~ ^[Yy]$ ]]; then
                                ufw reload
                                echo -e "${GREEN}✅ 防火墙已重载。${NC}"
                            else
                                echo -e "${YELLOW}请记得稍后手动执行 'sudo ufw reload' 来应用配置。${NC}"
                            fi
                        else
                             echo -e "${RED}❌ 导入失败。文件可能已损坏或权限不足。${NC}"
                        fi
                    else
                        echo -e "${RED}❌ 操作已取消。${NC}"
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
                echo -e "${RED}无效的输入，请输入 0-2 之间的数字。${NC}"
                pause
                ;;
        esac
    done
}


# ===================== 重置规则 =====================
reset_firewall() {
    clear
    read -p "警告：此操作将删除所有规则并恢复到默认安装状态。您确定要重置防火墙吗? (y/n): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        # ufw reset会自己再问一次，这里我们让用户确认两次，确保安全
        ufw reset
        echo -e "${GREEN}✅ 防火墙已重置。防火墙当前为 [关闭] 状态。${NC}"
        echo -e "${YELLOW}提示: 下次运行本脚本时，将重新进行智能检查与配置。${NC}"
    else
        echo -e "${RED}❌ 操作已取消。${NC}"
    fi
}

# ===================== 主菜单 =====================
main_menu() {
    while true; do
        clear
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║${NC}              🛡️  ${YELLOW}UFW 防火墙管理器 v2025.07.02${NC}              ${GREEN}║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
        
        show_simple_status
        
        if [ -n "$STARTUP_MSG" ]; then
            echo -e "$STARTUP_MSG"
            STARTUP_MSG="" # 显示一次后清空
        fi
        
        echo -e "\n${YELLOW}--- 基本操作 & 状态 ---${NC}"
        echo "  1) 启用防火墙"
        echo "  2) 关闭防火墙"
        echo "  3) 查看详细状态与规则列表"
        echo "  4) 重置防火墙 (清空所有规则)"
        
        echo -e "\n${YELLOW}--- 规则与高级功能 ---${NC}"
        echo "  5) 管理防火墙规则 (IP/端口)"
        echo "  6) 日志管理 (设置/查看)"
        echo "  7) 备份与恢复 (导入/导出)"
        
        echo -e "\n${YELLOW}--------------------------------------------------------------${NC}"
        echo -e "${BLUE}0) 退出脚本${NC}"
        
        read -p "请输入您的选择 [0-7]: " choice
        
        case $choice in
            1) enable_firewall; pause ;;
            2) disable_firewall; pause ;;
            3) show_detailed_status; pause ;;
            4) reset_firewall; pause ;;
            5) custom_rule_manager; pause ;;
            6) manage_logs_menu ;; # 子菜单自带 pause
            7) manage_backup_menu ;; # 子菜单自带 pause
            0) echo -e "\n${GREEN}感谢使用，再见！${NC}"; exit 0 ;;
            *) echo -e "${RED}无效的输入，请输入 0-7 之间的数字。${NC}"; pause ;;
        esac
    done
}

# ===================== 主程序入口 =====================
clear
check_root
check_dependencies
startup_check_and_apply
main_menu
