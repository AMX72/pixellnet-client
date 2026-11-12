#!/usr/bin/env bash
# Upload a GitHub release's assets to pixellnet.com server
# (/var/www/pixellnet-downloads/), update latest-* symlinks, keep last 3 versions.
#
# Required env:
#   GITHUB_TOKEN           PAT with contents:read for the release assets
#   SERVER_SSH_KEY         private key material (multi-line), or
#   SERVER_SSH_KEY_FILE    path to private key file
#   SERVER_HOST            default 159.195.27.39
#   SERVER_USER            default root
#   KEEP_LAST              default 3
#
# Usage: ./upload_release_to_server.sh v0.1.80

set -euo pipefail

TAG="${1:?usage: $0 <tag>}"
VER="${TAG#v}"
REPO="AMX72/pixellnet-client"
HOST="${SERVER_HOST:-159.195.27.39}"
USER="${SERVER_USER:-root}"
KEEP="${KEEP_LAST:-3}"
REMOTE="/var/www/pixellnet-downloads"

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

# Resolve SSH key
if [ -n "${SERVER_SSH_KEY:-}" ]; then
  KEY="$TMP/id_key"
  printf '%s\n' "$SERVER_SSH_KEY" > "$KEY"
  chmod 600 "$KEY"
elif [ -n "${SERVER_SSH_KEY_FILE:-}" ]; then
  KEY="$SERVER_SSH_KEY_FILE"
else
  echo "ERROR: set SERVER_SSH_KEY or SERVER_SSH_KEY_FILE" >&2
  exit 1
fi

SSH_OPTS="-i $KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "==> fetching release $TAG metadata"
curl -sfS -H "Authorization: Bearer ${GITHUB_TOKEN:?}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/releases/tags/$TAG" > "$TMP/release.json"

# Parse assets list with python (robust vs jq that may be missing).
# Reading from a file avoids heredoc issues with special chars in release body.
python3 -c "
import json
d = json.load(open('$TMP/release.json', encoding='utf-8'))
for a in d.get('assets', []):
    print(f\"{a['id']}\t{a['name']}\t{a['size']}\")
" > "$TMP/assets.tsv"

echo "==> downloading assets"
while IFS=$'\t' read -r id name size; do
  echo "  $name ($((size/1024)) KB)"
  curl -sfL -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/octet-stream" \
    "https://api.github.com/repos/$REPO/releases/assets/$id" -o "$TMP/$name"
done < "$TMP/assets.tsv"

# Canonical short names
declare -A RENAME=(
  ["pixellnet-$VER-app-arm64-v8a-release.apk"]="pixellnet-$VER-arm64.apk"
  ["pixellnet-$VER-app-armeabi-v7a-release.apk"]="pixellnet-$VER-armv7.apk"
  ["pixellnet-$VER-app-x86_64-release.apk"]="pixellnet-$VER-x86_64.apk"
  ["pixellnet-$VER-app-release.apk"]="pixellnet-$VER-universal.apk"
  ["pixellnet-setup-$VER.exe"]="pixellnet-setup-$VER.exe"
  ["pixellnet-windows-x64-$VER.zip"]="pxl-win-v$VER.zip"
)
for src in "${!RENAME[@]}"; do
  if [ -f "$TMP/$src" ]; then
    mv "$TMP/$src" "$TMP/${RENAME[$src]}"
  fi
done

# Skip the huge universal APK (>300MB) — modern phones take arm64 split
rm -f "$TMP/pixellnet-$VER-universal.apk"

echo "==> uploading to server"
# Use scp -i (not rsync, which may not be available on all runners)
for f in "$TMP"/pixellnet-*.apk "$TMP"/pixellnet-setup-*.exe "$TMP"/pxl-win-*.zip; do
  [ -f "$f" ] || continue
  scp $SSH_OPTS -q "$f" "$USER@$HOST:$REMOTE/"
  echo "  uploaded $(basename "$f")"
done

echo "==> updating symlinks and rotating"
ssh $SSH_OPTS "$USER@$HOST" "
  set -e
  cd $REMOTE
  ln -sfn pixellnet-$VER-arm64.apk pixellnet-latest-arm64.apk
  ln -sfn pixellnet-setup-$VER.exe pixellnet-setup-latest.exe
  ln -sfn pxl-win-v$VER.zip pixellnet-windows-latest.zip
  # Rotate keep_last per family (ignore latest-* symlinks)
  for pat in 'pixellnet-*-arm64.apk' 'pixellnet-*-armv7.apk' 'pixellnet-*-x86_64.apk' 'pixellnet-setup-*.exe' 'pxl-win-*.zip'; do
    ls -1 \$pat 2>/dev/null | grep -v latest | sort -V | head -n -$KEEP | while read f; do
      echo \"  rotated: \$f\"
      rm -f \"\$f\"
    done
  done
  chown -R www-data:www-data $REMOTE
  echo '==> final listing'
  ls -la | grep -vE '^(total|d)' | sort
"

echo "==> purging Cloudflare cache"
if [ -n "${CLOUDFLARE_MASTER_KEY:-}" ] && [ -n "${CLOUDFLARE_EMAIL:-}" ]; then
  curl -sfS -X POST "https://api.cloudflare.com/client/v4/zones/71ae649cd50e2ef8f51111836bfade3e/purge_cache" \
    -H "X-Auth-Email: $CLOUDFLARE_EMAIL" -H "X-Auth-Key: $CLOUDFLARE_MASTER_KEY" \
    -H "Content-Type: application/json" \
    --data '{"files":["https://pixellnet.com/latest.apk","https://pixellnet.com/download/pixellnet-latest-arm64.apk","https://pixellnet.com/download/pixellnet-setup-latest.exe","https://pixellnet.com/download/pixellnet-windows-latest.zip"]}' > /dev/null
  echo "  purged"
else
  echo "  (skip — CLOUDFLARE_MASTER_KEY/EMAIL not set)"
fi

echo "==> done, v$VER live at https://pixellnet.com/download"
