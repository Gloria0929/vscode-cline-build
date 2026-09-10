# Coder (VSCode Server) — 自托管 AI 编程助手

将 Cline 开源 AI 编程助手改造成 **Coder** 后直接集成到 Docker 化的 VSCode Server 中，无需下载插件，移除了登录功能，并自定义了图标体系。

## 特性

- **Docker 一键部署** — 基于 code-server 的完整 VSCode 浏览器 IDE
- **Coder 预装集成** — 从源码构建，直接打包进镜像，无需插件市场下载
- **移除登录功能** — 去除账户认证系统，用户直接配置 API Key 使用
- **自定义图标体系** — 彩色版用于扩展列表，白色单色版用于聊天框/活动栏/面板
- **内置扩展集成** — Coder 以内置扩展（built-in）安装，普通列表不显示、无卸载按钮、无法被卸载
- **VSIX 导出** — 一键导出为独立插件包，可安装到任意 VS Code
- **本地直接打包** — `scripts/build-local.sh` 无需 Docker 即可在 macOS 本地产出 VSIX
- **持久化存储** — 配置、扩展、工作区数据持久化到 Docker Volume

## 在别处使用本项目（Clone 后）

用 Git 克隆到任意机器后即可运行 —— 仓库里已包含**汉化后的 Coder 源码**与全部构建脚本，无需再从零改造：

```bash
git clone https://github.com/Gloria0929/vscode-cline-build.git
cd vscode-cline-build
```

### 方式 A：Docker 一键部署（推荐）

只在目标机器安装 **Docker** + **Docker Compose**即可，无需 Node：

```bash
./build.sh build     # 首次构建自动用 .env.example 生成 .env，构建约 10-20 分钟
```

- 完成后浏览器打开 **`http://localhost:8443`**
- 密码：`.env` 中的 `PASSWORD`（未改则为 `changeme`）
- 常用命令：`./build.sh start|stop|rebuild|logs|shell|status`

### 方式 B：本地编译 Coder 扩展（VSIX）

无需 Docker，装有 **Bun**（或 Node）并能联网即可，直接把 Coder 装进本机 VS Code：

```bash
BUILD_WORK_DIR="$PWD" bash scripts/build-local.sh --source
code --install-extension dist/coder-bot-4.1.17.vsix
```

`--source` 会直接编译仓库内这份**已汉化源码**（跳过补丁阶段），首次联网装依赖约需 2-4 分钟，产物为独立 VSIX。

> **务必保留 `BUILD_WORK_DIR="$PWD"`**：脚本默认去 `/tmp/aicoder-local-build/cline` 找源码，不带这个变量会报 "Patched source tree not found" 而退出；`$PWD` 让它指向仓库根下的 `cline/` 这份源码。若需按上游 baseline 重新重建（会重新 clone 上游并套用脚本汉化、不保留仓库内手工改动），则去掉该变量直接跑 `bash scripts/build-local.sh`。

> 注意：仓库刻意忽略了 `cline/node_modules` 与 `.vsix`/`dist` 产物，clone 下来是**纯净源码**，请按上述任一种方式构建后再运行。

## 快速开始

### 1. 准备环境

```bash
# 复制环境配置文件
cp .env.example .env

# 编辑 .env，设置访问密码和用户 ID
vi .env
```

### 2. 构建并启动

```bash
# 构建镜像（首次构建需要 10-20 分钟，需要编译 Cline 源码）
docker compose build

# 启动服务
docker compose up -d
```

### 3. 访问

浏览器打开 `http://localhost:8443`，输入 `.env` 中设置的密码即可进入 IDE。

### 4. 配置 Coder API Key

进入 IDE 后，打开左侧活动栏的 **Coder** 面板（首次进入只有 "Bring my own API key" 选项），选择你的 AI 服务商（如 OpenAI、Anthropic、OpenRouter 等），填入 API Key 即可开始使用。

