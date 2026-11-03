#!/usr/bin/env bash
# 生成 Android 侧载包：dist/app-<abi>-release.apk
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

flutter build apk --release --split-per-abi
mkdir -p dist
cp build/app/outputs/flutter-apk/app-*-release.apk dist/
ls -l dist/*.apk
