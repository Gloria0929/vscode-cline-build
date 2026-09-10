# AI Coder (VSCode Server + Cline) — 构建与运行手册

> 本项目把 Cline 开源 AI 编程助手从源码编译后**直接打包**进一个 Docker 化的 VSCode Server（code-server），
> 无需通过插件市场下载；同时去掉了登录功能、替换了品牌图标，用于替换 VSCode 自带 Chat 能力。
>
> 本文档覆盖两种使用方式：**Docker Compose**（推荐）与 **原生 `docker run`**。

---

## 1. 项目结构与一键脚本

```
vscode-cline-docker/
├── Dockerfile                  # Docker 镜像构建定义（两阶段构建）
├── docker-compose.yml          # 容器编排配置
├── build.sh                    # Docker 模式便捷入口
├── build/
│   ├── modify-cline.sh         # 核心改造脚本（克隆→改名→去登录→换图标→编译→打包）
│   └── templates/              # 模板文件（替代 heredoc，兼容 macOS bash 3.2）
│       ├── ClineLogoComponent.tsx.tpl    # 聊天框 Logo 组件模板
│       ├── ClinePassHint.tsx.tpl         # ClinePass 提示组件（空实现）
│       ├── data-steps.ts.tpl             # Onboarding 数据步骤（仅保留 BYOK）
│       ├── hide-login.css.tpl            # 隐藏登录 UI 的 CSS
│       ├── remove-telemetry.py.tpl       # 删除遥测选项的 Python 脚本
│       ├── vsixmanifest.xml.tpl          # VSIX 清单模板
│       ├── Content_Types.xml.tpl         # VSIX 内容类型模板
│       └── README-branded.md.tpl         # 品牌化 README
├── scripts/
│   ├── build-local.sh          # 本地构建 VSIX（无需 Docker）
│   ├── entrypoint.sh           # 容器启动脚本
│   └── export-vsix.sh          # 从运行中的容器导出 VSIX
├── config/
│   ├── settings.json           # VSCode 默认设置
│   └── extensions.json         # 推荐扩展列表
└── assets/
    ├── custom-icon.svg         # 彩色图标（插件图标）
    └── custom-icon-mono.svg    # 单色图标（活动栏、聊天框等）
```

构建镜像有两个入口，任选其一：
- `docker compose` 命令（下面第 4、5 节）
- `./build.sh`（第 6 节，封装了 compose）

**不构建镜像、直接产出 VSIX** 还有第三条路：
- `bash scripts/build-local.sh`（第 12 节，本地 macOS 构建，无需 Docker）

---

## 2. 前置要求

| 依赖 | 说明 |
|------|------|
| Docker | 20.10+（建议用 Docker Desktop / Docker Engine 均可），能访问外网拉取 `node:22-bookworm`、`moby/buildkit` 与 `github.com/cline/cline` |
| 磁盘 | 首次构建需要约 8–10 GB 磁盘空间（镜像 + 网络 + 依赖 + 构建缓存） |
| 内存 | 建议 ≥ 8 GB（构建阶段会编译 React + TypeScript，内存较吃紧） |

> 首次构建会 `git clone` Cline 仓库、安装依赖、编译 webview（7k+ 模块）与扩展宿主，通常需要 **10–20 分钟**。
> 之后的增量构建会命中 Docker 缓存，快很多。

---

## 3. 配置环境变量

```bash
cd /vscode-cline-docker

# 从模板生成 .env（如果已存在可跳过）
cp .env.example .env

# 编辑关键参数
vi .env
```

`.env` 中最重要的几项：

```env
# —— 访问密码（浏览器打开 IDE 时必填）——
PASSWORD=change-me-to-a-secret

# —— 终端中的 sudo 密码（留空则禁用）——
SUDO_PASSWORD=

# —— 文件属主 UID/GID，建议与宿主机一致，否则挂载目录权限可能混乱 ——
PUID=1000
PGID=1000

# —— 时区 ——
TZ=Asia/Shanghai

# —— 宿主机映射端口 ——
PORT=8443

# —— 反向代理域名（可选，正向代理场景才需要）——
PROXY_DOMAIN=

# —— 构建参数（高级）：改 Cline 上游仓库 / 分支 / tag ——
CLINE_REPO=https://github.com/cline/cline.git
CLINE_BRANCH=main
```

