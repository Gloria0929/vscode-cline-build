#!/bin/bash
set -e

# =============================================================================
# entrypoint.sh — code-server with AI Coder (rebranded Cline, replaces chat)
# =============================================================================

# ---- Ensure directories exist ----
mkdir -p /config/workspace /config/data /config/extensions

# ---- Sync extensions from image (/opt) into runtime locations ----
# /config is a Docker volume: image-layer extensions are shadowed after the
# first run, so we refresh on every start to pick up rebuilt extensions.
# AI Coder is installed as a BUILT-IN extension (system dir, no uninstall
# button in the UI); everything else stays in the user extensions dir.
BUILTIN_EXT_DIR="/usr/lib/code-server/lib/vscode/extensions"

if [ -d /opt/extensions ] && [ -n "$(ls -A /opt/extensions 2>/dev/null)" ]; then
    echo "[init] Syncing extensions..."
    # --- AI Coder → built-in extensions dir (hidden from uninstall UI) ---
    rm -rf /config/extensions/aicoder.ai-coder-* \
           /config/extensions/saoudrizwan.claude-dev-* \
           /config/extensions/claude-dev-*
    rm -f  /config/extensions/.obsolete
    rm -rf "${BUILTIN_EXT_DIR}"/aicoder.ai-coder-*
    cp -r /opt/extensions/aicoder.ai-coder-* "${BUILTIN_EXT_DIR}"/ 2>/dev/null || true
    echo "[init] AI Coder installed as built-in extension: ${BUILTIN_EXT_DIR}"
    # --- everything else (language pack, ...) stays user-level ---
    for d in /opt/extensions/*; do
        [ -d "${d}" ] || continue
        case "$(basename "${d}")" in
            aicoder.ai-coder-*|saoudrizwan*|claude-dev-*) continue ;;
        esac
        rm -rf "/config/extensions/$(basename "${d}")"
        cp -r "${d}" /config/extensions/ 2>/dev/null || true
    done
fi

# ---- Copy default settings on first run ----
SETTINGS_DIR="/config/data/Machine"
mkdir -p "${SETTINGS_DIR}"
if [ ! -f "${SETTINGS_DIR}/settings.json" ]; then
    echo "[init] Copying default settings.json..."
    cp /defaults/settings.json "${SETTINGS_DIR}/settings.json" 2>/dev/null || true
fi

# ---- Enable Chinese UI on first run (language pack is pre-installed) ----
USER_DIR="/config/data/User"
mkdir -p "${USER_DIR}"
if [ ! -f "${USER_DIR}/locale.json" ]; then
    echo "[init] Setting UI locale to zh-cn..."
    echo '{"locale":"zh-cn"}' > "${USER_DIR}/locale.json"
fi

# ---- Backup CSS injection into webview build (hide login UI) ----
# Extracted as a function so the anti-uninstall watcher can re-apply the
# injection to a restored extension copy (the /opt source has no CSS patch).
inject_hide_login_css() {
    local ext_dir="$1"
    for WEBVIEW_DIR in "${ext_dir}/webview-ui/build" "${ext_dir}/dist/webview-ui"; do
        if [ -d "${WEBVIEW_DIR}" ]; then
            cat > "${WEBVIEW_DIR}/hide-login.css" 2>/dev/null << 'CSS_EOF'
/* Hide account/login UI elements — self-hosted mode */
[class*="account"], [class*="Account"],
[class*="login"], [class*="Login"],
[data-testid*="account"], [data-testid*="login"] {
    display: none !important;
    visibility: hidden !important;
}
CSS_EOF
            if [ -f "${WEBVIEW_DIR}/index.html" ] && ! grep -q "hide-login.css" "${WEBVIEW_DIR}/index.html" 2>/dev/null; then
                sed -i 's|</head>|<link rel="stylesheet" href="hide-login.css"></head>|' "${WEBVIEW_DIR}/index.html" 2>/dev/null || true
            fi
        fi
    done
}

CLINE_EXT_DIR=$(ls -d "${BUILTIN_EXT_DIR}"/aicoder.ai-coder-* 2>/dev/null | head -1 || true)
if [ -z "${CLINE_EXT_DIR}" ]; then
    CLINE_EXT_DIR=$(ls -d /config/extensions/aicoder.ai-coder-* 2>/dev/null | head -1 || true)
fi

if [ -n "${CLINE_EXT_DIR}" ]; then
    inject_hide_login_css "${CLINE_EXT_DIR}"
fi

# ---- Print startup banner ----
echo ""
echo "============================================================"
echo "  VSCode Server + AI Coder (Self-hosted, No Login)"
echo "============================================================"
echo "  Access URL:  http://0.0.0.0:8443"
echo "  Workspace:   /config/workspace"
echo "  AI Coder:    Pre-installed, replaces built-in chat"
echo "  Login:       Disabled (configure API key in AI Coder settings)"
echo "============================================================"
echo ""

# ---- Start code-server ----
exec code-server \
    --bind-addr 0.0.0.0:8443 \
    --user-data-dir /config/data \
    --extensions-dir /config/extensions \
    --auth password \
    /config/workspace
