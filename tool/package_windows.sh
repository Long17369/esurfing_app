#!/usr/bin/env bash
# 生成 Windows 便携包：dist/esurfing-app-windows-x64.zip
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f packages/esurfing_native/windows/esurfing.dll ]]; then
  echo "缺少 packages/esurfing_native/windows/esurfing.dll，先运行 tool/build_native.sh windows" >&2
  exit 1
fi

flutter build windows --release
mkdir -p dist
rm -f dist/esurfing-app-windows-x64.zip
(cd build/windows/x64/runner/Release && zip -r "$ROOT/dist/esurfing-app-windows-x64.zip" .)
echo "-> dist/esurfing-app-windows-x64.zip"
