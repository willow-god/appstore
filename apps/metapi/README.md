# Metapi

中转站的中转站 —— 将分散的 AI 中转站聚合为一个统一网关。

Metapi 适合把 New API / One API / OneHub / DoneHub / Veloera / AnyRouter / Sub2API 等上游统一到一个入口，提供自动模型发现、智能路由、成本优先选路和本地数据目录部署。

## 部署说明

- 服务端口：`4000`
- 数据目录：`./data`
- 镜像：`1467078763/metapi:latest`
- 管理员令牌：`AUTH_TOKEN`
- 代理令牌：`PROXY_TOKEN`

## 快速启动

```bash
docker run -d --name metapi \
  -p 4000:4000 \
  -e AUTH_TOKEN=your-admin-token \
  -e PROXY_TOKEN=your-proxy-sk-token \
  -e TZ=Asia/Shanghai \
  -v ./data:/app/data \
  --restart unless-stopped \
  1467078763/metapi:latest
```

启动后访问 `http://localhost:4000`，使用 `AUTH_TOKEN` 登录后台。

## 常用说明

- 数据默认保存在本地 `./data`
- `PROXY_TOKEN` 用于下游客户端访问 `/v1/*`
- `AUTH_TOKEN` 用于管理后台登录
