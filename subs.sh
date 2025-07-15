#!/bin/bash
# 当任何命令失败时立即退出
set -e

# --- 模式与日志配置 ---
# 根据第一个参数设置模式，默认为 manual
MODE=${1:-manual}

# 定义日志函数，只在手动模式下输出
log_info() {
    if [ "$MODE" = "manual" ]; then
        echo "INFO: $@"
    fi
}

# --- 定时任务管理 ---
# 只在手动模式下检查和设置定时任务
if [ "$MODE" = "manual" ]; then
    log_info "检查定时任务设置..."
    # 获取脚本自己的绝对路径
    SCRIPT_PATH=$(realpath "$0")
    CRON_COMMENT="# subs.sh auto-update"
    # 每小时执行一次
    CRON_SCHEDULE="0 2 * * *"
    CRON_COMMAND="$CRON_SCHEDULE $SCRIPT_PATH auto > /dev/null 2>&1"
    CRON_JOB_ENTRY="$CRON_COMMAND $CRON_COMMENT"

    # 检查定时任务是否已存在
    if ! crontab -l 2>/dev/null | grep -Fq "$CRON_COMMENT"; then
        log_info "定时任务不存在，正在添加..."
        # 使用子 shell 添加任务，能兼容没有 crontab 的情况
        (crontab -l 2>/dev/null; echo "$CRON_JOB_ENTRY") | crontab -
        log_info "定时任务已添加: $CRON_JOB_ENTRY"
    else
        log_info "定时任务已存在。"
    fi
fi


# --- 配置 ---
REMOTE_CONFIG_URL="https://raw.githubusercontent.com/beck-8/subs-check/refs/heads/master/config/config.example.yaml"
LOCAL_CONFIG_PATH="/docker_data/subs/config.yaml"
FALLBACK_PROXY_URL="https://route.luxxk.dpdns.org/"

# --- 初始化 ---
log_info "初始化脚本..."
# 优先使用 /dev/shm (内存支持的目录) 以提高性能
if [ -d "/dev/shm" ] && [ -w "/dev/shm" ]; then
  TEMP_DIR=$(mktemp -d -p "/dev/shm")
else
  TEMP_DIR=$(mktemp -d)
fi
# 设置一个陷阱，在脚本退出时自动清理临时目录
trap 'log_info "正在清理临时文件..."; rm -rf "$TEMP_DIR"' EXIT

log_info "临时目录位于 $TEMP_DIR"
REMOTE_FILE="$TEMP_DIR/remote.yaml"
LOCAL_FILE_COPY="$TEMP_DIR/local.yaml"
MERGED_FILE="$TEMP_DIR/merged.yaml"
FINAL_FILE="$TEMP_DIR/final.yaml"

# --- 代理检查 ---
CURL_PROXY_PARAM=""
if [ -n "$https_proxy" ]; then
    CURL_PROXY_PARAM="--proxy $https_proxy"
    log_info "检测到系统代理 (https_proxy): $https_proxy"
elif [ -n "$HTTPS_PROXY" ]; then
    CURL_PROXY_PARAM="--proxy $HTTPS_PROXY"
    log_info "检测到系统代理 (HTTPS_PROXY): $HTTPS_PROXY"
else
    CURL_PROXY_PARAM="--proxy $FALLBACK_PROXY_URL"
    log_info "未检测到系统代理，使用备用代理: $FALLBACK_PROXY_URL"
fi

# --- 主逻辑 ---

# 1. 准备本地配置文件
if [ -f "$LOCAL_CONFIG_PATH" ]; then
    log_info "发现本地配置，将用于合并。"
    cp "$LOCAL_CONFIG_PATH" "$LOCAL_FILE_COPY"
else
    log_info "WARN: 本地配置文件 '$LOCAL_CONFIG_PATH' 不存在，将仅使用远程配置。"
    # 创建一个空的本地副本，以避免后续命令失败
    touch "$LOCAL_FILE_COPY"
fi

# 2. 下载远程配置
log_info "正在从 $REMOTE_CONFIG_URL 下载远程配置..."
if ! curl -sL --retry 3 --retry-delay 5 -m 20 $CURL_PROXY_PARAM "$REMOTE_CONFIG_URL" -o "$REMOTE_FILE"; then
    echo "ERROR: 下载远程配置失败。请检查网络或代理设置。" >&2
    exit 1
fi
log_info "远程配置已下载。"

