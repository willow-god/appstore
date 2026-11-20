## QingyuGist

QingyuGist 是 [OpenGist](https://github.com/thomiceli/opengist) 的独立分支，一个跑在自己服务器上的 Gist：用来放代码片段、笔记和配置，随手在网页里改，其余交给 Git。

每个 Gist **就是**一份真实的 Git 仓库，既能 `git clone` 下来用本地编辑器改完推回去，也能在网页编辑器和 Markdown 预览里直接改。公开、不公开、私有三种可见性，喜欢、派生、主题和全文搜索都自带。

- 默认端口：`6157`（网页与 HTTP Git）、`2222`（SSH Git）
- 上游仓库：<https://github.com/LiuShen-Fork/QingyuGist>
- 文档：<https://github.com/LiuShen-Fork/QingyuGist/tree/master/docs>
- 数据格式与 OpenGist 一致，可以直接接着老数据使用

## 首次启动

1. 安装完成后打开 `http://服务器IP:6157`。
2. **创建的第一个账号就是实例管理员**，密码登录、通行密钥、TOTP 都可以在之后绑定。
3. 登录后进入 `/admin/settings`：注册方式、第三方登录（GitHub / GitLab / Gitea / OIDC）、上传限制、审核、CORS、品牌与页脚公告都在这里，改完即时生效。

## 数据持久化

应用安装目录下的 `data/` 挂载到容器内的 `/qingyugist`，所有状态都在里面：

| 路径 | 内容 |
| --- | --- |
| `data/qingyugist.db` | SQLite 数据库：用户、Gist 元数据、站点设置 |
| `data/repos/` | 每个 Gist 的 Git 仓库本体 |
| `data/ssh/` | SSH 主机密钥（`qingyugist-ed25519`） |
| `data/log/` | 运行日志 |
| `data/qingyugist-secret.key` | 会话与 MFA 加密密钥，首次启动生成 |

会话密钥首次启动自动生成成 `data/qingyugist-secret.key`，全文搜索索引也在数据目录里；整份 `data` 备份即可。多副本部署时才需要显式指定 `QYG_SECRET_KEY`。升级镜像只替换容器，数据不会丢失。

## Git 访问

网页上每份 Gist 都能克隆，两种方式：

- **HTTPS**：`http://服务器IP:6157/<用户名>/<gist名>.git`，用网页的账号密码登录
- **SSH**：`ssh -p 2222 git@服务器IP`，先在「设置 → SSH 密钥」里添加公钥

SSH 端口在 `/admin/settings` 的 SSH 设置里配置，默认 `2222`；改过之后要同步修改安装表单里的 `PANEL_APP_PORT_SSH`，否则容器端口和实际监听对不上。

## 从 OpenGist 迁移

数据格式沿用上游，直接原地升级即可：

1. 停掉旧的 OpenGist 容器或进程，备份数据目录。
2. 安装本应用，把 `data` 指向（或复制自）旧的数据目录。
3. 启动后用原账号登录：SQLite 数据库与搜索索引会原地改名，仓库、令牌和 SSH 主机密钥都保留。

旧的 `opengist.db`、`repos/` 等文件会被自动识别，不需要手工转换。

## 反向代理与 HTTPS

在 1Panel 中用「网站」→「反向代理」指向 `http://127.0.0.1:6157`，即可申请证书并启用 HTTPS。挂在反向代理后面时，请把安装表单里的「对外地址」填成完整域名（例如 `https://gist.example.com`），否则 clone 链接和第三方登录回调会指向内网地址。

上传大文件时记得调大 `client_max_body_size`，并与后台的上传限制保持一致。

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `QYG_EXTERNAL_URL` | 空 | 对外地址，用于 clone 链接和 OAuth 回调；留空按请求域名推断 |
| `QYG_HTTP_PORT` | `6157` | HTTP 监听端口，容器内外保持一致即可 |
| `QYG_DB_URI` | `qingyugist.db` | 数据库地址，可换成 PostgreSQL 或 MySQL |
| `QYG_HOME` | `/qingyugist` | 数据目录，由镜像入口脚本按挂载点设置 |

进程级别的其余变量（日志级别、日志路径、索引器）见文档里的环境变量速查表。日常选项都不需要环境变量，直接在后台上改。
