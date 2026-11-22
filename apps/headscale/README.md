# Headscale

🛰️ **Headscale** 是 Tailscale 控制服务器的开源自托管实现。本应用已经开启 Headscale 自带的 **DERP 中继** 和 **STUN**，所以一个应用就同时提供了：

- **控制服务器**：设备注册、鉴权、ACL、节点管理
- **中继服务器**：设备无法直连时，通过 DERP 转发已经端到端加密的流量

客户端仍然使用官方 Tailscale 客户端，手机、电脑、NAS、路由器都可以加入同一个私有网络。

## 为什么不需要单独的 derper？

Headscale 自带嵌入式 DERP，个人和小团队直接用内置中继即可。单独的 `derper` 只适合下面这些场景：

- 想把中继放到另一台离用户更近的服务器；
- 中继流量很大，需要独立扩容；
- 需要多个 DERP 区域做容灾。

本应用不依赖单独的中继容器，也不需要你再写额外的 `derp.yaml`。默认只使用内置 DERP，不会在启动时拉取 Tailscale 官方 DERP 地图，因此服务器访问不了外网 DERP 地址也能正常启动。以后确实需要独立 derper 时，再单独部署并在 Headscale 中登记即可。

## 安装前准备

1. 一个域名（例如 `hs.example.com`）解析到 1Panel 所在服务器。
2. 在 1Panel「网站」中为该域名配置 HTTPS 证书和反向代理。
3. 防火墙放行：
   - TCP `443`：反向代理 HTTPS；
   - TCP `8080`：只给反向代理访问，不建议直接暴露公网；
   - UDP `3478`：STUN，必须公网可达，否则内置 DERP 无法帮助 NAT 穿透。

> 内置 DERP 必须使用 HTTPS。`server_url` 填 `http://` 时控制面可能能启动，但中继不会正常工作。

## 安装字段

| 字段 | 说明 |
| --- | --- |
| 控制面 HTTP 端口 | 容器内固定监听 `8080`，这里填宿主机端口，默认 `8080`；反向代理指向这个端口 |
| 对外访问地址 | 必须是与反向代理一致的 HTTPS 地址，例如 `https://hs.example.com` |
| 公网 IPv4 | 可选；填写后内置 DERP 的区域信息更完整，连接更稳定 |
| STUN 端口（UDP） | 默认 `3478`；宿主机与容器使用同一端口，需要放行 UDP |
| MagicDNS 基础域名 | 默认 `ts.internal`；设备会得到 `设备名.ts.internal` 的内部域名，无需公网 DNS |

## 反向代理（必须）

需要用 1Panel 的 OpenResty 把域名反代到 Headscale 的 HTTP 端口。关键是 **透传 `Upgrade` / `Connection` 头并关闭缓冲**：

```nginx
location / {
    proxy_pass http://127.0.0.1:8080;   # 或 http://<容器名>:8080
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_buffering off;
    proxy_read_timeout 3600s;
}
```

- 如果 1Panel 的站点配置里已经有 `Connection $connection_upgrade`，保留原写法也可以，只要 `Upgrade` 头能透传。
- `proxy_pass` 指向 `127.0.0.1:8080` 时，要求 OpenResty 能访问宿主机的 8080；如果 OpenResty 与 Headscale 容器都在 `1panel-network`，也可以直接写 `http://<容器名>:8080`。
- 不要套 Cloudflare 等 CDN 的 HTTP 代理。Tailscale 控制协议和 DERP 需要直连的 TCP/Upgrade，CDN 代理会导致连接失败。

## 接入第一台设备

下面的命令在 1Panel「容器」→ Headscale 容器「终端」中执行，或在宿主机执行 `docker exec -it <容器名> ...`。

1. 创建用户：

   ```bash
   headscale users create myuser
   headscale users list          # 记下用户 ID
   ```

2. 生成预授权 key（把 `<用户ID>` 换成上一步查到的 ID）：

   ```bash
   headscale preauthkeys create --user <用户ID> --expiration 24h
   ```