> `PORT` 只在此处（以及 `.env`）配置即可，`docker-compose.yml` 会自动读取；
> 若用第 5 节的 `docker run`，端口、密码、UID 等都直接写在命令参数里。

---

## 4. 构建 — Docker Compose 方式（推荐）

```bash
cd /vscode-cline-docker

# 带进度输出的构建（看清每一步在做什么）
docker compose build --progress=plain
# 或者精简输出
docker compose build
```

**各常见变体：**

| 命令 | 用途 |
|------|------|
| `docker compose build` | 增量构建（优先用缓存） |
| `docker compose build --progress=plain` | 同上，但输出全部构建日志 |
| `docker compose build --no-cache` | 完全重建，不信任任何缓存（改脚本/上游后想彻底重来用这个） |
| `docker build -t vscode-cline-docker-vscode-server:latest .` | 跳过 compose 直接 `docker build` |
| `./build.sh build` | 便捷脚本：先 build 再 up |

> **构建速度优化**：webview 已改为在 `webview-ui/` 目录直接执行 `vite build`（跳过 `tsc -b` 全量类型检查），
> 编译时间从 10+ 分钟降到约 1 分钟，内存峰值减半；若 vite 失败会自动 fallback 到完整构建。
> **磁盘注意**：构建缓存可能积累 20+ GB，可用 `docker builder prune -f` 清理。

> **要点：改了 `build/modify-cline.sh` 之后如何让改动生效？**
> `Dockerfile` 会把 `build/modify-cline.sh` `COPY` 进构建器，只要文件内容变化，对应 Docker 层的缓存就会自动失效并重新执行脚本。
> 但如果曾经用 `--no-cache` 或改动方式比较特殊，最稳妥的姿势仍是：
> ```bash
> docker compose build --no-cache
> docker compose up -d --force-recreate
> ```
> 先重建镜像，再强制重建容器（`--force-recreate`），确保运行中的容器使用的是**最新的镜像**。

---

## 5. 运行

### 5.1 Docker Compose 启动

```bash
cd /vscode-cline-docker

# 首次 / 一般启动
docker compose up -d

# 镜像更新后想让容器换新镜像时
docker compose up -d --force-recreate

# 查看状态
docker compose ps

# 查看日志
docker compose logs -f vscode-server
```

### 5.2 等价的原生命令 `docker run`

`docker-compose.yml` 为一等公民，但如果不想用 compose，下面这条命令做的是**完全一样**的事
（同样的端口、卷、环境变量、健康检查）：

```bash
# 先建一个 Docker 卷用于持久化（只需一次）
docker volume create vscode-config

IMAGE=vscode-cline-docker-vscode-server:latest
cd /vscode-cline-docker

docker run -d \
  --name vscode-cline \
  --restart unless-stopped \
  -p 8443:8443 \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Asia/Shanghai \
  -e PASSWORD=change-me-to-a-secret \
  -e SUDO_PASSWORD= \
  -e PROXY_DOMAIN= \
  -e DEFAULT_WORKSPACE=/config/workspace \
  -v vscode-config:/config \
  -v "$PWD/workspace":/config/workspace \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  --network vscode-net \
  ${IMAGE}
```

**逐项说明：**

| 参数 | 对应 compose | 说明 |
|------|--------------|------|
| `--name vscode-cline` | `container_name` | 容器名，`docker exec -it vscode-cline bash` 用 |
| `--restart unless-stopped` | `restart` | 宿主机重启/Docker 重启后自动拉起 |
| `-p 8443:8443` | `ports` | 宿主机 `8443` → 容器 `8443`，浏览器入口 |
| `-e PASSWORD` | `environment` | 浏览器访问 IDE 的密码 |
| `-e PUID/PGID` | `environment` | 文件属主 ID，与 `id -u`、`id -g` 一致 |
| `-v vscode-config:/config` | `volumes` | 持久化配置/扩展/用户数据（Volume） |
| `-v $PWD/workspace:/config/workspace` | `volumes` | 代码工作区（bind mount，宿主机可见） |
| `-v /var/run/docker.sock:...:ro` | `volumes` | 可选：容器内使用 Docker（DinD 场景） |
| `--network vscode-net` | `networks` | 若该网络不存在，先 `docker network create vscode-net` |

