# AxonHub-mysql

**AxonHub** 是一个一体化的 AI 开发与管理平台，提供统一 API 网关、项目管理、全链路追踪、权限治理和快速开发工具。本版本为 **MySQL 支持版**，适合需要稳定数据持久化的生产环境用户。

> 不知道啥原因，没法自动创建数据库，请先自行创建，然后填入对应的密码和用户名即可。

## 🚀 项目简介

AxonHub 主要用于为开发者和企业提供统一的 AI 服务接入层，简化多模型、多服务商的调用流程。平台兼容 **OpenAI、Anthropic** 等 API 格式，并支持多策略智能负载均衡，帮助用户构建可靠的 AI 应用。

它同时提供项目隔离、权限控制、线程级追踪与可视化 Playground，适用于企业内部平台搭建或个人自托管使用。

------

## ✨ 核心特性

### 🔗 统一 API 网关

- 完全兼容 **OpenAI / Anthropic** API 规范
- 自动将调用转换为多云、多模型提供商接口
- 通过 Transformer Pipeline 统一处理请求

### 🧵 全链路追踪（Tracing / Threads）

- 捕获每个请求的执行过程
- 支持线程化上下文
- 更适合调试、审计与性能分析

### 🔐 细粒度权限控制

- 基于 RBAC 的角色与项目管理
- 精准控制访问与资源隔离
- 适合团队与企业环境

### ⚖️ 智能负载均衡

- 多策略选择（权重、健康检查、会话一致性等）
- 自动选择最优模型/渠道
- 强化高可用性

### 🧩 综合开发工具

- 内置 Playground
- 项目管理与密钥管理
- API 调试体验优秀

------

## 🗄️ MySQL 版本说明

本应用使用 **MySQL 数据库** 作为持久化存储，适用于：

- 生产环境
- 团队协作场景
- 需要可靠备份与扩容的部署需求

配置简单，无需额外手动初始化。

------

## ⚙️ 配置说明

自 1.0 起，**配置文件是可选的**：镜像内不带 `config.yml`，启动时找不到就使用内置默认值 + `AXONHUB_*` 环境变量，因此本应用不再预置 `config.yml`。

- 所有配置项都能用环境变量覆盖，规则是配置路径加 `AXONHUB_` 前缀、`.` 换成 `_`，例如 `cache.mode` → `AXONHUB_CACHE_MODE`、`log.level` → `AXONHUB_LOG_LEVEL`、`server.public_url` → `AXONHUB_SERVER_PUBLIC_URL`。
- 数据库连接已由安装表单注入（`AXONHUB_DB_DIALECT` / `AXONHUB_DB_DSN`），无需额外填写。
- 需要文件式配置（如 Redis 缓存、Prometheus 指标、CORS）时，自行在编排里加挂载并放一份配置：

  ```yaml
  volumes:
    - ./data/data:/data
    - ./data/config.yml:/app/config.yml:ro
  ```

  配置格式参考上游 [`config.example.yml`](https://github.com/looplj/axonhub/blob/main/config.example.yml)，注意这份文件不会随应用升级自动更新，升级后请自行比对新增项。
- 健康检查走 `GET /health`，容器状态异常时先看日志里是否有 `invalid log level` 之类的配置错误。

## 💾 数据与端口

- 数据存在外部 MySQL（安装表单里选择/填写的实例与库名），`./data/data` 只用于零散文件。
- 容器内端口 `8090`，通过 `GET /health` 可做健康检查。

## 📦 部署说明

1. 通过 1Panel 安装应用
2. 配置 MySQL 连接参数
3. 启动容器后平台会自动初始化
4. 打开浏览器访问界面完成初始设置

> 当前镜像版本为 `1.0.0-rc.4`。上游迭代很快，长期只发布 rc / beta 预发布版，这些就是正常可用版本，本仓库会持续跟踪。

支持 AMD64 / ARM64 架构。