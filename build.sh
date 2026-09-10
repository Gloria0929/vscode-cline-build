#!/bin/bash
set -e

# =============================================================================
# build.sh — 便捷构建和启动脚本
# =============================================================================

cd "$(dirname "$0")"

# ---- 颜色输出 ----
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}"
echo "  ╔═══════════════════════════════════════════════╗"
echo "  ║  VSCode Server + Cline 构建脚本                ║"
echo "  ╚═══════════════════════════════════════════════╝"
echo -e "${NC}"

# ---- 检查 .env 文件 ----
if [ ! -f .env ]; then
    echo -e "${YELLOW}[INFO] 未找到 .env 文件，从模板创建...${NC}"
    cp .env.example .env
    echo -e "${YELLOW}[INFO] 请编辑 .env 设置密码等参数: vi .env${NC}"
    echo -e "${YELLOW}[INFO] 使用默认配置继续构建...${NC}"
fi

# ---- 命令处理 ----
case "${1:-build}" in
    build)
        echo -e "${GREEN}[1/3] 构建 Docker 镜像...${NC}"
        echo -e "${CYAN}    （首次构建需要 10-20 分钟，需要编译 Cline 源码）${NC}"
        docker compose build --progress=plain
        echo -e "${GREEN}[2/3] 构建完成!${NC}"
        echo -e "${GREEN}[3/3] 启动服务...${NC}"
        docker compose up -d
        echo ""
        echo -e "${GREEN}================================================${NC}"
        echo -e "${GREEN}  服务已启动!${NC}"
        echo -e "${GREEN}  访问: http://localhost:8443${NC}"
        PASSWORD=$(grep PASSWORD .env 2>/dev/null | head -1 | cut -d= -f2 || echo "changeme")
        echo -e "${GREEN}  密码: ${PASSWORD}${NC}"
        echo -e "${GREEN}================================================${NC}"
        ;;

    start|up)
        echo -e "${GREEN}启动服务...${NC}"
        docker compose up -d
        echo -e "${GREEN}访问: http://localhost:8443${NC}"
        ;;

    stop|down)
        echo -e "${YELLOW}停止服务...${NC}"
        docker compose down
        echo -e "${GREEN}服务已停止${NC}"
        ;;

    rebuild)
        echo -e "${YELLOW}重新构建 (不使用缓存)...${NC}"
        docker compose build --no-cache --progress=plain
        docker compose up -d
        echo -e "${GREEN}重建完成! 访问: http://localhost:8443${NC}"
        ;;

    logs)
        docker compose logs -f
        ;;

    shell|exec)
        docker exec -it vscode-cline bash
        ;;

    status)
        docker compose ps
        ;;

    clean)
        echo -e "${RED}清理构建缓存和卷...${NC}"
        read -p "确认清理? (y/N) " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            docker compose down -v
            docker system prune -f
            echo -e "${GREEN}清理完成${NC}"
        else
            echo "取消清理"
        fi
        ;;

    *)
        echo "用法: $0 {build|start|stop|rebuild|logs|shell|status|clean}"
        echo ""
        echo "命令:"
        echo "  build     首次构建并启动 (默认)"
        echo "  start     启动已构建的服务"
        echo "  stop      停止服务"
        echo "  rebuild   重新构建 (无缓存)"
        echo "  logs      查看日志"
        echo "  shell     进入容器 shell"
        echo "  status    查看状态"
        echo "  clean     清理所有数据和缓存"
        exit 1
        ;;
esac
