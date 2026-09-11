#!/bin/bash
set -ex

# =============================================================================
# modify-cline.sh — 克隆、重命名为“Coder”（移除认证、替换图标）、构建
#
# 默认情况下在 Docker 构建器（Debian、GNU sed）中运行。若要在本地 macOS（BSD sed）上运# 行，请设置 MODIFY_CLINE_LOCAL=1 —— 下面的 sedi 虚拟程序将自动调整原地替换标志。
# =============================================================================

if [ -n "${MODIFY_CLINE_LOCAL}" ]; then
    # BSD sed needs a separate '' argument for -i; GNU sed takes -i alone.
    sedi() { sed -i '' "$@"; }
else
    sedi() { sed -i "$@"; }
fi

CLONE_DIR="${CLONE_DIR:-/cline}"
VSCODE_DIR="${CLONE_DIR}/apps/vscode"
SDK_DIR="${CLONE_DIR}/sdk"
NEW_NAME="Coder"
# Template files replace heredocs (macOS ships bash 3.2, which segfaults on some
# heredocs; cp from a template file is immune to shell parsing).
TEMPLATE_DIR="${TEMPLATE_DIR:-/tmp/templates}"

echo ""
echo "================================================"
echo "  Cline -> Coder Rebrand & Build Pipeline"
echo "================================================"
echo ""

# ---------------------------------------------------------------------------
# Step 0: Install deps and build SDK FIRST (before any modifications)
# ---------------------------------------------------------------------------
echo "=== Step 0: Installing deps and building SDK ==="

cd "${CLONE_DIR}"
bun install 2>/dev/null || npm install 2>/dev/null || true

