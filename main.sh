#!/bin/bash

# 基础配置
original_url="https://raw.githubusercontent.com/tyy840913/backup/main"
proxy_url="https://route.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main"

# 检查是否设置了代理
if [ -n "$http_proxy" ] || [ -n "$https_proxy" ]; then
    echo -e "${COLOR_TITLE}检测到终端设置了代理，将直接使用GitHub地址。${COLOR_RESET}"
    base_url="$original_url"
else
    base_url="$proxy_url"
fi

memory_tmpdir="/dev/shm/script_platform_$$"  # 内存临时目录（使用PID保证唯一性）
catalog_file="${memory_tmpdir}/cata.txt"    # 内存中的目录文件
descriptions=()
filenames=()

# 颜色配置
COLOR_TITLE=$'\033[1;36m'
COLOR_OPTION=$'\033[1;33m'
COLOR_DIVIDER=$'\033[1;34m'
COLOR_INPUT=$'\033[1;35m'
COLOR_ERROR=$'\033[1;31m'
COLOR_RESET=$'\033[0m'

# 退出时清理函数
cleanup() {
    echo -e "\n${COLOR_TITLE}清理内存临时文件...${COLOR_RESET}"
    # 安全删除内存临时目录
    if [ -d "$memory_tmpdir" ]; then
        rm -rf "$memory_tmpdir" && echo "已清理内存目录: $memory_tmpdir"
    fi
}

# 注册退出清理钩子
trap cleanup EXIT INT TERM

# 初始化内存工作区
init_memory_space() {
    # 检查是否支持内存文件系统
    if [ ! -d "/dev/shm" ]; then
        echo -e "${COLOR_ERROR}错误：系统不支持内存临时文件系统(/dev/shm)！${COLOR_RESET}" >&2
        exit 1
    fi

    # 创建唯一临时目录
    if ! mkdir -p "$memory_tmpdir"; then
        echo -e "${COLOR_ERROR}无法创建内存临时目录！${COLOR_RESET}" >&2
        exit 1
    fi
    echo -e "${COLOR_TITLE}内存工作区已创建: ${memory_tmpdir}${COLOR_RESET}"
}

# 下载目录文件到内存
download_catalog() {
    if [ ! -f "$catalog_file" ]; then
        echo -e "${COLOR_TITLE}正在获取脚本目录到内存...${COLOR_RESET}"
        if ! curl -s "${base_url}/cata.txt" -o "$catalog_file"; then
            echo -e "${COLOR_ERROR}错误：目录文件下载失败！${COLOR_RESET}" >&2
            exit 1
        fi
    fi
}

# 解析目录文件
parse_catalog() {
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^*+$ ]]; then
            # 这是分割线
            descriptions+=("$line")
            filenames+=("")  # 空文件名表示这是分割线
        elif [[ "$line" =~ [[:space:]] ]]; then
            # 这是正常的脚本条目
            desc="${line% *}"
            file="${line##* }"
            descriptions+=("$desc")
            filenames+=("$file")
        fi
    done < "$catalog_file"
}

# 打印分割线
print_divider() {
    echo -e "${COLOR_DIVIDER}===============================================${COLOR_RESET}"
}

# 显示用户界面
show_interface() {
    clear
    # 显示标题
    echo -e "${COLOR_TITLE}"
    print_divider
    echo "             全内存脚本平台"
    print_divider
    echo -e "${COLOR_RESET}"

    # 显示菜单项
    for i in "${!descriptions[@]}"; do
        if [[ -z "${filenames[i]}" ]]; then
            # 显示分割线（彩色）
            echo ""
            echo -e "${COLOR_DIVIDER}${descriptions[i]}${COLOR_RESET}"
            echo ""
        else
            # 显示正常菜单项
            printf "${COLOR_OPTION}%2d.${COLOR_RESET} ${COLOR_TITLE}%-30s${COLOR_RESET}\n" \
                   $((i+1)) "${descriptions[i]}"
        fi
    done

    # 底部操作提示
    echo
    print_divider
    echo -en "${COLOR_INPUT}请输入序号选择脚本 (0 退出): ${COLOR_RESET}"
}

