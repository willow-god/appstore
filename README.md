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

## 🔄 同步脚本

同步逻辑都放在仓库的 `scripts/` 目录里，脚本和应用在同一份克隆中，所以每一份用法都是完整、可直接贴进 1Panel 定时任务的脚本：先克隆，再用绝对路径执行。

| 脚本 | 作用 |
| --- | --- |
| `scripts/sync-apps.sh` | 把克隆里的应用复制到 1Panel 本地应用目录，并清理超量历史版本 |
| `scripts/mirror.sh` | 对**已部署**的应用目录做镜像源替换，并执行 `adapters/` 下的适配脚本 |
| `scripts/refresh.sh` | 只调用 1Panel API，刷新本地应用商店列表 |
| `scripts/check-env.sh` | 校验环境变量并填默认值，被上面几个脚本 `source`，变量不全时不继续执行 |

三个脚本各做一件事，互不调用。完整链路按顺序串起来执行（下面各用法里都是这套顺序）：

```bash
bash "$TMP_WORK_DIR/scripts/sync-apps.sh" && bash "$TMP_WORK_DIR/scripts/mirror.sh" && bash "$TMP_WORK_DIR/scripts/refresh.sh"
```

镜像替换必须在 `sync-apps.sh` 之后（副本覆盖回未替换的版本，每次同步后都要重新替换）；`refresh.sh` 只刷新列表，不复制文件。

### `scripts/` 和 `adapters/` 的区别

- `scripts/`：所有同步流程共用的**全局脚本**，负责克隆落盘、镜像替换、刷新这一整套拉起流程，每个脚本只做一件事，改动会影响全部应用。
- `adapters/`：针对**单个应用**的适配脚本，比如清理已下线应用（`prune-apps.sh`）。`scripts/mirror.sh` 会按文件名顺序执行这里的每个 `.sh`，不需要注册。

### 环境变量

脚本顶部的变量已收敛为 `PANEL_ROOT` 和 `GIT_REPO`，其余目录由它们推导，不用再逐个填写。

| 变量 | 说明 | 默认值 |
| --- | --- | --- |
| `PANEL_ROOT` | 1Panel 安装根目录 | `/opt/1panel` |
| `GIT_REPO` | 应用仓库地址 | `https://github.com/willow-god/appstore` |
| `APPS` | 只同步指定应用，逗号或空格分隔；留空表示全部 | 空（全部） |
| `REPO_DIR` | 已克隆好的仓库目录，设置后 `sync-apps.sh` 不再重复克隆 | 空（现场克隆） |
| `KEEP_VERSIONS` | 兜底时每个应用保留的历史版本目录数量（能查到数据库时不生效） | `10` |
| `ONEPANEL_URL` | 面板地址，可省略协议（仅 `refresh.sh`） | 必填 |
| `ONEPANEL_APIKEY` | 面板「设置 - 密钥」生成的 API Key（仅 `refresh.sh`） | 必填 |
| `ONEPANEL_NODE` | 节点名称，留空操作主节点 | 空（主节点） |

以下目录自动推导，一般不需要设置：

```text
LOCAL_APPS_DIR = $PANEL_ROOT/resource/apps/local    # 1Panel 本地应用目录
TMP_DIR        = $LOCAL_APPS_DIR/tmp-appstore      # 临时克隆目录，退出时自动删除
PANEL_DB       = $PANEL_ROOT/db/agent.db            # 数据库，只读查询已安装版本
```

### 1. 同步全部应用

下面这段就是完整的定时任务脚本（脚本都在仓库里，所以要先克隆）：

```bash
#!/bin/bash
# 1Panel 安装根目录；LOCAL_APPS_DIR、TMP_DIR 都由它推导，通常不用改
export PANEL_ROOT=/opt/1panel

# 应用仓库地址；国内环境换成镜像仓库 https://cnb.cool/Liiiu/appstore 即可
export GIT_REPO=https://github.com/willow-god/appstore

# 只同步指定应用（应用目录名，逗号或空格分隔）；不设置表示同步全部
# export APPS="whoami,ech0"

# 读不到数据库时兜底保留的历史版本目录数，默认 10；见下文「历史版本保留」
# export KEEP_VERSIONS=10

# 脚本在仓库里，先克隆到临时目录；带 tmp- 前缀、和本地应用目录同级，
# 跑完（含失败）自动删除
TMP_WORK_DIR="$PANEL_ROOT/resource/apps/local/tmp-appstore"
trap 'rm -rf "$TMP_WORK_DIR"' EXIT
rm -rf "$TMP_WORK_DIR"
git clone --depth 1 "$GIT_REPO" "$TMP_WORK_DIR" || exit 1

# 让 sync-apps.sh 直接复用这份克隆，不再重复克隆
export REPO_DIR="$TMP_WORK_DIR"

bash "$TMP_WORK_DIR/scripts/sync-apps.sh" || exit 1
bash "$TMP_WORK_DIR/scripts/mirror.sh"
```

同步完成后到面板「应用商店 → 本地应用」点「更新应用列表」；想让脚本自己刷新见第 3 种用法。

### 2. 同步单独应用

同样是一份完整的定时任务脚本，只多了 `APPS`：

