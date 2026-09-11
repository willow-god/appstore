# MaiBot

MaiBot 是一个可通过 WebUI 配置模型和平台连接的 QQ 机器人核心。此应用使用官方文档中的精简 Docker Compose 配置，仅部署 MaiBot 核心，不包含 NapCat 或数据库工具。

## 使用说明

- WebUI：安装后访问 `http://服务器地址:18001`
- 首次启动会在容器日志中生成 WebUI 登录 Token，可使用 `docker compose logs core` 查看
- 配置文件、运行数据、插件和日志分别持久化到 `data/config/mmc/`、`data/MaiMBot/`、`data/MaiMBot/plugins/` 和 `data/MaiMBot/logs/`
- NapCat 可作为独立应用安装，再在 MaiBot WebUI 中完成适配器连接

官方文档：https://docs.mai-mai.org/manual/deployment/docker