3. 在设备上安装官方 Tailscale，然后加入网络：

   ```bash
   # Linux
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up --login-server https://hs.example.com --authkey <预授权key>
   ```

   Windows、macOS、iOS、Android 安装官方 Tailscale 客户端后，在登录界面选择「使用其他服务器」，填入 `https://hs.example.com`；也可以使用上面的 `--authkey` 免交互加入。

4. 查看设备：

   ```bash
   headscale nodes list
   ```

## MagicDNS

默认开启，基础域名为 `ts.internal`。设备加入后可以直接访问：

```text
nas.ts.internal
phone.ts.internal
```

客户端需要保持 `--accept-dns=true`（Tailscale 默认开启）。本应用默认不覆盖客户端原有 DNS（`override_local_dns=false`），因此局域网或公司内网域名不会被顶掉，`*.ts.internal` 仍由 MagicDNS 解析。如果不想使用 `ts.internal`，在应用参数里修改「MagicDNS 基础域名」并重建容器即可；该域名不能与对外访问地址的域名相同，也不能是对外访问地址域名的父域名。

## DERP / STUN 检查

在任意已加入的设备上执行：

```bash
tailscale netcheck
tailscale debug derp-map
```

- `netcheck` 中应能看到 `Headscale Embedded DERP` 区域；
- 如果 DERP 不可达，优先检查 UDP `3478` 是否放行、`server_url` 是否为 HTTPS、反向代理是否透传 `Upgrade`；
- 内置 DERP 适合个人和小团队，不追求大流量吞吐。

## 数据与升级

- 数据库、Noise 私钥、DERP 私钥、证书缓存都在 `./data`，挂载到容器 `/var/lib/headscale`。
- 升级或重建容器时请保留 `./data`，不要执行 `docker compose down -v`。
- 备份 `./data` 就相当于备份了整个 Headscale 的身份和网络数据。
- 修改端口、域名、MagicDNS 后，在 1Panel 中「重建」容器；仅「重启」不会重新加载 `.env`。

## 进阶配置

本应用把常用项都写成了 `HEADSCALE_*` 环境变量，因此不需要手写 `config.yaml`。需要 ACL、OIDC、自定义 DERP 地图等进阶配置时，可以编辑安装目录下的 `docker-compose.yml`，在 `environment:` 中追加变量，然后重建容器。

变量名规则是 `HEADSCALE_` + 配置路径大写，用 `_` 代替 `.`，例如：

```yaml
environment:
  HEADSCALE_POLICY_PATH: /var/lib/headscale/policy.hujson
  HEADSCALE_OIDC_ISSUER: https://id.example.com
```

参考文档：

- 配置参考：https://headscale.net/stable/ref/configuration/
- DERP 参考：https://headscale.net/stable/ref/derp/
- 反向代理：https://headscale.net/stable/ref/integration/reverse-proxy/

## 常见问题

**控制面能打开，但设备一直显示正在连接？**

检查反向代理是否透传 `Upgrade: tailscale-control-protocol`，并确认 `proxy_buffering off`。Tailscale 控制协议不是普通 WebSocket，代理必须允许 HTTP 101 协议切换。

**DERP 一直不可用？**

确认 UDP `3478` 已放行、`server_url` 是 `https://`、公网 IPv4 填写正确。用 `tailscale netcheck` 查看 STUN 和 DERP 的探测结果。

**有 Web 管理界面吗？**

Headscale 本身没有内置 Web UI，本应用通过命令行管理。需要图形界面可以另外部署 Headplane 等第三方面板。

**可以只使用自建中继，不连 Tailscale 官方 DERP 吗？**

可以，而且默认就是这样。应用把 `HEADSCALE_DERP_URLS` 设为 `[]`，只使用内置 DERP，这样即使服务器访问不了 `controlplane.tailscale.com` 也能正常启动。如果想让 Tailscale 官方 DERP 作为兜底，在 `docker-compose.yml` 的 `environment:` 中改成：

```yaml
HEADSCALE_DERP_URLS: '["https://controlplane.tailscale.com/derpmap/default"]'
```

然后重建容器。注意：服务器无法访问该地址时，Headscale 会在启动阶段报错。

## 项目地址

- 官网：https://headscale.net/
- GitHub：https://github.com/juanfont/headscale
- 客户端下载：https://tailscale.com/download
