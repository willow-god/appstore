#!/bin/bash
# ============================================================
# 按 PRUNE_APPS 清理 .env 应用清单里的指定条目
# ------------------------------------------------------------
# mirror.sh 执行镜像替换前会运行 adapters/ 下的所有 .sh 脚本。
# 本脚本读取 .env 里的 PRUNE_APPS（逗号分隔的应用名），只把这些名字
# 从 *_LIST / *_ARRAY 应用清单中移除，其余条目一律不动。
#
# 为什么不按 apps/ 目录是否存在来判断：用户的清单里可能有来自其他
# 应用商店的应用，本仓库里没有对应目录并不代表它是失效条目。
#
# - 幂等：清单里没有 PRUNE_APPS 中的名字时不写文件
# - 通用：任何以 _LIST / _ARRAY 结尾的键都会被处理
# - 保留原换行风格（LF / CRLF）
# - 可单独运行：bash adapters/prune-app-lists.sh
#   也可用 ENV_FILE=... 指向其他 .env，或用 PRUNE_APPS=... 直接传入清单
# ============================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"
# 清理清单的变量名。故意不以 _LIST 结尾，避免被当成待清理的清单处理
PRUNE_VAR="PRUNE_APPS"

if [[ ! -f "$ENV_FILE" ]]; then
    echo "⚠️  未找到 $ENV_FILE，跳过应用清单清理"
    exit 0
fi

# ---------- 读取 PRUNE_APPS ----------
# 优先用环境变量传入的值，否则从 .env 里解析
prune_raw="${PRUNE_APPS:-}"
if [[ -z "$prune_raw" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        if [[ "$line" =~ ^${PRUNE_VAR}=\"?([^\"]*)\"?$ ]]; then
            prune_raw="${BASH_REMATCH[1]}"
            break
        fi
    done <"$ENV_FILE"
fi

# 规整成 ,a,b,c, 形式，方便整词匹配
prune_set=","
IFS=',' read -r -a prune_items <<<"$prune_raw"
for item in ${prune_items[@]+"${prune_items[@]}"}; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    item="${item%$'\r'}"
    [[ -z "$item" ]] && continue
    prune_set="${prune_set}${item},"
done

if [[ "$prune_set" == "," ]]; then
    echo "✅ $PRUNE_VAR 为空，无需清理应用清单"
    exit 0
fi

# ---------- 逐行改写 .env ----------
# 保留原文件的换行风格：Git 仓库里是 LF，Windows 检出后可能是 CRLF
if [[ "$(head -c 8192 "$ENV_FILE")" == *$'\r'* ]]; then
    EOL=$'\r\n'
else
    EOL=$'\n'
fi

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

emit() { printf '%s%s' "$1" "$EOL" >>"$TMP_FILE"; }

changed=0

while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"

    # 匹配 KEY="a,b,c" / KEY=a,b,c，且 KEY 以 _LIST 或 _ARRAY 结尾
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*(_LIST|_ARRAY))=\"?([^\"]*)\"?$ ]]; then
        key="${BASH_REMATCH[1]}"
        raw_value="${BASH_REMATCH[3]}"

        kept=()
        dropped=()

        IFS=',' read -r -a items <<<"$raw_value"
        for item in ${items[@]+"${items[@]}"}; do
            # 去掉首尾空白
            item="${item#"${item%%[![:space:]]*}"}"
            item="${item%"${item##*[![:space:]]}"}"
            [[ -z "$item" ]] && continue

            if [[ "$prune_set" == *",$item,"* ]]; then
                dropped+=("$item")
            else
                kept+=("$item")
            fi
        done

        if [[ ${#dropped[@]} -gt 0 ]]; then
            new_value=""
            for item in ${kept[@]+"${kept[@]}"}; do
                new_value="${new_value:+$new_value,}$item"
            done
            emit "${key}=\"${new_value}\""
            echo "🧹 $key: 按 $PRUNE_VAR 移除 -> ${dropped[*]}"
            changed=1
        else
            # 没有命中就不动这一行，保持文件原样
            emit "$line"
        fi
    else
        emit "$line"
    fi
done <"$ENV_FILE"

if [[ $changed -eq 1 ]]; then
    cat "$TMP_FILE" >"$ENV_FILE"
    echo "✅ 应用清单已更新: $ENV_FILE"
else
    echo "✅ 应用清单无需清理（$PRUNE_VAR 中的名字都不在任何清单里）"
fi