> `Dockerfile` 里已内置 `HEALTHCHECK`，所以不传 `--health-*` 参数也会自动做健康检查。
> 手动确认状态：
> ```bash
> docker inspect --format '{{.State.Health.Status}}' vscode-cline   # healthy / starting / unhealthy
> ```

---

## 6. 便捷脚本 `./build.sh`

```bash
cd /vscode-cline-docker
chmod +x build.sh

./build.sh              # 等同 build：构建并启动，打印地址和密码
./build.sh start        # 仅启动已构建的服务
./build.sh stop         # 停止服务
./build.sh rebuild      # --no-cache 重建 + 启动
./build.sh logs         # 跟踪日志
./build.sh shell        # docker exec 进容器终端
./build.sh status       # 查看容器状态
./build.sh clean        # down -v + 清理缓存（危险，会删数据）
```

---

## 7. 访问与验证

浏览器打开 `http://localhost:8443`，输入上面设置的 `PASSWORD`。

### 7.1 验证扩展是否加载正常

```bash
# AI Coder 是内置扩展，位于 code-server 系统扩展目录
docker exec vscode-cline ls /usr/lib/code-server/lib/vscode/extensions/aicoder.ai-coder-4.1.17/

# 检查 webview 资产是否齐全（缺 build/ 会导致"一直加载打不开"）：
docker exec vscode-cline sh -c 'ls /usr/lib/code-server/lib/vscode/extensions/aicoder.ai-coder-4.1.17/webview-ui/build/assets/'
# 应当列出 index.js、index.css、codicon.ttf 等文件

# 扩展宿主日志（确认无报错、激活成功）
docker exec vscode-cline sh -c 'find /config/data/logs -name "1-AI Coder.log" | tail -1 | xargs tail -n 20'
```

打开 IDE 后，在左侧活动栏找到 **AI Coder** 面板；首次会进入 “How will you use AI Coder?” 引导，
只有 **Bring my own API key** 一个选项，选它并填好供应商 + API Key 即可开始对话。

### 7.2 图标体系（构建时自动分发）

| 图标文件 | 用途 | 颜色 |
|----------|------|------|
| `assets/custom-icon.svg` | 插件/扩展列表图标（icon.svg、icon.png） | 彩色渐变 |
| `assets/custom-icon-mono.svg` | 聊天框 Logo（chat-logo.svg）、活动栏图标、面板图标、命令字体图标 | 白色单色 |

> 活动栏图标经 VS Code **主题色 mask 渲染**，因此 mono 版必须使用**透明背景**（背景会被刷成主题色，白色符号才可见）。

### 7.3 内置插件形态（AI Coder 不可卸载）

AI Coder 以**内置扩展（built-in）**方式集成，而不是普通用户扩展：

- **位置**：`/usr/lib/code-server/lib/vscode/extensions/aicoder.ai-coder-4.1.17`（code-server 系统扩展目录）
- **扩展面板**：普通"已安装"列表**不显示**，只在"**内置**"（BUILT-IN）分类出现
- **卸载按钮**：**不存在**——VS Code 禁止卸载内置扩展
- **同步机制**：每次容器启动，`entrypoint.sh` 把镜像中的扩展同步到内置目录，并注入隐藏登录 UI 的 CSS（`hide-login.css`）

> 内置形态本身已不可卸载，因此早期版本的防卸载/防禁用 watcher 已移除，无需额外守护进程。

### 7.4 已移除的界面元素（构建时自动清理）

以下 Cline 残留/推广/冗余内容在构建时由 `modify-cline.sh` 自动移除（3i–3m 步骤），无需手动操作：

| 界面元素 | 位置 | 处理方式 |
|----------|------|---------|
| ClinePass 推广提示（"ClinePass — a low-cost subscription..."） | 设置页 API Provider 下拉下方 | 组件替换为空（3i） |
| "Try ClinePass" 横幅（"Get ClinePass / Switch to ClinePass provider..."） | 聊天欢迎区 | useMemo 短路，恒不渲染（3j） |
| "Let AI Coder take these actions without asking for approval. Docs" | 聊天输入框 Auto-approve 折叠面板 | 整块删除（3k） |
| "Having terminal issues? Check our Terminal Quick Fixes..." 帮助卡片 | 设置 → 终端（Terminal）分类底部 | 整块删除（3l） |
| "Allow error and usage reporting" 遥测设置项 | 设置 → General 分类 | Python 平衡 div 删除（3m） |

