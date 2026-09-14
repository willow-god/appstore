# 贡献指南：1Panel 第三方应用提交说明

本文用于指导在本仓库中新增或更新 1Panel 第三方应用。内容参考：

- [清羽飞扬：第三方 1Panel 应用商店不完全指北](https://blog.liushen.fun/posts/470abaf8/)
- [1Panel 官方：How to submit your own application](https://github.com/1Panel-dev/appstore/wiki/How-to-submit-your-own-application)

官方文档描述的是官方 `appstore` 仓库。本仓库是基于同一应用格式维护的第三方仓库，并额外使用了 `mirror.sh`、Renovate 和 GitHub Actions 处理镜像替换与版本目录更新。因此提交时应以本文和仓库现有应用为准。

## 一、应用目录结构

每个应用必须使用下面的结构：

```text
apps/<app-key>/
├── data.yml                  # 应用级元数据
├── README.md                 # 应用说明，显示在应用详情页
├── logo.png                  # 应用图标，必须放在应用根目录
└── <version>/
    ├── data.yml              # 当前版本的安装表单和环境变量
    └── docker-compose.yml    # 当前版本的 Compose 文件
```

例如：

```text
apps/openviking/
├── data.yml
├── README.md
├── logo.png
└── 0.4.20/
    ├── data.yml
    └── docker-compose.yml
```

版本目录中还可以放 `data/`、`scripts/` 等内容，但只有在应用确实需要时才添加。持久化数据应通过 `./data` 挂载到应用目录，避免把运行时数据提交到 Git。

### 必须遵守的命名关系

- `<app-key>` 必须与根 `data.yml` 中 `additionalProperties.key` 完全一致。
- `<app-key>` 只能使用英文小写、数字和连字符等适合 Linux 目录的名称。
- `<version>` 是应用商店显示和比较版本的依据，优先使用不带 `v` 前缀的 SemVer 目录名，例如 `0.4.20`。只有上游确实不发布版本号时才使用 `latest`，详见第二节。
- 版本目录内的镜像 tag 通常可以保留项目原始的 `v` 前缀，例如 `ghcr.io/example/app:v0.4.20`。本仓库的自动化会在重命名目录时去除镜像版本前的 `v`。
- 同一个应用可以并存多个版本目录，例如 `0.4.19/` 和 `0.4.20/`。

## 二、版本号与 `latest` 的使用原则

### 优先使用明确版本

1Panel 判断应用更新时，主要比较版本目录名称，而不是只看 Compose 内的镜像 tag。例如：

```text
apps/example/0.4.19/
apps/example/0.4.20/
```

如果目录一直叫 `latest/`，应用商店无法可靠判断新旧版本，也无法向用户展示明确的升级版本。因此：

- 版本目录名优先使用不带 `v` 前缀的明确版本，例如 `0.4.20`。
- Compose 中优先使用带明确版本 tag 的镜像。

镜像推荐写法：

```yaml
services:
  example:
    image: ghcr.io/example/example:v0.4.20
```

### 上游只有 `latest` 时的例外情况

如果上游仓库本身不发布任何带版本号的 tag，镜像只提供 `latest`，则无法凭空编造版本号，此时允许使用 `latest`：

- 版本目录名使用 `latest`，例如 `apps/example/latest/`。
- Compose 中的镜像 tag 使用 `latest`。
- 由于 Renovate 无法从 `latest` 判断版本变化，该应用不会自动产生版本升级 PR，也不会触发版本目录重命名，需要用户手动重新安装或重新拉取镜像来更新。

```text
apps/example/
├── data.yml
├── README.md
├── logo.png
└── latest/
    ├── data.yml
    └── docker-compose.yml
```

使用 `latest` 时，建议在根目录 `README.md` 中明确说明「上游未提供版本号，本应用跟随 `latest`，需要自行更新」，避免用户误以为应用商店会自动提示升级。仓库中已有部分应用采用这种写法，可对照参考。

### 需要注意

- 不要在同一个应用内混用明确版本目录和 `latest` 目录，避免版本比较混乱。
- 如果上游后续开始发布版本号，应迁移到明确版本目录。
- 明确版本和 `latest` 的选择依据是上游是否真实提供版本号，而不是为了方便。

### 不要把整个镜像写成变量默认值

也不要把整个镜像写成：

```yaml
image: ${APP_IMAGE:-ghcr.io/example/example:v0.4.20}
```

后一种写法虽然是 Docker Compose 支持的变量默认值语法，但不适合本仓库，原因如下：

- 本仓库的 `mirror.sh` 通过匹配 `ghcr.io/`、`quay.io/` 等字面量替换镜像地址。使用变量表达式后，脚本无法识别原始镜像仓库。
- Renovate 需要从 `image:` 行解析镜像名和版本号。变量表达式会使镜像依赖无法稳定识别。
- `.github/workflows/renovate-app-version.yml` 会读取 `image:` 行的冒号后内容，并据此重命名版本目录。使用变量表达式时，解析结果可能是变量文本而不是实际版本。
- 版本级 `data.yml` 中声明的 `envKey` 必须在 Compose 中实际使用。没有实际用途的镜像表单字段会造成配置项和部署行为不一致。

因此，本仓库推荐：

```yaml
image: ghcr.io/volcengine/openviking:v0.4.20
```

GHCR、Quay 等镜像的加速替换由仓库根目录的 `mirror.sh` 和服务器上的 `/opt/mirror-config.env` 统一完成，不通过应用安装表单传入镜像地址。

## 三、根目录 `data.yml`

根目录 `data.yml` 只描述应用本身，不放安装表单字段。推荐结构：

```yaml
name: Example
tags:
  - AI
  - Tool
title: 应用标题
description: 应用简介
additionalProperties:
  key: example
  name: Example
  tags:
    - Tool
  shortDescZh: 中文短描述
  shortDescEn: English short description
  type: tool
  crossVersionUpdate: true
  limit: 0
  recommend: 0
  website: https://example.com
  github: https://github.com/example/example
  document: https://example.com/docs
  description:
    en: English description.
    zh: 中文描述。
    zh-Hant: 繁體中文描述。
  architectures:
    - amd64
    - arm64
```

### 字段说明

- `name`：应用显示名称。
- 顶层 `tags`：应用分类展示标签。本仓库沿用现有应用的中文标签写法。
- `title`：应用标题。
- `description`：应用简介。
- `additionalProperties.key`：应用唯一 key，必须等于应用目录名。
- `additionalProperties.name`：应用商店中的名称。
- `additionalProperties.tags`：1Panel 识别的标签，优先使用 `WebSite`、`Server`、`Runtime`、`Database`、`Tool`、`CI/CD`、`Local` 等官方标签。
- `type`：`website`、`runtime` 或 `tool`，只能填写一个。
- `crossVersionUpdate`：是否允许跨大版本更新。普通应用一般使用 `true`。
- `limit`：安装限制，`0` 表示不限制。
- `recommend`：推荐权重，普通应用可以使用 `0`。
- `website`、`github`、`document`：项目相关链接。
- `description`：至少提供 `en` 和 `zh`，可按需要补充 `zh-Hant`、`ja`、`ms`、`pt-br`、`ru`、`ko`。
- `architectures`：根据镜像实际支持情况填写，不能为了通过检查而虚构架构。

## 四、版本目录 `data.yml`

版本目录内的 `data.yml` 不是应用元数据，而是用于生成 1Panel 安装表单。即使没有可配置项，也必须保留该文件，并包含 `additionalProperties.formFields`。

最小端口字段示例：

```yaml
additionalProperties:
  formFields:
    - default: 8080
      envKey: PANEL_APP_PORT_HTTP
      labelEn: HTTP Port
      labelZh: HTTP 端口
      label:
        en: HTTP Port
        zh: HTTP 端口
        zh-Hant: HTTP 連接埠
      required: true
      rule: paramPort
      type: number
```

### 表单字段规则

`envKey` 是安装时写入 `.env` 的变量名，并且必须在 `docker-compose.yml` 中被实际引用。例如：

```yaml
# 版本 data.yml
envKey: PANEL_APP_PORT_HTTP

# docker-compose.yml
ports:
  - "${PANEL_APP_PORT_HTTP}:8080"
```

常用字段类型：

- `number`：端口等数字字段。
- `text`：普通文本字段。
- `password`：密码、密钥等敏感字段。
- `select`：固定选项。
- `service` 或 `apps`：依赖其他 1Panel 应用时使用。

常用校验规则：

- `paramPort`：端口范围校验。
- `paramExtUrl`：外部 URL 校验。
- `paramCommon`：普通文本校验。
- `paramComplexity`：复杂密码校验。

建议为公开 HTTP 服务使用 `PANEL_APP_PORT_HTTP`，因为 1Panel 会把 `PANEL_APP_PORT` 前缀识别为端口字段并在安装前检查端口冲突。这里填写的是宿主机端口，不是容器端口。

### 字段最小化原则

只为用户真正需要配置的内容添加表单字段。镜像版本、容器内部固定端口、固定路径等不应无意义地暴露成表单项。

例如 OpenViking 的镜像应直接写在 Compose 中：

```yaml
image: ghcr.io/volcengine/openviking:v0.4.20
```

而不是额外创建一个用户可编辑的 `OPENVIKING_IMAGE` 字段。这样能保持镜像版本、目录版本和自动更新逻辑一致。

## 五、`docker-compose.yml` 编写规则

推荐使用以下基础结构：

```yaml
services:
  example:
    image: ghcr.io/example/example:v0.4.20
    container_name: ${CONTAINER_NAME}
    restart: always
    labels:
      createdBy: "Apps"
    ports:
      - "${PANEL_APP_PORT_HTTP}:8080"
    volumes:
      - ./data:/app/data
    environment:
      TZ: Asia/Shanghai
    networks:
      - 1panel-network

networks:
  1panel-network:
    external: true
```

### Compose 要点

- 服务名使用简洁、稳定的英文名称。
- `container_name` 使用 `${CONTAINER_NAME}`，由 1Panel 生成实例名。
- 必须连接外部网络 `1panel-network`，与本仓库其他应用保持一致。
- 添加 `labels.createdBy: "Apps"`。
- 宿主机端口使用版本 `data.yml` 声明的 `${PANEL_APP_PORT_HTTP}`。
- 配置、数据库和运行数据优先挂载到 `./data` 下。
- 容器内端口、内部路径和镜像版本应直接写入 Compose，除非确实需要用户配置。
- 健康检查应使用镜像提供的可靠检查命令；没有可靠命令时不要凭空添加。
- 多服务 Compose 中，如果某个服务只是基础依赖或辅助服务，不应被版本更新脚本选为主应用镜像，可以在 `image:` 行添加 `[ignore]` 注释，例如 `image: docker:dind # [ignore]`。
- 不要提交密码、Token、私钥或真实域名。

## 六、Logo 和 README

### Logo

- 文件名必须为 `logo.png`。
- 必须放在 `apps/<app-key>/logo.png`，不放在版本目录中。
- 官方文档建议约 `180x180` 且不超过 `10 KB`；本仓库已有应用可能存在不同尺寸，但新应用应尽量遵守官方建议。
- Logo 应实际提交到仓库，不要只在 README 中引用远程图片。

### README

根目录 `README.md` 用于应用详情页，至少应说明：

- 应用用途。
- 默认访问端口。
- 数据持久化位置。
- 初始账号或首次启动操作（如果有）。
- 重要配置项。
- 官方项目文档链接。
- 反向代理、HTTPS 或外部依赖的特殊说明。

## 七、镜像加速与 `.env` 配置

`mirror.sh` 的镜像替换依赖两个文件：

| 文件 | 位置 | 作用 | 是否提交 |
| --- | --- | --- | --- |
| `.env` | 仓库根目录 | 声明每个镜像源下**有哪些应用**需要替换 | 是 |
| `mirror-config.env` | 服务器 `/opt/mirror-config.env` | 声明**是否启用**该源以及**替换成哪个地址** | 否 |

### 7.1 根目录 `.env` 的作用

根目录 `.env` **不是给应用安装使用的**，而是 `mirror.sh` 的「应用清单」。脚本会重新 `source` 该文件，然后按镜像源分组遍历应用列表。只有出现在对应列表里的应用，其版本目录下的 `docker-compose.yml` 才会执行该镜像源的替换。

本仓库当前内容示例：

```ini
# ghcr.io 源的应用列表（逗号分隔）
GHCR_IO_LIST="moontv,umami-mysql,umami-pgsql,hubproxy,tinyauth,termix,chronoframe,axonhub-lite-mysql,openviking"

# quay.io 源的应用列表
QUAY_IO_LIST=""

# gcr.io 源的应用列表
GCR_IO_LIST=""

# k8s.gcr.io 源的应用列表
K8S_GCR_IO_LIST=""

# registry.k8s.io 源的应用列表
REGISTRY_K8S_IO_LIST=""

# docker.io 之外的所有应用列表
NON_DOCKER_IO_LIST=""
```

使用规则：

- 变量值填写**应用目录名**（app-key），使用英文逗号分隔，不要添加空格。
- 应用使用 `ghcr.io` 镜像时，必须把它的 app-key 加入 `GHCR_IO_LIST`，否则 `mirror.sh` 不会替换该应用。
- `mirror.sh` 开头会检查 `.env` 是否存在，缺失时直接 `exit 1`，因此不要删除该文件。
- 如果 `.env` 中列出的应用目录不存在，脚本会打印「应用目录不存在，跳过」并继续执行，不会中断。
- 新增应用的 PR 中，如果该应用需要镜像替换，必须同时修改 `.env` 和 `mirror-config.env` 说明。

> 已知问题：`mirror.sh` 中 `K8S_GCR` 一项读取的变量名是 `K8S_GCR_IO_ARRAY`，与 `.env` 中定义的 `K8S_GCR_IO_LIST` 不一致；`K8S_REG`（`registry.k8s.io`）读取的是 `NON_DOCKER_IO_LIST`，而不是 `.env` 中定义的 `REGISTRY_K8S_IO_LIST`，该变量当前未被使用。这两处会导致对应的替换不会按预期命中。如确有需要，请先修正脚本中的变量名。

### 7.2 `.env` 与其他 `.env` 的区别

本仓库存在两种容易混淆的 `.env`：

| 文件 | 位置 | 作用 |
| --- | --- | --- |
| 仓库根目录 `.env` | 由维护者提交到仓库 | `mirror.sh` 的应用清单，决定哪些应用执行镜像替换 |
| 应用目录下的 `.env` | 部署时由 1Panel 自动生成 | 保存安装表单填写的值，供该应用的 Compose 读取 |

不要把这两者混为一谈：应用安装时生成的 `.env` 是被 Compose 消费的；仓库根目录的 `.env` 只服务于 `mirror.sh`。提交应用时不要提交应用目录下的 `.env`。

### 7.3 服务器端 `mirror-config.env`

`mirror.sh` 会读取：

```text
/opt/mirror-config.env
```

根据配置替换应用 Compose 中的镜像仓库前缀。当前支持的主要源包括：

- `ghcr.io`
- `quay.io`
- `gcr.io`
- `k8s.gcr.io`
- `registry.k8s.io`

示例：

```ini
GHCR_ENABLE=true
GHCR_MIRROR=ghcr.io.mirror
```

应用 Compose 必须保留原始仓库字面量，示例：

```yaml
image: ghcr.io/volcengine/openviking:v0.4.20
```

不要写成 `${OPENVIKING_IMAGE}` 或 `${OPENVIKING_IMAGE:-...}`，否则 `mirror.sh` 无法按仓库前缀替换。

镜像替换只改变拉取地址，不改变版本目录的版本号，也不影响 1Panel 的升级判断。

## 八、版本更新流程

本仓库使用 Renovate 检测 Compose 中的 Docker 镜像更新：

1. Renovate 定时扫描 `apps/*/*/docker-compose.yml`。
2. 识别 `image: registry/name:tag` 中的镜像和版本。
3. 检测到新版本后修改 Compose 中的 tag，并创建 Renovate 分支或 PR。
4. `.github/workflows/renovate-app-version.yml` 读取被修改的 Compose 文件。
5. 工作流从 `image:` 行提取新版本，去掉开头的 `v`。
6. 工作流把版本目录从旧版本重命名为新版本，例如 `0.4.20` 改为 `0.4.21`。
7. 工作流提交目录迁移结果并继续处理 PR。

因此一次版本更新必须保持以下三者一致：

```text
目录：apps/example/0.4.21/
镜像：registry.example/example:v0.4.21
Compose：位于 apps/example/0.4.21/docker-compose.yml
```

特殊 tag 格式（例如 `release-2.7.1`、`mysql-latest`）必须在 `renovate.json` 中添加对应的 `versionCompatibility` 或排除规则，否则不要假设 Renovate 能正确处理。

## 九、新增应用提交步骤

### 1. 确认上游项目

确认项目满足：

- 仍在维护。
- 有公开源码或公开项目主页。
- 有官方或可信的 Docker 镜像。
- 已确认镜像支持的 CPU 架构。
- 已确认容器端口、启动命令、健康检查和数据目录。
- 已确认镜像 tag 的版本格式。

### 2. 创建目录和文件

```text
apps/<app-key>/
├── data.yml
├── README.md
├── logo.png
└── <version>/
    ├── data.yml
    └── docker-compose.yml
```

版本目录名不要添加 `v` 前缀。如果上游确实没有版本号，可使用 `latest`，但需按第二节说明处理。

### 3. 填写根 `data.yml`

先复制一个结构最接近的现有应用作为参考，例如：

```text
apps/maibot/
apps/chronoframe/
apps/pansou/
```

然后只修改应用元数据。确认 `key` 与目录名完全一致。

### 4. 填写版本 `data.yml`

只添加实际需要的安装字段。对外 HTTP 服务通常至少需要 `PANEL_APP_PORT_HTTP`。

### 5. 编写 Compose

使用固定版本镜像和本仓库网络、容器名、标签、挂载目录约定。所有 `${...}` 变量都必须在版本 `data.yml` 中声明。

### 6. 添加 Logo 和 README

Logo 放根目录。README 不要只复制上游 README，应补充本仓库应用的端口、挂载目录和安装注意事项。

### 7. 本地校验

在仓库根目录执行：

```powershell
python -c "import yaml; from pathlib import Path; files=['apps/example/data.yml','apps/example/0.4.20/data.yml','apps/example/0.4.20/docker-compose.yml']; [yaml.safe_load(Path(f).read_text(encoding='utf-8')) for f in files]; print('YAML OK')"
git diff --check
```

另外检查：

```powershell
Get-ChildItem apps/example -Recurse
rg "latest|image:|PANEL_APP_PORT|CONTAINER_NAME" apps/example
```

确认：

- 两个 `data.yml` 都能解析。
- Compose 中的变量都在版本 `data.yml` 中声明。
- Compose 中的镜像使用明确版本号（上游只有 `latest` 除外）。
- 版本目录名与镜像版本对应（使用 `latest` 时目录名也应为 `latest`）。
- Logo 位于应用根目录。
- 所有数据挂载都位于 `./data` 下或有明确理由。
- 没有多余的 `.env`、密钥或运行时数据库文件。

如果本机安装了 Docker，还可以在版本目录执行：

```bash
docker compose config
```

检查 Compose 展开结果；如果需要实际启动，再执行：

```bash
docker compose up -d
```

### 8. 提交变更

```bash
git status --short
git add apps/example
git commit -m "Add example app"
git push
```

本仓库不要求为每个应用单独创建提交脚本；如修改了现有工作流或 Renovate 规则，应在提交说明中解释原因。

## 十、提交前检查清单

- [ ] 应用目录名与 `additionalProperties.key` 一致。
- [ ] 根目录存在 `data.yml`、`README.md` 和 `logo.png`。
- [ ] 版本目录名不带 `v` 前缀；使用 `latest` 时已确认上游确实没有版本号，并在 README 中说明。
- [ ] 版本目录存在 `data.yml`，并包含 `additionalProperties.formFields`。
- [ ] Compose 中所有 `${...}` 变量都在版本 `data.yml` 中声明。
- [ ] Compose 中的镜像包含真实版本号（上游只有 `latest` 时除外）。
- [ ] 不使用 `${IMAGE:-default}` 形式隐藏镜像地址。
- [ ] 使用 `latest` 时已确认上游无版本号，且已在 README 中说明需自行更新。
- [ ] GHCR 等镜像保留字面量仓库地址，便于 `mirror.sh` 替换。
- [ ] 使用 `ghcr.io` 等镜像的应用已加入根目录 `.env` 的对应 `*_IO_LIST`。
- [ ] `container_name` 使用 `${CONTAINER_NAME}`。
- [ ] HTTP 宿主机端口使用 `${PANEL_APP_PORT_HTTP}`。
- [ ] 服务连接 `1panel-network`。
- [ ] 服务包含 `createdBy: "Apps"` 标签。
- [ ] 数据挂载在 `./data` 下。
- [ ] Logo 已实际提交且位于应用根目录。
- [ ] YAML 解析通过。
- [ ] `git diff --check` 通过。
- [ ] 没有提交敏感信息和运行时数据。

## 十一、当前仓库的额外约定

与官方模板相比，本仓库还包含以下行为：

- 根目录 `.env` 维护各镜像源对应的应用清单，供 `mirror.sh` 判断需要替换哪些应用。
- `mirror.sh` 根据 `/opt/mirror-config.env` 替换 GHCR、Quay、GCR 和 Kubernetes 镜像源。
- `renovate.json` 使用 Renovate 自动检测 Docker 镜像更新。
- `.github/workflows/renovate-app-version.yml` 会根据 Compose 镜像 tag 自动重命名版本目录。
- 应用同步脚本会把仓库 `apps/` 下的应用复制到 1Panel 的 `/opt/1panel/resource/apps/local/`。
- `scripts/sync-and-refresh.sh` 在完成同步后调用 1Panel API 刷新本地应用商店，详见第十二节。
- 新增应用时应优先复用仓库现有应用的格式，不要直接套用与本仓库自动化冲突的官方示例。

## 十二、全量同步并刷新应用商店（API）

仓库根目录的 `scripts/sync-and-refresh.sh` 是独立脚本，与 README 中「同步更新脚本」「单应用同步」互相独立、互不替代：

| 脚本 | 是否复制应用文件 | 是否执行 mirror.sh | 是否调用 1Panel API 刷新 |
| --- | --- | --- | --- |
| README 全量同步脚本 | 是 | 是 | 否，需要手动到面板点「更新应用列表」 |
| README 单应用同步脚本 | 是（部分应用） | 是 | 否 |
| `scripts/sync-and-refresh.sh` | 是（全部） | 是 | 是 |

适用场景：服务器做完全局软件更新、或应用商店内容有变更后，希望一次性把最新应用文件落地并让 1Panel 立即重新扫描，无需手动点击面板按钮。

### 12.1 使用方式

先把脚本放到服务器上，然后设置必要变量执行：

```bash
ONEPANEL_URL=https://panel.example.com \
ONEPANEL_APIKEY=你的APIKey \
bash scripts/sync-and-refresh.sh
```

`ONEPANEL_NODE` 可留空，默认操作主节点；多节点环境才需要填写从节点名称。

也可以直接编辑脚本开头的变量默认值。

### 12.2 可用变量

| 变量 | 说明 | 默认值 |
| --- | --- | --- |
| `GIT_REPO` | 应用仓库地址 | `https://github.com/willow-god/appstore` |
| `TMP_DIR` | 临时克隆目录 | `/opt/1panel/resource/apps/local/appstore-localApps` |
| `LOCAL_APPS_DIR` | 1Panel 本地应用目录 | `/opt/1panel/resource/apps/local` |
| `ONEPANEL_URL` | 面板地址，可省略协议 | 必填 |
| `ONEPANEL_APIKEY` | 面板 API Key | 必填 |
| `ONEPANEL_NODE` | 节点名称，留空为主节点 | 空（主节点） |

### 12.3 脚本流程

1. 克隆应用仓库到临时目录，退出时通过 `trap` 自动清理。
2. 进入仓库执行 `mirror.sh`，按 `.env` 与 `/opt/mirror-config.env` 完成镜像替换。
3. 遍历 `apps/`，把每个应用复制到 `/opt/1panel/resource/apps/local/`，覆盖旧版本。
4. 生成随机 `TASK_ID` 和秒级时间戳。
5. 计算 `Token = md5("1panel" + APIKey + Timestamp)`。
6. 调用 `POST /api/v2/apps/sync/local`，携带 `1Panel-Timestamp`、`1Panel-Token`、`CurrentNode` 请求头。
7. 校验响应中包含 `"code":200`，失败时以非零状态码退出，便于接入定时任务告警。

### 12.4 API 鉴权说明

1Panel v2 的 API 使用时间戳加 MD5 的方式鉴权：

```text
Token = md5("1panel" + APIKey + Timestamp)
```

- `Timestamp` 为秒级时间戳，与请求头 `1Panel-Timestamp` 保持一致。
- 时间戳与服务器时间偏差过大会导致鉴权失败，请确认服务器时间已同步。
- `CurrentNode` 请求头表示操作哪个节点，留空时不发送该头，1Panel 默认将其视为主节点（内部标识为 `local`）。只有多节点环境操作从节点时才需要填写节点名称。
- API Key 属于敏感信息，不要提交到仓库，建议通过环境变量或服务器的 root-only 文件传入。

### 12.5 定时执行建议

如需自动化，可在服务器上配置定时任务，例如：

```bash
# 每天凌晨 4 点同步并刷新
0 4 * * * ONEPANEL_URL=https://panel.example.com ONEPANEL_APIKEY=xxxx /bin/bash /opt/scripts/sync-and-refresh.sh >> /var/log/appstore-sync.log 2>&1
```

建议同时把日志文件加入轮转，避免长期运行占满磁盘。
