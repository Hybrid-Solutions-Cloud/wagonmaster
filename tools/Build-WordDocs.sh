#!/usr/bin/env bash
# Regenerates the Word copies of the Manifest docs under docs/public/downloads.
# Requires pandoc and python3 with python-docx. Run from the repo root.
set -euo pipefail
site='https://labs.hybridsolutions.cloud/Wagonmaster'
out='docs/public/downloads'
mkdir -p "$out"
for page in usage security api-reference; do
  tmp="$(mktemp --suffix=.md)"
  sed -E \
    -e 's/ \[Download this page as a Word document\]\([^)]*\)\{target="_self"\}\.//' \
    -e "s#\]\(\./([a-z-]+)\)#](${site}/manifest/\1)#g" \
    -e "s#\]\(/([a-z/-]+)\)#](${site}/\1)#g" \
    "docs/manifest/${page}.md" > "$tmp"
  pandoc "$tmp" -f gfm -o "${out}/wagonmaster-manifest-${page}.docx"
  python3 tools/fix_tables.py "${out}/wagonmaster-manifest-${page}.docx"
  rm -f "$tmp"
done
