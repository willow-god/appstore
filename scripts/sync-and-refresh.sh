#!/bin/bash
# ============================================================
# 全量同步应用 + 触发 1Panel 本地应用商店刷新（API 方式）
# ------------------------------------------------------------
# 先执行 scripts/sync-apps.sh 落盘，再调用 1Panel API 让面板重新扫描
# 本地应用目录，不需要手动到面板点「更新应用列表」。
#
# 变量（未设置时使用 scripts/check-env.sh 里的默认值）：
#   PANEL_ROOT       1Panel 安装根目录，默认 /opt/1panel
#   GIT_REPO         应用仓库地址，默认 https://github.com/willow-god/appstore
#   APPS             只同步指定应用（逗号或空格分隔），留空表示全部
#   ONEPANEL_URL     面板地址，可省略协议（必填）
#   ONEPANEL_APIKEY  面板「设置 - 密钥」中生成的 API Key（必填）
#   ONEPANEL_NODE    节点名称，留空表示主节点
#
# 示例：
#   ONEPANEL_URL=https://panel.example.com ONEPANEL_APIKEY=xxxx \
#   bash scripts/sync-and-refresh.sh
# ============================================================
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=check-env.sh
. "$SCRIPT_DIR/check-env.sh" sync-and-refresh

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

# ---------- 1. 同步应用文件 ----------
bash "$SCRIPT_DIR/sync-apps.sh"

# ---------- 2. 调用 1Panel API 刷新本地应用商店 ----------
# 鉴权方式：Token = md5("1panel" + APIKey + Timestamp)
# 请求头需携带 1Panel-Timestamp / 1Panel-Token
# CurrentNode 可选：留空时不发送该头，1Panel 将默认为主节点
echo "🔄 Refreshing 1Panel local app store..."

TASK_ID=$(cat /proc/sys/kernel/random/uuid)
TIMESTAMP=$(date +%s)

TOKEN=$(echo -n "1panel${ONEPANEL_APIKEY}${TIMESTAMP}" | md5_hex)

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