## 项目结构

```
.
├── Dockerfile                  # 多阶段构建：Stage1 编译 Coder, Stage2 部署 code-server
├── docker-compose.yml          # Docker Compose 编排文件
├── .env.example                # 环境变量模板
├── build/
│   └── modify-cline.sh         # 核心脚本：克隆 Cline → 移除登录 → 替换图标 → 构建 VSIX
├── assets/
│   ├── custom-icon.svg         # 彩色版：插件/扩展列表图标
│   └── custom-icon-mono.svg    # 白色单色版：聊天框 Logo、活动栏、面板、命令字体图标
├── config/
│   ├── settings.json           # VSCode 默认设置（禁用内置 Chat 等）
│   └── extensions.json         # 推荐扩展列表
├── scripts/
│   ├── entrypoint.sh           # 容器入口：内置化同步扩展、登录隐藏、启动 code-server
│   ├── export-vsix.sh          # 导出 Coder 为独立 VSIX 插件包（容器运行后执行）
│   └── build-local.sh          # 本地 macOS 直接构建 VSIX，无需 Docker
└── workspace/                  # 工作区目录（挂载到容器 /config/workspace）
```

### 脚本速查

| 脚本 | 用途 | 运行位置 |
|------|------|---------|
| `scripts/entrypoint.sh` | 容器入口：内置化同步、登录隐藏、启动 code-server | 容器内（自动） |
| `scripts/export-vsix.sh` | 从运行中的容器导出 VSIX 插件包 | 手动 |
| `scripts/build-local.sh` | 本地直接构建 VSIX（无需 Docker，输出 `dist/`） | 手动（macOS） |

## 自定义

### 替换图标

图标分为两套，按需替换后重新构建镜像即可：

| 文件 | 作用 |
|------|------|
| `assets/custom-icon.svg` | 插件/扩展列表图标（彩色版） |
| `assets/custom-icon-mono.svg` | 聊天框 Logo、活动栏图标、面板图标、命令字体图标（白色单色版） |

```bash
docker compose build --no-cache
docker compose up -d
```

### 导出独立 VSIX 插件包

```bash
# 容器运行后执行
bash scripts/export-vsix.sh
# 生成 ai-coder-4.1.17.vsix，可安装到任意 VS Code / code-server
```

### 本地直接构建 VSIX（无需 Docker）

不想等 Docker 构建时，可在 macOS 本地直接产出：

```bash
# 前置：node、bun、git、python3、rsvg-convert、zip（protoc 可选）
bash scripts/build-local.sh
# 输出: dist/ai-coder-4.1.17.vsix
```

`modify-cline.sh` 支持双模式：Docker 内（默认，GNU sed）与本地（`MODIFY_CLINE_LOCAL=1`，BSD sed），改造逻辑同一份脚本，产出一致。

### 调整 Cline 源码修改

所有源码修改逻辑在 `build/modify-cline.sh` 中，可按需调整：

- 移除更多功能（遥测、Marketplace 链接等）
- 保留部分登录功能
- 修改默认配置

### 指定 Cline 版本

在 `.env` 中设置分支或 tag：

```env
CLINE_BRANCH=v4.1.17
```

或使用自己的 fork：

```env
CLINE_REPO=https://github.com/yourname/cline.git
CLINE_BRANCH=your-branch
```

## 常见问题

### Q: 构建时间太长？

首次构建需要克隆 Cline 仓库、安装依赖、编译 TypeScript + React，通常 10-20 分钟。后续构建会利用 Docker 缓存层。

### Q: Coder 显示登录残留按钮？

修改脚本会尝试移除登录功能，但由于上游版本更新可能导致文件结构变化。如果登录按钮仍然出现：

1. 进入容器：`docker exec -it vscode-cline bash`
2. 检查扩展目录：`ls /config/extensions/aicoder.ai-coder-*/`
3. 检查容器日志是否有扩展激活报错，或编辑 `build/modify-cline.sh` 中的隐藏样式后重建