# 执行子脚本（完全内存操作）
run_script() {
    local index=$(($1 - 1))
    local script_url="${base_url}/${filenames[index]}"
    local tmp_script="${memory_tmpdir}/${filenames[index]##*/}"  # 内存临时脚本
    
    echo -e "\n${COLOR_TITLE}正在获取 ${COLOR_OPTION}${filenames[index]}${COLOR_RESET}"
    if curl -s "$script_url" -o "$tmp_script"; then
        chmod +x "$tmp_script"
        
        # 定义一个函数用于处理换行符，避免代码重复
        convert_newlines() {
            local script_path=$1
            if grep -q $'\r' "$script_path"; then
                echo -e "${COLOR_TITLE}检测到Windows风格换行符，正在转换为Unix风格...${COLOR_RESET}"
                # 使用sed原地替换，删除所有回车符
                sed -i 's/\r//g' "$script_path"
                if [ $? -eq 0 ]; then
                    echo -e "${COLOR_TITLE}换行符转换成功。${COLOR_RESET}"
                else
                    echo -e "${COLOR_ERROR}换行符转换失败，尝试继续执行，但可能存在兼容性问题。${COLOR_RESET}"
                fi
            fi
        }

        # 根据后缀选择执行方式
        case "${filenames[index]##*.}" in
            sh) 
                convert_newlines "$tmp_script"
                bash "$tmp_script" 
                ;;
            py) 
                convert_newlines "$tmp_script"
                # 检查Python3是否安装
                if ! command -v python3 &> /dev/null; then
                    echo -e "${COLOR_ERROR}脚本需要Python3运行，但未检测到Python3。${COLOR_RESET}"
                    echo -en "${COLOR_INPUT}是否自动安装Python3？[Y/n]: ${COLOR_RESET}"
                    read -r answer
                    case "$answer" in
                        [Nn]*)
                            echo -e "${COLOR_ERROR}用户取消安装，返回主界面。${COLOR_RESET}"
                            return 1
                            ;;
                        *)
                            echo "正在尝试安装Python3..."
                            local install_cmd_prefix=""

                            if [ "$(id -u)" -ne 0 ]; then
                                if command -v sudo &> /dev/null; then
                                    install_cmd_prefix="sudo "
                                    echo -e "${COLOR_TITLE}检测到非root用户，将尝试使用 sudo 进行安装。${COLOR_RESET}"
                                else
                                    echo -e "${COLOR_ERROR}警告：当前用户不是root，且未检测到 'sudo' 命令。${COLOR_RESET}"
                                    echo -e "${COLOR_ERROR}无法自动安装Python3，请手动安装后重试。${COLOR_RESET}"
                                    return 1
                                fi
                            else
                                echo -e "${COLOR_TITLE}检测到root用户，将直接进行安装。${COLOR_RESET}"
                            fi

                            if command -v apt &> /dev/null; then
                                ${install_cmd_prefix}apt update && ${install_cmd_prefix}apt install -y python3 || {
                                    echo -e "${COLOR_ERROR}安装失败，请检查网络或权限。${COLOR_RESET}"
                                    return 1
                                }
                            elif command -v yum &> /dev/null; then
                                ${install_cmd_prefix}yum install -y python3 || {
                                    echo -e "${COLOR_ERROR}安装失败，请检查网络或权限。${COLOR_RESET}"
                                    return 1
                                }
                            elif command -v dnf &> /dev/null; then
                                ${install_cmd_prefix}dnf install -y python3 || {
                                    echo -e "${COLOR_ERROR}安装失败，请检查网络或权限。${COLOR_RESET}"
                                    return 1
                                }
                            elif command -v zypper &> /dev/null; then
                                ${install_cmd_prefix}zypper install -y python3 || {
                                    echo -e "${COLOR_ERROR}安装失败，请检查网络或权限。${COLOR_RESET}"
                                    return 1
                                }
                            else
                                echo -e "${COLOR_ERROR}无法检测到支持的包管理器 (apt, yum, dnf, zypper)，请手动安装Python3。${COLOR_RESET}"
                                return 1
                            fi
                            
                            if ! command -v python3 &> /dev/null; then
                                echo -e "${COLOR_ERROR}Python3安装失败，请手动安装。${COLOR_RESET}"
                                return 1
                            else
                                echo -e "${COLOR_TITLE}Python3安装成功！${COLOR_RESET}"
                            fi
                            ;;
                    esac
                fi
                python3 "$tmp_script"
                ;;
            *)  
                echo -e "${COLOR_ERROR}不支持的脚本格式！${COLOR_RESET}"
                ;;
        esac
    else
        echo -e "${COLOR_ERROR}脚本下载失败！${COLOR_RESET}"
    fi
    
    echo -e "\n${COLOR_DIVIDER}═══════════════ 操作完成 ═══════════════${COLOR_RESET}"
}

# 主程序
init_memory_space
download_catalog
parse_catalog

# 主循环
while true; do
    show_interface
    
    # 输入验证
    while :; do
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            if ((choice == 0)); then
                echo -e "\n${COLOR_TITLE}感谢使用，再见！${COLOR_RESET}"
                exit 0
            elif ((choice > 0 && choice <= ${#descriptions[@]})); then
                break
            fi
        fi
        echo -en "\033[1A\033[K${COLOR_ERROR}无效输入，请重新输入: ${COLOR_RESET}"
    done

    run_script "$choice"
    read -rp "按回车键继续..."
done
