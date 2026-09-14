#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ============================================================
# 全量同步应用 + 触发 1Panel 本地应用商店刷新（API 方式）
# ------------------------------------------------------------
# 本脚本与 README 中的「全量同步」「单应用同步」脚本相互独立：
#   - 前两者只负责把仓库中的应用文件复制到本地应用目录
#   - 本脚本在完成同样的复制后，额外调用 1Panel API 刷新应用商店，
#     因此不需要再手动到面板点击「更新应用列表」
#
# 使用前请设置 1Panel 信息，可直接修改下方变量，
# 也可以通过同名环境变量传入，例如：
#   ONEPANEL_URL=https://panel.example.com \
#   ONEPANEL_APIKEY=xxxxxxxx \
#   bash scripts/sync-and-refresh.sh
#
# ONEPANEL_NODE 可留空（默认），表示操作主节点；
# 多节点环境才需要填写从节点名称。
# ============================================================

# ---------- 仓库同步配置 ----------
GIT_REPO="${GIT_REPO:-https://github.com/willow-god/appstore}"
TMP_DIR="${TMP_DIR:-/opt/1panel/resource/apps/local/appstore-localApps}"
LOCAL_APPS_DIR="${LOCAL_APPS_DIR:-/opt/1panel/resource/apps/local}"

# ---------- 1Panel API 配置 ----------
# 面板站点地址：可带或不带 http(s)://，不要带结尾斜杠
ONEPANEL_URL="${ONEPANEL_URL:-}"
# 面板「设置 - 密钥」中生成的 API Key
ONEPANEL_APIKEY="${ONEPANEL_APIKEY:-}"
# 节点名称：留空表示主节点（默认），多节点环境填写从节点名称
ONEPANEL_NODE="${ONEPANEL_NODE:-}"

if [[ -z "$ONEPANEL_URL" || -z "$ONEPANEL_APIKEY" ]]; then
    echo "❌ 缺少 1Panel API 配置"
    echo "   请设置 ONEPANEL_URL 与 ONEPANEL_APIKEY 后再执行，例如："
    echo "   ONEPANEL_URL=https://panel.example.com ONEPANEL_APIKEY=xxxx bash $0"
    exit 1
fi

# 规范化站点地址：去掉结尾斜杠，缺少协议时补 http://
ONEPANEL_URL="${ONEPANEL_URL%/}"
if [[ "$ONEPANEL_URL" != http://* && "$ONEPANEL_URL" != https://* ]]; then
    ONEPANEL_URL="http://${ONEPANEL_URL}"
fi

# md5 命令兼容 Linux(md5sum) 与 macOS(md5)
md5_hex() {
    if command -v md5sum >/dev/null 2>&1; then
        md5sum | awk '{print $1}'
    else
        md5 -q
    fi
}

# ============================================================
# 1. 同步仓库应用文件到本地应用目录
# ============================================================

trap 'rm -rf "$TMP_DIR"' EXIT

echo "📥 Cloning appstore repo..."
[ -d "$TMP_DIR" ] && rm -rf "$TMP_DIR"
git clone "$GIT_REPO" "$TMP_DIR"

echo "🔄 Mirroring apps..."
cd "$TMP_DIR"
if [[ -f ./mirror.sh ]]; then
    chmod +x ./mirror.sh
    ./mirror.sh
else
    echo "⚠️ mirror.sh not found, skipping mirroring"
fi
cd - >/dev/null

mkdir -p "$LOCAL_APPS_DIR"

for app_path in "$TMP_DIR/apps/"*; do
    [ -d "$app_path" ] || continue
    app_name=$(basename "$app_path")
    local_app_path="$LOCAL_APPS_DIR/$app_name"

    echo "🔁 Updating app: $app_name"
    [ -d "$local_app_path" ] && rm -rf "$local_app_path"
    cp -r "$app_path" "$local_app_path"
done

echo "✅ Local app files updated."

# ============================================================
# 2. 调用 1Panel API 刷新本地应用商店
# ============================================================
# 鉴权方式：Token = md5("1panel" + APIKey + Timestamp)
# 请求头需携带 1Panel-Timestamp / 1Panel-Token
# CurrentNode 可选：留空时不发送该头，1Panel 将默认为主节点
# ============================================================

echo "🔄 Refreshing 1Panel local app store..."

TASK_ID=$(cat /proc/sys/kernel/random/uuid)
TIMESTAMP=$(date +%s)

TOKEN=$(echo -n "1panel${ONEPANEL_APIKEY}${TIMESTAMP}" | md5_hex)

# 节点留空时不发送 CurrentNode 请求头，1Panel 会将其视为主节点
NODE_HEADER=()
if [[ -n "$ONEPANEL_NODE" ]]; then
    NODE_HEADER=(-H "CurrentNode: ${ONEPANEL_NODE}")
fi

RESPONSE=$(curl -ksS \
    -X POST \
    "${ONEPANEL_URL}/api/v2/apps/sync/local" \
    -H "Content-Type: application/json" \
    -H "1Panel-Timestamp: ${TIMESTAMP}" \
    -H "1Panel-Token: ${TOKEN}" \
    ${NODE_HEADER[@]+"${NODE_HEADER[@]}"} \
    -d "{\"taskID\":\"${TASK_ID}\"}") || {
        echo "❌ curl 请求失败，请检查 1Panel 地址与网络连通性。"
        exit 1
    }

echo "1Panel response:"
echo "$RESPONSE"

if ! echo "$RESPONSE" | grep -q '"code":200'; then
    echo "❌ Failed to trigger 1Panel app store refresh."
    exit 1
fi

echo "✅ 1Panel local app store refresh triggered."
echo "TaskID: ${TASK_ID}"
echo "🎉 All done."