### Q: 页面一直加载中 / AI 面板打不开？

十有八九是扩展里 `webview-ui/build/` 缺失（vsce 因 `.gitignore` 忽略 build 目录导致）。重建并验证：

```bash
docker compose build --no-cache && docker compose up -d --force-recreate
docker exec vscode-cline sh -c 'ls /config/extensions/aicoder.ai-coder-*/webview-ui/build/assets/'
# 应列出 index.js、index.css 等文件
```

### Q: 活动栏图标显示灰色方块？

活动栏图标经 VS Code 主题色 mask 渲染，mono 图标必须用透明背景。当前已修复（透明背景 + 白色符号），若自定义图标务必保持透明背景。

### Q: `docker` 命令全部没反应？

Docker Desktop 守护进程可能假死，重启：

```bash
pkill -f "Docker Desktop"; sleep 5; open -a Docker
```

### Q: Coder 为什么在扩展列表找不到 / 无法卸载？

Coder 是**内置扩展**（built-in）：位于 code-server 系统扩展目录
`/usr/lib/code-server/lib/vscode/extensions/`，普通"已安装"列表**不显示**，只在扩展面板"**内置**"分类出现，
且**没有卸载按钮**（VS Code 禁止卸载内置扩展）。这是设计使然。

### Q: 如何更新 Coder？

```bash
docker compose build --no-cache
docker compose up -d
```

### Q: 如何备份数据？

```bash
# 备份配置和扩展
docker run --rm -v vscode-config:/data -v $(pwd)/backup:/backup alpine \
    tar czf /backup/vscode-config-backup.tar.gz -C /data .

# 恢复
docker run --rm -v vscode-config:/data -v $(pwd)/backup:/backup alpine \
    tar xzf /backup/vscode-config-backup.tar.gz -C /data
```

## 技术细节

### 构建流程

1. **Stage 1 (cline-builder)**: 使用 `node:22-bookworm` 镜像
   - 安装 bun、protoc、Python 等构建工具
   - 克隆 Cline 仓库
   - 执行 `modify-cline.sh` 修改源码：
     - 用 jq 从 package.json 移除账户命令
     - 将 AuthService 替换为 stub（返回未认证状态）
     - 将 auth 服务目录文件替换为空导出
     - 在 webview 中注入 CSS 隐藏登录 UI
     - 将 SDK 层认证文件替换为 stub
     - 替换图标文件（SVG + PNG）
   - 执行构建：`bun run protos` → `webview-ui/` 目录 `vite build`（跳过 `tsc -b` 类型检查，快且省内存，失败自动 fallback）→ esbuild 打包扩展宿主 → 手动打包 VSIX（保留 `webview-ui/build` 层级）
   - 打包后校验 VSIX 内含 `webview-ui/build/assets/index.js`，缺失则强制手动打包，避免产出坏包

2. **Stage 2 (code-server)**: 使用 `linuxserver/code-server`
   - 复制 VSIX 并用 `code-server --install-extension` 安装
   - 配置默认设置和工作区
   - 设置健康检查和自定义入口

### 移除的登录功能

| 原始文件 | 处理方式 |
|---------|---------|
| `src/sdk/auth-service.ts` | 替换为 stub，所有方法返回空值 |
| `src/services/auth/` | 目录下所有 .ts 文件替换为 `export {}` |
| `src/core/controller/account/` | 目录下所有 .ts 文件替换为 `export {}` |
| `sdk/packages/core/src/auth/cline.ts` | 替换为 stub |
| `sdk/packages/core/src/account/` | 目录下文件替换为 stub |
| `package.json` 中账户命令 | 用 jq 删除 |
| Webview 中登录 UI | 注入 CSS 隐藏 |

## License

- Cline: Apache-2.0 (https://github.com/cline/cline)
- 本项目配置文件: MIT
