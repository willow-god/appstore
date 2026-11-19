#!/bin/bash
# ============================================================
# 镜像源替换 + 执行 adapters/ 下的适配脚本
# ------------------------------------------------------------
# 由同步脚本在克隆目录里调用，也可以手动执行：
#   bash scripts/mirror.sh
#
# 变量（未设置时使用 scripts/check-env.sh 里的默认值）：
#   PANEL_ROOT   1Panel 安装根目录，默认 /opt/1panel
#   MIRROR_CONFIG  镜像加速配置文件，默认 /opt/mirror-config.env
#
# 流程：
#   1. 依次执行 adapters/*.sh（应用级适配，如 PRUNE_APPS 清理）
#   2. 按 .env 的应用清单，把 docker-compose.yml 里的镜像仓库替换为加速地址
# ============================================================
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=check-env.sh
. "$ROOT_DIR/scripts/check-env.sh" mirror

# ---------- 1. 执行 adapters 目录下的所有 .sh ----------
# 不管镜像配置文件是否存在都执行，避免缺配置时适配脚本被跳过
ADAPTERS_DIR="$ROOT_DIR/adapters"

if [ -d "$ADAPTERS_DIR" ]; then
    for script in "$ADAPTERS_DIR"/*.sh; do
        [ -f "$script" ] || { echo "目录 $ADAPTERS_DIR 下没有找到 .sh 文件"; break; }
        echo "执行 adapters 脚本: $script"
        chmod +x "$script"
        "$script"
    done
else
    echo "目录不存在: $ADAPTERS_DIR，跳过 adapters 脚本执行"
fi

# ---------- 2. 镜像替换 ----------
MIRROR_CONFIG="${MIRROR_CONFIG:-/opt/mirror-config.env}"
if [[ ! -f "$MIRROR_CONFIG" ]]; then
    echo "镜像配置文件不存在: $MIRROR_CONFIG，跳过镜像替换"
else
    set -a
    # shellcheck disable=SC1090
    source "$MIRROR_CONFIG"
    set +a
fi

ENV_FILE="$ROOT_DIR/.env"
if [[ ! -f "$ENV_FILE" ]]; then
    echo ".env 文件不存在: $ENV_FILE"
    exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

replace_image() {
    local file="$1"
    local src_registry="$2"
    local target_registry="$3"

    cp "$file" "${file}.bak"
    # 只匹配镜像开头，例如 ghcr.io/xxx -> MIRROR/xxx
    sed -i -E "s#\b${src_registry}/#${target_registry}/#g" "$file"
    echo "已替换 $file: $src_registry -> $target_registry"
}

if [[ -f "$MIRROR_CONFIG" ]]; then
    # 每个源可以对应多个清单变量（空格分隔），指向的清单都会处理
    declare -A SOURCES
    SOURCES=(
        ["GHCR"]="GHCR_ENABLE GHCR_MIRROR ghcr.io GHCR_IO_LIST"
        ["QUAY"]="QUAY_ENABLE QUAY_MIRROR quay.io QUAY_IO_LIST"
        ["GCR"]="GCR_ENABLE GCR_MIRROR gcr.io GCR_IO_LIST"
        ["K8S_GCR"]="K8S_GCR_ENABLE K8S_GCR_MIRROR k8s.gcr.io K8S_GCR_IO_LIST"
        ["K8S_REG"]="K8S_REG_ENABLE K8S_REG_MIRROR registry.k8s.io REGISTRY_K8S_IO_LIST NON_DOCKER_IO_LIST"
    )

    for key in "${!SOURCES[@]}"; do
        read -r ENABLE_VAR MIRROR_VAR SRC_REG ARRAY_NAMES <<<"${SOURCES[$key]}"

        ENABLE=${!ENABLE_VAR}
        MIRROR=${!MIRROR_VAR}

        [[ "$ENABLE" != "true" ]] && continue

        for ARRAY_NAME in $ARRAY_NAMES; do
            APP_LIST=${!ARRAY_NAME:-}
            IFS=',' read -r -a APPS <<<"$APP_LIST"

            for app in "${APPS[@]}"; do
                # 清单为空或有多余逗号时会解析出空名字，跳过以免误扫整个 apps 目录
                [ -z "$app" ] && continue

                app_dir="$ROOT_DIR/apps/$app"
                if [ ! -d "$app_dir" ]; then
                    echo "应用目录不存在，跳过: $app_dir"
                    continue
                fi

                files=$(find "$app_dir" -type f \( -name "docker-compose.yml" -o -name "docker-compose.yaml" \))
                for file in $files; do
                    replace_image "$file" "$SRC_REG" "$MIRROR"
                done
            done
        done
    done

    echo "镜像替换完成。"
fi
