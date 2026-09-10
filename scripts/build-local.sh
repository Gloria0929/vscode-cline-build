#!/bin/bash
set -e

# =============================================================================
# build-local.sh — Build the Coder VSIX locally (macOS), no Docker needed.
#
# Two modes:
#
#   bash scripts/build-local.sh            Pipeline mode (default):
#                                          clone cline → apply ALL modifications
#                                          (modify-cline.sh steps 2-3) → build → VSIX.
#                                          The source tree is reset to upstream
#                                          first, so any manual edits are wiped.
#
#   bash scripts/build-local.sh --source   Source-edit mode:
#                                          build from the ALREADY-patched tree at
#                                          .build/cline WITHOUT cloning or re-patching.
#                                          Edit .build/cline/apps/vscode/... by hand,
#                                          then run this to rebuild in ~2-4 min.
#
# Typical source-edit workflow:
#   1. bash scripts/build-local.sh                  (once: creates patched tree)
#   2. cd .build/cline && git checkout -b my-edits  (protect edits from resets)
#   3. edit files, e.g. webview-ui/src/...          (changes live in the tree)
#   4. bash scripts/build-local.sh --source         (fast incremental build)
#   5. install dist/coder-bot-4.1.17.vsix
#
# Prerequisites (check with `which`):
#   node, bun, git, python3, zip  (rsvg-convert optional)
#
# Output: dist/coder-bot-4.1.17.vsix
# =============================================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SOURCE_MODE=0
if [ "${1}" = "--source" ] || [ "${1}" = "-s" ]; then
    SOURCE_MODE=1
fi

# Working tree location. Default /tmp/aicoder-local-build (survives across
# builds; cleaned only on reboot). Set BUILD_WORK_DIR to relocate, e.g.:
#   BUILD_WORK_DIR=~/projects/cline-src bash scripts/build-local.sh
WORK_DIR="${BUILD_WORK_DIR:-/tmp/aicoder-local-build}"
CLONE_DIR="${WORK_DIR}/cline"
OUT_DIR="${OUT_DIR:-${ROOT_DIR}/dist}"
OUT_VSIX="${OUT_DIR}/coder-bot-4.1.17.vsix"

MODE_LABEL="pipeline (clone + patch + build)"
if [ "${SOURCE_MODE}" = "1" ]; then
    MODE_LABEL="source-edit (build only)"
fi

mkdir -p "${WORK_DIR}" "${OUT_DIR}"

echo ""
echo "╔═════════════════════════════════════════════════════╗"
echo "║  Local Coder VSIX build (no Docker)              ║"
echo "╚═════════════════════════════════════════════════════╝"
echo "  mode     : ${MODE_LABEL}"
echo "  work dir : ${WORK_DIR}"
echo "  output   : ${OUT_VSIX}"
echo ""

if [ "${SOURCE_MODE}" = "1" ]; then
    # ------------------------------------------------------------------
    # Source-edit mode: the patched tree must already exist.
    # ------------------------------------------------------------------
    echo "=== 1/3 Verifying source tree ==="
    if [ ! -f "${CLONE_DIR}/apps/vscode/package.json" ]; then
        echo "  ✗ Patched source tree not found at:"
        echo "      ${CLONE_DIR}"
        echo "    Run the pipeline once first to create it:"
        echo "      bash scripts/build-local.sh"
        exit 1
    fi
    PUB="$(python3 -c "import json;print(json.load(open('${CLONE_DIR}/apps/vscode/package.json'))['publisher'])" 2>/dev/null || echo "?")"
    if [ "${PUB}" = "saoudrizwan" ] || [ "${PUB}" = "?" ]; then
        echo "  ✗ Source tree is UNPATCHED (publisher=${PUB})."
        echo "    Run the pipeline once first: bash scripts/build-local.sh"
        exit 1
    fi
    echo "  ✓ Patched source tree found (publisher=${PUB})"

    echo "=== 2/3 Building (patch steps skipped) ==="
    export MODIFY_CLINE_LOCAL=1
    export CLONE_DIR="${CLONE_DIR}"
    export TEMPLATE_DIR="${ROOT_DIR}/build/templates"
    export SKIP_PATCH=1
    bash "${ROOT_DIR}/build/modify-cline.sh"
else
    # ------------------------------------------------------------------
    # Pipeline mode: reset upstream tree, then apply every modification.
    # ------------------------------------------------------------------
    echo "=== 1/3 Cloning Cline source ==="
    if [ -d "${CLONE_DIR}/.git" ]; then
        if [ -n "$(cd "${CLONE_DIR}" && git status --porcelain 2>/dev/null | head -1)" ]; then
            echo "  ⚠ Source tree has uncommitted edits — pipeline mode will DISCARD them"
            echo "    (git reset --hard origin/main)."
            echo "    To keep your edits: commit them on a branch, or use --source mode."
            echo "    Continuing in 10s ... (Ctrl+C to abort)"
            sleep 10
        fi
        echo "  - repo exists, refreshing (fast-forward only)..."
        (cd "${CLONE_DIR}" && git fetch origin main --depth 1 && git reset --hard origin/main) || true
    else
        git clone --depth 1 --branch main https://github.com/cline/cline.git "${CLONE_DIR}"
    fi

    echo "=== 2/3 Running modify-cline.sh (local mode) ==="
    export MODIFY_CLINE_LOCAL=1
    export CLONE_DIR="${CLONE_DIR}"
    # Point the icon paths at the repo assets (inside Docker the Dockerfile copies
    # them to /tmp/custom-icon*.svg first).
    export CUSTOM_SVG="${ROOT_DIR}/assets/custom-icon.svg"
    export CUSTOM_MONO="${ROOT_DIR}/assets/custom-icon-mono.svg"
    # Same for the template files that replace heredocs.
    export TEMPLATE_DIR="${ROOT_DIR}/build/templates"
    bash "${ROOT_DIR}/build/modify-cline.sh"
fi

echo "=== 3/3 Collecting VSIX ==="
SRC_VSIX="$(ls -t "${CLONE_DIR}"/apps/vscode/*.vsix 2>/dev/null | head -1)"
if [ -z "${SRC_VSIX}" ]; then
    echo "  ✗ No VSIX produced. Check the modify-cline.sh output above."
    exit 1
fi
cp "${SRC_VSIX}" "${OUT_VSIX}"
echo "  ✓ Copied ${SRC_VSIX}"
echo "  ✓ Done → ${OUT_VSIX}"
ls -lh "${OUT_VSIX}"

echo ""
echo "  Source tree (edit here): ${CLONE_DIR}"
echo "  Rebuild after edits    : bash scripts/build-local.sh --source"
