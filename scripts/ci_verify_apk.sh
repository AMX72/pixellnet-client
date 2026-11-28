#!/usr/bin/env bash
# T-027 / А2.5 — проверка готовых APK: подпись, пакет, метка. Падает при любом расхождении.
#
# usage: ci_verify_apk.sh <каталог с APK> <ожидаемый пакет> <bridge|app> <ожидаемая метка>
#   bridge → отпечаток ключа v2, app → отпечаток ключа v3 (android/pixellnet-identities.properties).
# Нужны apksigner и aapt2 из Android build-tools (на ubuntu-latest лежат в $ANDROID_HOME/build-tools/*).
# Печатает для каждого APK: SHA-256 сертификата подписи, схемы подписи, пакет, versionCode/versionName, метку.
set -euo pipefail

DIR="${1:?каталог с APK}"
EXPECT_PACKAGE="${2:?ожидаемый пакет}"
CERT_KEY="${3:?bridge|app}"
EXPECT_LABEL="${4:?ожидаемая метка}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IDENT="$HERE/../android/pixellnet-identities.properties"

fail() { echo "::error::$*" >&2; exit 1; }
normalize() { tr -d ':[:space:]' | tr 'A-F' 'a-f'; }

EXPECT_CERT=$(grep -m1 "^${CERT_KEY}\.cert\.sha256=" "$IDENT" | cut -d= -f2-)
[ -n "$EXPECT_CERT" ] || fail "в $IDENT нет ${CERT_KEY}.cert.sha256"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
BT=$(ls -d "$SDK"/build-tools/*/ 2>/dev/null | sed 's#/$##' | sort -V | tail -1 || true)
[ -n "$BT" ] && [ -x "$BT/apksigner" ] || fail "не найден apksigner в $SDK/build-tools"
APKSIGNER="$BT/apksigner"
AAPT2="$BT/aapt2"
echo "build-tools: $BT"
echo "ожидаем: пакет=$EXPECT_PACKAGE, отпечаток($CERT_KEY)=$EXPECT_CERT, метка='$EXPECT_LABEL'"

shopt -s nullglob
apks=("$DIR"/*.apk)
[ "${#apks[@]}" -gt 0 ] || fail "в $DIR нет APK"
bad=0
for apk in "${apks[@]}"; do
  name=$(basename "$apk")
  echo "---- $name ($(( $(wc -c < "$apk") / 1024 )) КБ)"
  if ! sig=$("$APKSIGNER" verify --print-certs -v "$apk" 2>&1); then
    echo "$sig" | sed 's/^/  /'
    echo "::error::apksigner verify не прошёл для $name"; bad=1; continue
  fi
  signers=$(printf '%s\n' "$sig" | sed -n 's/^Number of signers: *//p' | head -1)
  digest=$(printf '%s\n' "$sig" | sed -n 's/^Signer #1 certificate SHA-256 digest: *//p' | head -1)
  schemes=$(printf '%s\n' "$sig" | sed -n 's/^Verified using \(v[0-9.]*\) .*: true/\1/p' | tr '\n' ' ')
  echo "  подписей: ${signers:-?}; схемы: ${schemes:-?}"
  echo "  отпечаток SHA-256 сертификата: $digest"
  if [ "$(printf '%s' "$digest" | normalize)" != "$(printf '%s' "$EXPECT_CERT" | normalize)" ]; then
    echo "::error::$name подписан не тем ключом: $digest, ожидался $EXPECT_CERT ($CERT_KEY)"; bad=1
  fi
  [ "${signers:-1}" = "1" ] || { echo "::error::$name: подписантов $signers, ожидался 1"; bad=1; }

  badging=$("$AAPT2" dump badging "$apk" 2>/dev/null || true)
  pkg=$(printf '%s\n' "$badging" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -1)
  vcode=$(printf '%s\n' "$badging" | sed -n "s/^package: .*versionCode='\([^']*\)'.*/\1/p" | head -1)
  vname=$(printf '%s\n' "$badging" | sed -n "s/^package: .*versionName='\([^']*\)'.*/\1/p" | head -1)
  label=$(printf '%s\n' "$badging" | sed -n "s/^application-label:'\(.*\)'$/\1/p" | head -1)
  echo "  пакет: $pkg; versionCode=$vcode; versionName=$vname; метка: '$label'"
  [ "$pkg" = "$EXPECT_PACKAGE" ] || { echo "::error::$name: пакет '$pkg', ожидался '$EXPECT_PACKAGE'"; bad=1; }
  [ "$label" = "$EXPECT_LABEL" ] || { echo "::error::$name: метка '$label', ожидалась '$EXPECT_LABEL'"; bad=1; }
done
[ "$bad" = 0 ] || fail "проверка APK не прошла"
echo "Проверка APK пройдена: ${#apks[@]} файл(ов), пакет $EXPECT_PACKAGE, ключ $CERT_KEY"
