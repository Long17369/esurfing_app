#!/usr/bin/env bash
# release 签名密钥的小工具：本地与 CI 用的是 android/keystore/release.jks 这一份。
#   export       打印填进 GitHub Secrets 的两个值
#   fingerprint  打印证书 SHA-256（核对 APK 签名是否一致）
#   verify <apk> 校验 APK 的签名者
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ks="$root/android/keystore/release.jks"
props="$root/android/key.properties"

die() { echo "$*" >&2; exit 1; }

[ -f "$ks" ] || die "找不到 $ks（密钥不入库，只在本地和 CI Secrets 里）"

case "${1:-}" in
  export)
    [ -f "$props" ] || die "找不到 $props"
    store_password="$(sed -n 's/^storePassword=//p' "$props")"
    [ -n "$store_password" ] || die "key.properties 里没有 storePassword"
    cat <<EOF
把下面两个值填到仓库 Settings → Secrets and variables → Actions：

ANDROID_KEYSTORE_BASE64
$(base64 "$ks" | tr -d '\n')

ANDROID_KEYSTORE_PASSWORD
$store_password
EOF
    ;;
  fingerprint)
    keytool -list -v -keystore "$ks" -storepass "$(sed -n 's/^storePassword=//p' "$props")" 2>/dev/null \
      | sed -n 's/^[[:space:]]*SHA256: //p'
    ;;
  verify)
    apk="${2:-}"
    [ -f "$apk" ] || die "用法：$0 verify <apk>"
    apksigner="$(ls -d "${ANDROID_HOME:-$HOME/Android/Sdk}"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)"
    [ -n "$apksigner" ] || die "找不到 apksigner，可用 unzip -l 看 META-INF 或装 Android build-tools"
    "$apksigner" verify --print-certs "$apk"
    ;;
  *)
    sed -n '2,5p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
