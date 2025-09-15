#!/bin/bash
set -e
# --- 读取镜像配置 ---
MIRROR_CONFIG="/opt/mirror-config.env"
if [[ ! -f "$MIRROR_CONFIG" ]]; then
    echo "镜像配置文件不存在: $MIRROR_CONFIG，跳过镜像替换"
else
    # 导入配置
    set -a
    source "$MIRROR_CONFIG"
    set +a
fi
# --- 读取应用列表 ---
ENV_FILE="./.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo ".env 文件不存在: $ENV_FILE"
    exit 1
fi
source "$ENV_FILE"
# --- 定义函数：安全替换 docker-compose 中的镜像 ---
replace_image() {
    local file="$1"
    local src_registry="$2"
    local target_registry="$3"
    # 备份原文件
    cp "$file" "${file}.bak"
    # 用 sed 进行安全替换，只匹配镜像开头
    # 匹配示例：ghcr.io/xxx -> MIRROR/xxx
    sed -i -E "s#\b${src_registry}/#${target_registry}/#g" "$file"
    echo "已替换 $file: $src_registry -> $target_registry"
}
# 如果镜像配置文件存在，才执行镜像替换
if [[ -f "$MIRROR_CONFIG" ]]; then
    # --- 遍历每个源 ---
    declare -A SOURCES
    SOURCES=(
        ["GHCR"]="GHCR_ENABLE GHCR_MIRROR ghcr.io GHCR_IO_LIST"
        ["QUAY"]="QUAY_ENABLE QUAY_MIRROR quay.io QUAY_IO_LIST"
        ["GCR"]="GCR_ENABLE GCR_MIRROR gcr.io GCR_IO_LIST"
        ["K8S_GCR"]="K8S_GCR_ENABLE K8S_GCR_MIRROR k8s.gcr.io K8S_GCR_IO_ARRAY"
        ["K8S_REG"]="K8S_REG_ENABLE K8S_REG_MIRROR registry.k8s.io NON_DOCKER_IO_LIST"
    )
    for key in "${!SOURCES[@]}"; do
        read -r ENABLE_VAR MIRROR_VAR SRC_REG ARRAY_NAME <<<"${SOURCES[$key]}"
        ENABLE=${!ENABLE_VAR}
        MIRROR=${!MIRROR_VAR}
        # 如果源未启用，跳过
        if [[ "$ENABLE" != "true" ]]; then
            continue
        fi
        # 获取应用数组
        APP_LIST=${!ARRAY_NAME}
        IFS=',' read -r -a APPS <<< "$APP_LIST"
        for app in "${APPS[@]}"; do
            # 查找 docker-compose 文件
            files=$(find "./apps/$app" -type f \( -name "docker-compose.yml" -o -name "docker-compose.yaml" \))
            for file in $files; do
                replace_image "$file" "$SRC_REG" "$MIRROR"
            done
        done
    done
    echo "镜像替换完成。"
fi
