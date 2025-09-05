#!/usr/bin/env bash
# merge_config.sh
set -euo pipefail

# 远端地址
URL_TOP="https://route.woskee.dpdns.org/raw.githubusercontent.com/tyy840913/backup/main/mihomo_config.yaml"
URL_BOTTOM="http://127.0.0.1:8199/sub/mihomo.yaml"

# 本地目标
TARGET_DIR="/etc/mihomo"
TARGET_FILE="${TARGET_DIR}/config.yaml"

# 创建目录
mkdir -p "${TARGET_DIR}"

# 临时文件
TMP_TOP=$(mktemp)
TMP_BOTTOM=$(mktemp)
trap 'rm -f "${TMP_TOP}" "${TMP_BOTTOM}"' EXIT

# 下载
echo ">>> 下载上半部分配置..."
if ! curl -fsSL "${URL_TOP}" -o "${TMP_TOP}"; then
    echo "!!! 下载失败：${URL_TOP}"
    exit 1
fi

echo ">>> 下载下半部分配置..."
if ! curl -fsSL "${URL_BOTTOM}" -o "${TMP_BOTTOM}"; then
    echo "!!! 下载失败：${URL_BOTTOM}"
    exit 1
fi

# 合并（中间留一个空行）
cat "${TMP_TOP}" > "${TARGET_FILE}"
echo "" >> "${TARGET_FILE}"
cat "${TMP_BOTTOM}" >> "${TARGET_FILE}"

echo ">>> 合并完成，已写入：${TARGET_FILE}"
