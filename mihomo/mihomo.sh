#!/bin/bash

# 脚本：合并Clash配置文件并重启mihomo容器
# 功能：从三个链接获取配置部分并合并成完整配置，然后重启mihomo容器

# 定义输出文件
output_file="config.yaml"

# 临时文件
part1_temp="part1.yaml"
part2_temp="part2.yaml"
part3_temp="part3.yaml"

# 颜色输出函数
red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }

# 清理函数
cleanup() {
    rm -f "$part1_temp" "$part2_temp" "$part3_temp"
    green "临时文件已清理"
}

# 注册清理函数
trap cleanup EXIT

# 重启mihomo容器
restart_mihomo() {
    yellow "正在重启mihomo容器..."
    
    if docker restart mihomo; then
        green "✓ mihomo容器重启成功！"
    else
        red "✗ mihomo容器重启失败"
        return 1
    fi
}

# 下载函数
download_config() {
    local url=$1
    local output=$2
    local part_name=$3
    
    yellow "正在下载 $part_name..."
    
    if command -v curl &> /dev/null; then
        if curl -s -L --connect-timeout 30 "$url" -o "$output"; then
            green "✓ $part_name 下载成功"
            return 0
        fi
    elif command -v wget &> /dev/null; then
        if wget -q -T 30 -O "$output" "$url"; then
            green "✓ $part_name 下载成功"
            return 0
        fi
    else
        red "错误：未找到curl或wget"
        return 1
    fi
    
    red "✗ $part_name 下载失败"
    return 1
}

# 处理第二部分（只提取proxies:部分）
process_part2() {
    yellow "处理第二部分配置（提取proxies部分）..."
    
    # 提取proxies:部分
    awk '
    BEGIN {in_proxies=0}
    /^proxies:/ {in_proxies=1; print; next}
    /^[a-zA-Z][a-zA-Z0-9_-]*:/ && !/^[[:space:]]/ && !/^proxies:/ {in_proxies=0}
    in_proxies {print}
    ' "$part2_temp" > "${part2_temp}.processed"
    
    mv "${part2_temp}.processed" "$part2_temp"
    green "✓ 第二部分处理完成"
}

# 合并配置文件
merge_configs() {
    yellow "开始合并配置文件..."
    
    # 清空输出文件
    > "$output_file"
    
    # 合并第一部分（全部内容）
    cat "$part1_temp" >> "$output_file"
    
    # 添加分隔注释
    echo "" >> "$output_file"
    echo "# ===== 代理节点配置 =====" >> "$output_file"
    echo "" >> "$output_file"
    
    # 合并第二部分（proxies部分）
    cat "$part2_temp" >> "$output_file"
    
    # 添加分隔注释
    echo "" >> "$output_file"
    echo "# ===== 代理组和规则配置 =====" >> "$output_file"
    echo "" >> "$output_file"
    
    # 合并第三部分（全部内容）
    cat "$part3_temp" >> "$output_file"
    
    green "✓ 配置文件合并完成"
}

# 主函数
main() {
    yellow "开始合并Clash配置文件..."
    echo ""
    
    # 下载三个部分的配置
    if ! download_config "https://cdn.woskee.dpdns.org/raw.githubusercontent.com/tyy840913/backup/refs/heads/main/mihomo/config.yaml" "$part1_temp" "第一部分配置"; then
        exit 1
    fi
    
    if ! download_config "https://sub.woskee.nyc.mn/auto?clash" "$part2_temp" "第二部分配置"; then
        exit 1
    fi
    
    if ! download_config "https://cdn.luxxk.qzz.io/raw.githubusercontent.com/tyy840913/backup/refs/heads/main/mihomo/ACL4SSR_Online_Full.yaml" "$part3_temp" "第三部分配置"; then
        exit 1
    fi
    
    echo ""
    
    # 处理第二部分（提取proxies部分）
    process_part2
    
    echo ""
    
    # 合并配置
    merge_configs
    
    echo ""
    green "🎉 配置文件合并成功！"
    green "📁 输出文件: $output_file"
    echo ""
    yellow "最终文件信息："
    echo "行数: $(wc -l < "$output_file")"
    echo "大小: $(du -h "$output_file" | cut -f1)"
    echo ""
    
    # 直接重启容器，不询问
    restart_mihomo
}

# 运行主函数
main
