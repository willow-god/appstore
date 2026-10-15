# Hindsight

<div align="center">
  <img src="logo.png" alt="Hindsight" width="180" height="180">
</div>

Hindsight 是面向 AI Agent 的可自托管长期记忆服务。它把对话与文档中的事实、实体和关系抽取到 PostgreSQL，用语义、关键词、时间与图四条检索链路召回，再经由 reflect 流程作答；内置控制台（Control Plane）提供记忆库管理、检索调试与模型配置界面。

- 项目地址：[vectorize-io/hindsight](https://github.com/vectorize-io/hindsight)
- 官方文档：[hindsight.vectorize.io](https://hindsight.vectorize.io/developer/installation)
- 本应用使用的镜像：`ghcr.io/vectorize-io/hindsight:1.0.0-slim`

## 使用说明

- **控制台（GUI）端口**：`9999`，对应安装表单里的「控制台(GUI)端口」（`PANEL_APP_PORT_HTTP`）。
- **数据面 API 端口**：`8888`，对应「数据面 API 端口」（`PANEL_APP_PORT_API`）。API 与 MCP 都走这个端口。
- **数据持久化**：全部在 PostgreSQL 中。Hindsight 不使用本地卷 —— 记忆、实体、操作记录以及上传的文件附件（文件存储默认 `native`，即存 PostgreSQL 的 BYTEA 字段）都在数据库里。**备份应用等于备份这个数据库**，容器可以随时删除重建。
- **首次启动**：容器会自动在目标数据库的 `public` schema 中建表并执行迁移，首次启动到 `/health` 转为健康需要一两分钟。健康检查探针会验证数据库连通性，因此数据库不可达时容器会显示为 unhealthy。
- **初始账号**：没有内置账号。控制台用「GUI 访问密钥」登录，API/MCP 用「API / MCP 访问密钥」鉴权，两者都在安装表单里随机生成。
- **装完想改配置**：1Panel 应用页 →「参数」→ 右上角「编辑」。除数据库连接（库名 / 用户 / 密码）外**所有字段都能改**，保存后容器会自动重建。数据库连接属于安装时决定，要换库请重装应用。

## 安装前置条件（重要）

1. **PostgreSQL 必须已安装 pgvector 扩展。**
   Hindsight 强制要求向量扩展（默认 `pgvector`），启动时会自行执行 `CREATE EXTENSION vector`，但扩展文件必须先存在于数据库。1Panel 官方 PostgreSQL 应用使用的 `postgres:XX-alpine` 镜像**不含** pgvector，需要把镜像换成带扩展的版本（例如 `pgvector/pgvector:pg18`）或自行安装扩展。安装前可确认：

   ```sql
   SELECT * FROM pg_available_extensions WHERE name = 'vector';
   ```

   返回空结果说明扩展不可用，Hindsight 会在迁移阶段直接失败。

2. **必须准备外部嵌入（Embeddings）与重排（Reranker）服务。**
   本应用使用 `-slim` 镜像，镜像内不含本地嵌入与重排模型（这是 slim 与标准镜像的主要区别），两者都必须走外部接口。本应用已把这两项都**锁定到硅基流动**（[siliconflow.cn](https://siliconflow.cn)）：嵌入走它的 OpenAI 兼容端点，重排走它 Cohere 兼容的 `/rerank` 端点。安装前请确认账号里可用的嵌入与重排模型，并把对应的 API Key 填进表单。

3. **LLM 需要足够大的输出上限。**
   Retain（事实提取）单次调用最多输出 64000 token（已写死在 compose 里），官方要求所选模型至少支持 65000 输出 token。模型输出上限较小时，把 compose 里的 `HINDSIGHT_API_RETAIN_MAX_COMPLETION_TOKENS` 调低（例如 32000 / 16000）；该值必须大于 3000，否则启动即报错。

## 配置说明

### 已经替你锁定的部分

安装表单只留两类东西：真实凭据（API Key）和真实选择（端口、库名、模型名）。其余全部写死在 compose 里并加了注释，装完不用管：

- **LLM 提供商锁死 `openai`**（OpenAI 兼容协议）—— 官方 OpenAI、DeepSeek、硅基流动、各类中转都用这套接口，用「LLM 接口地址」指向实际服务即可。
- **备用 LLM 也锁死 `openai`**，接口地址与 Key 留空时回落到主 LLM；开关关闭时该成员根本不存在。
- **嵌入模型锁死硅基流动**（走 OpenAI 兼容通道）。
- **重排模型锁死硅基流动**（走 Cohere 兼容的 `/rerank`）。
- **Retain 输出预算写死 `64000`**（上游默认值）。
- **故障转移策略写死 `{"mode": "failover"}`**，**API / MCP 鉴权默认开启**。

模型名和接口地址这类字段只校验非空，**字符不受限** —— 带斜杠的模型名（`qwen/qwen3-embedding-4b`、`deepseek/deepseek-chat` 等）可以直接填。

### 表单字段顺序

从上到下依次是：数据库 → 端口 → **1. 主 LLM** → **2. 备用 LLM** → **3. 嵌入模型** → **4. 重排模型** → **5. 通用配置**（全局 LLM 并发 + 访问密钥）。

1Panel 的安装表单是平铺的、没有分组控件，所以**组号直接写在字段名开头** —— 这是用户在界面上分辨「哪几项是一组」的唯一办法。数据库连接、端口、访问密钥含义自明，不编号，组号从主 LLM 起算；组内一律按「接口地址 → 模型 → Key」排列。

### 1. 主 LLM

提供商已锁定为 `openai`（OpenAI 兼容协议，写在 compose 里）—— 官方 OpenAI、DeepSeek、硅基流动、各类中转等绝大多数服务都提供 OpenAI 兼容接口，用「接口地址」指向实际服务即可。这一组三项：

- **1. 主 LLM 接口地址**：OpenAI 兼容端点，以 `/v1` 结尾（**不是**账号根地址）。默认填的是官方示例 `https://api.openai.com/v1`，用别家时直接覆盖。
- **1. 主 LLM 模型**：**必填**，填这个接口真实提供的模型。这里刻意不留默认值 —— 若回落到 OpenAI 的 `gpt-4o-mini`，用中转时只会得到一个"模型不存在"的报错。
- **1. 主 LLM API Key**：对应服务的 Key。

> 「Retain 最大输出 Token」已写死为 `64000`（上游默认值），不再作为表单项。模型输出上限较小导致调用失败时，改 compose 里那行即可（必须大于 3000）。
> 要用 `anthropic`、`gemini`、`ollama` 等原生协议，改 compose 里的 `HINDSIGHT_API_LLM_PROVIDER`，并按官方 `.env.example` 补上该提供商所需的变量。

### 2. 备用 LLM（故障转移）

主模型报错时按顺序切到备用模型，策略 `HINDSIGHT_API_LLM_STRATEGY={"mode": "failover"}` 已写在 compose 里。这一组是**可选**的，默认关闭，表单四项：

- **2. 备用 LLM 开关**：默认**关**。开 = 使用 `openai`；关 = 留空，不创建备用成员。
- **2. 备用 LLM 接口地址**：**留空 = 跟随主 LLM**。要给备用模型接另一家服务商（例如主用中转、备用直连 DeepSeek）时才填，必须写全（含 `/v1`）—— 上游的备用成员**不会继承**主 LLM 的地址，留空时用的是 OpenAI SDK 自己的默认地址（`api.openai.com`），接中转站的话就是 401。
- **2. 备用 LLM 模型**：**开关打开后必填**，必须是上面那个接口**真实提供**的模型。留空不会报错 —— 上游会回落到 `openai` 的默认模型，等于把请求发给了错的模型，要等真正故障转移时才会暴露。
- **2. 备用 LLM API Key**：**留空 = 跟随主 LLM**。换成别家服务商时填该家的 Key —— 上游规定成员 provider 非空时 Key 不能为空，**留空会在启动时直接抛错**，所以不能靠"留空"来跳过它。

两项的「留空跟随」是 compose 里的 `${HINDSIGHT_API_LLM_1_API_KEY:-${HINDSIGHT_API_LLM_API_KEY}}` 实现的（Compose 规范支持嵌套默认值，且 `:-` 对空字符串同样生效）。

「关」的状态是安全的：上游扫描多模型成员时，遇到空的 provider 会在**读取 API Key 之前**就停止，所以该成员根本不存在，也不会触发"Key 不能为空"的强校验（策略此时同样失效，因为成员列表为空）。这也是为什么这一组可以放心做成开关，而不必担心关掉后启动失败。

> 需要轮询或按元数据路由时，把策略改成 `{"mode": "round-robin"}` 或 `{"mode": "metadata", "routes": [...]}`，并可按官方 `.env.example` 追加 `HINDSIGHT_API_LLM_2_*`、`HINDSIGHT_API_LLM_3_*` 等成员（序号必须从 1 连续）。

### 3. 嵌入模型（锁定硅基流动）

上游**没有** `siliconflow` 这个嵌入提供商（合法值只有 `local`、`onnx`、`tei`、`openai`、`openai-codex`、`openrouter`、`requesty`、`cohere`、`google`、`zeroentropy`、`litellm`、`litellm-sdk`），所以这里走 OpenAI 兼容通道指向硅基流动：compose 里固定了 `HINDSIGHT_API_EMBEDDINGS_PROVIDER: openai` 和 `HINDSIGHT_API_EMBEDDINGS_OPENAI_BASE_URL: https://api.siliconflow.cn/v1`，OpenAI SDK 会自动在其后拼上 `/embeddings`。

表单三项：

- **3. 嵌入模型 API Key**：你的硅基流动 Key。
- **3. 嵌入模型**：默认 `BAAI/bge-m3`，**必须存在于你账号的模型列表里**。
- **3. 嵌入维度**：留空用模型原生维度。硅基流动的 bge / Qwen 系列请保持留空 —— `dimensions` 参数只有 OpenAI `text-embedding-3` 系列接受，其他模型带上会被服务端拒绝。填写后它会作为请求参数下发，并决定数据库向量列的宽度。

**嵌入模型一旦写入记忆就不要更换**：更换后新旧记忆不在同一向量空间，已有记忆需要重新向量化。

> 换到别的 OpenAI 兼容嵌入服务（OpenAI、各类中转）只需改 compose 里的 `HINDSIGHT_API_EMBEDDINGS_OPENAI_BASE_URL`，其余不动；换成 `cohere`、`google`、`tei` 这类非 OpenAI 兼容的服务，则要同时改 `HINDSIGHT_API_EMBEDDINGS_PROVIDER` 并使用该提供商自己的变量（`HINDSIGHT_API_EMBEDDINGS_<提供商>_*`）。

### 4. 重排模型（锁定硅基流动）

compose 里固定了 `HINDSIGHT_API_RERANKER_PROVIDER: siliconflow`，并且**不设** `_SILICONFLOW_BASE_URL` —— 上游的默认值就是 `https://api.siliconflow.cn/v1`，客户端再拼上 `/rerank`，最终请求 `https://api.siliconflow.cn/v1/rerank`（Cohere 兼容格式）。

表单三项：

- **4. 重排模型 API Key**：你的硅基流动 Key。
- **4. 重排模型**：默认 `BAAI/bge-reranker-v2-m3`，**必须存在于你账号的模型列表里，不要留空**（空值不会被当作「用默认」，会变成空模型名）。
- **4. 重排候选上限**：默认 300，控制每次召回交给重排模型精排的候选数；调小可降低重排延迟，调大覆盖更多候选（精度略升、耗时增加）。

#### 想停用重排或换 provider

- **停用重排**：把 `HINDSIGHT_API_RERANKER_PROVIDER` 改成 `rrf`。它是透传实现（`RRFPassthroughCrossEncoder`），只做多路召回的融合排序，不加载模型、不需要 Key。**注意上游不接受 `none`**：`none` 会抛 `Unknown reranker provider`，config.py 告警文案里那句「（or none）」是上游过期的说法。
- **换其它 provider**：合法值有 `local`、`tei`、`cohere`、`openrouter`、`siliconflow`、`alibaba`、`google`、`zeroentropy`、`typesafe`、`litellm`、`litellm-sdk`、`flashrank`、`jina-mlx`、`rrf`，其中 `local` / `flashrank` / `jina-mlx` 依赖镜像内本地模型，**slim 不可用**。各家所需变量见下表（前缀统一为 `HINDSIGHT_API_RERANKER_`）；模型变量不写或填真实值都可以，但**不要写成空字符串**。

| provider | 需要补的变量 |
| --- | --- |
| `siliconflow` | `_SILICONFLOW_API_KEY`（必填）、`_SILICONFLOW_MODEL`（默认 `BAAI/bge-reranker-v2-m3`）、可选 `_SILICONFLOW_BASE_URL` |
| `cohere` | `_COHERE_API_KEY`（必填，也可回退到全局 `HINDSIGHT_API_COHERE_API_KEY`）、`_COHERE_MODEL`（默认 `rerank-english-v3.0`）、可选 `_COHERE_BASE_URL` |
| `openrouter` | `_OPENROUTER_API_KEY`（必填，可回退到全局 `HINDSIGHT_API_OPENROUTER_API_KEY` 或 LLM 的 Key）、`_OPENROUTER_MODEL`、可选 `_OPENROUTER_BASE_URL` |
| `tei` | 只要 `_TEI_URL`（自建 HuggingFace TEI 服务，模型由服务端决定，没有 key 和 model 变量） |
| `alibaba` | `_ALIBABA_API_KEY`、`_ALIBABA_MODEL`（DashScope，没有 base_url 变量） |
| `google` | `_GOOGLE_PROJECT_ID`、`_GOOGLE_SERVICE_ACCOUNT_KEY`、`_GOOGLE_MODEL` |
| `zeroentropy` / `typesafe` / `litellm` / `litellm-sdk` | 各自的 `_*_API_KEY`、`_*_MODEL`，必要时加 `_*_BASE_URL` |

- **故障转移链**：按 `HINDSIGHT_API_RERANKER_1_*`、`_2_*` 继续编号即可，成员之间不继承任何配置、要用什么就写全；链尾写 `rrf` 可以让重排失败时退回融合排序，而不是让整次召回失败。

### 5. 通用配置

这一组是与具体模型无关的应用级设置，因此排在所有模型组之后。

- **5. 全局 LLM 并发**：默认 `4`，上游默认是 `32`。它管的是**整个 LLM 栈**——同一时刻最多有多少个 LLM 请求在跑，主 LLM 与备用 LLM 一起受它限制（嵌入与重排不走这条路，不受影响），所以它不属于上面任何一组模型，单独编号放在最后。并发越高瞬时 token 消耗越猛，中转服务还容易触发限流；后台任务多、账单偏高就往下调，接本地模型（Ollama / LM Studio）建议 `1~2`，云端 API 且追求吞吐可以往上加。

#### 访问密钥与鉴权

- **API / MCP 访问密钥**（`HINDSIGHT_API_TENANT_API_KEY`）：Hindsight 默认**完全无鉴权**，本应用通过内置的 `ApiKeyTenantExtension` 打开 API Key 校验，请求必须携带 `Authorization: Bearer <密钥>`，否则返回 401。控制台访问数据面 API 时复用同一把密钥，无需另外配置。
- **GUI 访问密钥**（`HINDSIGHT_CP_ACCESS_KEY`）：访问控制台时会出现登录页，输入该密钥才能进入（`/api/health` 除外）。它必须与 API 访问密钥不同。

## 如果发现后台 Token 消耗异常

Hindsight 会在后台自动刷新**心智模型（mental model）**与知识页，这条路径跑的是完整的 reflect 流程（多轮自回归推理），如果触发频繁，消耗会显著高于日常的 retain/recall。注意这与上面的模型配置无关：把模型换成便宜的只会降低单价，不会减少调用次数。

表单里的「5. 全局 LLM 并发」默认 `4`（上游默认 `32`），后台任务不会一次性全部开火；想再省一点可以改到 `1~2`（代价是 retain / recall 变慢），装完也能在「参数 → 编辑」里随时调整。

当前版本没有全局开关，按下面两点处理：

1. **在控制台里检查**每个记忆库下的心智模型 / 知识页及其触发器。触发器里的 `refresh_after_consolidation: true` 意味着每次记忆整合后都会刷新一次，这是最常见的放大来源；删除或改用 `refresh_cron` 定时触发即可。
2. 需要全局兜底时，可以给 compose 追加 `HINDSIGHT_API_MENTAL_MODEL_MIN_REFRESH_INTERVAL_SECONDS`（例如 `86400`），为所有自动刷新设一个最小间隔，把密集触发合并成一次。

**重建应用不会清掉这些配置** —— 心智模型和触发器都存在数据库里（外部 PostgreSQL），只重装容器它们依然存在，必须在上面的第 1 点里处理。

## 公网部署

### 端口与反向代理

- **控制台必须挂在域名的根路径**（`https://memory.example.com/`）。控制台基于 Next.js 构建，上游镜像在**构建期**就把基准路径烘焙进去了，运行时设置 `NEXT_PUBLIC_BASE_PATH` 不会改变前端资源与路由的基准路径，因此无法把 GUI 搬到子目录。
- **浏览器不需要直连 8888**。控制台是服务端代理：它读取 `HINDSIGHT_CP_DATAPLANE_API_URL`（镜像内默认为同容器的 `http://localhost:8888`）再去请求数据面。因此你可以只对外开放 9999，把 8888 留给 API/MCP 客户端或仅限内网。
- 只有 API / MCP 客户端（Claude Code、OpenCode、Codex 等）才需要访问 8888。要用域名访问时建议单独给 API 一个子域，或用 1Panel 反向代理加一条路径规则。
- 官方推荐通过 1Panel 反向代理配置域名与 HTTPS，不要直接把 8888 / 9999 暴露到公网。

### 可选：把 API 放到子路径

如果需要让 API 与其它服务共用同一个域名，可以给 API 设置基准路径（运行时生效）：

```yaml
HINDSIGHT_API_BASE_PATH: /mem
```

此时 API 地址变为 `https://example.com/mem/`，MCP 端点在 `https://example.com/mem/mcp/`。**同时必须让控制台指向同一个子路径**，否则控制台会 404：

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

- 本应用跟随上游的 **slim** 镜像变体（版本目录 `1.0.0-slim`）。使用 slim 的原因是拉取体积更小（镜像层压缩后约 458MB，标准镜像约 880MB），代价是嵌入与重排必须依赖外部服务。
- 想改用镜像自带的本地嵌入/重排模型时，把 compose 中的镜像换成不带 `-slim` 的 tag（例如 `ghcr.io/vectorize-io/hindsight:1.0.0`），并把 `HINDSIGHT_API_EMBEDDINGS_PROVIDER` 改成 `local`、`HINDSIGHT_API_RERANKER_PROVIDER` 改成 `local`。标准镜像已预置 `BAAI/bge-small-en-v1.5`（嵌入）与 `cross-encoder/ms-marco-MiniLM-L-6-v2`（重排），无需联网下载。
- 上游同时提供带 `-slim` 和不带 `-slim` 的两套 tag，因此 `renovate.json` 中为该镜像加了 `allowedVersions` 规则，自动升级只会落在 `-slim` 这一支上。
- 该规则里的 `"ignoreUnstable": false` **不能删**：`-slim` 在 semver 里属于预发布版，而当前版本也是预发布版时，Renovate 默认只允许跳到 minor 与 patch 都相同的另一个预发布版，结果是任何版本号变化都不会产生升级 PR。加上这个开关后，才是「按版本号正常升级、且只取 `-slim` 这一支」。

## 官方文档

- [安装与部署](https://hindsight.vectorize.io/developer/installation)
- [模型配置](https://hindsight.vectorize.io/developer/models)
- [存储与数据库要求](https://hindsight.vectorize.io/developer/storage)
- [MCP Server](https://hindsight.vectorize.io/developer/mcp-server)
- [完整环境变量清单 `.env.example`](https://github.com/vectorize-io/hindsight/blob/main/.env.example)