> 修改这些界面元素的逻辑都固化在 `build/modify-cline.sh` 的 3i–3m 步骤，改源码重新构建即恢复 Cline 原始行为。

---

## 8. 常见问题排查

| 现象 | 处理 |
|------|------|
| **页面一直“加载中/AI 面板打不开** | 十有八九是扩展里的 `webview-ui/build/` 缺失（vsce 会因 `.gitignore` 忽略 `build` 目录）。走 `docker compose build --no-cache + up -d --force-recreate` 重建，再用第 7.1 节确认 `webview-ui/build/assets` 存在 |
| 报错 `command 'ai-coder.xxxButtonClicked' not found` | 命令前缀/注册对不上。先确认 `build/modify-cline.sh` 里已把 `src/registry.ts` 的 prefix 固定为 `"ai-coder"`，再重建 |
| 扩展列表里仍出现旧 ID `saoudrizwan.claude-dev` | 说明用的是缓存旧镜像，`docker compose build --no-cache` 后重新拉起 |
| 登录按钮/About 没去掉 | 编辑 `build/modify-cline.sh` 中对应修改，重新构建 |
| 改了源码想重来 | `docker compose build --no-cache && docker compose up -d --force-recreate` |
| 访问要密码 | 密码在 `.env` 的 `PASSWORD`；忘记就改 `.env` 后重启容器 |
| **`docker` 命令全部无响应/卡住（构建没反应）** | Docker Desktop 守护进程假死。重启：`pkill -f "Docker Desktop"; sleep 5; open -a Docker`，等 `docker info` 恢复后再构建 |
| **构建日志停在 fantasticon/字体图标，几十秒无新输出** | 正常。`[cline-builder 9/9] RUN modify-cline.sh` 是完整流程（SDK+webview+esbuild+打包），需 5–8 分钟，等行尾出现 `done ... sha256:` 即完成 |
| **活动栏图标显示灰色方块** | mono 图标带背景色会被 mask 成主题色方块。使用透明背景的 SVG（当前已修复），或参考第 7.2 节图标体系 |
| **AI Coder 无法卸载（扩展列表里找不到）** | 属正常设计：AI Coder 是**内置扩展**（系统扩展目录），普通列表不显示、无卸载按钮；在扩展面板"内置"分类中可见（见 7.3） |
| 聊天框图标想改成别的图形 | 修改 `assets/custom-icon-mono.svg` 后重建镜像（构建时自动替换为 `chat-logo.svg`） |

---

## 9. 数据备份与恢复

```bash
# 备份配置卷（/config 下包含扩展、设置、用户数据）
docker run --rm \
  -v vscode-config:/data \
  -v "$PWD/backup":/backup \
  alpine tar czf /backup/vscode-config-backup.tar.gz -C /data .

# 恢复
docker run --rm \
  -v vscode-config:/data \
  -v "$PWD/backup":/backup \
  alpine tar xzf /backup/vscode-config-backup.tar.gz -C /data

# 工作区本身在宿主机 ./workspace 下，直接复制该目录即可
```

---

## 10. 自定义构建参数

```bash
# 想从自己的 fork / 指定 tag 构建：
CLINE_REPO=https://github.com/yourname/cline.git CLINE_BRANCH=v4.1.17 \
  docker compose build
# 等价地写入 .env：
#   CLINE_REPO=... 
#   CLINE_BRANCH=...
```

更换图标只需替换两个文件（分工见第 7.2 节），再重建镜像：

- `assets/custom-icon.svg`（彩色版）→ 插件/扩展列表图标
- `assets/custom-icon-mono.svg`（白色单色版）→ 聊天框 Logo、活动栏图标、面板图标、命令字体图标

---

## 11. 导出 AI Coder 为独立 VSIX 插件

容器运行后，可把改造后的扩展导出为标准 VSIX 包，安装到**任意** VS Code / code-server 环境（无需 Docker）：

```bash
# 1. 确保容器运行
docker compose up -d

# 2. 导出（默认输出到项目根目录 ai-coder-4.1.17.vsix）
bash scripts/export-vsix.sh
# 自定义输出路径： bash scripts/export-vsix.sh vscode-cline /path/to/output.vsix
```

### 安装导出的 VSIX

