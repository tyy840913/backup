#!/bin/bash

# 定义PVE的ISO/IMG存储目录
source_dir="/var/lib/vz/template/iso"

# 获取指定目录中的IMG/ISO文件
imgs=()
while IFS= read -r -d $'\0' file; do
    imgs+=("$file")
done < <(find "$source_dir" -maxdepth 1 -type f \( -iname "*.img" -o -iname "*.iso" \) -print0 2>/dev/null)

# 检查是否有IMG/ISO文件
if [ ${#imgs[@]} -eq 0 ]; then
    echo -e "\033[31m错误：未在 $source_dir 中找到任何IMG/ISO文件。\033[0m"
    exit 1
elif [ ${#imgs[@]} -eq 1 ]; then
    # 单个文件自动选择
    selected_img="${imgs[0]}"
    echo -e "\033[33m检测到唯一的镜像文件：\033[0m"
    echo -e "\033[33m$(basename "$selected_img")\n\033[0m"
else
    # 多个文件显示选择菜单
    echo -e "\033[33m发现多个镜像文件，请选择使用哪一个：\033[0m"
    for i in "${!imgs[@]}"; do
        printf "\033[33m%2d) %s\033[0m\n" $((i+1)) "$(basename "${imgs[$i]}")"
    done

    # 用户选择文件
    while true; do
        read -p "请输入要转换的文件编号： " file_num
        if [[ "$file_num" =~ ^[0-9]+$ ]] && [ "$file_num" -ge 1 ] && [ "$file_num" -le ${#imgs[@]} ]; then
            selected_img="${imgs[$((file_num-1))]}"
            break
        else
            echo "输入无效，请输入正确的编号。"
        fi
    done
fi

# 输入虚拟机ID
while true; do
    read -p "请输入目标虚拟机ID： " vmid
    if [[ "$vmid" =~ ^[0-9]+$ ]]; then
        break
    else
        echo "虚拟机ID必须是数字，请重新输入。"
    fi
done

# 输入存储名称（默认为local-lvm）
read -p "请输入存储名称 [默认 local-lvm]： " storage
storage=${storage:-local-lvm}

# 执行导入
echo -e "\033[33m正在导入磁盘，请稍候...\033[0m"
if qm importdisk "$vmid" "$selected_img" "$storage"; then
    echo -e "\n\033[32m导入成功！\033[0m"
    echo -e "\033[33m现在可以执行以下操作："
    echo "1. 在虚拟机硬件配置中挂载新磁盘"
    echo -e "2. 启动虚拟机检查磁盘\033[0m"
else
    echo -e "\n\033[31m导入失败，请检查："
    echo "- 虚拟机 $vmid 是否存在"
    echo "- 存储 $storage 是否可用"
    echo -e "- 文件权限是否正常\033[0m"
    exit 1
fi
