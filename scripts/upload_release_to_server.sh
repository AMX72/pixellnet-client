#!/usr/bin/env bash
# Upload a GitHub release's assets to pixellnet.com (/var/www/pixellnet-downloads/),
# update latest-* symlinks, keep the last N versions, write latest.json (the
# manifest the in-app updater reads), purge Cloudflare cache.
#
# Required env:
#   GITHUB_TOKEN           token with contents:read for the release assets
#   SERVER_SSH_KEY         private key material (multi-line), or
#   SERVER_SSH_KEY_FILE    path to private key file
#   SERVER_HOST            default 159.195.27.39
#   SERVER_USER            default root
#   KEEP_LAST              default 3
#   CLOUDFLARE_MASTER_KEY, CLOUDFLARE_EMAIL   optional, for cache purge
#
# Usage: ./upload_release_to_server.sh v0.1.85

set -euo pipefail

trim() { printf '%s' "$1" | tr -d '[:space:]'; }

TAG="${1:?usage: $0 <tag>}"
VER="${TAG#v}"
REPO="AMX72/pixellnet-client"
# Secrets pasted into the GitHub UI often carry a trailing newline.
HOST=$(trim "${SERVER_HOST:-159.195.27.39}")
USER=$(trim "${SERVER_USER:-root}")
KEEP="${KEEP_LAST:-3}"
REMOTE="/var/www/pixellnet-downloads"
CF_KEY=$(trim "${CLOUDFLARE_MASTER_KEY:-}")
CF_EMAIL=$(trim "${CLOUDFLARE_EMAIL:-}")

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Windows Python (git-bash runs) cannot open /tmp/... paths.
PYTMP=$(cygpath -m "$TMP" 2>/dev/null || echo "$TMP")

if [ -n "${SERVER_SSH_KEY:-}" ]; then
  KEY="$TMP/id_key"
  printf '%s\n' "$SERVER_SSH_KEY" | tr -d '\r' > "$KEY"
  chmod 600 "$KEY"
elif [ -n "${SERVER_SSH_KEY_FILE:-}" ]; then
  KEY="$SERVER_SSH_KEY_FILE"
else
  echo "ERROR: set SERVER_SSH_KEY or SERVER_SSH_KEY_FILE" >&2
  exit 1
fi

SSH_OPTS=(-i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=20)

echo "==> fetching release $TAG metadata"
curl -sfS -H "Authorization: Bearer ${GITHUB_TOKEN:?}" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$REPO/releases/tags/$TAG" > "$TMP/release.json"

python3 -c "
import json
d = json.load(open('$PYTMP/release.json', encoding='utf-8'))
for a in d.get('assets', []):
    print(f\"{a['id']}\t{a['name']}\t{a['size']}\")
" | tr -d '\r' > "$TMP/assets.tsv"

# Android and Windows builds attach assets independently; this script runs after
# each of them. Upload only once both platforms are in the release.
if ! grep -q "arm64-v8a-release.apk" "$TMP/assets.tsv" || ! grep -q "windows-x64-$VER.zip" "$TMP/assets.tsv"; then
  echo "==> release $TAG is incomplete (waiting for the other platform build), nothing to do"
  cut -f2 "$TMP/assets.tsv" | sed 's/^/  have: /'
  exit 0
fi

echo "==> downloading assets"
while IFS=$'\t' read -r id name size; do
  case "$name" in *-app-release.apk) continue ;; esac  # universal APK, 300MB, not served
  echo "  $name ($((size/1024)) KB)"
  curl -sfL -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "Accept: application/octet-stream" \
    "https://api.github.com/repos/$REPO/releases/assets/$id" -o "$TMP/$name"
done < "$TMP/assets.tsv"

declare -A RENAME=(
  ["pixellnet-$VER-app-arm64-v8a-release.apk"]="pixellnet-$VER-arm64.apk"
  ["pixellnet-$VER-app-armeabi-v7a-release.apk"]="pixellnet-$VER-armv7.apk"
  ["pixellnet-$VER-app-x86_64-release.apk"]="pixellnet-$VER-x86_64.apk"
  ["pixellnet-windows-x64-$VER.zip"]="pxl-win-v$VER.zip"
)
for src in "${!RENAME[@]}"; do
  [ -f "$TMP/$src" ] && mv "$TMP/$src" "$TMP/${RENAME[$src]}"