| 环境 | 方法 |
|------|------|
| VS Code 界面 | 扩展面板（Ctrl+Shift+X）→ `···` → **从 VSIX 安装...** → 选择文件 → 重启窗口 |
| VS Code 命令行 | `code --install-extension ai-coder-4.1.17.vsix` |
| code-server 浏览器 | 扩展面板 → `···` → **从 VSIX 安装...** |
| 直接拖拽 | 把 `.vsix` 拖进扩展面板区域 |

> 导出的 VSIX 已包含完整 webview 资源与自定义图标，但**不含**容器内的内置扩展形态（那由放置位置决定）。
> 注意：VSIX 按容器内 VS Code 版本编译，装到本地需 VS Code 1.80+。

### 导出后如何做成"内置插件"

**通过 VSIX 正常安装 = 普通用户扩展（有卸载按钮）**。若目标环境也要不可卸载的内置形态，把 VSIX 解压后的 `extension/` 目录放到目标环境的内置扩展目录：

```bash
# 1. 解压 vsix（本质是 zip，extension/ 是真正的扩展内容）
unzip ai-coder-4.1.17.vsix -d /tmp/aicoder

# 2. 放入目标环境的内置扩展目录
#    code-server（Linux 容器）：
cp -r /tmp/aicoder/extension /usr/lib/code-server/lib/vscode/extensions/aicoder.ai-coder-4.1.17
#    桌面 VS Code（macOS）：
cp -r /tmp/aicoder/extension "/Applications/Visual Studio Code.app/Contents/Resources/app/extensions/aicoder.ai-coder-4.1.17"
#    桌面 VS Code（Windows/Linux）：<VS Code 安装目录>/resources/app/extensions/
```

> 各平台内置扩展目录路径不同，且需确认目标 VS Code 版本兼容（1.80+）。

---

## 12. 本地构建 VSIX（无需 Docker）

不想等 Docker 构建时，可以在 macOS 本地直接产出 VSIX：

```bash
cd /vscode-cline-docker
bash scripts/build-local.sh
# 输出: dist/ai-coder-4.1.17.vsix
```

### 前置依赖（本地需已安装）

| 依赖 | 说明 |
|------|------|
| node + bun | 编译 webview 与扩展宿主 |
| git | 克隆 Cline 源码 |
| python3 | 脚本内文本修改（平衡 div 删除等） |
| rsvg-convert（librsvg） | 图标 SVG → PNG 转换 |
| zip | 手动打包 VSIX |
| protoc（可选） | 缺失时 proto 生成步骤自动跳过，通常不影响构建 |

### 实现原理

`scripts/build-local.sh` 内部流程：

```
克隆源码到 /tmp/aicoder-local-build/cline
    → 设置 MODIFY_CLINE_LOCAL=1 + CLONE_DIR（本地模式）
    → 运行 build/modify-cline.sh（与 Docker 内同一套改造逻辑）
    → 收集 VSIX 到 dist/ai-coder-4.1.17.vsix
```

`modify-cline.sh` 的双模式支持：

- **Docker 内（默认）**：`sedi` shim 用 GNU sed（`-i`），`CLONE_DIR` 默认 `/cline`
- **本地 macOS（`MODIFY_CLINE_LOCAL=1`）**：`sedi` shim 用 BSD sed（`-i ''`），`CLONE_DIR` 通过环境变量覆盖

两者产出完全相同的 VSIX，改造逻辑同一份脚本，无分叉。

### 与 Docker 构建对比

| | Docker 构建 | 本地构建 |
|--|------------|---------|
| 耗时 | 10–15 分钟 | 约 5–8 分钟 |
| 依赖 | 自动（镜像内装好） | 需本地安装（见上表） |
| 产出 | 镜像内扩展 + 可导出 VSIX | 直接产出 VSIX |
| 适用 | 部署运行、内置插件形态 | 快速打包分发 |

---

## 清理

```bash
# 停止并删除容器（保留数据卷）
docker compose down

# 连同数据卷一起删除（⚠ 会清除全部配置/扩展数据）
docker compose down -v
```

---

## 13. 直接修改源码后打包（`--source` 模式）

> 本章适用场景：**不跑 `modify-cline.sh` 的 patch/汉化阶段**，而是直接编辑项目里的 `cline/` 源码树后打包。
> 适合想精细控制每一行改动的开发者；`--source` 会跳过裁剪脚本，因此手工改动不会被覆盖。

