#!/bin/bash
# ============================================================
# 同步应用文件到 1Panel 本地应用目录（只做这一件事）
# ------------------------------------------------------------
# 克隆仓库，把 apps/<应用>/ 复制到 $LOCAL_APPS_DIR，并清理超出保留数量的
# 历史版本目录。不执行镜像替换（scripts/mirror.sh），也不调用 1Panel API
# （scripts/refresh.sh）——完整链路按 README 的顺序依次执行。
#
# 用法：
#   bash scripts/sync-apps.sh
#   APPS="whoami,ech0" bash scripts/sync-apps.sh
#
# 变量：
#   PANEL_ROOT     1Panel 安装根目录，默认 /opt/1panel
#   GIT_REPO       应用仓库地址，默认 https://github.com/willow-god/appstore
#   APPS           要同步的应用（逗号或空格分隔），留空表示全部
#   KEEP_VERSIONS  每个应用保留的历史版本目录数量，默认 10
#   REPO_DIR       已克隆好的仓库目录；设置后不再重复克隆（定时任务外层
#                  已经 clone 过时用）
#
# 版本目录策略：仓库里存在的版本每次覆盖更新。1Panel 本地应用同步会删除
# 本地已不存在的版本对应的 app_details 记录，而 app_installs.app_detail_id
# 仍指着它，删掉目录就会让已安装应用的详情页和升级报 JSON 错误。所以清理
# 前会用只读 sqlite 查询 $PANEL_DB（由 PANEL_ROOT 拼出，即
# $PANEL_ROOT/db/agent.db）里的 app_installs：
#
#   能查到准确数据 → 只保留「仓库里有的版本」和「已安装的版本」，其余旧目录
#     全部删除，不受数量限制（残留越少越好）；
#   查不到（没有 sqlite3、文件不存在、被锁、应用未入库、指针已失效）→ 兜底
#     只保留最近 KEEP_VERSIONS 个（默认 10 个）。
#
# 数据库只读打开，带 PRAGMA query_only=ON，不会写入任何内容。
# ============================================================
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=check-env.sh
. "$SCRIPT_DIR/check-env.sh" sync-apps

cleanup() {
    if [ -n "${TMP_DIR:-}" ] && [ -d "$TMP_DIR" ]; then
        rm -rf -- "$TMP_DIR"
    fi
}
trap cleanup EXIT

# ---------- 1. 准备仓库内容 ----------
# REPO_DIR 指向已经克隆好的仓库时直接用，不再重复克隆（定时任务外层
# 已经 clone 过一次的情况）。否则现场克隆到 TMP_DIR，退出时删除。
if [ -n "${REPO_DIR:-}" ]; then
    if [ ! -d "$REPO_DIR/apps" ]; then
        echo "❌ REPO_DIR 不是应用仓库（缺少 apps/ 目录）: $REPO_DIR"
        exit 1
    fi
    SRC_DIR="$(cd "$REPO_DIR" && pwd)"
    trap - EXIT
    echo "📂 使用已有仓库目录: $SRC_DIR"
else
    echo "📥 克隆仓库到 $TMP_DIR ..."
    rm -rf -- "$TMP_DIR"
    mkdir -p "$(dirname "$TMP_DIR")"
    git clone --depth 1 "$GIT_REPO" "$TMP_DIR"
    SRC_DIR="$TMP_DIR"
fi

# ---------- 2. 应用列表 ----------
app_list=()
if [ -n "${APPS:-}" ]; then
    IFS=', ' read -r -a app_list <<<"$APPS"
else
    for app_path in "$SRC_DIR/apps/"*/; do
        [ -d "$app_path" ] && app_list+=("$(basename "$app_path")")
    done
fi

if [ "${#app_list[@]}" -eq 0 ]; then
    echo "❌ 没有可同步的应用"
    exit 1
fi

mkdir -p "$LOCAL_APPS_DIR"

# ---------- 3. 复制应用 ----------
# 清理规则有两档：
#   1. 能只读查到 app_installs 时，只保留仓库里有的版本和已安装的版本，
#      其余旧目录全部删除（不受数量限制）；
#   2. 读不到准确数据（没有 sqlite3、数据库不存在或被锁、应用未入库、
#      指针已失效）时，退化为「保留最近 KEEP_VERSIONS 个」。
# 数据库只用于 SELECT，连接带 -readonly 和 PRAGMA query_only，不会写入。
DB_STATE="unknown"
DB_REASON=""
DB_APP_REASON=""

