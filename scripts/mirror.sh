#!/bin/bash
# ============================================================
# 镜像源替换（只做这一件事，直接在已部署的 1Panel 应用目录上改）
# ------------------------------------------------------------
# 用法（在 scripts/sync-apps.sh 之后执行，顺序反了改的是上一次的内容）：
#   bash scripts/mirror.sh
#
#   # 换镜像加速配置
#   MIRROR_CONFIG=/opt/mirror-config.env bash scripts/mirror.sh
#
# 作用：
#   1. 依次执行 adapters/*.sh（应用级适配，如按 PRUNE_APPS 删除已下线应用）
#   2. 按仓库根目录 .env 的应用清单，把
#      $LOCAL_APPS_DIR/<应用>/<版本>/docker-compose.yml 里的镜像仓库前缀
#      替换成配置文件里的加速地址
#
# 说明：
#   - 幂等：重复执行不会二次替换，也不留备份文件
#   - 只改已部署目录，不改仓库克隆；每次 sync-apps.sh 覆盖回去后要重新执行
#
# 变量：
#   PANEL_ROOT     1Panel 安装根目录，默认 /opt/1panel（LOCAL_APPS_DIR 由它拼出）
#   MIRROR_CONFIG  镜像加速配置文件，默认 /opt/mirror-config.env
#   ENV_FILE       应用清单文件，默认仓库根目录 .env
#
# 退出码：0 完成（配置缺失时跳过替换）；1 .env 不存在；2/4 check-env 拒绝
# ============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=check-env.sh
. "$SCRIPT_DIR/check-env.sh" mirror

MIRROR_CONFIG="${MIRROR_CONFIG:-/opt/mirror-config.env}"

# ---------- 1. 执行 adapters 目录下的所有 .sh ----------
# 不管镜像配置文件是否存在都执行，避免缺配置时适配脚本被跳过
ADAPTERS_DIR="$ROOT_DIR/adapters"

if [ -d "$ADAPTERS_DIR" ]; then
    adapter_scripts=()
    for script in "$ADAPTERS_DIR"/*.sh; do
        [ -f "$script" ] && adapter_scripts+=("$script")
    done
    if [ "${#adapter_scripts[@]}" -eq 0 ]; then
        echo "目录 $ADAPTERS_DIR 下没有找到 .sh 文件"
    else
        # 只报一条汇总，各适配脚本自己的输出照常打印
        adapter_names=""
        for script in "${adapter_scripts[@]}"; do
            adapter_names="${adapter_names:+$adapter_names、}$(basename "$script")"
        done
        echo "🔧 执行 adapters: $adapter_names"
        for script in "${adapter_scripts[@]}"; do
            chmod +x "$script"
            "$script"
        done
    fi
else
    echo "目录不存在: $ADAPTERS_DIR，跳过 adapters 脚本执行"
fi

# ---------- 2. 镜像替换 ----------
if [[ ! -f "$MIRROR_CONFIG" ]]; then
    echo "镜像配置文件不存在: $MIRROR_CONFIG，跳过镜像替换"
    exit 0
fi

set -a
# shellcheck disable=SC1090
source "$MIRROR_CONFIG"
set +a

ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
if [[ ! -f "$ENV_FILE" ]]; then
    echo ".env 文件不存在: $ENV_FILE"
    exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

REPLACED_FILES=0
declare -A REPLACED_BY_SOURCE=()

replace_image() {
    local file="$1"
    local src_registry="$2"
    local target_registry="$3"
    local pair="${src_registry} → ${target_registry}"

    # 已经替换过的文件不会再有源前缀，直接跳过（幂等，也不产生备份文件）
    grep -qE "\b${src_registry}/" "$file" || return 0
    sed -i -E "s#\b${src_registry}/#${target_registry}/#g" "$file"
    REPLACED_FILES=$((REPLACED_FILES + 1))
    REPLACED_BY_SOURCE["$pair"]=$(( ${REPLACED_BY_SOURCE["$pair"]:-0} + 1 ))
}

if [[ ! -d "$LOCAL_APPS_DIR" ]]; then
    echo "本地应用目录不存在: $LOCAL_APPS_DIR，跳过镜像替换"
    exit 0
fi

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
            # 清单为空或有多余逗号时会解析出空名字，跳过以免误扫整个目录
            [ -z "$app" ] && continue

            app_dir="$LOCAL_APPS_DIR/$app"
            # 清单里有、本机没部署的应用（没安装或已被 PRUNE_APPS 清掉）直接跳过，不刷屏
            [ -d "$app_dir" ] || continue

            files=$(find "$app_dir" -type f \( -name "docker-compose.yml" -o -name "docker-compose.yaml" \))
            for file in $files; do
                replace_image "$file" "$SRC_REG" "$MIRROR"
            done
        done
    done
done

if [ "$REPLACED_FILES" -gt 0 ]; then
    for pair in "${!REPLACED_BY_SOURCE[@]}"; do
        echo "✅ 镜像替换 $pair：${REPLACED_BY_SOURCE[$pair]} 个文件"
    done
    echo "✅ 镜像替换完成，共 $REPLACED_FILES 个文件"
else
    echo "ℹ️ 没有需要替换的镜像（清单为空、应用未部署或已经替换过）"
fi
