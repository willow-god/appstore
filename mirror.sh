#!/bin/bash
set -e

# ============================================================
# 1. 执行 ./adapters/ 目录下的所有 .sh 文件
# ============================================================
# 这里的逻辑是：不管镜像配置文件是否存在，都会执行 adapters 目录下的脚本。
# 这样就避免了因为缺少镜像配置文件而导致 adapters 脚本没执行的情况。
# ============================================================

ADAPTERS_DIR="./adapters"

if [ -d "$ADAPTERS_DIR" ]; then
    for script in "$ADAPTERS_DIR"/*.sh; do
        # 如果目录下没有 .sh 文件，通配符不会展开，直接跳过
        if [ ! -f "$script" ]; then
            echo "目录 $ADAPTERS_DIR 下没有找到 .sh 文件"
            break
        fi
        echo "执行 adapters 脚本: $script"
        chmod +x "$script"
        "$script"
    done
else
    echo "目录不存在: $ADAPTERS_DIR，跳过 adapters 脚本执行"
fi

# ============================================================
# 2. 镜像替换逻辑
# ============================================================
# 功能：
# - 从 /opt/mirror-config.env 读取镜像加速配置
# - 从当前目录的 .env 文件读取应用列表
# - 遍历应用，查找 docker-compose.yml 文件
# - 替换镜像源地址为镜像仓库地址
# ============================================================

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

# --- 如果镜像配置文件存在，才执行镜像替换 ---
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

        # 获取应用数组（以逗号分隔）
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
