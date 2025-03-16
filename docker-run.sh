#!/bin/bash
set -eo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
DOWNLOAD_URL="https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/docker.txt"

process_commands() {
    local content="$1"
    declare -a missing_containers

    # 提取容器名并检查状态
    while IFS= read -r line; do
        cmd=$(echo "$line" | xargs)
        [ -z "$cmd" ] && continue
        container_name=$(echo "$cmd" | sed -nE 's/.*--name[= ]([^ ]+).*/\1/p')
        [ -n "$container_name" ] && names+=("$container_name")
    done < <(echo "$content")

    # 去重后检查缺失容器
    for name in $(echo "${names[@]}" | tr ' ' '\n' | sort -u); do
        if ! docker ps -a --format "{{.Names}}" | grep -qx "$name"; then
            missing_containers+=("$name")
        fi
    done

    # 安装缺失容器
    if [ ${#missing_containers[@]} -gt 0 ]; then
        echo -e "${CYAN}以下容器将被安装：${NC}"
        printf "%s\n" "${missing_containers[@]}"
        while IFS= read -r line; do
            cmd=$(echo "$line" | xargs)
            container_name=$(echo "$cmd" | sed -nE 's/.*--name[= ]([^ ]+).*/\1/p')
            if [[ " ${missing_containers[@]} " =~ " $container_name " ]]; then
                echo -e "${CYAN}安装容器: $container_name${NC}"
                eval "$cmd" || { echo -e "安装失败: $cmd"; exit 1; }
            fi
        done < <(echo "$content")
    else
        echo -e "${YELLOW}所有容器已存在，无需操作${NC}"
    fi
}

main() {
    echo -e "${CYAN}开始下载并处理Docker命令...${NC}"
    local content
    if ! content=$(curl -sSfL --retry 3 "$DOWNLOAD_URL"); then
        echo -e "下载失败，请检查URL或网络连接" >&2
        exit 1
    fi
    process_commands "$content"
    echo -e "${GREEN}操作完成${NC}"
}

main
