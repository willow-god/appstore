## Memora

Memora 是可自托管的个人相册，用于浏览、整理和在地图上探索照片：瀑布流画廊、相册与搜索、反应与照片信息编辑、EXIF 解析、逆地理编码、Live/Motion Photo，以及本地、S3、OpenList 三种存储。

它从 [ChronoFrame](https://github.com/HoshinoSuzumi/chronoframe) 硬分叉而来，界面与使用方式基本一致，但后端换成了 Go，数据库结构和 `/app/data` 挂载保持兼容。

- 默认端口：`6232`（容器内 `3000`）
- 当前维护仓库：<https://github.com/LiuShen-Fork/Memora>
- 中文文档：<https://github.com/LiuShen-Fork/Memora/tree/main/docs>

## 与 ChronoFrame 的区别

两者已经硬分叉，各自独立发版（ChronoFrame 目前是 v1.2.0，Memora 是 v1.5.x），上游的新功能不会自动出现在另一边，也不能互相覆盖升级。对部署影响最大的几处：

| 项目 | ChronoFrame | Memora |
| --- | --- | --- |
| 运行时 | Nuxt/Nitro，容器内跑 Node 服务，负责 SSR 和 API | 单个 Go 进程，同时提供 API 和构建时预生成的静态前端，生产环境不需要 Node |
| 数据目录 | `/app/data`：`app.sqlite3`、会话密钥、本地存储 | 结构相同，SQLite 库和 `/app/data` 挂载兼容，可把 ChronoFrame 的 `data` 目录直接挂给 Memora，无需迁移 |
| 媒体处理 | 内置解析与缩略图流程 | 用 FFmpeg 生成缩略图并处理 Live/Motion Photo，用 ExifTool 提取元数据，镜像内已包含 |
| HEIC/HEIF | 按原格式保存 | 上传后转换为 JPEG 作为原图保存，原始 HEIC 不再保留，元数据一并转移 |
| 地图 | MapLibre、Mapbox | MapLibre、Mapbox，另支持高德地图（AMap），地图提供者在后台选择 |
| 配置方式 | 1.0 起由设置向导和后台维护 | 相同，站点/存储/地图/上传全部在向导和后台维护；进程设置用 `MEMORA_*` 变量，旧名 `CFRAME_*` 仍可读取但会输出弃用警告 |
| 健康检查 | 无内置检查接口 | 提供 `/api/health`，本应用已用它做容器健康检查 |

首次创建管理员时，Memora 的设置向导会拒绝空密码、过短密码，以及 ChronoFrame 曾经内置的那个默认密码，避免照搬旧密码；已有账号即使正在使用该密码仍可正常登录，请到「设置 → 基本设置」修改。

## 数据持久化

应用安装目录下的 `data/` 挂载到容器内的 `/app/data`：

| 路径 | 内容 |
| --- | --- |
| `data/app.sqlite3` | 照片信息、相册与全部站点设置 |
| `data/.session-secret` | 自动生成的会话密钥（首次启动时创建，权限 0600） |
| `data/storage/` | 使用本地存储时的原图与缩略图 |

升级镜像只替换容器，数据不会丢失。备份应用目录即可备份相册；使用 S3 或 OpenList 时原图在外部服务里，需要另外备份。

## 首次启动

1. 安装完成后打开 `http://服务器IP:6232`，首次访问进入设置向导。
2. 在向导里创建管理员账号。向导不接受空密码和过短的密码，也会拒绝 ChronoFrame 曾经内置的默认密码；若使用已有的 ChronoFrame 或 Memora 数据目录，直接登录原账号即可，向导不会覆盖已有账号。
3. 站点信息、存储、地图按需填写。本地存储的路径保持 `/app/data/storage` 即可随数据卷保存，其余设置也可以稍后在后台修改。

之后进入 `/dashboard`，站点、存储、地图、上传大小、语言、主题等设置都在后台维护；需要改密码请到「设置 → 基本设置」。

## 环境变量（可选）

安装时不需要填写任何环境变量：管理员账号在向导里创建，会话密钥首次启动自动生成到 `data/.session-secret`。只有在需要预填或覆盖时才用 `MEMORA_*`，例如 `MEMORA_ADMIN_EMAIL`、`MEMORA_ADMIN_NAME`、`MEMORA_ADMIN_PASSWORD`（只预填向导，不会改动已有账号）、`MEMORA_SESSION_SECRET`（多副本共用会话时显式设置）、`MEMORA_WORKERS`、`MEMORA_MAX_UPLOAD_MB`。旧名 `CFRAME_*` 与 `NUXT_SESSION_PASSWORD` 仍会被读取，但日志会提示已弃用。

从 1.4.x 升级不需要改任何配置：1.4 表单里的 `CFRAME_ADMIN_*` 和 `NUXT_SESSION_PASSWORD` 仍在被识别，数据目录原样保留即可；1.4 里已经写入的会话密钥不受影响。

## 从 ChronoFrame 迁移

1. 停止 ChronoFrame 容器，保留它的 `data` 目录。
2. 安装 Memora，把挂载指向上一步的 `data` 目录（或把该目录内容复制到 Memora 的 `data/` 下）。
3. 启动后用原来的管理员账号登录。数据库结构兼容，不需要额外的迁移命令；如果原实例使用本地存储，照片会照常出现在画廊里。

迁移前请完整备份 `data` 目录，并注意 Memora 的版本与 ChronoFrame 的版本各自独立，迁移后不要再把同一份 `data` 交回 ChronoFrame 使用。

## 反向代理与 HTTPS

在 1Panel 中用「网站」→「反向代理」指向 `http://127.0.0.1:6232` 即可申请证书并启用 HTTPS。代理配置建议：

```nginx
client_max_body_size 256M;   # 与后台「系统设置」里的上传限制保持一致
proxy_buffering off;         # 保留流式响应，实时日志才能正常显示
proxy_read_timeout 300s;
```

在容器里运行代理时，让代理通过 1Panel 网络访问 `http://<容器名>:3000`，不必暴露宿主机端口。