```bash
#!/bin/bash
export PANEL_ROOT=/opt/1panel
export GIT_REPO=https://github.com/willow-god/appstore

# 只同步这几个应用；名字是 apps/ 下的目录名，不是商店里显示的名称
export APPS="whoami,ech0,moments"

TMP_WORK_DIR="$PANEL_ROOT/resource/apps/local/tmp-appstore"
trap 'rm -rf "$TMP_WORK_DIR"' EXIT
rm -rf "$TMP_WORK_DIR"
git clone --depth 1 "$GIT_REPO" "$TMP_WORK_DIR" || exit 1
export REPO_DIR="$TMP_WORK_DIR"

bash "$TMP_WORK_DIR/scripts/sync-apps.sh" || exit 1
bash "$TMP_WORK_DIR/scripts/mirror.sh"
```

### 3. 同步后自动刷新应用商店（API）

不想手动点「更新应用列表」时，在同步和镜像替换之后执行 `refresh.sh`，它只调用 `POST /api/v2/apps/sync/local`：

```bash
#!/bin/bash
export PANEL_ROOT=/opt/1panel
export GIT_REPO=https://github.com/willow-god/appstore

# 面板地址，可省略 http(s)://，但端口要写全
export ONEPANEL_URL=https://panel.example.com:端口

# 面板「设置 → 密钥」里生成的 API Key，属于敏感信息，不要提交到仓库
export ONEPANEL_APIKEY=你的APIKey

# 多节点环境操作从节点时填写节点名称；留空或注释掉表示主节点
# export ONEPANEL_NODE=节点名

# 同样可以只同步部分应用
# export APPS="whoami,ech0"

TMP_WORK_DIR="$PANEL_ROOT/resource/apps/local/tmp-appstore"
trap 'rm -rf "$TMP_WORK_DIR"' EXIT
rm -rf "$TMP_WORK_DIR"
git clone --depth 1 "$GIT_REPO" "$TMP_WORK_DIR" || exit 1
export REPO_DIR="$TMP_WORK_DIR"

bash "$TMP_WORK_DIR/scripts/sync-apps.sh" || exit 1
bash "$TMP_WORK_DIR/scripts/mirror.sh" || exit 1
bash "$TMP_WORK_DIR/scripts/refresh.sh"
```

鉴权方式：`Token = md5("1panel" + APIKey + Timestamp)`，请求携带 `1Panel-Timestamp`、`1Panel-Token` 请求头。请确保服务器时间准确，并把非零退出码接入告警。

三个脚本各自独立：想跳过刷新就不写最后一行，只想改镜像就单独跑 `mirror.sh`。

### 历史版本保留

`sync-apps.sh` 覆盖仓库里存在的版本目录，其余旧目录按两档规则清理：

1. **能查到准确数据时（推荐）**：以只读方式查询 `$PANEL_DB`（由 `PANEL_ROOT` 拼出，即 `$PANEL_ROOT/db/agent.db`）里的 `app_installs`，**只保留「仓库里有的版本」和「已安装的版本」**，其余旧目录全部删除，不受 `KEEP_VERSIONS` 限制。
2. **查不到时**：没有 `sqlite3`、数据库文件不存在、被占用、应用还没入库或存在失效指针，退回「保留最近 `KEEP_VERSIONS` 个」（默认 10）的兜底规则。

`KEEP_VERSIONS` 只在兜底规则里生效；能读到数据库时按实际安装情况清理，残留最少。

数据库只用于 `SELECT`，连接带 `-readonly` 参数和 `PRAGMA query_only=ON`，不会写入数据库，也不会创建 `-wal`/`-shm` 文件。

原因在 1Panel 的本地应用同步逻辑：它会删掉磁盘上已不存在的版本对应的 `app_details` 记录，但 `app_installs.app_detail_id` 仍指向那条记录，于是已安装应用的详情页和升级会报 `unexpected end of json input`。仓库通常只保留最新一个版本目录，直接整目录替换就会不断制造这种悬挂指针；保留已安装版本的目录是避免这个问题的关键。

每次清理只输出有变化的行，例如：

```text
🗄 已连接 1Panel 数据库（只读）: /opt/1panel/db/agent.db
✅ memora：已安装 1.5.3；目录 13 个 → 保留 2 个，删除 11 个（1.4.0、1.3.2、1.2.0、1.1.0、1.0.8、等）
✅ 已同步 43 个应用到 /opt/1panel/resource/apps/local：检查 43 个，39 个无变化，删除 11 个旧版本目录
```

出现 `⚠️` 表示该应用退回兜底规则，原因（数据库缺失、被锁、指针失效等）会一并打印。

> 💡 脚本只负责复制应用；上游已下线（或从未出现在仓库里）的应用不会自动从 1Panel 本地应用目录消失。仓库根目录 `.env` 的 `PRUNE_APPS` 就是用来清理它们的：执行 `scripts/mirror.sh` 时 `adapters/prune-apps.sh` 会删除 `$LOCAL_APPS_DIR/<应用名>` 这份已部署副本（不会卸载已安装实例）。详见 [CONTRIBUTING.md](CONTRIBUTING.md)。

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

同步完成后执行 `scripts/mirror.sh`，对已部署目录完成镜像源替换。

这样即使镜像源被墙，也能快速替换为你配置的加速地址。

> **目前还在测试中**：由于目前还在测试中，所以可能会出现一些问题。如果出现问题，请及时反馈。

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
