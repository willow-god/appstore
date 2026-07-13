# PanSou 网盘搜索 API

PanSou 是一个高性能的网盘资源搜索 API 服务，支持 Telegram 搜索和自定义插件扩展，系统以性能和可扩展性为核心，支持并发搜索、结果智能排序和多网盘类型分类。

## ✨ 特性
- **高性能搜索**：并发执行多个 Telegram 频道及插件搜索，显著提升搜索速度
- **多网盘类型分类**：自动识别百度网盘、阿里云盘、夸克网盘等多种链接
- **智能排序**：基于插件等级、时间新鲜度和关键词权重的综合排序
- **异步插件系统**：支持“尽快响应，持续处理”的搜索模式
- **二级缓存**：内存 + 磁盘分片缓存机制，大幅提升重复查询性能

## 🛠 支持的网盘类型
百度网盘、阿里云盘、夸克网盘、天翼云盘、UC网盘、移动云盘、115网盘、PikPak、迅雷网盘、123网盘、磁力链接、电驴链接等。

## 🚀 快速开始

### 使用 Docker 部署（前后端一体）
```bash
docker run -d --name pansou -p 80:80 ghcr.io/fish2018/pansou-web
```

### 使用 Docker Compose（推荐）

```bash
curl -o docker-compose.yml https://raw.githubusercontent.com/fish2018/pansou-web/refs/heads/main/docker-compose.yml
docker-compose up -d
```

### 仅后端 API

```bash
docker run -d --name pansou -p 8888:8888 -v pansou-cache:/app/cache -e CHANNELS="tgsearchers2,xxx" ghcr.io/fish2018/pansou:latest
```

## 📚 API 文档

### 搜索 API

- 接口：`/api/search`
- 方法：`POST` / `GET`
- 参数：
  - `kw`：搜索关键词
  - `channels`：搜索的频道
  - `cloud_types`：网盘类型过滤
  - 更多详见[项目文档](https://github.com/fish2018/pansou)

### 健康检查 API

- 接口：`/api/health`
- 方法：`GET`

## ⚙️ 应用商店配置说明

应用商店版本默认使用官方镜像 `ghcr.io/fish2018/pansou-web:latest`。如果你需要替换为自己的镜像，可以在拉起前自行修改 Compose，应用模板本身不绑定个人自定义镜像。

常用配置项：

- `DOMAIN`：访问域名，用于 Nginx server_name 和 HTTPS 场景。
- `PROXY`：代理地址，常用于访问 Telegram 频道，例如 `socks5://host:7897`。
- `ENABLED_PLUGINS`：服务端启用的插件列表，逗号分隔；这是全局限制。
- `CHANNELS`：默认 Telegram 频道列表，逗号分隔。
- `CACHE_ENABLED` / `CACHE_TTL`：是否启用缓存以及缓存有效期，TTL 单位为分钟。
- `MAX_CONCURRENCY` / `MAX_PAGES`：搜索并发和最大页数。
- `HEALTH_CHECK_INTERVAL` / `HEALTH_CHECK_TIMEOUT` / `HEALTH_CHECK_RETRIES`：容器内部后端健康检查参数。
- `AUTH_ENABLED`：是否启用访问认证。
- `AUTH_USERS`：认证账号，格式为 `admin:password,user:password`。
- `AUTH_TOKEN_EXPIRY`：Token 有效期，单位小时。
- `AUTH_JWT_SECRET`：JWT 签名密钥，公网部署建议改成随机长字符串。

## 🔐 认证与页面配置

启用 `AUTH_ENABLED=true` 后，网页搜索和 API 搜索都应由后端校验 token；直接请求 `/api/search` 也需要带 `Authorization: Bearer <token>`。

网页里的“搜索配置”只保存在当前浏览器，用于决定本浏览器搜索时携带哪些频道、插件和网盘类型参数。它不会修改服务器环境变量，也不会改变其他用户的配置。真正全局可用的插件和频道仍以 `ENABLED_PLUGINS` 与 `CHANNELS` 为准。

## 🔗 项目地址

- GitHub: https://github.com/fish2018/pansou
- 文档: https://github.com/fish2018/pansou
