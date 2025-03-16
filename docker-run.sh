#!/bin/bash
set -eo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
DOWNLOAD_URL="https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/docker.txt"

process_commands() {
    local content="$1"
    local cmd container_name
    declare -a missing_containers names

    echo -e "${YELLOW}正在解析Docker命令并检查容器状态...${NC}"

    # 禁用通配符扩展，防止*被错误展开
    set -f

    # 提取容器名称
    while IFS= read -r line; do
        cmd=$(echo "$line" | xargs)
        [ -z "$cmd" ] && continue
        container_name=$(echo "$cmd" | sed -nE 's/.*--name[= ]([^ ]+).*/\1/p')
        [ -n "$container_name" ] && names+=("$container_name")
    done < <(echo "$content")

    # 恢复通配符扩展
    set +f

    # 检查容器是否存在
    for name in $(printf "%s\n" "${names[@]}" | sort -u); do
        if ! docker ps -a --format "{{.Names}}" | grep -qxF "$name"; then
            missing_containers+=("$name")
        fi
    done

    if [ ${#missing_containers[@]} -eq 0 ]; then
        echo -e "${YELLOW}所有容器已存在，无需操作${NC}"
        return
    fi

    echo -e "${CYAN}即将安装以下容器：${NC}"
    printf "%s\n" "${missing_containers[@]}"
    echo "----------------------------------"

    # 执行安装命令
    set -f  # 再次禁用通配符扩展
    while IFS= read -r line; do
        cmd=$(echo "$line" | xargs)
        [ -z "$cmd" ] && continue
        container_name=$(echo "$cmd" | sed -nE 's/.*--name[= ]([^ ]+).*/\1/p')
        if [[ " ${missing_containers[@]} " =~ " $container_name " ]]; then
            echo -e "${CYAN}启动容器: $container_name${NC}"
            if eval "$cmd"; then
                echo -e "${GREEN}成功${NC}"
            else
                echo -e "错误：启动失败，命令：$cmd" >&2
                exit 1
            fi
            echo "----------------------------------"
        fi
    done < <(echo "$content")
    set +f
}

main() {
    echo -e "${CYAN}开始下载Docker命令配置文件...${NC}"
    local content
    if ! content=$(curl -sSfL --retry 3 "$DOWNLOAD_URL"); then
        echo -e "下载失败，请检查URL或网络连接" >&2
        exit 1
    fi
    process_commands "$content"
    echo -e "${GREEN}所有容器已处理完毕${NC}"
}

main
