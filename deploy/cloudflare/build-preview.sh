#!/usr/bin/env bash
# Builds the browser preview of DeepSeek Harness into apps/web/dist, shaped the
# way .github/workflows/build-preview-cloudflare.yml shapes it for upstream:
# workspace artifacts, the preview page and its packed VFS image, no source
# maps, and preview.html served as the root page (index.html alone cannot boot
# without a host injecting window.__DSH_BOOT__).
# Runs from the repository root after `pnpm install --frozen-lockfile`.
set -euo pipefail

export DSH_CLIENT_TITLE="${DSH_CLIENT_TITLE:-DeepSeek Harness (aperçu)}"
export DSH_TELEMETRY_DISABLED=1

pnpm run build:artifacts
pnpm --filter @deepseek-ai/dsh-web-frontend run build:preview

find apps/web/dist -name '*.map' -delete
cp apps/web/dist/preview.html apps/web/dist/index.html

echo "preview ready: $(find apps/web/dist -type f | wc -l) files, $(du -sh apps/web/dist | cut -f1)"
