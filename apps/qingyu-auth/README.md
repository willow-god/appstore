## Qingyu Auth

Qingyu Auth（清羽通行证）是面向**单站点部署**的 OAuth 2.0 / OIDC 单点登录服务，也是这套应用的统一账号中心。

- 登录方式：密码、邮箱验证码、Passkey、TOTP，以及上游 OAuth 提供商
- 协议端点：OAuth 2.0 / OIDC 的授权、Token、UserInfo、Consent 与注销
- 管理端：用户、应用、Provider、邮件、存储与安全策略
- 数据库：MySQL 8.0+ 或较新的 MariaDB（utf8mb4 与严格模式），启动时自动执行 schema 迁移

默认端口 `8000`。上游仓库 <https://github.com/qingyu-org/Auth>，部署与安全说明见
<https://github.com/qingyu-org/Auth/blob/main/docs/DEPLOYMENT.md>。

## 安装字段

| 字段 | 说明 |
| --- | --- |
| HTTP 端口 | 宿主机端口，默认 `8000`；反向代理指向这个端口 |
| 对外访问地址（Issuer） | 必须是反向代理对外提供的 HTTPS 地址，例如 `https://auth.example.com`，OIDC 客户端会把它当作 issuer |
| 数据库服务 | 选择 1Panel 里已经装好的 MySQL 或 MariaDB 应用 |
| 数据库名 / 用户 / 密码 | 首次安装会随机生成；升级或迁移时保持与原实例一致即可连回原库 |
| Redis 服务 / 密码 | 选择 1Panel 已安装的 Redis 应用，用于登录失败保护的封禁缓存；Redis 未启用时密码留空 |
| 主密钥 | 加密 Provider Secret、SMTP 密码、TOTP 密钥、OIDC 签名私钥和 S3 凭据 |
| 邮箱验证码密钥 / CSRF 密钥 | 分别用于邮箱验证码签名和 CSRF 校验 |
| 仅使用安全 Cookie | HTTPS 下保持启用；纯 HTTP 部署时关闭 |
| 自动迁移数据库 | 启动时应用待执行的 schema 迁移，数据库用户需要有建表和变更权限 |

## 首次启动

1. 安装完成后，空数据库会自动创建一个超级管理员 `admin`。
2. 随机初始密码只打印在启动日志里：

   ```bash
   docker logs <容器名> 2>&1 | grep WELCOME
   ```

3. 用这组账号登录，先修改密码，再到后台配置邮件、Provider、注册策略等。

只要数据库里已经存在任何账号，升级或重启都不会再创建管理员，也不会打印新的密码。

## 数据持久化与备份

- **业务数据全部在数据库里**：账号、应用、OAuth 客户端、会话、审计记录等。备份数据库即可备份主体数据。
- 应用目录下的 `data/` 挂载到容器内的 `/var/lib/qingyu/data`，用于本地文件存储和可选的 ip2region 地区库。
- **主密钥不能丢**：它负责解开数据库里的密文。备份数据库时要单独保存主密钥（例如放进密码管理器），不要让它和数据库备份放在同一处；更换主密钥会让已有的第三方登录 Secret、SMTP 密码、TOTP、OIDC 私钥全部失效。
- `邮箱验证码密钥`、`CSRF 密钥` 在安装后不建议随意更换；更换会让尚未使用的验证码和表单令牌立即失效。

## 反向代理与 HTTPS

在 1Panel「网站」里为域名配置 HTTPS 证书，反向代理指向 `http://127.0.0.1:<HTTP 端口>`。

- 安装表单里的「对外访问地址」必须与浏览器实际访问的地址完全一致（协议、域名、端口都不能差），否则 OAuth 回调与 OIDC issuer 会不匹配。
- HTTPS 下保持「仅使用安全 Cookie」启用；如果先在内网用纯 HTTP 调试，需要把它关掉。
- 服务默认按 Casdoor 兼容方式读取转发头，适合直接挂在反向代理后面。如果要把可信代理由「任意对端」收紧到固定网段，可以在已安装应用的 `docker-compose.yml` 里补充 `QINGYU_TRUSTED_PROXY_CIDRS`；设为 `none` 表示完全忽略转发头。

## 来源地区解析（可选）

1. 把 ip2region 的 `ip2region.xdb`、`ip2region_v6.xdb` 放进应用目录的 `data/`。
2. 重启容器即可，登录记录会附带来源地区。

文件不存在时只会跳过地区解析，不影响登录，也不会阻止容器启动。

## Redis

Redis 用于登录失败保护的封禁缓存，MySQL 始终是权威数据源；Redis 不可用时服务会记一条 `WARN` 并自动回退，不影响登录。

- 安装表单里的「Redis 服务」选 1Panel 已装好的 Redis 应用，「Redis 服务密码」填该实例的密码；密码留空表示不做 AUTH。
- 密码里如果含有 `@`、`:`、`/`、`#` 等字符，需要先做 URL 编码，否则连接串会被截断。
- v3.0.0 默认使用 `qingyu-auth:` 前缀；旧的 `qingyu-sso:` 键会自然过期，不影响封禁逻辑。

## 镜像说明

本应用使用上游公开的 `ghcr.io/qingyu-org/auth:v3.0.0`（`amd64` / `arm64` 双架构），应用已在仓库根目录
`.env` 的 `GHCR_IO_LIST` 里登记，同步时会走镜像加速。Renovate 会跟随该镜像的新版本创建升级 PR。

从 v3.0.0 起项目更名为 Qingyu Auth，可执行文件和 Compose 服务名从 `qingyu-sso` 改为 `qingyu-auth`；
`QINGYU_` 前缀的环境变量、数据库名 `qingyu_sso` 和 Cookie 名都没有变。自定义脚本或监控如果写死了
`qingyu-sso`，升级时需要同步改成 `qingyu-auth`。

## 从旧的 qingyu-sso 应用迁移

之前手写的本地应用使用的是 `qingyu-sso` 这个 key；本应用已改名为 `qingyu-auth`，在 1Panel 里是独立应用，不会出现升级入口，需要重装：

1. 备份数据库、旧应用目录下的 `data/`（ip2region 地区库），并记下主密钥、邮箱验证码密钥、CSRF 密钥和 Redis 服务/密码（schema 迁移只向前演进，数据库备份是唯一的回滚依据）。
2. 停掉旧实例释放端口，按本应用重新安装。数据库名、数据库用户和三个密钥都填成原来的值，Redis 选择原来的 Redis 应用。
3. 把备份的 ip2region 文件放回新应用目录的 `data/`。启动后账号、OAuth 应用、OIDC 客户端和已有会话都会从原库恢复。
4. 确认 `/healthz`、管理员登录和一次 OIDC 授权码登录正常后，再删除旧实例。

> 重新安装后 Redis 默认使用 `qingyu-auth:` 前缀，旧的 `qingyu-sso:` 键会自然过期；需要沿用旧前缀时，
> 在已安装应用里设置 `QINGYU_REDIS_PREFIX=qingyu-sso:` 即可。仓库 `.env` 的 `PRUNE_APPS` 已包含
> `qingyu-sso`，下次同步会清掉旧的本地应用定义（不影响已安装实例）。