done

for need in "pixellnet-$VER-arm64.apk" "pxl-win-v$VER.zip" "pixellnet-setup-$VER.exe"; do
  if [ ! -s "$TMP/$need" ]; then
    echo "ERROR: $need was not downloaded, refusing to touch the server" >&2
    exit 1
  fi
done

echo "==> uploading to $HOST"
for f in "$TMP"/pixellnet-*.apk "$TMP"/pixellnet-setup-*.exe "$TMP"/pxl-win-*.zip; do
  [ -f "$f" ] || continue
  scp "${SSH_OPTS[@]}" -q "$f" "$USER@$HOST:$REMOTE/"
  echo "  uploaded $(basename "$f")"
done

echo "==> symlinks, rotation, latest.json"
ssh "${SSH_OPTS[@]}" "$USER@$HOST" "VER='$VER' KEEP='$KEEP' REMOTE='$REMOTE' bash -s" <<'REMOTE_SCRIPT'
set -e
cd "$REMOTE"
for f in "pixellnet-$VER-arm64.apk" "pixellnet-setup-$VER.exe" "pxl-win-v$VER.zip"; do
  [ -s "$f" ] || { echo "ERROR: $f missing on server, symlinks left unchanged" >&2; exit 1; }
done
ln -sfn "pixellnet-$VER-arm64.apk" pixellnet-latest-arm64.apk
ln -sfn "pixellnet-setup-$VER.exe" pixellnet-setup-latest.exe
ln -sfn "pxl-win-v$VER.zip" pixellnet-windows-latest.zip
for pat in 'pixellnet-*-arm64.apk' 'pixellnet-*-armv7.apk' 'pixellnet-*-x86_64.apk' 'pixellnet-setup-*.exe' 'pxl-win-*.zip'; do
  ls -1 $pat 2>/dev/null | grep -v latest | sort -V | head -n -"$KEEP" | while read -r f; do
    echo "  rotated: $f"; rm -f "$f"
  done
done
python3 - "$VER" <<'PY'
import hashlib, json, os, sys, datetime
ver = sys.argv[1]
files = {
    "android": {"arm64": f"pixellnet-{ver}-arm64.apk",
                "armv7": f"pixellnet-{ver}-armv7.apk",
                "x86_64": f"pixellnet-{ver}-x86_64.apk"},
    "windows": {"zip": f"pxl-win-v{ver}.zip",
                "setup": f"pixellnet-setup-{ver}.exe"},
}
def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()
out = {"version": ver,
       "published_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
for platform, entries in files.items():
    out[platform] = {}
    for key, name in entries.items():
        if os.path.exists(name):
            out[platform][key] = {"file": name, "size": os.path.getsize(name), "sha256": sha(name)}
tmp = "latest.json.tmp"
with open(tmp, "w") as f:
    json.dump(out, f, indent=2)
os.replace(tmp, "latest.json")
print("  latest.json ->", ver)
PY
chown -R www-data:www-data "$REMOTE"
ls -la | grep -vE '^(total|d)' | awk '{print "  " $NF " " $5}' | sort
REMOTE_SCRIPT

echo "==> purging Cloudflare cache"
if [ -n "$CF_KEY" ] && [ -n "$CF_EMAIL" ]; then
  curl -sfS -X POST "https://api.cloudflare.com/client/v4/zones/71ae649cd50e2ef8f51111836bfade3e/purge_cache" \
    -H "X-Auth-Email: $CF_EMAIL" -H "X-Auth-Key: $CF_KEY" \
    -H "Content-Type: application/json" \
    --data '{"files":["https://pixellnet.com/latest.apk","https://pixellnet.com/download/latest.json","https://pixellnet.com/download/pixellnet-latest-arm64.apk","https://pixellnet.com/download/pixellnet-setup-latest.exe","https://pixellnet.com/download/pixellnet-windows-latest.zip"]}' > /dev/null
  echo "  purged"
else
  echo "  (skip — CLOUDFLARE_MASTER_KEY/EMAIL not set)"
fi

echo "==> done, v$VER live at https://pixellnet.com/download"
