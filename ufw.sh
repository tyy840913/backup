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
#   最终版本：2025.07.03 - 再次修正 Q 键退出问题
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
        # 恢复为更精确的 grep 判断，确保只匹配 ALLOW 规则
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

# 带有 Q/q 返回功能的输入函数
# 返回 0 表示成功输入，返回 1 表示用户输入 Q
prompt_for_input() {
    local prompt_msg="$1"
    local __result_var="$2" # Variable to store the result
    local input_val=""
    
    read -p "${prompt_msg} (输入 Q 返回): " input_val
    input_val=$(echo "$input_val" | xargs) # Trim whitespace

    if [[ "$input_val" =~ ^[Qq]$ ]]; then
        eval "$__result_var=\"\"" # Clear the variable
        return 1 # Indicate that user chose to return
    else
        eval "$__result_var=\"$input_val\"" # Store actual input
        return 0 # Indicate success
    fi
}

# 处理多个端口的函数
process_ports() {
    local ports_input=$1
    local action=$2 # allow or deny
    local proto=$3
    local ip=$4 # For IP based rules

    # 使用空格作为分隔符
    read -ra ADDR <<< "$ports_input"
    local success_count=0
    local fail_count=0
    local success_msg=""
    local fail_msg=""

    for p in "${ADDR[@]}"; do
        p=$(echo "$p" | xargs) # Trim whitespace
        if [ -z "$p" ]; then
            continue
        fi

        # 校验端口格式
        if ! [[ "$p" =~ ^[0-9]+(-[0-9]+)?$ ]]; then
            fail_count=$((fail_count + 1))
            fail_msg+="无效端口格式 [${p}]。请检查并重新输入。\n"
            continue # 跳过当前无效端口，继续处理下一个
        fi

        local current_success=true
        if [[ "$action" == "allow" ]]; then
            if [ -n "$ip" ]; then # 针对 IP + 端口的允许规则
                if [[ "$proto" =~ ^(tcp|both)$ ]]; then
                    if ufw allow proto tcp from "$ip" to any port "$p" comment "自定义-IP-端口放行"; then
                        success_msg+="TCP: 已允许来自 [${ip}] 访问端口 [${p}]。\n"
                    else
                        current_success=false
                    fi
                fi
                if [[ "$proto" =~ ^(udp|both)$ ]]; then
                    if ufw allow proto udp from "$ip" to any port "$p" comment "自定义-IP-端口放行"; then
                        success_msg+="UDP: 已允许来自 [${ip}] 访问端口 [${p}]。\n"
                    else
                        current_success=false
                    fi
                fi
            else # 针对只开放端口的允许规则
                if [[ "$proto" =~ ^(tcp|both)$ ]]; then
                    if ufw allow "$p"/tcp comment "自定义-TCP-端口放行"; then
                        success_msg+="TCP 端口 [${p}] 已开放。\n"
                    else
                        current_success=false
                    fi
                fi
                if [[ "$proto" =~ ^(udp|both)$ ]]; then
                    if ufw allow "$p"/udp comment "自定义-UDP-端口放行"; then
                        success_msg+="UDP 端口 [${p}] 已开放。\n"
                    else
                        current_success=false
                    fi
                fi
            fi
        elif [[ "$action" == "deny" ]]; then
            if [[ "$proto" =~ ^(tcp|both)$ ]]; then
                if ufw deny "$p"/tcp comment "自定义-端口封禁"; then
                    success_msg+="TCP 端口 [${p}] 已封禁。\n"
                else
                    current_success=false
                fi
            fi
            if [[ "$proto" =~ ^(udp|both)$ ]]; then
                if ufw deny "$p"/udp comment "自定义-端口封禁"; then
                    success_msg+="UDP 端口 [${p}] 已封禁。\n"
                else
                    current_success=false
                fi
                fi
        fi

        if [ "$current_success" = true ]; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
            fail_msg+="操作端口 [${p}] 失败。\n"
        fi
    done

    if [ "$success_count" -gt 0 ]; then
        echo -e "${GREEN}${success_msg}${NC}"
    fi
    if [ "$fail_count" -gt 0 ]; then
        echo -e "${RED}❌ 以下操作未能成功：\n${fail_msg}${NC}"
    fi
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
        echo -e "${YELLOW}⚠️ 防火墙已经是 [启用] 状态，无需重复操作。${NC}"
    else
        read -p "您确定要启用防火墙吗? (y/n): " confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            if ! ufw status | grep -q '22/tcp.*ALLOW'; then
                echo -e "${YELLOW}⚠️ 为防止失联，将自动放行 SSH (22/tcp) 端口...${NC}"
                ufw allow 22/tcp comment "紧急-SSH-启用"
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
        echo -e "\n${YELLOW}自定义访问规则管理:${NC}"
        echo "  1) 允许特定 IP/IP段 访问 (可指定端口)"
        echo "  2) 开放端口 (可指定范围，支持空格分隔多个端口)"
        echo "  3) 封禁/拒绝 IP 或 端口 (支持空格分隔多个端口)"
        echo "  4) 删除规则 (输入编号)"
        echo -e "\n  0) 返回主菜单"
        read -p "请选择一个操作 [0-4]: " opt
        
        case $opt in
            1) # 允许特定 IP/IP段 访问
                local ip=""
                while true; do
                    if ! prompt_for_input "请输入要允许的 IP 地址或 IP 段" ip; then 
                        # 用户输入 Q，跳出当前输入循环，并继续到 custom_rule_manager 的下一次迭代
                        break 
                    fi
                    if [ -n "$ip" ]; then break; fi
                    echo -e "${RED}⚠️ IP 地址不能为空，请重新输入。${NC}"
                done
                if [ -z "$ip" ]; then continue; fi # 如果 ip 为空 (用户按 Q)，则跳过当前 case

                local ports=""
                if ! prompt_for_input "请输入端口 (留空为所有端口，支持空格分隔多个端口)" ports; then 
                    # 用户输入 Q，跳出当前输入循环，并继续到 custom_rule_manager 的下一次迭代
                    continue 
                fi

                local proto_input=""
                local proto="both" # Default protocol
                while true; do
                    if ! prompt_for_input "请输入协议 [tcp|udp|both] (默认为 both)" proto_input; then 
                        # 用户输入 Q，跳出当前输入循环，并继续到 custom_rule_manager 的下一次迭代
                        continue 
                    fi
                    if [ -z "$proto_input" ]; then
                        proto="both"
                        break
                    elif [[ "$proto_input" =~ ^(tcp|udp|both)$ ]]; then
                        proto="$proto_input"
                        break
                    else
                        echo -e "${RED}⚠️ 无效的协议类型，请重新输入。${NC}"
                    fi
                done
                
                if [ -z "$ports" ]; then
                    ufw allow from "$ip" comment "自定义-IP-放行"
                    echo -e "${GREEN}✅ 已添加规则：允许来自 [${ip}] 的所有协议访问。${NC}"
                else
                    process_ports "$ports" "allow" "$proto" "$ip"
                fi
                pause
                ;;
            2) # 开放端口
                local ports=""
                while true; do
                    if ! prompt_for_input "请输入要开放的端口或端口范围 (支持空格分隔多个端口，例如: 80 443 8000-8005)" ports; then 
                        # 用户输入 Q，跳出当前输入循环，并继续到 custom_rule_manager 的下一次迭代
                        break 
                    fi
                    if [ -n "$ports" ]; then break; fi
                    echo -e "${RED}⚠️ 端口不能为空，请重新输入。${NC}"
                done
                if [ -z "$ports" ]; then continue; fi # 如果 ports 为空 (用户按 Q)，则跳过当前 case

                local proto_input=""
                local proto="both"
                while true; do
                    if ! prompt_for_input "请输入协议 [tcp|udp|both] (默认为 both)" proto_input; then 
                        # 用户输入 Q，跳出当前输入循环，并继续到 custom_rule_manager 的下一次迭代
                        continue 
                    fi
                    if [ -z "$proto_input" ]; then
                        proto="both"
                        break
                    elif [[ "$proto_input" =~ ^(tcp|udp|both)$ ]]; then
                        proto="$proto_input"
                        break
                    else
                        echo -e "${RED}⚠️ 无效的协议类型，请重新输入。${NC}"
                    fi
                done

                process_ports "$ports" "allow" "$proto"
                pause
                ;;
            3) # 封禁/拒绝 IP 或 端口
                local block_type=""
                while true; do
                    if ! prompt_for_input "您想封禁 IP 还是端口? [ip/port]" block_type; then 
                        # 用户输入 Q，跳出当前输入循环，并继续到 custom_rule_manager 的下一次迭代
                        break 
                    fi

                    block_type=$(echo "$block_type" | tr '[:upper:]' '[:lower:]') # 转为小写
                    if [[ "$block_type" == "ip" || "$block_type" == "port" ]]; then
                        break
                    else
                        echo -e "${RED}⚠️ 无效的选择，请输入 'ip' 或 'port'。${NC}"
                    fi
                done
                if [ -z "$block_type" ]; then continue; fi # 如果 block_type 为空 (用户按 Q)，则跳过当前 case

                if [[ "$block_type" == "ip" ]]; then
                    local target_ip=""
                    while true; do
                        if ! prompt_for_input "请输入要封禁的 IP 地址" target_ip; then 
                            # 用户输入 Q，跳出当前输入循环，并继续到 custom_rule_manager 的下一次迭代
                            continue 2 
                        fi
                        if [ -n "$target_ip" ]; then break; fi
                        echo -e "${RED}⚠️ IP 地址不能为空，请重新输入。${NC}"
                    done
                    if [ -z "$target_ip" ]; then continue; fi # 如果 target_ip 为空 (用户按 Q)，则跳过当前 if
                    ufw deny from "$target_ip" to any comment "自定义-IP-封禁"
                    echo -e "${GREEN}✅ 来自 [${target_ip}] 的所有访问已被封禁。${NC}"
                elif [[ "$block_type" == "port" ]]; then
                    local target_ports=""
                    while true; do
                        if ! prompt_for_input "请输入要封禁的端口或范围 (支持空格分隔多个端口，例如: 21 23 3389)" target_ports; then 
                            # 用户输入 Q，跳出当前输入循环，并继续到 custom_rule_manager 的下一次迭代
                            continue 2 
                        fi
                        if [ -n "$target_ports" ]; then break; fi
                        echo -e "${RED}⚠️ 端口不能为空，请重新输入。${NC}"
                    done
                    if [ -z "$target_ports" ]; then continue; fi # 如果 target_ports 为空 (用户按 Q)，则跳过当前 if

                    local proto_input=""
                    local proto="both"
                    while true; do
                        if ! prompt_for_input "协议类型 [tcp|udp|both] (默认为 both)" proto_input; then 
                            # 用户输入 Q，跳出当前输入循环，并继续到 custom_rule_manager 的下一次迭代
                            continue 3 
                        fi
                        if [ -z "$proto_input" ]; then
                            proto="both"
                            break
                        elif [[ "$proto_input" =~ ^(tcp|udp|both)$ ]]; then
                            proto="$proto_input"
                            break
                        else
                            echo -e "${RED}⚠️ 无效的协议类型，请重新输入。${NC}"
                        fi
                    done
                    process_ports "$target_ports" "deny" "$proto"
                fi
                pause
                ;;
            4) # 删除规则
                local rule_num=""
                while true; do
                    if ! prompt_for_input "请输入要删除的规则【编号】" rule_num; then 
                        # 用户输入 Q，跳出当前输入循环，并继续到 custom_rule_manager 的下一次迭代
                        continue 2 
                    fi
                    if [[ "$rule_num" =~ ^[0-9]+$ ]]; then # 确保是纯数字
                        break
                    else
                        echo -e "${RED}❌ 错误: 请输入有效的规则编号 (纯数字)。${NC}"
                    fi
                done
                if [ -z "$rule_num" ]; then continue; fi # 如果 rule_num 为空 (用户按 Q)，则跳过当前 case
                
                read -p "您确定要删除规则【#${rule_num}】吗? (y/n): " confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
                    ufw --force delete "$rule_num"
                    echo -e "${GREEN}✅ 规则 #${rule_num} 已成功删除。${NC}"
                else
                    echo -e "${RED}❌ 操作已取消。${NC}"
                fi
                pause
                ;;
            0) # 返回主菜单
                return
                ;;
            *)
                echo -e "${RED}无效的输入。${NC}"
                pause
                ;;
        esac
    done
}