# 清理统计，脚本结束时汇总输出（多数应用只有 1~2 个版本目录，不会触发清理细节）
PRUNE_APPS_TOTAL=0
PRUNE_APPS_QUIET=0
PRUNE_DIRS_REMOVED=0

init_installed_db() {
    if ! command -v sqlite3 >/dev/null 2>&1; then
        DB_STATE="unavailable"
        DB_REASON="未找到 sqlite3 命令（apt install -y sqlite3 后可启用保护）"
        return
    fi
    if [ ! -f "$PANEL_DB" ]; then
        DB_STATE="unavailable"
        DB_REASON="数据库不存在: $PANEL_DB"
        return
    fi
    if ! sqlite3 -readonly -batch "$PANEL_DB" "PRAGMA query_only=ON; SELECT 1;" >/dev/null 2>&1; then
        DB_STATE="unavailable"
        DB_REASON="数据库只读打开失败（被占用或权限不足）: $PANEL_DB"
        return
    fi
    DB_STATE="ready"
    echo "🗄 已连接 1Panel 数据库（只读）: $PANEL_DB"
}

# 只读查询；失败时返回非零，调用方按兜底规则处理
sqlite_ro() {
    sqlite3 -readonly -batch -noheader -cmd "PRAGMA query_only=ON;" "$PANEL_DB" "$1" 2>/dev/null
}

# 输出该应用已安装的版本，每行 "OK|install_id|install_name|version"
# 无法可靠判断时输出一行 "ERR|原因"（应用未入库、指针失效或查询失败）
installed_versions() {
    local app_name="$1"
    local key app_id dangling out
    key="$(printf '%s' "local$app_name" | sed "s/'/''/g")"

    if ! app_id="$(sqlite_ro "SELECT id FROM apps WHERE resource='local' AND key='$key' LIMIT 1;")"; then
        echo "ERR|数据库查询失败"
        return 0
    fi
    if [ -z "$app_id" ]; then
        echo "ERR|数据库中没有该应用记录（1Panel 尚未扫描到它）"
        return 0
    fi

    # 指针已经失效时无法把安装记录映射到版本号，退回兜底规则更安全
    if ! dangling="$(sqlite_ro "SELECT count(*) FROM app_installs WHERE app_id=$app_id AND app_detail_id NOT IN (SELECT id FROM app_details WHERE app_id=$app_id);")"; then
        echo "ERR|数据库查询失败"
        return 0
    fi
    if [ -n "$dangling" ] && [ "$dangling" != "0" ]; then
        echo "ERR|该应用有 $dangling 条安装记录的 app_detail_id 已失效，无法判断安装版本"
        return 0
    fi

    if ! out="$(sqlite_ro "SELECT i.id, i.name, d.version FROM app_installs i JOIN app_details d ON d.id = i.app_detail_id WHERE i.app_id=$app_id;")"; then
        echo "ERR|数据库查询失败"
        return 0
    fi
    [ -n "$out" ] || return 0
    printf '%s\n' "$out" | sed 's/^/OK|/'
}