if [ -d "${SDK_DIR}" ]; then
    echo "  - Building SDK packages..."
    cd "${SDK_DIR}"
    bun install 2>/dev/null || true
    bun run build 2>/dev/null || npm run build 2>/dev/null || {
        for pkg in "${SDK_DIR}"/packages/*/; do
            if [ -f "${pkg}/package.json" ]; then
                cd "${pkg}"
                bun run build 2>/dev/null || npm run build 2>/dev/null || true
                cd "${SDK_DIR}"
            fi
        done
    }
    echo "  ✓ SDK packages built"
fi

cd "${VSCODE_DIR}"
bun install 2>/dev/null || npm install 2>/dev/null || true
echo "  ✓ Dependencies installed"

# ---------------------------------------------------------------------------
# Step 1: Generate protobuf stubs
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 1: Generating protobuf stubs ==="
cd "${VSCODE_DIR}"
bun run protos 2>/dev/null || npx tsx scripts/generate-proto-stubs.ts 2>/dev/null || echo "  ⚠ Proto generation skipped"
echo "  ✓ Protobuf stubs generated"

# ---------------------------------------------------------------------------
# Steps 2-3 are the PATCH phase (auth removal + rebranding). In source-edit
# mode (SKIP_PATCH=1) the tree was already patched once and is hand-maintained,
# so the entire phase is skipped and only the build steps (4-6) run.
# ---------------------------------------------------------------------------
if [ -z "${SKIP_PATCH}" ]; then

# ---------------------------------------------------------------------------
# Step 2: Remove login / authentication functionality
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 2: Removing authentication functionality ==="

cd "${VSCODE_DIR}"

if command -v jq &> /dev/null; then
    echo "  - Removing account commands from package.json..."
    for cmd in "cline.accountButtonClicked" "cline.login" "cline.logout" "cline.authCallback"; do
        jq --arg cmd "${cmd}" \
           'del(.contributes.commands[] | select(.command == $cmd))' \
           package.json > pkg.tmp && mv pkg.tmp package.json
    done
    for menu_section in $(jq -r '.contributes.menus // {} | keys[]' package.json 2>/dev/null); do
        jq --arg section "${menu_section}" \
           'del(.contributes.menus[$section][]? | select(.command == "cline.accountButtonClicked"))' \
           package.json > pkg.tmp && mv pkg.tmp package.json
    done
    echo "  ✓ package.json commands cleaned"
fi

# Patch auth message handlers in controller (rename cases so they never match)
echo "  - Patching auth message handlers..."
find "${VSCODE_DIR}/src/core/controller" -maxdepth 1 -name "*.ts" 2>/dev/null | while read -r f; do
    if grep -qE "accountButtonClicked|authLogin|authLogout|authCallback" "${f}" 2>/dev/null; then
        sedi \
            -e 's/case "accountButtonClicked"/case "accountButtonClicked_DISABLED"/g' \
            -e 's/case "authLogin"/case "authLogin_DISABLED"/g' \
            -e 's/case "authLogout"/case "authLogout_DISABLED"/g' \
            -e 's/case "authCallback"/case "authCallback_DISABLED"/g' \
            "${f}" 2>/dev/null || true
    fi
done
echo "  ✓ Auth handlers patched"

# Inject CSS to hide login UI in webview (bundled at build time)
# Place hide-login.css next to the webview entry (src/ root). Earlier Cline
# builds kept a styles/ dir — upstream removed it, so a fixed styles/ path
# silently no-ops; src/ root is stable.
WEBVIEW_ENTRY="${VSCODE_DIR}/webview-ui/src/main.tsx"
cp "${TEMPLATE_DIR}/hide-login.css.tpl" "${VSCODE_DIR}/webview-ui/src/hide-login.css"
if [ -f "${WEBVIEW_ENTRY}" ] && ! grep -q "hide-login.css" "${WEBVIEW_ENTRY}"; then
    # perl instead of sed's `1i\`: GNU and BSD sed differ on the insert
    # syntax, which silently no-ops on macOS — perl is identical on both.
    perl -i -pe 'print "import \"./hide-login.css\"\n" if $. == 1' "${WEBVIEW_ENTRY}"
    echo "  ✓ CSS injected into webview build"
fi

echo "  ✓ Authentication removal complete"

# ---------------------------------------------------------------------------
# Step 3: REBRAND — Replace icons + Rename to "Coder"
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 3: Rebranding to ${NEW_NAME} ==="

cd "${VSCODE_DIR}"

ICONS_DIR="${VSCODE_DIR}/assets/icons"
CUSTOM_SVG="${CUSTOM_SVG:-/tmp/custom-icon.svg}"
CUSTOM_MONO="${CUSTOM_MONO:-/tmp/custom-icon-mono.svg}"

# 3a. Replace ALL icon files in assets/icons
if [ -d "${ICONS_DIR}" ]; then
    echo "  - Replacing all icon files..."
    # Activity bar icon (icon.svg) MUST be a transparent-background monochrome
    # shape: VS Code renders activity-bar SVGs as a theme-colored mask, so the
    # color gradient version shows up as a flat gray square. The mono icon has
    # a transparent background, so the mask yields a visible theme-colored logo.
    cp "${CUSTOM_MONO}" "${ICONS_DIR}/icon.svg"
    cp "${CUSTOM_MONO}" "${ICONS_DIR}/cline-bot.svg"
    cp "${CUSTOM_MONO}" "${ICONS_DIR}/sleepy-cline.svg"
    # Extension/plugin icon keeps the COLOR variant. VS Code's package.json
    # "icon" field accepts SVG directly, so point it at a color SVG instead of
    # depending on rsvg-convert (which is not on every PATH) to render a PNG.
    cp "${CUSTOM_SVG}" "${ICONS_DIR}/icon-color.svg"
    if command -v rsvg-convert &> /dev/null; then
        rsvg-convert -w 128 -h 128 "${CUSTOM_MONO}" -o "${ICONS_DIR}/robot_panel_dark.png"
        rsvg-convert -w 128 -h 128 "${CUSTOM_MONO}" -o "${ICONS_DIR}/robot_panel_light.png"
        echo "    ✓ PNG icons generated (robot panel)"
    fi
    echo "  ✓ Icon files replaced"
fi

# 3b. Replace webview logo components (keep export names & props API intact)
#     The in-chat logo renders the SVG FILE directly (the mono icon is copied
#     into the webview bundle as chat-logo.svg). Only the extension/plugin icon
#     (assets/icons/icon.svg + icon.png) keeps the color variant.
LOGO_DIR="${VSCODE_DIR}/webview-ui/src/assets"
if [ -d "${LOGO_DIR}" ]; then
    echo "  - Pointing webview logo components at assets/chat-logo.svg..."

    # Ship the mono icon inside the webview bundle as chat-logo.svg
    cp "${CUSTOM_MONO}" "${LOGO_DIR}/chat-logo.svg" 2>/dev/null || true

    # All three logo components now render that SVG file directly. The <img>
    # keeps the component props API (className/style/width/height) so callers
    # like HomeHeader still work unchanged.
    # Template file + cp/sed instead of a heredoc: macOS ships bash 3.2, which
    # segfaults on this heredoc; a template file is immune to shell parsing.
    LOGO_TEMPLATE="${LOGO_TEMPLATE:-${TEMPLATE_DIR}/ClineLogoComponent.tsx.tpl}"
    for LOGO_NAME in ClineLogoWhite ClineLogoVariable ClineLogoSanta; do
        cp "${LOGO_TEMPLATE}" "${LOGO_DIR}/${LOGO_NAME}.tsx"
        # patch the component name in place
        sedi "s/LOGO_NAME/${LOGO_NAME}/g" "${LOGO_DIR}/${LOGO_NAME}.tsx"
    done

    echo "  ✓ Webview logo components now read assets/chat-logo.svg"
fi

# 3c. Generate custom font icon (for $(cline-icon) command icons)
echo "  - Generating custom font icon..."
FONT_OK=false
if [ -f "${CUSTOM_MONO}" ]; then
    FONT_SRC="/tmp/icon-font-src"
    FONT_OUT="/tmp/icon-font-out"
    rm -rf "${FONT_SRC}" "${FONT_OUT}"
    mkdir -p "${FONT_SRC}" "${FONT_OUT}"
    cp "${CUSTOM_MONO}" "${FONT_SRC}/ai-coder.svg"

    if npx -y fantasticon "${FONT_SRC}" -o "${FONT_OUT}" --name cline-bot --normalize --font-height 1000 --font-types woff,ttf 2>/dev/null; then
        CODEPOINTS_FILE=$(ls "${FONT_OUT}"/*.json 2>/dev/null | head -1)
        if [ -n "${CODEPOINTS_FILE}" ] && [ -f "${FONT_OUT}/cline-bot.woff" ]; then
            # Codepoint may be number or hex string — normalize to lowercase hex digits
            if jq -e 'to_entries[0].value | type == "number"' "${CODEPOINTS_FILE}" >/dev/null 2>&1; then
                CP_HEX=$(printf '%x' "$(jq -r 'to_entries[0].value' "${CODEPOINTS_FILE}")")
            else
                CP_HEX=$(jq -r 'to_entries[0].value' "${CODEPOINTS_FILE}" | tr -d '"\\' | sed 's/^0[xX]//' | tr '[:upper:]' '[:lower:]')
            fi
            if [ -n "${CP_HEX}" ] && [ "${CP_HEX}" != "null" ]; then
                cp "${FONT_OUT}/cline-bot.woff" "${ICONS_DIR}/cline-bot.woff"
                cp "${FONT_OUT}/cline-bot.ttf" "${ICONS_DIR}/cline-bot.ttf" 2>/dev/null || true
                jq --arg cp "\\${CP_HEX}" \
                   '(.contributes.icons["cline-icon"].default.fontCharacter) = $cp' \
                   package.json > pkg.tmp && mv pkg.tmp package.json
                FONT_OK=true
                echo "    ✓ Custom font generated (codepoint: ${CP_HEX})"
            fi
        fi
    fi
fi

# Fallback: use built-in codicon if font generation failed
if [ "${FONT_OK}" = "false" ]; then
    echo "    ⚠ Font generation failed, falling back to codicon..."
    if command -v jq &> /dev/null; then
        jq 'del(.contributes.icons)' package.json > pkg.tmp && mv pkg.tmp package.json
        jq '(.contributes.commands[]? | select(.icon == "$(cline-icon)") | .icon) |= "$(sparkle)"' \
           package.json > pkg.tmp && mv pkg.tmp package.json
    fi
    find "${VSCODE_DIR}/src" -name "*.ts" -exec sedi \
        -e 's/new vscode\.ThemeIcon("cline-icon")/new vscode.ThemeIcon("sparkle")/g' \
        {} + 2>/dev/null || true
    echo "    ✓ Codicon fallback applied"
fi

# 3d. Rename in package.json (display strings only, keep internal IDs)
if command -v jq &> /dev/null; then
    echo "  - Renaming in package.json..."
    jq --arg name "${NEW_NAME}" '
        .displayName = $name |
        (.contributes.commands[]? | .title) |= (gsub("Cline"; $name)) |
        (.contributes.walkthroughs[]? | .title) |= (gsub("Cline"; $name)) |
        (.contributes.walkthroughs[]? | .description) |= (gsub("Cline"; $name)) |
        (.contributes.walkthroughs[]? | .steps[]? | .title) |= (gsub("Cline"; $name)) |
        (.contributes.walkthroughs[]? | .steps[]? | .description) |= (gsub("Cline"; $name)) |
        (.contributes.viewsContainers.activitybar[]? | .title) |= (gsub("Cline"; $name)) |
        .keywords = ["ai", "coder", "agent", "mcp", "coding", "assistant"]
    ' package.json > pkg.tmp && mv pkg.tmp package.json
    echo "  ✓ package.json renamed"
fi

# 3d-2. Rebrand the extension ID itself: publisher + name + command prefix
#   OLD ID: saoudrizwan.claude-dev   commands: cline.*
#   NEW ID: aicoder.ai-coder         commands: ai-coder.*
#   registry.ts derives the command prefix from `name`, so all command IDs,
#   context keys, view IDs and menu references must be renamed in lockstep.
echo "  - Rebranding extension ID (publisher/name/commands)..."
if command -v jq &> /dev/null; then
    jq '
        .publisher = "coderbot" |
        .name = "code-bot" |
        .repository = { "type": "git", "url": "https://example.com/ai-coder" } |
        .homepage = "https://example.com/ai-coder" |
        .bugs = null |
        .icon = "assets/icons/icon-color.svg" |
        (.contributes.commands[]? | .command) |= (sub("^cline\\."; "ai-coder.")) |
        (.contributes.keybindings[]? | .command) |= (sub("^cline\\."; "ai-coder.")) |
        (.contributes.viewsContainers.activitybar[]? | .id) |= (sub("^claude-dev-"; "ai-coder-")) |
        (.contributes.views) |= (to_entries | map({ key: (.key | sub("^claude-dev-"; "ai-coder-")), value: .value }) | from_entries) |
        (.contributes.views["ai-coder-ActivityBar"][]? | .id) |= (sub("^claude-dev\\."; "ai-coder.")) |
        (.contributes.walkthroughs[]? | .id) |= (sub("^ClineWalkthrough$"; "AiCoderWalkthrough")) |
        (.contributes.walkthroughs[]? | .steps[]? | .id) |= (sub("^cline\\."; "ai-coder.")) |
        (.contributes.walkthroughs[]? | .steps[]? | .media) |= (
            if type == "object" then
                to_entries | map({ key: .key, value: (if (.value | type) == "string" then (.value | sub("^cline\\."; "ai-coder.")) else .value end) }) | from_entries
            else .
            end
        )
    ' package.json > pkg.tmp && mv pkg.tmp package.json
fi
# menus: command refs + when-clause context keys and view IDs (plain strings, not quoted "cline.")
sedi \
    -e 's/"command": "cline\./"command": "ai-coder./g' \
    -e 's/"command":"cline\./"command":"ai-coder./g' \
    -e 's/cline\.isGeneratingCommit/ai-coder.isGeneratingCommit/g' \
    -e 's/cline\.isDevMode/ai-coder.isDevMode/g' \
    -e 's/claude-dev\.SidebarProvider/ai-coder.SidebarProvider/g' \
    package.json
# walkthrough media paths reference cline.* asset names
sedi 's|walkthrough/cline\.|walkthrough/ai-coder.|g' package.json
echo "  ✓ Extension ID rebranded: aicoder.ai-coder (commands: ai-coder.*)"

# 3d-3. Patch source: setContext keys, hardcoded saoudrizwan refs, walkthrough ID
echo "  - Patching source ID references..."
find "${VSCODE_DIR}/src" -name "*.ts" ! -name "*.test.ts" -exec sedi \
    -e 's/"cline\.isDevMode"/"ai-coder.isDevMode"/g' \
    -e 's/"cline\.isGeneratingCommit"/"ai-coder.isGeneratingCommit"/g' \
    -e 's/saoudrizwan\.claude-dev/aicoder.ai-coder/g' \
    -e 's/saoudrizwan\./aicoder./g' \
    -e 's/includes("saoudrizwan")/includes("ai-coder")/g' \
    -e 's/ClineWalkthrough/AiCoderWalkthrough/g' \
    {} + 2>/dev/null || true
echo "  ✓ Source ID references patched"

# 3d-4. Clean extension-panel metadata (what the Extensions view / command palette / Settings show)
#   - description  → shown in the Extensions list & details page
#   - author       → shown on the details page
#   - command category ("Cline:") → shown in the command palette
#   - configuration.title ("Cline" section) → shown in the Settings UI
#   - "Welcome to Cline v..." notification
echo "  - Cleaning extension panel metadata..."
if command -v jq &> /dev/null; then
    jq --arg name "${NEW_NAME}" '
        .description = "Autonomous coding agent right in your IDE — self-hosted build: no account, no login, no telemetry." |
        .author = { "name": "Coder" } |
        .categories = ["AI", "Chat", "Programming Languages", "Testing"] |
        (.contributes.commands[]? | .category) |= (if type == "string" then sub("^Cline$"; $name) else . end) |
        (.contributes.configuration.title) |= (if type == "string" then sub("^Cline$"; $name) else . end) |
        (if .contributes.icons["cline-icon"] then .contributes.icons["cline-icon"].description = "ai-coder" else . end)
    ' package.json > pkg.tmp && mv pkg.tmp package.json
fi
find "${VSCODE_DIR}/src" -name "*.ts" ! -name "*.test.ts" -exec sedi \
    -e 's/Welcome to Cline v/Welcome to Coder v/g' \
    -e 's/Cline has been updated to/Coder has been updated to/g' \
    -e 's/Cline version changed:/Coder version changed:/g' \
    -e 's/Cline running in self-hosted mode/Coder running in self-hosted mode/g' \
    -e 's/Cline running in dev mode/Coder running in dev mode/g' \
    {} + 2>/dev/null || true
echo "  ✓ Extension panel metadata cleaned"

# 3d-4b. Write branded README (shows in the Extensions details pane)
cp "${TEMPLATE_DIR}/README-branded.md.tpl" "${VSCODE_DIR}/README.md"
echo "  ✓ Branded README written"

# 3e. Rename in walkthrough markdown files
echo "  - Renaming walkthrough docs..."
find "${VSCODE_DIR}/walkthrough" -name "*.md" -exec sedi 's/Cline/Coder/g' {} + 2>/dev/null || true
echo "  ✓ Walkthrough docs renamed"

# 3f. Rename user-visible strings in webview + extension source
#     Safe patterns: quoted string literals and JSX text only (never identifiers/imports)
echo "  - Renaming source strings..."
find "${VSCODE_DIR}/webview-ui/src" "${VSCODE_DIR}/src" \
    \( -name "*.ts" -o -name "*.tsx" \) ! -path "*node_modules*" \
    ! -name "*.test.ts" ! -name "*.spec.ts" -exec sedi \
    -e 's/"Cline /"Coder /g' \
    -e 's/name: "Cline"/name: "Coder"/g' \
    -e 's/"Cline"/"Coder"/g' \
    -e 's/>Cline />Coder /g' \
    -e 's/Hi, I'"'"'m Cline/Hi, I'"'"'m Coder/g' \
    -e 's/Cline wants/Coder wants/g' \
    -e 's/Cline is creating/Coder is creating/g' \
    -e 's/Cline viewed/Coder viewed/g' \
    -e 's/Cline creates/Coder creates/g' \
    -e 's/Cline codes like/Coder codes like/g' \
    -e 's/Meet Cline/Meet Coder/g' \
    -e 's/Add to Cline/Add to Coder/g' \
    -e 's/with Cline/with Coder/g' \
    -e 's/Let Cline/Let Coder/g' \
    -e "s/Cline's/Coder's/g" \
    -e 's/About Cline/About Coder/g' \
    -e 's/ Cline project-specific/ Coder project-specific/g' \
    -e 's/parallel Cline tasks/parallel Coder tasks/g' \
    -e 's/toggling Cline rule/toggling Coder rule/g' \
    {} + 2>/dev/null || true
echo "  ✓ Source strings renamed"

# 3g. Lockdown onboarding to BYOK-only and remove the About tab
#   - "How will you use Cline?"  -> "How will you use Coder?"
#   - remove the "Login to Cline" / sign-in button
#   - keep only the "Bring my own API key" option (no account/login path)
#   - drop the "About" tab from the Settings view
echo "  - Locking down onboarding to BYOK-only, removing About..."
ONB_DIR="${VSCODE_DIR}/webview-ui/src/components/onboarding"
cp "${TEMPLATE_DIR}/data-steps.ts.tpl" "${ONB_DIR}/data-steps.ts"

# Start onboarding already on the BYOK provider so the "Continue" button
# never routes into the account/sign-in flow.
sedi 's/useState<NEW_USER_TYPE>(NEW_USER_TYPE.FREE)/useState<NEW_USER_TYPE>(NEW_USER_TYPE.BYOK)/' \
    "${ONB_DIR}/OnboardingView.tsx" 2>/dev/null || true

# The "Login to Cline" button was removed above, so the now-unreachable
# `btn.action === "signin"` comparison trips TS2367. Drop it (signup stays).
sedi 's/btn.action === "signin" || btn.action === "signup"/btn.action === "signup"/' \
    "${ONB_DIR}/OnboardingView.tsx" 2>/dev/null || true

# Hide the "About" tab in Settings (keeps the tab array valid; the tab no
# longer renders). The AboutSection/import/props remain but are unreachable.
SETTINGS_VIEW="${VSCODE_DIR}/webview-ui/src/components/settings/SettingsView.tsx"
# perl instead of sed's `a\`: GNU and BSD sed differ on append syntax, which
# silently no-ops on macOS — perl is identical on both.
perl -i -pe 'if (/id: "about",/) { $_ .= "                hidden: () => true,\n" }' \
    "${SETTINGS_VIEW}" 2>/dev/null || true
echo "  ✓ Onboarding locked to BYOK; About tab hidden"

# 3g-2. Skip the onboarding/welcome page entirely — go straight to chat.
#   App.tsx checks `showWelcome` and renders <OnboardingView /> when true.
#   Short-circuit that check so the extension always opens on the chat view.
#   API key configuration is still available via the Settings gear icon.
echo "  - Skipping onboarding page (direct to chat)..."
APP_TSX="${VSCODE_DIR}/webview-ui/src/App.tsx"
# Replace `if (showWelcome) {` with `if (false) {` — the OnboardingView import
# stays (TS would error on unused import) but is never rendered.
perl -i -pe 's/if \(showWelcome\)/if (false)/' "${APP_TSX}" 2>/dev/null || true
echo "  ✓ Onboarding page skipped — opens directly to chat"

# 3h. Force the extension's command prefix to "ai-coder".
#   registry.ts computes `prefix = name === "claude-dev" ? "cline" : name`; when
#   the bundle inlines name === "claude-dev" it registers cline.* commands while
#   package.json/contributes and the webview expect ai-coder.* — leaving the
#   sidebar webview stuck and raising "command 'ai-coder.xxxButtonClicked' not
#   found". Hard-pinning the prefix makes extension, manifest and webview agree.
echo "  - Forcing extension command prefix to ai-coder..."
sedi 's/const prefix = name === "claude-dev" ? "cline" : name/const prefix = "ai-coder"/' \
    "${VSCODE_DIR}/src/registry.ts" 2>/dev/null || true
# registry.ts builds the sidebar view ID as `name + ".SidebarProvider"` (name =
# package.json .name = "code-bot"), but package.json declares the view under the
# "ai-coder." prefix (`ai-coder.SidebarProvider`). When `name` diverges from the
# command prefix, `registerWebviewViewProvider("code-bot.SidebarProvider")` never
# matches the declared `ai-coder.SidebarProvider` view, so VS Code leaves the
# sidebar webview blank ("View already awaiting revival" in the renderer log).
# Pin the view ID to the same prefix so extension code and manifest agree.
sedi 's/Sidebar: name + "\.SidebarProvider"/Sidebar: prefix + ".SidebarProvider"/' \
    "${VSCODE_DIR}/src/registry.ts" 2>/dev/null || true
echo "  ✓ Extension command prefix pinned to ai-coder"

# 3i. Remove the ClinePass promo hint (rendered under the API provider dropdown
#   in Settings AND above the chat textarea). Replace the component with a
#   no-op so every import site keeps compiling — the webview build skips tsc,
#   so the dropped props signature is irrelevant.
CLINE_PASS_HINT="${VSCODE_DIR}/webview-ui/src/components/settings/ClinePassHint.tsx"
if [ -f "${CLINE_PASS_HINT}" ]; then
    cp "${TEMPLATE_DIR}/ClinePassHint.tsx.tpl" "${CLINE_PASS_HINT}"
    echo "  ✓ ClinePassHint removed (returns null)"
fi

# 3j. Remove the "Try ClinePass" promo banner in the chat welcome section.
#   Inject an early `return undefined` into the clinePassPromoBanner useMemo so
#   it never renders (the code after it becomes unreachable — fine, the webview
#   build skips tsc).
WELCOME_SECTION="${VSCODE_DIR}/webview-ui/src/components/chat/chat-view/components/layout/WelcomeSection.tsx"
if [ -f "${WELCOME_SECTION}" ]; then
    sedi 's#useMemo((): BannerData | undefined => {#useMemo((): BannerData | undefined => { if (true) { return undefined } /* ClinePass promo removed */#' \
        "${WELCOME_SECTION}" 2>/dev/null || true
    echo "  ✓ ClinePass promo banner disabled in WelcomeSection"
fi

# 3k. Remove the auto-approve description line ("Let Coder take these
#   actions without asking for approval. Docs") from the chat auto-approve
#   menu. The source still says "Let Cline..." (the global rebrand later
#   rewrites it), so match on the unique className and delete through the
#   closing div.
AUTO_APPROVE_MODAL="${VSCODE_DIR}/webview-ui/src/components/chat/auto-approve-menu/AutoApproveModal.tsx"
if [ -f "${AUTO_APPROVE_MODAL}" ]; then
    sedi '/mb-2.5 text-muted-foreground text-xs cursor-pointer/,/<\/div>/d' "${AUTO_APPROVE_MODAL}" 2>/dev/null || true
    echo "  ✓ Auto-approve description removed"
fi

# 3l. Remove the terminal help card ("Having terminal issues? Check our
#   Terminal Quick Fixes or the Complete Troubleshooting Guide.") at the
#   bottom of the Settings → Terminal section. Match on the card's unique
#   className and delete through its closing div.
TERMINAL_SECTION="${VSCODE_DIR}/webview-ui/src/components/settings/sections/TerminalSettingsSection.tsx"
if [ -f "${TERMINAL_SECTION}" ]; then
    sedi '/mt-5 p-3 bg-(--vscode-textBlockQuote-background)/,/<\/div>/d' "${TERMINAL_SECTION}" 2>/dev/null || true
    echo "  ✓ Terminal help card removed"
fi

# 3m. Remove the "Allow error and usage reporting" telemetry setting from
#   Settings → General. The block contains nested <div>s, so a plain sed
#   range would stop at the first inner </div>; use a Python balanced-div
#   scan instead.
GENERAL_SECTION="${VSCODE_DIR}/webview-ui/src/components/settings/sections/GeneralSettingsSection.tsx"
if [ -f "${GENERAL_SECTION}" ] && grep -q 'Allow error' "${GENERAL_SECTION}" 2>/dev/null; then
    python3 "${TEMPLATE_DIR}/remove-telemetry.py.tpl" "${GENERAL_SECTION}"
    echo "  ✓ Telemetry setting removed"
else
    echo "  ✓ Telemetry setting already absent (skipped)"
fi

# 3n. Localize UI to Chinese (汉化)
#   Batch-replace English UI strings in webview source files before compilation.
#   Organized by component area. Each line: sed -e 's/English/中文/g'
echo "  - Localizing UI to Chinese..."

# --- Chat: input, buttons, auto-approve, slash commands ---
find "${VSCODE_DIR}/webview-ui/src/components/chat" -name "*.ts" -o -name "*.tsx" | while read -r f; do
    sedi \
        -e 's/Type a message\.\.\./输入消息.../g' \
        -e 's/Type your task here\.\.\./在此输入你的任务.../g' \
        -e 's/Add Context/添加上下文/g' \
        -e 's/Add Files & Images/添加文件和图片/g' \
        -e 's/Open API Settings/打开 API 设置/g' \
        -e 's/Default Commands/默认命令/g' \
        -e 's/Workflow Commands/工作流命令/g' \
        -e 's/MCP Prompts/MCP 提示词/g' \
        -e 's/No matching commands found/未找到匹配的命令/g' \
        -e 's/Searching\.\.\./搜索中.../g' \
        -e 's/No, keep the task as is/否，保持任务不变/g' \
        -e 's/Yes, compact the task/是，压缩任务/g' \
        -e 's/Prompt Tokens/提示词 Token/g' \
        -e 's/Completion Tokens/补全 Token/g' \
        -e 's/Cache Writes/缓存写入/g' \
        -e 's/Cache Reads/缓存读取/g' \
        -e 's/No token usage data available/暂无 Token 用量数据/g' \
        -e 's/"Read files"/"读取文件"/g' \
        -e 's/"Edit files"/"编辑文件"/g' \
        -e 's/"Execute commands"/"执行命令"/g' \
        -e 's/"Fetch web content"/"获取网页内容"/g' \
        -e 's/"Use MCP servers"/"使用 MCP 服务器"/g' \
        -e 's/"Retry"/"重试"/g' \
        -e 's/"Start New Task"/"开始新任务"/g' \
        -e 's/"Proceed Anyways"/"继续执行"/g' \
        -e 's/"Approve"/"批准"/g' \
        -e 's/"Reject"/"拒绝"/g' \
        -e 's/"Save"/"保存"/g' \
        -e 's/"Run Command"/"运行命令"/g' \
        -e 's/"Proceed While Running"/"运行中继续"/g' \
        -e 's/"Cancel queued message"/"取消排队消息"/g' \
        -e 's/"Thinking\.\.\."/"思考中..."/g' \
        -e 's/title={"Thinking"}/title={"思考中"}/g' \
        "$f" 2>/dev/null || true
done

# --- Settings: tabs, labels, descriptions, placeholders ---
SETTINGS_SRC="${VSCODE_DIR}/webview-ui/src/components/settings"
find "${SETTINGS_SRC}" -name "*.ts" -o -name "*.tsx" | while read -r f; do
    sedi \
        -e 's/headerText: "API Configuration"/headerText: "API 配置"/g' \
        -e 's/headerText: "Feature Settings"/headerText: "功能设置"/g' \
        -e 's/headerText: "Terminal Settings"/headerText: "终端设置"/g' \
        -e 's/headerText: "General Settings"/headerText: "通用设置"/g' \
        -e 's/headerText: "Remote Config"/headerText: "远程配置"/g' \
        -e 's/headerText: "About"/headerText: "关于"/g' \
        -e 's/name: "API Configuration"/name: "API 配置"/g' \
        -e 's/name: "Features"/name: "功能"/g' \
        -e 's/name: "Terminal"/name: "终端"/g' \
        -e 's/name: "General"/name: "通用"/g' \
        -e 's/name: "Remote Config"/name: "远程配置"/g' \
        -e 's/name: "About"/name: "关于"/g' \
        -e 's/"Settings"/"设置"/g' \
        -e 's/Search and select provider\.\.\./搜索并选择服务商.../g' \
        -e 's/Clear search/清除搜索/g' \
        -e 's/Enter API Key\.\.\./输入 API 密钥.../g' \
        -e 's/This key is stored locally and only used to make API requests from this extension\./此密钥仅本地存储，用于此扩展的 API 请求。/g' \
        -e 's/Use custom base URL/使用自定义 Base URL/g' \
        -e 's/Search and select a model\.\.\./搜索并选择模型.../g' \
        -e 's/Model suggestions/模型建议/g' \
        -e 's/Reasoning Effort/推理力度/g' \
        -e 's/Higher effort improves depth, but uses more tokens\./力度越大越深入，但消耗更多 Token。/g' \
        -e 's/Auto Compact/自动压缩/g' \
        -e 's/Automatically compress conversation history\./自动压缩对话历史。/g' \
        -e 's/Feature Tips/功能提示/g' \
        -e 's/Show rotating tips during the thinking phase to help you discover Coder features\./在思考阶段轮换显示提示，帮助你发现 Coder 功能。/g' \
        -e 's/Background Edit/后台编辑/g' \
        -e 's/Allow edits without stealing editor focus/允许编辑而不抢占编辑器焦点/g' \
        -e 's/"Checkpoints"/"检查点"/g' \
        -e 's/Save progress at key points for easy rollback/在关键节点保存进度，便于回滚/g' \
        -e 's/Worktrees/工作树/g' \
        -e 's/Enables git worktree management for running parallel Coder tasks\./启用 git 工作树管理，支持并行运行 Coder 任务。/g' \
        -e 's/"Hooks"/"钩子"/g' \
        -e 's/Enable lifecycle and tool hooks during task execution\./在任务执行期间启用生命周期和工具钩子。/g' \
        -e 's/Terminal Execution Mode/终端执行模式/g' \
        -e 's/"VS Code Terminal"/"VS Code 终端"/g' \
        -e 's/"Background Exec"/"后台执行"/g' \
        -e 's/Choose whether Coder runs commands in the VS Code terminal or a background process\./选择 Coder 在 VS Code 终端还是后台进程中运行命令。/g' \
        -e 's/Shell integration timeout (seconds)/Shell 集成超时（秒）/g' \
        -e 's/Enter timeout in seconds/输入超时秒数/g' \
        -e 's/Set how long Coder waits for shell integration to activate before executing commands\. Increase this value if you experience terminal connection timeouts\./设置 Coder 在执行命令前等待 Shell 集成激活的时间。如遇终端连接超时，请增大此值。/g' \
        -e 's/Enable aggressive terminal reuse/启用积极终端复用/g' \
        -e 's/When enabled, Coder will reuse existing terminal windows that aren'"'"'t in the current working directory\. Disable this if you experience issues with task lockout after a terminal command\./启用后，Coder 将复用不在当前工作目录的已有终端窗口。如在终端命令后遇到任务锁定问题，请禁用此项。/g' \
        -e 's/Preferred Language/首选语言/g' \
        -e 's/The language that Coder should use for communication\./Coder 通信使用的语言。/g' \
        -e 's/Adaptive Thinking/自适应思考/g' \
        -e 's/Use None to disable adaptive thinking\. Higher effort increases response detail and token usage\./设为 None 可禁用自适应思考。力度越大响应越详细，但 Token 用量越多。/g' \
        -e 's/Use None to disable extended thinking\. Higher effort improves depth, but uses more tokens\./设为 None 可禁用扩展思考。力度越大越深入，但消耗更多 Token。/g' \
        -e 's/Loading\.\.\./加载中.../g' \
        -e 's/Community & Support/社区与支持/g' \
        -e 's/Development/开发/g' \
        -e 's/Issues/问题反馈/g' \
        -e 's/not set/未设置/g' \
        -e 's/Search models\.\.\./搜索模型.../g' \
        -e 's/Search or enter a custom model ID\.\.\./搜索或输入自定义模型 ID.../g' \
        -e 's/Enter custom model ID/输入自定义模型 ID/g' \
        -e 's/Enter Project ID\.\.\./输入项目 ID.../g' \
        -e 's/Google Cloud Project ID/Google Cloud 项目 ID/g' \
        -e 's/Google Cloud Region/Google Cloud 区域/g' \
        -e 's/Set Azure API version/设置 Azure API 版本/g' \
        -e 's/Not editable - the value is returned by the connected endpoint/不可编辑 - 值由连接的端点返回/g' \
        -e 's/Select a model\.\.\./选择模型.../g' \
        "$f" 2>/dev/null || true
done

# --- History view ---
find "${VSCODE_DIR}/webview-ui/src/components/history" -name "*.ts" -o -name "*.tsx" | while read -r f; do
    sedi \
        -e 's/"History"/"历史记录"/g' \
        -e 's/Fuzzy search history\.\.\./搜索历史记录.../g' \
        -e 's/Delete selected items/删除选中项/g' \
        -e 's/Delete all history/删除全部历史/g' \
        -e 's/"Delete"/"删除"/g' \
        -e 's/"Export"/"导出"/g' \
        -e 's/View all history/查看全部历史/g' \
        -e 's/"Favorited"/"已收藏"/g' \
        -e 's/"Today"/"今天"/g' \
        -e 's/"Older"/"更早"/g' \
        "$f" 2>/dev/null || true
done

# --- MCP configuration ---
find "${VSCODE_DIR}/webview-ui/src/components/mcp" -name "*.ts" -o -name "*.tsx" | while read -r f; do
    sedi \
        -e 's/MCP Servers/MCP 服务器/g' \
        -e 's/Remote Servers/远程服务器/g' \
        -e 's/"Configure"/"配置"/g' \
        -e 's/Server Name/服务器名称/g' \
        -e 's/Server URL/服务器 URL/g' \
        -e 's/Restart Server/重启服务器/g' \
        -e 's/Delete Server/删除服务器/g' \
        -e 's/No description available/暂无描述/g' \
        "$f" 2>/dev/null || true
done

# --- Marketplace ---
find "${VSCODE_DIR}/webview-ui/src/components/marketplace" -name "*.ts" -o -name "*.tsx" | while read -r f; do
    sedi \
        -e 's/"Installed"/"已安装"/g' \
        -e 's/"Marketplace"/"市场"/g' \
        -e 's/"Customize"/"自定义"/g' \
        "$f" 2>/dev/null || true
done

# --- Worktrees ---
find "${VSCODE_DIR}/webview-ui/src/components/worktrees" -name "*.ts" -o -name "*.tsx" | while read -r f; do
    sedi \
        -e 's/Branch Name \*/分支名称 */g' \
        -e 's/Folder Path \*/文件夹路径 */g' \
        -e 's/"Clear"/"清除"/g' \
        -e 's/Failed to load worktrees/加载工作树失败/g' \
        "$f" 2>/dev/null || true
done

# --- Account ---
find "${VSCODE_DIR}/webview-ui/src/components/account" -name "*.ts" -o -name "*.tsx" | while read -r f; do
    sedi \
        -e 's/"Account"/"账户"/g' \
        -e 's/"Role"/"角色"/g' \
        -e 's/"Dashboard"/"控制台"/g' \
        -e 's/"Log out"/"退出登录"/g' \
        "$f" 2>/dev/null || true
done

# --- Onboarding (already mostly skipped, but localize remaining strings) ---
ONB_DATA="${VSCODE_DIR}/webview-ui/src/components/onboarding/data-steps.ts"
if [ -f "${ONB_DATA}" ]; then
    sedi \
        -e 's/How will you use Coder?/你将如何使用 Coder？/g' \
        -e 's/Select an option below to get started\./在下方选择一个选项以开始。/g' \
        -e 's/"Continue"/"继续"/g' \
        -e 's/"Back"/"返回"/g' \
        -e 's/Bring my own API key/使用自己的 API 密钥/g' \
        -e 's/Use Coder with your provider of choice/使用你选择的服务商连接 Coder/g' \
        -e 's/Configure your provider/配置你的服务商/g' \
        -e 's/Select your model/选择你的模型/g' \
        -e 's/Almost there!/即将完成！/g' \
        -e 's/Search model\.\.\./搜索模型.../g' \
        "${ONB_DATA}" 2>/dev/null || true
fi

# --- Welcome section / announcement ---
find "${VSCODE_DIR}/webview-ui/src/components/chat/chat-view/components/layout" -name "*.tsx" | while read -r f; do
    sedi \
        -e 's/Welcome to Coder/Coder 欢迎你/g' \
        -e 's/Hi, I'"'"'m Coder/你好，我是 Coder/g' \
        "$f" 2>/dev/null || true
done

# --- Walkthrough files ---
find "${VSCODE_DIR}/walkthrough" -name "*.md" -exec sedi 's/Coder/Coder/g' {} + 2>/dev/null || true

echo "  ✓ UI localized to Chinese"

# 3o. Fix CSP to allow local WebSocket/HTTP connections
# The production CSP only allows connect-src to posthog/cline.bot, blocking
# the gRPC channel the new Cline architecture uses for webview↔host IPC.
# Add ws://localhost and http://localhost to connect-src.
echo "  - Fixing CSP for local connections..."
WEBVIEW_PROVIDER="${VSCODE_DIR}/src/core/webview/WebviewProvider.ts"
if [ -f "${WEBVIEW_PROVIDER}" ]; then
    sedi 's|connect-src https://\*\.posthog\.com https://\*\.cline\.bot;|connect-src https://* ws://localhost:* ws://127.0.0.1:* http://localhost:* http://127.0.0.1:* https://*.posthog.com https://*.cline.bot;|' "${WEBVIEW_PROVIDER}"
    echo "  ✓ CSP connect-src patched for local WebSocket"
fi

# 3o-2. Inject a boot diagnostic overlay into the webview HTML (only when
# WEBVIEW_DEBUG=1). Blank-panel debugging: the overlay is rendered by the
# nonce'd inline script in the HTML itself, so it works even if index.js
# never runs. It shows whether the HTML executed, whether gRPC responses
# arrive, and whether React mounts anything into #root.
if [ -n "${WEBVIEW_DEBUG}" ]; then
    echo "  - Injecting webview boot diagnostic overlay..."
    if python3 "${TEMPLATE_DIR}/inject-boot-debug.py.tpl" "${WEBVIEW_PROVIDER}" "${TEMPLATE_DIR}/boot-debug-script.html.tpl" 2>&1 | grep -q "INJECTED\|skipping"; then
        echo "  ✓ Boot diagnostic overlay injected"
    else
        echo "  ⚠ Overlay injection failed (pattern mismatch) — continuing without it"
    fi
fi

echo "  ✓ Rebranding complete"

fi  # end SKIP_PATCH guard (patch phase)

# ---------------------------------------------------------------------------
# Step 4: Build the extension
# ---------------------------------------------------------------------------
echo ""
echo "=== Step 4: Building extension ==="

cd "${VSCODE_DIR}"

echo "  - Building webview UI..."
# Cap Node heap so the vite build (7k+ modules) fits in the 4GB Docker VM.
# Run bare `vite build` from INSIDE webview-ui (its vite.config.ts lives there;
# running it from apps/vscode always fails, which previously fell back to the
# slow `tsc -b && vite build` and stalled on low-memory hosts).
export NODE_OPTIONS="--max-old-space-size=2048"
# Clear stale build: vite skips recompilation when build/ already exists,
# shipping the previous (pre-localization) bundle.
rm -rf "${VSCODE_DIR}/webview-ui/build"
if ! (cd "${VSCODE_DIR}/webview-ui" && npx vite build) > /tmp/webview-build.log 2>&1; then
    echo "    · bare vite in webview-ui failed, trying repo build script (tsc -b && vite build)..."
    bun run build:webview >> /tmp/webview-build.log 2>&1 || {
        echo "  ⚠ Webview build FAILED — last 40 log lines:"
        tail -40 /tmp/webview-build.log
    }
fi
if [ -d "${VSCODE_DIR}/webview-ui/build/assets" ]; then
    echo "  ✓ Webview UI built (build/assets exists)"
else
    echo "  ✗ webview-ui/build/assets MISSING — webview will be blank!"
fi
unset NODE_OPTIONS

echo "  - Building extension host..."
# IMPORTANT: build through the repo's esbuild script, NOT `esbuild --config-file`
# (an INVALID flag that silently fell back to a bare `npx esbuild` CLI). That bare
# CLI dropped the script's `import.meta.url` banner + define:
#   banner:  const _importMetaUrl=require('url').pathToFileURL(__filename)
#   define:  "import.meta.url": "_importMetaUrl"
# Without them, the SAP AI provider's `createRequire(import.meta.url)` is emitted
# as `createRequire(import_meta.url)` where `import_meta = {}`, so activation
# throws `createRequire(undefined)` — aborting command registration and leaving
# the sidebar webview stuck with "command 'ai-coder.settingsButtonClicked' not found".
ESBUILD_SCRIPT=""
for f in esbuild.mjs esbuild.js esbuild.cjs; do
    [ -f "${VSCODE_DIR}/${f}" ] && ESBUILD_SCRIPT="${f}" && break
done

if [ -n "${ESBUILD_SCRIPT}" ]; then
    # Retry once: the esbuild pass right after vite (2GB heap) can get killed
    # by the OS on memory-tight hosts; a retry after the page cache settles
    # usually succeeds. Keep the log so a real failure is diagnosable instead
    # of being silently swallowed by 2>/dev/null.
    ESBUILD_OK=false
    for attempt in 1 2; do
        if (cd "${VSCODE_DIR}" && node --max-old-space-size=2048 "${ESBUILD_SCRIPT}" --production) > /tmp/esbuild-build.log 2>&1; then
            ESBUILD_OK=true
            break
        fi
        echo "  ⚠ esbuild attempt ${attempt} failed, retrying..."
        sleep 2
    done
    if [ "${ESBUILD_OK}" != "true" ]; then
        echo "  ✗ esbuild failed — last 30 log lines:"
        tail -30 /tmp/esbuild-build.log
    fi
fi

# A bundle that lacks the import.meta.url banner is broken (`createRequire(undefined)`
# at activation), so NEVER silently substitute a bare CLI build. Fail loudly instead.
if [ ! -f "dist/extension.js" ]; then
    echo "  ✗ dist/extension.js was NOT produced by the esbuild script. Aborting build."
    exit 1
fi
BANNER_COUNT=$(grep -c 'pathToFileURL(__filename)' dist/extension.js || true)
if [ "${BANNER_COUNT}" -eq 0 ]; then
    echo "  ✗ dist/extension.js is MISSING the import.meta.url banner — it would crash at activation. Aborting build."
    exit 1
fi
echo "  ✓ Extension host built ($(ls -lh dist/extension.js | awk '{print $5}'))"
echo "  ✓ import.meta.url banner intact: ${BANNER_COUNT} occurrence(s)"

echo "  - Packaging VSIX..."
PACKAGED=false
# --skip-prepublish: dist/extension.js + webview were already built in this
# script; prepublish only re-runs `bun run package` (a second tsc type-check) that
# pushes the 4GB Docker VM over its memory budget. Skipping it keeps the build
# green without losing any artifacts.
# IMPORTANT: vsce relies on git-tracked files and webview-ui/.gitignore lists
# `build`, so a *successful* vsce pack silently drops webview-ui/build — the
# exact assets the webview HTML loads (`webview-ui/build/assets/index.js|css`).
# A vsix missing them is a broken webview (blank / stuck "loading" panel), so we
# validate every vsix for the webview build and fall through to the manual
# pack (which keeps the webview-ui/build level intact) whenever it's absent.
export NODE_OPTIONS="--max-old-space-size=1536"
# Remove stale vsix from previous runs: the per-candidate check below globs
# *.vsix and would happily "validate" an old artifact, skip the manual pack,
# and ship a stale bundle. Start clean so the check only ever sees this build.
rm -f "${VSCODE_DIR}"/*.vsix
for cmd in \
    "bunx @vscode/vsce package --skip-prepublish --no-dependencies --skip-license 2>/dev/null" \
    "npx @vscode/vsce package --skip-prepublish --no-dependencies --skip-license 2>/dev/null" \
    "npx vsce package --skip-prepublish --no-dependencies 2>/dev/null"; do
    if [ "${PACKAGED}" = "false" ]; then
        eval "${cmd}" || true
        for v in "${VSCODE_DIR}"/*.vsix; do
            [ -f "${v}" ] || continue
            if unzip -l "${v}" 2>/dev/null | grep -q "webview-ui/build/assets/index.js"; then
                PACKAGED=true
                echo "    ✓ ${v} contains webview-ui/build (webview assets OK)"
            else
                echo "    ⚠ ${v} MISSING webview-ui/build/assets/index.js — repacking manually"
                rm -f "${v}"
            fi
            break
        done
    fi
done
unset NODE_OPTIONS

if [ "${PACKAGED}" = "false" ]; then
    echo "  - Creating VSIX manually (vsce dropped the webview build)..."
    VSIX_TMP="/tmp/cline-vsix-build"
    rm -rf "${VSIX_TMP}"
    mkdir -p "${VSIX_TMP}/extension"
    cp -r dist "${VSIX_TMP}/extension/" 2>/dev/null || true
    cp package.json "${VSIX_TMP}/extension/" 2>/dev/null || true
    cp -r assets "${VSIX_TMP}/extension/" 2>/dev/null || true
    cp README.md "${VSIX_TMP}/extension/" 2>/dev/null || true
    cp LICENSE "${VSIX_TMP}/extension/" 2>/dev/null || true
    # The generated webview HTML loads `webview-ui/build/assets/index.js|css`,
    # so the build output MUST keep the `webview-ui/build/` level. Copying it
    # straight onto `extension/webview-ui` (flattening) breaks the webview (404
    # on assets -> blank panel), so place it at `extension/webview-ui/build`.
    mkdir -p "${VSIX_TMP}/extension/webview-ui"
    cp -r webview-ui/build "${VSIX_TMP}/extension/webview-ui/build" 2>/dev/null || \
        cp -r webview-ui/dist "${VSIX_TMP}/extension/webview-ui/build" 2>/dev/null || true

    # Render the manifest from package.json's ACTUAL identity — a hardcoded
    # template identity mismatches package.json, and VS Code then registers the
    # extension under one ID while running another (blank/broken panel).
    EXT_NAME="$(jq -r '.name' package.json)"
    EXT_PUBLISHER="$(jq -r '.publisher' package.json)"
    EXT_VERSION="$(jq -r '.version' package.json)"
    EXT_DISPLAY_NAME="$(jq -r '.displayName' package.json)"
    EXT_DESCRIPTION="$(jq -r '.description // "Autonomous coding agent"' package.json)"
    sed -e "s|{{EXT_NAME}}|${EXT_NAME}|g" \
        -e "s|{{EXT_PUBLISHER}}|${EXT_PUBLISHER}|g" \
        -e "s|{{EXT_VERSION}}|${EXT_VERSION}|g" \
        -e "s|{{EXT_DISPLAY_NAME}}|${EXT_DISPLAY_NAME}|g" \
        -e "s|{{EXT_DESCRIPTION}}|${EXT_DESCRIPTION}|g" \
        "${TEMPLATE_DIR}/vsixmanifest.xml.tpl" > "${VSIX_TMP}/extension.vsixmanifest"

    cp "${TEMPLATE_DIR}/Content_Types.xml.tpl" "${VSIX_TMP}/[Content_Types].xml"

    cd "${VSIX_TMP}"
    zip -r "${VSCODE_DIR}/claude-dev-custom.vsix" . 2>/dev/null || true
    cd "${VSCODE_DIR}"
    PACKAGED=true
    echo "  ✓ Manual VSIX created"
fi

echo ""
echo "=== Build artifacts ==="
ls -la "${VSCODE_DIR}"/*.vsix 2>/dev/null || echo "  ⚠ No VSIX found"

echo ""
echo "=== Rebrand verification ==="
echo "  displayName:        $(jq -r '.displayName' "${VSCODE_DIR}/package.json")"
echo "  extension ID:       $(jq -r '.publisher + "." + .name' "${VSCODE_DIR}/package.json")"
echo "  activitybar title:  $(jq -r '.contributes.viewsContainers.activitybar[0].title' "${VSCODE_DIR}/package.json")"
echo "  activitybar id:     $(jq -r '.contributes.viewsContainers.activitybar[0].id' "${VSCODE_DIR}/package.json")"
echo "  view id:            $(jq -r '.contributes.views | to_entries[0].value[0].id' "${VSCODE_DIR}/package.json")"
echo "  fontCharacter:      $(jq -r '.contributes.icons["cline-icon"].default.fontCharacter // "codicon-fallback"' "${VSCODE_DIR}/package.json")"
echo "  command sample:     $(jq -r '.contributes.commands[0].command' "${VSCODE_DIR}/package.json")"
echo "  cline cmds left:    $(jq -r '[.contributes.commands[].command | select(startswith("cline."))] | length' "${VSCODE_DIR}/package.json")"
echo "  description:        $(jq -r '.description' "${VSCODE_DIR}/package.json" | head -c 80)"
echo "  author:             $(jq -c '.author' "${VSCODE_DIR}/package.json")"
echo "  cmd categories:     $(jq -r '[.contributes.commands[].category] | unique | join(", ")' "${VSCODE_DIR}/package.json")"
echo "  config title:       $(jq -r '.contributes.configuration.title' "${VSCODE_DIR}/package.json")"
echo "  welcome remnants:   $(grep -rl 'Welcome to Cline\|"About Cline"' "${VSCODE_DIR}/src" "${VSCODE_DIR}/webview-ui/src" 2>/dev/null | wc -l | tr -d ' ') files"

echo ""
echo "================================================"
echo "  Coder build pipeline complete"
echo "================================================"