# ===================== 日志管理 (子菜单) =====================
manage_logs_menu() {
    while true; do
        clear
        echo -e "${YELLOW}--- 日志管理 ---${NC}"
        echo "  1) 设置日志级别 (低, 中, 高, 完整, 关闭)"
        echo "  2) 查看最近 50 条日志"
        echo "  3) 实时监控日志"
        echo -e "\n  0) 返回主菜单"
        read -p "请选择一个操作 [0-3]: " log_opt
        case $log_opt in
            1)
                local level_choice=""
                local level=""
                while true; do
                    echo -e "请选择日志级别："
                    echo "  1) 低 (low)"
                    echo "  2) 中 (medium)"
                    echo "  3) 高 (high)"
                    echo "  4) 完整 (full)"
                    echo "  5) 关闭 (off)"
                    read -p "请输入选项 [1-5] (输入 Q 返回): " level_choice
                    level_choice=$(echo "$level_choice" | xargs | tr '[:upper:]' '[:lower:]')
                    
                    if [[ "$level_choice" =~ ^[Qq]$ ]]; then 
                        break # 用户输入 Q 返回日志管理菜单的 top-level while
                    fi
                    
                    case "$level_choice" in
                        1) level="low"; break ;;
                        2) level="medium"; break ;;
                        3) level="high"; break ;;
                        4) level="full"; break ;;
                        5) level="off"; break ;;
                        *) echo -e "${RED}❌ 无效的级别选择，请重新输入。${NC}" ;;
                    esac
                done
                if [ -z "$level" ]; then continue; fi # 如果 level 为空 (用户按 Q)，则跳过当前 case

                ufw logging "$level"
                echo -e "${GREEN}✅ 日志级别已设置为: $(echo $level | sed 's/low/低/;s/medium/中/;s/high/高/;s/full/完整/;s/off/关闭/')${NC}"
                pause
                ;;
            2)
                echo -e "\n${YELLOW}--- 最近 50 行 UFW 日志 ---${NC}"
                if [ -f "/var/log/ufw.log" ]; then
                    tail -n 50 /var/log/ufw.log
                else
                    echo -e "${RED}日志文件 /var/log/ufw.log 不存在（可能是日志功能未开启）。${NC}"
                fi
                echo -e "${YELLOW}----------------------------${NC}"
                pause
                ;;
            3)
                echo -e "\n${YELLOW}--- 实时监控 UFW 日志 (按 Ctrl+C 退出) ---${NC}"
                 if [ -f "/var/log/ufw.log" ]; then
                    tail -f /var/log/ufw.log
                else
                    echo -e "${RED}日志文件 /var/log/ufw.log 不存在（可能是日志功能未开启）。${NC}"
                    pause
                fi
                ;;
            0) # 返回主菜单
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
        echo "  1) 导出 (备份) 当前所有UFW规则"
        echo "  2) 导入 (恢复) UFW规则"
        echo "  0) 返回主菜单"
        read -p "请选择一个操作 [0-2]: " backup_opt
        case $backup_opt in
            1)
                local file_path="/root/ufw-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
                local custom_path=""
                if ! prompt_for_input "请输入备份文件保存路径 (默认为 ${file_path})" custom_path; then 
                    # 用户输入 Q，跳出当前输入循环，并继续到 manage_backup_menu 的下一次迭代
                    continue 
                fi
                file_path=${custom_path:-$file_path} # 如果用户输入为空，则使用默认路径
                
                if tar -czf "$file_path" /etc/ufw; then
                    echo -e "${GREEN}✅ 规则已成功导出到: $file_path${NC}"
                else
                    echo -e "${RED}❌ 导出失败。请检查路径和权限。${NC}"
                fi
                pause
                ;;
            2)
                local file=""
                while true; do
                    if ! prompt_for_input "请输入要导入的备份文件路径" file; then 
                        # 用户输入 Q，跳出当前输入循环，并继续到 manage_backup_menu 的下一次迭代
                        break 
                    fi
                    if [ -f "$file" ]; then break; fi
                    echo -e "${RED}❌ 文件 '$file' 不存在。请重新输入。${NC}"
                done
                if [ -z "$file" ]; then continue; fi # 如果 file 为空 (用户按 Q)，则跳过当前 case
                
                read -p "警告：这将覆盖所有现有规则，是否继续? (y/n): " confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
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
                pause
                ;;
            0) # 返回主菜单
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
    read -p "警告：此操作将删除所有规则并恢复到默认安装状态。您确定要重置防火墙吗? (y/n): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        ufw reset
        echo -e "${GREEN}✅ 防火墙已重置。防火墙当前为 [关闭] 状态。${NC}"
        echo -e "${YELLOW}下次运行脚本时，将重新进行智能检查与配置。${NC}"
    else
        echo -e "${RED}❌ 操作已取消。${NC}"
    fi
}

# ===================== 主菜单 =====================
main_menu() {
    while true; do
        clear
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║${NC}              🛡️  ${YELLOW}UFW 防火墙管理器 v2025.07.03${NC}              ${GREEN}║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
        
        show_simple_status
        
        if [ -n "$STARTUP_MSG" ]; then
            echo -e "$STARTUP_MSG"
            STARTUP_MSG=""
        fi
        
        echo -e "\n${YELLOW}--- 基本操作与状态 ---${NC}"
        echo "  1) 启用防火墙"
        echo "  2) 关闭防火墙"
        echo "  3) 查看详细状态与规则列表"
        echo "  4) 重置防火墙 (清空所有规则)"
        
        echo -e "\n${YELLOW}--- 规则与高级功能 ---${NC}"
        echo "  5) 管理防火墙规则 (IP/端口)"
        echo "  6) 日志管理 (设置/查看)"
        echo "  7) 备份与恢复 (导入/导出)"
        
        echo -e "\n${YELLOW}--------------------------------------------------------------${NC}"
        echo "  0) 退出脚本"
        
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
