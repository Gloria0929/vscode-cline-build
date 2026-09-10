# =============================================================================
# Stage 1: Build Cline extension from source (rebranded as "AI Coder")
# =============================================================================
FROM node:22-bookworm AS cline-builder

RUN apt-get update && apt-get install -y \
    git protobuf-compiler python3 make g++ curl jq librsvg2-bin zip unzip \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g bun

ARG CLINE_REPO=https://github.com/cline/cline.git
ARG CLINE_BRANCH=main
RUN git clone --depth 1 --branch ${CLINE_BRANCH} ${CLINE_REPO} /cline

WORKDIR /cline

COPY build/modify-cline.sh /tmp/modify-cline.sh
COPY build/templates /tmp/templates
COPY assets/custom-icon.svg /tmp/custom-icon.svg
COPY assets/custom-icon-mono.svg /tmp/custom-icon-mono.svg

RUN chmod +x /tmp/modify-cline.sh && /tmp/modify-cline.sh

# =============================================================================
# Stage 2: code-server with "AI Coder" pre-installed (replaces built-in chat)
# =============================================================================
FROM node:22-bookworm

LABEL maintainer="custom"
LABEL description="VSCode Server (code-server) with AI Coder (rebranded Cline, no login, custom icons) replacing the built-in chat"

ENV PUID=1000
ENV PGID=1000
ENV TZ=Asia/Shanghai
ENV DEFAULT_WORKSPACE=/config/workspace

# Install system packages and code-server
RUN apt-get update && apt-get install -y \
    git curl wget unzip jq sudo ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://code-server.dev/install.sh | sh

# Remove built-in GitHub Copilot Chat extension — AI Coder replaces it
RUN rm -rf /usr/lib/code-server/lib/vscode/extensions/copilot

# Create non-root user
RUN useradd -m -s /bin/bash -u 1000 codeserver 2>/dev/null || true

# Copy the built VSIX from builder stage
COPY --from=cline-builder /cline/apps/vscode/*.vsix /tmp/cline-extension.vsix

# Install AI Coder into a pristine image location (/opt).
# /config is a Docker volume and would shadow image layers, so the
# entrypoint syncs from /opt into /config/extensions on every start.
RUN mkdir -p /opt/extensions \
    && code-server --install-extension /tmp/cline-extension.vsix --force \
        --extensions-dir /opt/extensions 2>/dev/null || \
    (cd /opt/extensions && \
     unzip -q -o /tmp/cline-extension.vsix && \
     mv extension aicoder.ai-coder 2>/dev/null || true) \
    ; ls /opt/extensions/

# Install additional VSCode extensions (Chinese language pack)
RUN code-server --install-extension MS-CEINTL.vscode-language-pack-zh-hans \
    --extensions-dir /opt/extensions 2>/dev/null || true

# Copy configuration files
COPY config/settings.json /defaults/settings.json
COPY config/extensions.json /defaults/extensions.json

# Copy entrypoint script
COPY scripts/entrypoint.sh /custom-entrypoint.sh
RUN chmod +x /custom-entrypoint.sh

# Create workspace and config directories
RUN mkdir -p /config/workspace /config/data /config/extensions

EXPOSE 8443

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8443/healthz || exit 1

ENTRYPOINT ["/custom-entrypoint.sh"]
