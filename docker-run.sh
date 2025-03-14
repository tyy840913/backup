#!/bin/bash

DOWNLOAD_URL="https://add.woskee.nyc.mn/raw.githubusercontent.com/tyy840913/backup/main/docker.txt"
TEMP_FILE=$(mktemp)
LOG_FILE="/var/log/docker-setup.log"

# 日志记录函数
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# 容器名提取函数（兼容所有格式）
extract_container_name() {
    local cmd="$1"
    local name=""
    
    # 分解命令为数组
    IFS=' ' read -ra parts <<< "$cmd"
    
    # 遍历参数查找--name
    for ((i=0; i<${#parts[@]}; i++)); do
        if [[ "${parts[i]}" =~ ^--name(=|$) ]]; then
            # 处理--name=container格式
            name="${parts[i]#*=}"
            [ -z "$name" ] && name="${parts[i+1]}" # 处理--name container格式
            break
        elif [ "${parts[i]}" = "--name" ] && [ $((i+1)) -lt ${#parts[@]} ]; then
            # 处理--name container格式
            name="${parts[i+1]}"
            break
        fi
    done
    
    echo "$name"
}

process_command() {
    local cmd="$1"
    local container_name=$(extract_container_name "$cmd")
    
    [ -z "$container_name" ] && {
        log "错误：无法提取容器名，原始命令: $cmd"
        return 1
    }

    log "处理容器: $container_name"
    
    # 容器存在检查
    if docker ps -a --format '{{.Names}}' | grep -qw "$container_name"; then
        log "发现已存在的容器 [$container_name]"
        read -p "是否重新安装 [$container_name]？[y/N] " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log "开始删除容器 [$container_name]..."
            docker rm -f "$container_name" >/dev/null 2>&1 || {
                log "删除容器失败 [$container_name]"
                return 2
            }
            
            # 获取并删除关联镜像
            local image_name=$(docker inspect --format='{{.Config.Image}}' "$container_name" 2>/dev/null | cut -d':' -f1)
            [ -n "$image_name" ] && {
                log "删除关联镜像 [$image_name]..."
                docker rmi -f "$image_name" >/dev/null 2>&1 || log "镜像删除失败（可能被其他容器使用）"
            }
        else
            log "用户选择跳过 [$container_name]"
            return 0
        fi
    fi
    
    # 执行Docker命令
    log "启动容器 [$container_name]..."
    if ! eval "$cmd"; then
        log "启动失败 [$container_name]"
        return 3
    fi
}

main() {
    log "开始下载配置..."
    if ! curl -sSLf "$DOWNLOAD_URL" -o "$TEMP_FILE"; then
        log "错误：文件下载失败！"
        exit 1
    fi

    while IFS= read -r line; do
        line=$(echo "$line" | sed -e 's/#.*//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [ -z "$line" ] && continue
        
        process_command "$line"
        local ret=$?
        
        case $ret in
            0) log "状态：成功执行" ;;
            1) log "状态：跳过（无法提取容器名）" ;;
            2) log "状态：错误（容器删除失败）" ;;
            3) log "状态：错误（容器启动失败）" ;;
        esac
    done < "$TEMP_FILE"

    rm -f "$TEMP_FILE"
    log "所有操作完成，日志见 $LOG_FILE"
}

main
