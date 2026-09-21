# Hindsight

<div align="center">
  <img src="logo.png" alt="Hindsight" width="180" height="180">
</div>

Hindsight 是面向 AI Agent 的可自托管长期记忆服务。它把对话与文档中的事实、实体和关系抽取到 PostgreSQL，用语义、关键词、时间与图四条检索链路召回，再经由 reflect 流程作答；内置控制台（Control Plane）提供记忆库管理、检索调试与模型配置界面。

- 项目地址：[vectorize-io/hindsight](https://github.com/vectorize-io/hindsight)
- 官方文档：[hindsight.vectorize.io](https://hindsight.vectorize.io/developer/installation)
- 本应用使用的镜像：`ghcr.io/vectorize-io/hindsight:0.10.1-slim`

## 使用说明

- **控制台（GUI）端口**：`9999`，对应安装表单里的「控制台（GUI）端口」（`PANEL_APP_PORT_HTTP`）。
- **数据面 API 端口**：`8888`，对应「数据面 API 端口」（`PANEL_APP_PORT_API`）。API 与 MCP 都走这个端口。
- **数据持久化**：全部在 PostgreSQL 中。Hindsight 不使用本地卷 —— 记忆、实体、操作记录以及上传的文件附件（文件存储默认 `native`，即存 PostgreSQL 的 BYTEA 字段）都在你的数据库里。**备份应用等于备份这个数据库**，容器可以随时删除重建。
- **首次启动**：容器会自动在目标数据库的 `public` schema 中建表并执行迁移，首次启动到 `/health` 转为健康需要一两分钟，请耐心等待。健康检查探针会验证数据库连通性，因此数据库不可达时容器会显示为 unhealthy。
- **初始账号**：没有内置账号。控制台用「GUI 访问密钥」登录，API/MCP 用「API / MCP 访问密钥」鉴权，两者都在安装表单里随机生成；安装后在 1Panel 应用页的「参数」中可以查看和修改。

## 安装前置条件（重要）

1. **PostgreSQL 必须已安装 pgvector 扩展。**
   Hindsight 强制要求向量扩展（默认 `pgvector`，另有 `vchord` / `pgvectorscale` 可选），启动时会自行执行 `CREATE EXTENSION vector`，但扩展文件必须先存在于数据库。
   1Panel 官方 PostgreSQL 应用使用的 `postgres:XX-alpine` 镜像**不含** pgvector，需要把该应用的镜像换成带扩展的镜像（例如 `pgvector/pgvector:pg18`）或自行安装扩展。安装前可用下面这条语句确认：

   ```sql
   SELECT * FROM pg_available_extensions WHERE name = 'vector';
   ```

   返回空结果说明扩展不可用，Hindsight 会在迁移阶段直接失败。

2. **必须准备外部嵌入（Embeddings）服务。**
   本应用使用 `-slim` 镜像，镜像内**不含**本地嵌入与重排模型（这是 slim 变体与标准镜像的主要区别），所以嵌入必须走外部接口。表单里固定使用 OpenAI 兼容的嵌入接口，任何 OpenAI 兼容的嵌入服务（OpenAI、SiliconFlow、各家中转、TEI 网关等）都能用：填好接口地址与模型，API Key 留空时会自动复用全局 LLM 的 Key。

3. **LLM 需要足够大的输出上限。**
   Retain（事实提取）默认单次调用最多输出 64000 token，官方要求所选模型至少支持 65000 输出 token。如果你的模型输出上限较小（32k / 16k），请把表单里的「Retain 最大输出 Token」相应调低（例如 32000 或 16000）；该值必须大于 3000，否则启动即报错。

## 配置说明

### 全局 LLM

`HINDSIGHT_API_LLM_*` 四个字段是所有操作的默认模型：

| 表单字段 | 说明 |
| --- | --- |
| LLM 提供商 | `openai`、`anthropic`、`gemini`、`groq`、`deepseek`、`zai`、`minimax`、`atlas`、`meta`、`ollama`、`lmstudio`、`vertexai`、`bedrock`、`litellm` 等 |
| LLM API Key | 对应提供商的密钥 |
| LLM 模型 | 留空则使用该提供商的推荐默认模型（例如 `openai` → `gpt-4o-mini`） |
| LLM 接口地址 | 走 OpenAI 兼容端点时填写，通常是 `https://xxx/v1`（**不是**账号根地址） |

### 按操作拆分模型（子模型）

Hindsight 把一次记忆的写入和读取拆成几个独立操作，每个操作都可以单独指定模型、密钥和接口地址，未填写的字段会**逐级回落**：操作级 → 全局 LLM。这正是降低 token 开销的主要手段：把便宜的模型放在后台批量任务上，把贵的模型只留给真正需要的环节。

| 操作 | 表单前缀 | 干什么 | 选型建议 |
| --- | --- | --- | --- |
| Retain | `HINDSIGHT_API_RETAIN_LLM_*` | 从对话/文档中提取事实、实体、关系并写入记忆 | 结构化输出能力要好，不必是最强的推理模型 |
| Reflect | `HINDSIGHT_API_REFLECT_LLM_*` | 召回记忆后的多轮推理与作答 | 官方建议用**更小更快**的模型：它是交互路径上的主要延迟来源 |
| Consolidation | `HINDSIGHT_API_CONSOLIDATION_LLM_*` | 后台合并、去重已有事实 | 便宜的模型即可 |
| Mental Model Refresh | `HINDSIGHT_API_MENTAL_MODEL_REFRESH_LLM_*` | 后台刷新心智模型 | 建议 no-think 的快速模型，避免和交互式 Reflect 抢资源 |

四组字段每组的含义一致（提供商 / API Key / 模型 / 接口地址），**全部留空就等同于不拆分**，只跑全局 LLM。填的时候通常只需要填「模型」一个字段：只要模型所在的接口和密钥与全局一致，其余留空即可继承。

> 官方多模型策略（`HINDSIGHT_API_LLM_STRATEGY` 的 failover / round-robin / metadata 模式、`HINDSIGHT_API_LLM_1_*` 备选模型链）没有作为表单字段暴露，需要时在应用 compose 的 `environment` 中按官方 `.env.example` 自行补充。

### 视觉模型（VLM）

`HINDSIGHT_API_VLM_*` 只在 retain 内容**带图片附件**时生效，纯文本内容仍然走 Retain 模型，所以偶尔收几张截图不需要为全部记忆付费。留空时图片附件交给 Retain LLM 处理（该模型必须支持读图）。

### 嵌入与重排

- 嵌入：`HINDSIGHT_API_EMBEDDINGS_PROVIDER` 固定为 `openai`（OpenAI 兼容接口），表单提供 API Key / 接口地址 / 模型三项。**嵌入模型一旦写入记忆就不要随意更换**，更换会导致已有记忆与新记忆不在同一向量空间，需要重新向量化。
- 重排：表单只提供 `rrf`（仅用融合排序，无需外部服务）和 `none`（关闭重排）两个选项，因为 slim 镜像不含本地 cross-encoder。需要神经重排（`cohere`、`siliconflow`、`tei`、`google`、`alibaba`、`zeroentropy`、`typesafe`、`litellm` 等）时，在 compose 里把 `HINDSIGHT_API_RERANKER_PROVIDER` 改成目标值，并补上该提供商所需变量（例如 `HINDSIGHT_API_RERANKER_TEI_URL`）。

### 访问密钥与鉴权

- **API / MCP 访问密钥**（`HINDSIGHT_API_TENANT_API_KEY`）：Hindsight 默认**完全无鉴权**，本应用通过内置的 `ApiKeyTenantExtension` 打开 API Key 校验，请求必须携带 `Authorization: Bearer <密钥>`，否则返回 401。控制台访问数据面 API 时复用同一把密钥，无需另外配置。
- **GUI 访问密钥**（`HINDSIGHT_CP_ACCESS_KEY`）：访问控制台时会出现登录页，输入该密钥才能进入（`/api/health` 除外）。它必须与 API 访问密钥不同。

## 公网部署

### 端口与反向代理

- **控制台必须挂在域名的根路径**（`https://memory.example.com/`）。控制台是基于 Next.js 构建的，上游镜像在**构建期**就把基准路径烘焙进去了，运行时设置 `NEXT_PUBLIC_BASE_PATH` 不会改变前端资源与路由的基准路径，因此无法把 GUI 搬到子目录。
- **浏览器不需要直连 8888**。控制台是服务端代理：它读取 `HINDSIGHT_CP_DATAPLANE_API_URL`（镜像内默认为同容器的 `http://localhost:8888`）再去请求数据面。因此你可以只对外开放 9999，把 8888 留给 API/MCP 客户端或仅限内网。
- 只有 API / MCP 客户端（Claude Code、OpenCode、Codex 等）才需要访问 8888。要用域名访问时建议单独给 API 一个子域，或用 1Panel 反向代理加一条路径规则。
- 官方推荐通过 1Panel 反向代理配置域名与 HTTPS，不要直接把 8888 / 9999 暴露到公网。

### 可选：把 API 放到子路径

如果需要让 API 与其它服务共用同一个域名，可以给 API 设置基准路径（运行时生效）：

```yaml
HINDSIGHT_API_BASE_PATH: /mem
```

此时 API 的地址从 `https://example.com/` 变为 `https://example.com/mem/`，MCP 端点在 `https://example.com/mem/mcp/`。**同时必须让控制台指向同一个子路径**，否则控制台会 404：

```yaml
HINDSIGHT_CP_DATAPLANE_API_URL: http://localhost:8888/mem
```

也可以在 compose 里用 `${HINDSIGHT_API_BASE_PATH}` 拼接，保持两处一致。反向代理转发时需要**去掉** `/mem` 前缀（`proxy_pass http://127.0.0.1:8888/;` 末尾的斜杠即是此意）—— Hindsight 只是把该前缀作为 FastAPI 的 `root_path` 声明，容器内的路由仍然从 `/` 开始，因此健康检查探针不受影响。

### MCP

MCP 默认开启并挂在 API 服务的 `/mcp` 上，支持两种连接形式：`/mcp`（多记忆库模式）与 `/mcp/{bank_id}/`（单记忆库模式）。本应用开启了 API Key 校验后，MCP 请求同样需要携带 `Authorization: Bearer <API 访问密钥>`，例如：

```bash
claude mcp add --transport http hindsight https://memory.example.com/mem/mcp \
  --header "Authorization: Bearer <API 访问密钥>"
```

上游另有 `HINDSIGHT_API_MCP_AUTH_TOKEN`（legacy bearer token）和扩展配置项 `HINDSIGHT_API_TENANT_MCP_AUTH_DISABLED`，后者会让 MCP 端点免鉴权 —— **公网环境不要打开它**。

## 镜像与版本说明

- 本应用跟随上游的 **slim** 镜像变体（版本目录 `0.10.1-slim`）。使用 slim 的原因是拉取体积更小（镜像层压缩后约 458MB，标准镜像约 880MB），代价是嵌入与重排必须依赖外部服务 —— 这是 slim 与标准镜像的主要区别。
- 想改用镜像自带的本地嵌入/重排模型时，把 compose 中的镜像换成不带 `-slim` 的 tag（例如 `ghcr.io/vectorize-io/hindsight:0.10.1`），并把 `HINDSIGHT_API_EMBEDDINGS_PROVIDER` 改成 `local`、`HINDSIGHT_API_RERANKER_PROVIDER` 改成 `local`。标准镜像已预置 `BAAI/bge-small-en-v1.5`（嵌入）与 `cross-encoder/ms-marco-MiniLM-L-6-v2`（重排），无需联网下载。
- 上游同时提供带 `-slim` 和不带 `-slim` 的两套 tag，因此 `renovate.json` 中为该镜像加了 `allowedVersions` 规则，自动升级只会落在 `-slim` 这一支上，不会悄悄换成标准镜像。

## 官方文档

- [安装与部署](https://hindsight.vectorize.io/developer/installation)
- [模型配置（含各操作的模型选型）](https://hindsight.vectorize.io/developer/models)
- [存储与数据库要求](https://hindsight.vectorize.io/developer/storage)
- [MCP Server](https://hindsight.vectorize.io/developer/mcp-server)
- [完整环境变量清单 `.env.example`](https://github.com/vectorize-io/hindsight/blob/main/.env.example)