prune_versions() {
    local app_name="$1" src="$2" dst="$3"
    local -a versions=()
    local version

    while IFS= read -r version; do
        [ -n "$version" ] && versions+=("$version")
    done < <(find "$dst" -mindepth 1 -maxdepth 1 -type d | sed 's#.*/##' | sort -V)

    local total=${#versions[@]}
    PRUNE_APPS_TOTAL=$((PRUNE_APPS_TOTAL + 1))
    [ "$total" -eq 0 ] && return 0

    local -A protected=()
    local -a installed=() removed=()
    local tag iid iname iver reason="" db_failed=0 fallback=0

    if [ "$DB_STATE" = "ready" ]; then
        while IFS='|' read -r tag iid iname iver; do
            case "$tag" in
                ERR)
                    reason="$iid"
                    db_failed=1
                    ;;
                OK)
                    [ -n "$iver" ] || continue
                    protected["$iver"]=1
                    installed+=("$iver")
                    ;;
            esac
        done < <(installed_versions "$app_name")
    fi

    if [ "$DB_STATE" = "ready" ] && [ "$db_failed" -eq 0 ]; then
        # 有准确数据：只保留「仓库里有的版本」和「已安装的版本」，其余一律清掉，
        # 不再受 KEEP_VERSIONS 限制
        for version in "${versions[@]}"; do
            if [ -n "${protected[$version]:-}" ] || [ -d "$src/$version" ]; then
                continue
            fi
            rm -rf -- "$dst/$version"
            removed+=("$version")
        done
    else
        # 兜底：读不到准确的安装记录，只能按数量保留最近 KEEP_VERSIONS 个
        fallback=1
        if [ "$total" -gt "$KEEP_VERSIONS" ]; then
            local remove=$((total - KEEP_VERSIONS)) i
            for ((i = 0; i < remove; i++)); do
                version="${versions[$i]}"
                if [ -d "$src/$version" ]; then
                    continue
                fi
                rm -rf -- "$dst/$version"
                removed+=("$version")
            done
        fi
    fi

    # 每个应用只输出一行，细节（已安装版本、删掉的版本）都在这一行里
    local status="无安装实例" line
    if [ "${#installed[@]}" -gt 0 ]; then
        local joined="" v
        for v in "${installed[@]}"; do
            joined="${joined:+$joined、}$v"
        done
        status="已安装 $joined"
    fi
    if [ "$fallback" -eq 1 ]; then
        # 数据库整体读不到时原因已经在开头统一说过一次，这里只写结果；
        # 单个应用自身的原因（指针失效、未入库）才写在这一行
        if [ -n "$reason" ]; then
            status="读不到安装记录（$reason），按数量保留最近 $KEEP_VERSIONS 个"
        else
            status="按数量保留最近 $KEEP_VERSIONS 个"
        fi
    fi

    PRUNE_DIRS_REMOVED=$((PRUNE_DIRS_REMOVED + ${#removed[@]}))
    kept_count=$((total - ${#removed[@]}))
    line="✅ $app_name：$status；目录 $total 个 → 保留 $kept_count 个，删除 ${#removed[@]} 个"
    if [ "${#removed[@]}" -gt 0 ]; then
        local detail="" n=0
        for v in "${removed[@]}"; do
            n=$((n + 1))
            [ "$n" -gt 5 ] && { detail="$detail、等"; break; }
            detail="${detail:+$detail、}$v"
        done
        [ "$fallback" -eq 1 ] && line="⚠️ ${line#✅ }"
        line="$line（$detail）"
    fi
    # 没有安装实例、没删东西、也没出问题：不单独刷一行，只在结尾汇总里计数
    if [ "${#removed[@]}" -eq 0 ] && [ "${#installed[@]}" -eq 0 ] && [ -z "$reason" ]; then
        PRUNE_APPS_QUIET=$((PRUNE_APPS_QUIET + 1))
        return 0
    fi

    echo "$line"
}

sync_app() {
    local app_name="$1"
    local src="$SRC_DIR/apps/$app_name"
    local dst="$LOCAL_APPS_DIR/$app_name"
    local version_dir version

    if [ ! -d "$src" ]; then
        echo "❌ 仓库中没有应用 $app_name，跳过"
        return 1
    fi

    mkdir -p "$dst"

    # 应用级文件（data.yml、logo.png、README.md 等）直接覆盖
    find "$src" -mindepth 1 -maxdepth 1 -type f -exec cp -f {} "$dst/" \;

    # 仓库里存在的版本目录覆盖更新，不碰其他历史版本
    for version_dir in "$src"/*/; do
        [ -d "$version_dir" ] || continue
        version="$(basename "$version_dir")"
        rm -rf -- "$dst/$version"
        cp -r "$version_dir" "$dst/$version"
    done

    prune_versions "$app_name" "$src" "$dst"
}

init_installed_db
if [ "$DB_STATE" != "ready" ]; then
    echo "⚠️ 未启用已安装版本保护：$DB_REASON（历史版本只按数量清理）"
fi

failed=()
for app_name in "${app_list[@]}"; do
    [ -n "$app_name" ] || continue
    sync_app "$app_name" || failed+=("$app_name")
done

echo "✅ 已同步 ${#app_list[@]} 个应用到 $LOCAL_APPS_DIR：检查 $PRUNE_APPS_TOTAL 个，$PRUNE_APPS_QUIET 个无变化，删除 $PRUNE_DIRS_REMOVED 个旧版本目录"

if [ "${#failed[@]}" -gt 0 ]; then
    echo "⚠️ 以下应用未同步: ${failed[*]}"
    exit 1
fi