# 3. 合并 sub-urls
log_info "正在合并 'sub-urls'..."
awk_script_urls=$(cat <<'EOF'
BEGIN { in_urls_block = 0 }
/^sub-urls:/ { in_urls_block = 1; next }
in_urls_block && /^\s*-/ {
    url = $0;
    sub(/^\s*-\s*[\x27"]?/, "", url);
    sub(/[\x27"]?\s*$/, "", url);
    if (url) print url;
}
in_urls_block && !/^\s*-/ { in_urls_block = 0 }
EOF
)
log_info "[DEBUG] Step 3: awk_script_urls variable defined."
( awk "$awk_script_urls" "$REMOTE_FILE" "$LOCAL_FILE_COPY" || true ) | sort -u > "$TEMP_DIR/unique_urls.txt"
log_info "[DEBUG] Step 3: awk | sort command finished. Status: $?"

# 4. 以远程文件为模板，替换 sub-urls 列表
log_info "正在将合并后的 'sub-urls' 列表注入模板..."
awk_script_template=$(cat <<'EOF'
BEGIN {
    if (system("test -s " unique_urls_file) == 0) {
        while ((getline url < unique_urls_file) > 0) {
          urls[NR] = "  - \"" url "\""
        }
        close(unique_urls_file)
    }
  }
  {
    if (in_urls_block && /^\s*-/) {
      next
    }
    if (in_urls_block && !/^\s*-/) {
      in_urls_block = 0
    }
    if (/^sub-urls:/) {
      print
      for (i=1; i<=length(urls); i++) {
        print urls[i]
      }
      in_urls_block = 1
    } else {
      print
    }
  }
EOF
)
log_info "[DEBUG] Step 4: awk_script_template variable defined."
awk -v unique_urls_file="$TEMP_DIR/unique_urls.txt" "$awk_script_template" "$REMOTE_FILE" > "$MERGED_FILE"
log_info "[DEBUG] Step 4: awk template injection finished. Status: $?"
log_info "'sub-urls' 注入完成。"

# 5. 使用本地值智能覆盖模板
log_info "正在使用本地值智能覆盖模板..."
awk_script_merge=$(cat <<'EOF'
FNR==NR {
    if (/^\s*#/ || /^\s*$/) { next }
    if (/^sub-urls:/) { in_block=1; next }
    if (in_block && /^\s*-/) { next }
    if (in_block && !/^\s*-/) { in_block=0; next }
    
    key = $1
    sub(/:$/, "", key)
    local_values[key] = $0
    next
  }
  {
    key = $1
    sub(/:$/, "", key)

    if (key in local_values) {
      print local_values[key]
      delete local_values[key]
    } else {
      print
    }
  }
  END {
    if (length(local_values) > 0) {
      cmd = "sort"
      print "" | cmd
      print "# --- 本地特有配置 ---" | cmd
      for (key in local_values) {
        print local_values[key] | cmd
      }
      close(cmd)
    }
  }
EOF
)
log_info "[DEBUG] Step 5: awk_script_merge variable defined."
awk "$awk_script_merge" "$LOCAL_FILE_COPY" "$MERGED_FILE" > "$FINAL_FILE"
log_info "[DEBUG] Step 5: awk merge finished. Status: $?"
log_info "模板覆盖完成。"


# 6. 检查变更并应用
log_info "正在比较变更..."
# 比较最终生成的文件与现有配置文件
if [ -f "$LOCAL_CONFIG_PATH" ] && diff -q "$LOCAL_CONFIG_PATH" "$FINAL_FILE" &>/dev/null; then
    log_info "配置无变化，无需更新。"
    exit 0
fi

# 如果脚本执行到这里，说明配置有变更或原配置文件不存在。
log_info "检测到配置变更，正在应用更新..."
# 在手动模式下，如果原文件存在，则显示差异
if [ "$MODE" = "manual" ] && [ -f "$LOCAL_CONFIG_PATH" ]; then
  log_info "变更摘要:"
  diff --color=always -u "$LOCAL_CONFIG_PATH" "$FINAL_FILE" 2>/dev/null || true
fi

if ! mv "$FINAL_FILE" "$LOCAL_CONFIG_PATH"; then
    echo "ERROR: 无法将合并文件移动到最终目标位置。" >&2
    # 由于没有备份，这里不再尝试恢复
    exit 1
fi
log_info "✅ 配置同步完成。 '$LOCAL_CONFIG_PATH' 已更新。"

log_info "脚本执行完毕。"
exit 0
