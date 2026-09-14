# 🌈 清羽飞扬 · 1Panel 第三方 App Store

这是一个由 **清羽飞扬** 自建维护的 **1Panel 第三方应用商店仓库**，用于收纳个人常用的容器化应用与预设配置，基于 [1Panel](https://github.com/1Panel-dev/1Panel) 的 App Store 架构。

> 本项目旨在补充官方 App Store，适用于特定需求场景或实验性环境。

---

## ✅ 应用收录标准

本仓库优先收录以下类型的容器应用：

- 📦 **常用工具或服务**：覆盖个人或开发者日常使用频繁的项目
- 🔒 **官方 Docker 镜像优先**：确保稳定与安全
- 🧑‍🤝‍🧑 **活跃社区支持项目**：优先选择活跃维护或高质量项目
- 🧾 **简洁配置模板**：配套清晰的 Docker Compose 和 formFields 文件，方便一键部署

---

## 🛠 使用说明

你可以将本仓库作为第三方 App Store 添加至 1Panel，即可在 Web 面板中浏览、安装、管理其中的应用。

### 添加第三方应用仓库

参考官方文档：[📚 如何添加第三方应用仓库](https://github.com/1Panel-dev/appstore/wiki/%E5%A6%82%E4%BD%95%E6%8F%90%E4%BA%A4%E8%87%AA%E5%B7%B1%E6%83%B3%E8%A6%81%E7%9A%84%E5%BA%94%E7%94%A8)

---

## 🔄 同步更新脚本

以下是自动同步 App 应用至 1Panel 的脚本，适用于开发或部署用户。

### 📥 国内同步脚本：

镜像仓库地址：https://cnb.cool/Liiiu/appstore

使用github action保持同步更新。

```bash
#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

GIT_REPO="https://cnb.cool/Liiiu/appstore"
TMP_DIR="/opt/1panel/resource/apps/local/appstore-localApps"
LOCAL_APPS_DIR="/opt/1panel/resource/apps/local"

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
cd -

mkdir -p "$LOCAL_APPS_DIR"

for app_path in "$TMP_DIR/apps/"*; do
    [ -d "$app_path" ] || continue
    app_name=$(basename "$app_path")
    local_app_path="$LOCAL_APPS_DIR/$app_name"

    echo "🔁 Updating app: $app_name"
    [ -d "$local_app_path" ] && rm -rf "$local_app_path"
    cp -r "$app_path" "$local_app_path"
done

echo "✅ Sync completed."
```

🌍 国外环境请替换为 GitHub 仓库：

```bash
GIT_REPO="https://github.com/willow-god/appstore"
```

------

## 😎 单应用同步

如果你想同步部分应用，可以采用以下脚本：

```bash
#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# ========= 配置：要安装的应用列表 =========
APPS_TO_INSTALL=(
    "whoami"
    "ech0"
    "moments"
)

# ========= 常量 =========
GIT_REPO="https://cnb.cool/Liiiu/appstore"
TMP_DIR="/opt/1panel/resource/apps/local/appstore-localApps"
LOCAL_APPS_DIR="/opt/1panel/resource/apps/local"

trap 'rm -rf "$TMP_DIR"' EXIT

echo "📥 Cloning appstore repo..."
[ -d "$TMP_DIR" ] && rm -rf "$TMP_DIR"
git clone "$GIT_REPO" "$TMP_DIR"

echo "🔄 Running mirror.sh (if exists)..."
cd "$TMP_DIR"
if [[ -f ./mirror.sh ]]; then
    chmod +x ./mirror.sh
    ./mirror.sh || echo "⚠️ mirror.sh 执行失败，继续..."
else
    echo "⚠️ mirror.sh not found, skipping mirroring"
fi
cd - >/dev/null

mkdir -p "$LOCAL_APPS_DIR"

# ========= 遍历安装列表 =========
for app_name in "${APPS_TO_INSTALL[@]}"; do
    app_path="$TMP_DIR/apps/$app_name"
    local_app_path="$LOCAL_APPS_DIR/$app_name"

    if [[ ! -d "$app_path" ]]; then
        echo "❌ 应用 $app_name 不存在于仓库，跳过"
        continue
    fi

    echo "🔁 Updating app: $app_name"
    [ -d "$local_app_path" ] && rm -rf "$local_app_path"
    cp -r "$app_path" "$local_app_path"
done

echo "✅ Selected apps sync completed."
```

## 🎡 镜像加速配置

在国内环境下，部分容器镜像源（如 `ghcr.io`、`gcr.io`、`quay.io` 等）可能会出现访问缓慢或被墙的情况。

你可以通过本镜像库独有的 **镜像映射配置文件** 来自动替换 `docker-compose.yml` 中的镜像地址，提升下载速度。

**注意该方式可能仅仅适用于本应用商店。**

### 1️⃣ 配置文件路径

镜像配置文件固定放在：

```bash
/opt/mirror-config.env
```

如果需要配置对应镜像，请自行创建以上文件，然后写入以下内容。

### 2️⃣ 配置文本

```ini
# ====== GHCR (GitHub Container Registry) ======
# 是否经常被墙：是
GHCR_ENABLE=true
GHCR_MIRROR=ghcr.io.mirror

# ====== Quay.io (RedHat/Community images) ======
# 是否经常被墙：是
QUAY_ENABLE=false
QUAY_MIRROR=quay.io.mirror

# ====== GCR (Google Container Registry) ======
# 是否经常被墙：是
GCR_ENABLE=false
GCR_MIRROR=gcr.io.mirror

# ====== k8s.gcr.io (旧 Kubernetes 镜像仓库) ======
# 是否经常被墙：是
K8S_GCR_ENABLE=false
K8S_GCR_MIRROR=k8s.gcr.io.mirror

# ====== registry.k8s.io (新 Kubernetes 镜像仓库) ======
# 是否经常被墙：是
K8S_REG_ENABLE=false
K8S_REG_MIRROR=registry.k8s.io.mirror
```

> 💡 **说明**：
>
> - `*_ENABLE` 为 `true` 时才会进行替换。
> - `*_MIRROR` 填写你可用的镜像源地址。
> - 不存在该配置文件时，脚本会跳过替换步骤，不会影响后续流程。
> - 哪些应用会被替换由仓库根目录的 `.env` 决定，维护者请参考 [CONTRIBUTING.md](CONTRIBUTING.md)。

### 3️⃣ 自动替换逻辑

> 该部分无需配置，仅供说明脚本的绿色性质，替换脚本开源于非docker.io镜像中如**MoonTV**仓库，有需要请自行查看

在克隆仓库后，按照本仓库的脚本，会在应用目录下执行 `mirror.sh`进行镜像源替换。

这样即使镜像源被墙，也能快速替换为你配置的加速地址。

> **目前还在测试中**：由于目前还在测试中，所以可能会出现一些问题。如果出现问题，请及时反馈。

---

## ⚡ 全量同步并刷新应用商店（API）

如果你希望**同步应用后自动让 1Panel 重新扫描本地应用**，而不必到面板手动点击「更新应用列表」，可以使用仓库中的 [scripts/sync-and-refresh.sh](scripts/sync-and-refresh.sh)。

该脚本与上面的「同步更新脚本」「单应用同步」是**相互独立的**，区别如下：

| 脚本 | 复制应用文件 | 执行 mirror.sh | 调用 1Panel API 刷新 |
| --- | --- | --- | --- |
| 同步更新脚本 | ✅ 全部 | ✅ | ❌ 需手动点击 |
| 单应用同步 | ✅ 部分应用 | ✅ | ❌ 需手动点击 |
| `scripts/sync-and-refresh.sh` | ✅ 全部 | ✅ | ✅ 自动刷新 |

### 使用方法

```bash
ONEPANEL_URL=https://panel.example.com \
ONEPANEL_APIKEY=你的APIKey \
bash scripts/sync-and-refresh.sh
```

`ONEPANEL_NODE` 可留空，默认操作主节点；多节点环境才需填写从节点名称。也可直接编辑脚本开头同名变量的默认值。

### 可用变量

| 变量 | 说明 | 默认值 |
| --- | --- | --- |
| `GIT_REPO` | 应用仓库地址 | `https://github.com/willow-god/appstore` |
| `TMP_DIR` | 临时克隆目录 | `/opt/1panel/resource/apps/local/appstore-localApps` |
| `LOCAL_APPS_DIR` | 1Panel 本地应用目录 | `/opt/1panel/resource/apps/local` |
| `ONEPANEL_URL` | 面板地址，可省略协议 | 必填 |
| `ONEPANEL_APIKEY` | 面板 API Key | 必填 |
| `ONEPANEL_NODE` | 节点名称，留空为主节点 | 空（主节点） |

### 鉴权方式

1Panel v2 API 使用时间戳加 MD5 鉴权：

```text
Token = md5("1panel" + APIKey + Timestamp)
```

请求会携带 `1Panel-Timestamp`、`1Panel-Token` 请求头，调用 `POST /api/v2/apps/sync/local`。`CurrentNode` 留空时不发送，1Panel 默认视为主节点。请确保服务器时间准确，并在脚本以非零状态码退出时接入告警。

---

## 📮 问题反馈

如发现配置错误或希望新增应用，欢迎在 Issues 区提交反馈：

- 🛠 [本仓库 Issues](https://github.com/willow-god/appstore/issues)

> ⚠️ 本项目仅对仓库中提供的应用内容提供支持。1Panel 本体问题请前往 [1Panel 主项目](https://github.com/1Panel-dev/1Panel/issues) 提问。

------

## ✨ 项目作者

- 💻 清羽飞扬（willow-god）
- 🌐 [个人主页](https://www.liushen.fun/)
- 📘 [技术博客](https://blog.liushen.fun/)

------

## 🧩 想添加自己的应用？

如果你希望向本仓库提交新应用或修改现有应用，请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)，其中说明了目录结构、`data.yml`、镜像版本、`.env` 应用清单和提交前检查清单。若想构建自己的 App Store 仓库，可参考官方教程：

👉 [📘 官方指南：如何提交自己想要的应用](https://github.com/1Panel-dev/appstore/wiki/如何提交自己想要的应用)
