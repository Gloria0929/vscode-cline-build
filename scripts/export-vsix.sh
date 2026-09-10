#!/bin/bash
# export-vsix.sh — 从运行中的容器导出 AI Coder 扩展为独立 VSIX 插件包
# 用法: ./scripts/export-vsix.sh [容器名] [输出路径]
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONTAINER="${1:-vscode-cline}"
DEFAULT_OUT="${ROOT_DIR}/ai-coder-4.1.17.vsix"
OUT="${2:-${DEFAULT_OUT}}"

echo "==> 从容器 ${CONTAINER} 导出扩展..."
EXT=$(docker exec "${CONTAINER}" sh -c 'ls -d /config/extensions/coderbot.code-bot* 2>/dev/null | head -1')
if [ -z "${EXT}" ]; then
    echo "✗ 容器内未找到 coderbot.code-bot 扩展" >&2
    exit 1
fi
echo "    源目录: ${EXT}"

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT

docker cp "${CONTAINER}:${EXT}" "${TMP}/extension"

# ---- VSIX 清单（vsix 本质是 zip，需要这两个清单文件才能被 VS Code 识别）----
cat > "${TMP}/extension.vsixmanifest" << 'MANIFEST'
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011" xmlns:d="http://schemas.microsoft.com/developer/vsx-schema-design/2011">
  <Metadata>
    <Identity Language="en-US" Id="ai-coder" Version="4.1.17" Publisher="aicoder" />
    <DisplayName>AI Coder</DisplayName>
    <Description>Your AI pair programmer in VS Code. Rebranded from Cline.</Description>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Code" />
  </Installation>
  <Dependencies />
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" />
  </Assets>
</PackageManifest>
MANIFEST

cat > "${TMP}/[Content_Types].xml" << 'CONTENT_TYPES'
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="vsixmanifest" ContentType="application/vnd.microsoft.vsix.manifest+xml" />
  <Default Extension="json" ContentType="application/json" />
  <Default Extension="js" ContentType="text/javascript" />
  <Default Extension="css" ContentType="text/css" />
  <Default Extension="html" ContentType="text/html" />
  <Default Extension="svg" ContentType="image/svg+xml" />
  <Default Extension="png" ContentType="image/png" />
  <Default Extension="ttf" ContentType="font/ttf" />
  <Default Extension="woff" ContentType="font/woff" />
  <Default Extension="woff2" ContentType="font/woff2" />
  <Default Extension="map" ContentType="application/json" />
  <Default Extension="md" ContentType="text/markdown" />
</Types>
CONTENT_TYPES

cd "${TMP}"
zip -rq "${OUT}" .
echo "✓ VSIX 已导出: ${OUT}"
ls -lh "${OUT}"