### 13.1 打包命令

```bash
cd /vscode-cline-docker
BUILD_WORK_DIR=/vscode-cline-docker \
  bash scripts/build-local.sh --source
```

- `BUILD_WORK_DIR` 指向项目根，使脚本内部 `CLONE_DIR = <工作根>/cline` 命中你直接编辑的源码树。
- `--source` 触发 `SKIP_PATCH=1`，**跳过 Step 2–3（克隆后的一切 patch/汉化）**，只执行依赖安装 → proto 生成 → 编译 → 打包。
- 首次构建需联网拉依赖（`bun install`），较慢；之后增量约 2–4 分钟。

### 13.2 产物与安装

- 产物：`dist/coder-bot-4.1.17.vsix`
- 安装：`code --install-extension dist/coder-bot-4.1.17.vsix`

### 13.3 `--source` 模式注意事项

| 事项 | 说明 |
|------|------|
| 会覆盖的 | `build-proto.mjs` 启动时会重建 `src/generated/` 与 `src/shared/proto/`。若你改的是 **proto 源**（`proto/*.proto`）则无影响；若改的是**生成产物**（如 `src/shared/proto/host/env.ts` 的注释），重生成后会被还原。功能性改动都在非生成目录，不受影响 |
| 不会覆盖的 | 其余 `src/`、`webview-ui/src/` 的所有手工编辑 |

---

## 14. 汉化与品牌命名记录

当前源码树已把用户可见命名统一为 **Coder**，并将界面文案汉化。以下为已完成的修改记录，新增改动请同步维护。

### 14.1 品牌命名（已统一为 Coder）

- `displayName`、创建终端的名字、日志前缀 `[Coder]`、错误提示、About 页版本号均为 Coder。
- 源码/worktree 回退文案中的 “Cline” 亦改为 “Coder”；`cline.*Service`（proto 包命名空间）与命令前缀 `ai-coder.*` 属内部标识，保持不变。

### 14.2 已汉化界面清单

| 位置 | 内容 |
|------|------|
| 终端设置（TerminalSettingsSection） | 执行模式、Shell 集成超时、终端复用、默认配置文件等解释文字 |
| 工作树页（WorktreesView） | 标题、说明、徽章、操作 tooltip、新建/删除/合并弹窗全部文本 |
| API 配置（ApiConfigurationSection） | “为 Plan 与 Act 模式使用不同的模型”及其说明 |
| **聊天输入框 Auto-approve（AutoApproveBar）** | “自动批准：”、已启用动作 shortName（读取/编辑/命令/网页/MCP）、“无”、展开/收起 aria-label |
| Auto-approve 浮层（AutoApproveModal/MenuItem） | 动作 label 已为中文；浮层无其他可见英文 |
| 提示条（FeatureTip） | auto-approve 提示文字 |
| 设置侧边栏 | 移除「通用」分类（删除 SettingsTabID 的 `general`、SETTINGS_TABS 项、渲染映射，并删除孤儿文件 GeneralSettingsSection.tsx） |
| Customize 入口（Navbar） | 顶栏图标 tooltip/aria：「Customize」→「自定义」 |
| Customize 弹窗（ClineRulesToggleModal） | 开关按钮 tooltip/aria：「Customize」→「自定义」；tab 名「Rules/Skills/Workflows」→「规则/技能/工作流」（Hooks 保留）；删除展开面板的说明文字块（Rules/Workflows/Skills/Hooks 描述） |
| Skills/MCP 面板（MarketplaceView） | 删除 Skills 与 MCP 栏目顶部各自的说明文字 |
| SettingsView 通用「完成」按钮（ViewHeader） | 公共 ViewHeader 的 Done → 完成（所有子页面右上角共用） |
| API 配置页与全部 provider 组件 | 大量字段标签/说明/按钮/提示汉化，覆盖 providers/*、common/*、各 ModelPicker（模型、模型 ID、输入 API 密钥、AWS 区域、正在连接…、退出登录等）；保留 provider 品牌名与 API Key/Base URL 等专有术语 |

> 备注：浮层内动作项的 `label` 与输入框行的 `shortName` 分属不同字段（constants.ts 的 `ActionMetadata`），改动时两处都要改。