#!/usr/bin/env bash
# Выпуск GitHub Release -> pixellnet.com (/var/www/pixellnet-downloads/) и зеркала: файлы, ссылки latest-*, ротация,
# latest.json (манифест, который читает приложение), очистка кэша Cloudflare.
#
# T-027 / А2.5: три вида выпуска и откат по секциям latest.json (проект переезда §3.2, С-14).
#   legacy  как раньше: pixellnet-<ver>-<abi>.apk -> секция android
#   bridge  мост 0.1.106 (com.pixellnet.vpn): pixellnet-bridge-<ver>-<abi>.apk -> секция android, потом ЗАМОРОЖЕНА;
#           файлы моста вне ротации «хранить 3»
#   app     новое приложение (com.pxllnet.app): pxllnet-<ver>-<abi>.apk -> секция android_app, ссылка latest.apk -> оно
# Вид выпуска берётся из android-kind.json в релизе (его кладёт build-android.yml); нет файла — legacy.
# Windows всегда в секции windows. Состояние и история секций — release_manifest.py (рядом).
#
# Порядок (правило «манифест — последним»): 1) файлы на ВСЕ хосты, 2) проверка SHA-256 файлов на каждом хосте,
# 3) только потом latest.json/ссылки/ротация на хостах, где файлы проверены, 4) очистка кэша Cloudflare.
# Упал хост-зеркало — его манифест не трогаем (остаётся прежний, согласованный с его файлами).
#
# Использование:
#   upload_release_to_server.sh [--hold] vX.Y.Z            выпуск (тег строго X.Y.Z: теги с дефисом, v0.1.106-rc1, не заливаются никогда)
#   upload_release_to_server.sh activate <секция|all> <версия>   включить подготовленный (--hold) выпуск
#   upload_release_to_server.sh rollback <секция> [<версия>|previous|none] [--force]   откат ОДНОЙ секции
#   upload_release_to_server.sh migration [--enabled true|false] [--min-bridge-version X] [--remind-from ДАТА|--remind-in-days N|--remind-clear]
#   upload_release_to_server.sh freeze|unfreeze <секция> | rotate | verify | show
#
# Окружение:
#   GITHUB_TOKEN           токен с contents:read для файлов релиза
#   SERVER_SSH_KEY         ключ (многострочный) или SERVER_SSH_KEY_FILE — путь к файлу ключа
#   SERVER_HOST            по умолчанию 159.195.27.39        SERVER_USER  по умолчанию root
#   KEEP_LAST              по умолчанию 3 (версий в ротации; мост и файлы активных/откатных снимков не удаляются)
#   MIRROR_HOSTS           зеркала через пробел, по умолчанию 178.236.254.45 (download.pixellnet.com, Aeza MSK)
#   CLOUDFLARE_MASTER_KEY, CLOUDFLARE_EMAIL   необязательно, для очистки кэша
#   HOLD=1                 как --hold: файлы на серверах, latest.json и ссылки не трогаем
#   FORCE_REPLACE=1        разрешить перезаписать на сервере файл с тем же именем, но другим SHA-256 (по умолчанию — отказ)
# Только для проверок (сухой прогон, сервер не нужен):
#   DRY_RUN_DIR=<папка>    «серверы» — подпапки primary/www и mirror/www; ssh/scp/Cloudflare не вызываются
#   ASSETS_DIR=<папка>     файлы релиза берём оттуда вместо GitHub (имена как у ассетов релиза)
#   DRY_MIRRORS=""         без зеркала в сухом прогоне (по умолчанию одно зеркало "mirror")
#   MIN_APK_BYTES          минимальный размер arm64-APK (по умолчанию 10000000; в сухом прогоне уменьшают)

set -euo pipefail

trim() { printf '%s' "$1" | tr -d '[:space:]'; }
die() { echo "ERROR: $*" >&2; exit 1; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_PY="$HERE/release_manifest.py"
[ -f "$MANIFEST_PY" ] || die "нет $MANIFEST_PY"

REPO="AMX72/pixellnet-client"
# Secrets pasted into the GitHub UI often carry a trailing newline.
HOST=$(trim "${SERVER_HOST:-159.195.27.39}")
USER=$(trim "${SERVER_USER:-root}")
KEEP="${KEEP_LAST:-3}"
REMOTE="/var/www/pixellnet-downloads"
MIRROR_HOSTS="${MIRROR_HOSTS-178.236.254.45}"
CF_KEY=$(trim "${CLOUDFLARE_MASTER_KEY:-}")
CF_EMAIL=$(trim "${CLOUDFLARE_EMAIL:-}")
MIN_APK_BYTES="${MIN_APK_BYTES:-10000000}"
export MIN_APK_BYTES

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# Windows Python (git-bash runs) cannot open /tmp/... paths.
pypath() { cygpath -m "$1" 2>/dev/null || echo "$1"; }

DRY="${DRY_RUN_DIR:-}"
if [ -n "$DRY" ]; then
  HOST="primary"
  MIRROR_HOSTS="${DRY_MIRRORS-mirror}"
  mkdir -p "$DRY"
else
  if [ -n "${SERVER_SSH_KEY:-}" ]; then
    KEY="$TMP/id_key"
    printf '%s\n' "$SERVER_SSH_KEY" | tr -d '\r' > "$KEY"
    chmod 600 "$KEY"
  elif [ -n "${SERVER_SSH_KEY_FILE:-}" ]; then
    KEY="$SERVER_SSH_KEY_FILE"
  else
    die "set SERVER_SSH_KEY or SERVER_SSH_KEY_FILE"
  fi
  SSH_OPTS=(-i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=20 -o ServerAliveInterval=15)
  # Одно TCP-соединение на хост (scp и ssh через него): у Aeza анти-DDoS, пачки новых соединений не нужны.
  if [ "$(uname -s)" = "Linux" ]; then
    SSH_OPTS+=(-o ControlMaster=auto -o "ControlPath=$TMP/cm-%C" -o ControlPersist=120)
  fi
fi

# ---- работа с хостом (в сухом прогоне «хост» — локальная папка) --------------------------------------------------------
remote_dir() { if [ -n "$DRY" ]; then echo "$DRY/$1/www"; else echo "$REMOTE"; fi; }

rsh() { # <хост> <команда оболочки>; stdin передаётся
  local host="$1" cmd="$2"
  if [ -n "$DRY" ]; then bash -c "$cmd"; else ssh "${SSH_OPTS[@]}" "$USER@$host" "$cmd"; fi
}

rcopy() { # <хост> <файлы...>
  local host="$1"; shift
  if [ -n "$DRY" ]; then
    cp "$@" "$(remote_dir "$host")/"
  else
    scp "${SSH_OPTS[@]}" -q "$@" "$USER@$host:$REMOTE/"
  fi
}

rtool() { # <хост> <аргументы release_manifest.py без --root/--keep>
  local host="$1"; shift
  local root; root=$(remote_dir "$host")
  if [ -n "$DRY" ]; then
    python3 - --root "$(pypath "$root")" --keep "$KEEP" "$@" < "$MANIFEST_PY"
  else
    local q=""; local x
    for x in "$@"; do q+=" $(printf '%q' "$x")"; done
    ssh "${SSH_OPTS[@]}" "$USER@$host" "python3 - --root $(printf '%q' "$root") --keep $KEEP$q" < "$MANIFEST_PY"
  fi
}

purge_cf() {
  echo "==> purging Cloudflare cache"
  if [ -n "$DRY" ]; then echo "  (dry run — skip)"; return 0; fi
  if [ -n "$CF_KEY" ] && [ -n "$CF_EMAIL" ]; then
    curl -sfS -X POST "https://api.cloudflare.com/client/v4/zones/71ae649cd50e2ef8f51111836bfade3e/purge_cache" \
      -H "X-Auth-Email: $CF_EMAIL" -H "X-Auth-Key: $CF_KEY" \
      -H "Content-Type: application/json" \
      --data '{"files":["https://pixellnet.com/latest.apk","https://pixellnet.com/download/latest.json","https://pixellnet.com/download/pixellnet-latest-arm64.apk","https://pixellnet.com/download/pixellnet-setup-latest.exe","https://pixellnet.com/download/pixellnet-windows-latest.zip"]}' > /dev/null
    echo "  purged"
  else
    echo "  (skip — CLOUDFLARE_MASTER_KEY/EMAIL not set)"
  fi
}

# ---- администрирование секций: activate / rollback / migration / freeze / ... ------------------------------------------
admin() {
  local cmd="$1"; shift
  echo "==> $cmd $* on all hosts"
  local failed=0 h
  for h in "$HOST" $MIRROR_HOSTS; do
    h=$(trim "$h")
    echo "-- $h"
    if ! rtool "$h" "$cmd" "$@"; then echo "WARNING: $h: команда не выполнена" >&2; failed=1; fi
  done
  case "$cmd" in activate|rollback|migration) purge_cf ;; esac
  [ "$failed" = 0 ] || die "команда $cmd не выполнена на части хостов (см. выше); манифесты на них не менялись"
}

case "${1:-}" in
  activate|rollback|migration|freeze|unfreeze|rotate|verify|show)
    admin "$@"
    exit 0
    ;;
esac

# ---- выпуск ---------------------------------------------------------------------------------------------------------
HOLD_FLAG="${HOLD:-}"
if [ "${1:-}" = "--hold" ]; then HOLD_FLAG=1; shift; fi
TAG="${1:?usage: $0 [--hold] vX.Y.Z | activate|rollback|migration|freeze|unfreeze|rotate|verify|show ...}"
if ! [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  die "тег '$TAG' не вида vX.Y.Z: предварительные теги (v0.1.106-rc1, -beta) на серверы не заливаем"
fi
VER="${TAG#v}"

echo "==> fetching release $TAG metadata"
if [ -n "${ASSETS_DIR:-}" ]; then
  : > "$TMP/assets.tsv"
  for f in "$ASSETS_DIR"/*; do
    [ -f "$f" ] || continue
    printf '%s\t%s\t%s\n' "$(basename "$f")" "$(basename "$f")" "$(wc -c < "$f")" >> "$TMP/assets.tsv"
  done
else
  curl -sfS -H "Authorization: Bearer ${GITHUB_TOKEN:?}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/$REPO/releases/tags/$TAG" > "$TMP/release.json"
  python3 -c "
import json
d = json.load(open('$(pypath "$TMP")/release.json', encoding='utf-8'))
for a in d.get('assets', []):
    print(f\"{a['id']}\t{a['name']}\t{a['size']}\")
" | tr -d '\r' > "$TMP/assets.tsv"
fi

fetch_asset() { # <id> <name> -> $TMP/<name>
  local id="$1" name="$2"
  if [ -n "${ASSETS_DIR:-}" ]; then
    cp "$ASSETS_DIR/$name" "$TMP/$name"
  else
    curl -sfL -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/octet-stream" \
      "https://api.github.com/repos/$REPO/releases/assets/$id" -o "$TMP/$name"
  fi
}

# Вид выпуска: android-kind.json кладёт CI вместе с APK (мост / новое приложение / как раньше).
KIND="legacy"; MARKER_PUBLISH="live"
marker_id=$(awk -F'\t' '$2=="android-kind.json"{print $1}' "$TMP/assets.tsv" | head -1)
if [ -n "$marker_id" ]; then
  fetch_asset "$marker_id" android-kind.json
  marker_out=$(python3 -c "
import json
d = json.load(open('$(pypath "$TMP")/android-kind.json', encoding='utf-8'))
k = d.get('kind', 'legacy'); p = d.get('publish', 'live')
assert k in ('legacy', 'bridge', 'app'), k
assert p in ('live', 'hold'), p
print('KIND=%s; MARKER_PUBLISH=%s' % (k, p))
") || die "android-kind.json в релизе не разобран — не гадаем, какой это выпуск"
  eval "$marker_out"
fi
[ "$MARKER_PUBLISH" = "hold" ] && HOLD_FLAG=1
echo "  kind=$KIND publish=$([ -n "$HOLD_FLAG" ] && echo hold || echo live)"

case "$KIND" in
  app) GH_PREFIX="pxllnet" ;;
  *)   GH_PREFIX="pixellnet" ;;
esac
case "$KIND" in
  legacy) SRV_PREFIX="pixellnet-$VER" ;;
  bridge) SRV_PREFIX="pixellnet-bridge-$VER" ;;
  app)    SRV_PREFIX="pxllnet-$VER" ;;
esac

has_asset() { awk -F'\t' -v n="$1" '$2==n{f=1} END{exit f?0:1}' "$TMP/assets.tsv"; }

# Android и Windows собираются отдельно и прикрепляют файлы по очереди; скрипт запускается после каждого.
# Работаем, когда в релизе есть и APK нужного вида, и Windows.
if ! has_asset "$GH_PREFIX-$VER-app-arm64-v8a-release.apk" || ! has_asset "pixellnet-windows-x64-$VER.zip" || ! has_asset "pixellnet-setup-$VER.exe"; then
  echo "==> release $TAG is incomplete (kind=$KIND; waiting for the other platform build), nothing to do"
  cut -f2 "$TMP/assets.tsv" | sed 's/^/  have: /'
  exit 0
fi

echo "==> downloading assets"
while IFS=$'\t' read -r id name size; do
  case "$name" in
    *-app-release.apk) continue ;;   # universal APK, 300MB, not served
    android-kind.json) continue ;;
  esac
  echo "  $name ($((size/1024)) KB)"
  fetch_asset "$id" "$name"
done < "$TMP/assets.tsv"

# GitHub-имена -> имена на сервере. Мост: pixellnet-bridge-<ver>-<abi>.apk — вне шаблонов ротации.
declare -A RENAME=(
  ["$GH_PREFIX-$VER-app-arm64-v8a-release.apk"]="$SRV_PREFIX-arm64.apk"
  ["$GH_PREFIX-$VER-app-armeabi-v7a-release.apk"]="$SRV_PREFIX-armv7.apk"
  ["$GH_PREFIX-$VER-app-x86_64-release.apk"]="$SRV_PREFIX-x86_64.apk"
  ["pixellnet-windows-x64-$VER.zip"]="pxl-win-v$VER.zip"
)
for src in "${!RENAME[@]}"; do
  [ -f "$TMP/$src" ] && mv "$TMP/$src" "$TMP/${RENAME[$src]}"
done

# Что именно заливаем (только этот выпуск; чужие pixellnet-*.apk в $TMP не лежат).
UPLOAD=()
for f in "$SRV_PREFIX-arm64.apk" "$SRV_PREFIX-armv7.apk" "$SRV_PREFIX-x86_64.apk" "pxl-win-v$VER.zip" "pixellnet-setup-$VER.exe"; do
  [ -f "$TMP/$f" ] && UPLOAD+=("$f")
done

# Файл на выходе должен быть тем, чем назван: тип (магические байты), размер, непустой (случай подмены APK на Диске 11.11.2026).
magic() { head -c"$2" "$1" | od -An -c | tr -d ' \n'; }
for need in "$SRV_PREFIX-arm64.apk" "pxl-win-v$VER.zip" "pixellnet-setup-$VER.exe"; do
  [ -s "$TMP/$need" ] || die "$need was not downloaded, refusing to touch the server"
done
for f in "${UPLOAD[@]}"; do
  case "$f" in
    *.apk|*.zip) [ "$(magic "$TMP/$f" 2)" = "PK" ] || die "$f не похож на APK/ZIP (нет сигнатуры PK) — не заливаем" ;;
    *.exe)       [ "$(magic "$TMP/$f" 2)" = "MZ" ] || die "$f не похож на Windows-установщик (нет сигнатуры MZ) — не заливаем" ;;
  esac
done
arm_size=$(wc -c < "$TMP/$SRV_PREFIX-arm64.apk")
[ "$arm_size" -ge "$MIN_APK_BYTES" ] || die "$SRV_PREFIX-arm64.apk слишком мал ($arm_size < $MIN_APK_BYTES байт) — не заливаем"

( cd "$TMP" && sha256sum "${UPLOAD[@]}" ) > "$TMP/sums.txt"
echo "==> files to deploy ($KIND $VER):"
sed 's/^/  /' "$TMP/sums.txt"

# ---- 1) файлы на все хосты, 2) проверка хеша на хосте -----------------------------------------------------------------
# имя:sha256 для проверки «не перезапишем ли мы на сервере другой файл с тем же именем»
EXPECT=()
while read -r sum name; do EXPECT+=("${name#\*}:$sum"); done < "$TMP/sums.txt"   # sha256sum на Windows ставит «*» перед именем

READY=()
for h in "$HOST" $MIRROR_HOSTS; do
  h=$(trim "$h")
  echo "==> uploading to $h"
  ok=1
  rsh "$h" "mkdir -p '$(remote_dir "$h")'" || ok=0
  if [ "$ok" = 1 ]; then
    # до заливки: правила выпуска (секция android заморожена после моста, версия не ниже текущей) — чтобы не плодить файлы-«сироты»;
    # и не перезапишем ли мы на сервере другой файл с тем же именем
    PRE=(precheck --kind "$KIND" --version "$VER")
    [ -z "${FORCE_REPLACE:-}" ] || PRE+=(--replace-ok)
    rtool "$h" "${PRE[@]}" "${EXPECT[@]}" || ok=0
  fi
  if [ "$ok" = 1 ]; then
    for f in "${UPLOAD[@]}"; do
      if rcopy "$h" "$TMP/$f"; then echo "  uploaded $f"; else ok=0; break; fi
    done
  fi
  if [ "$ok" = 1 ]; then
    if rsh "$h" "cd '$(remote_dir "$h")' && sha256sum -c --quiet -" < "$TMP/sums.txt"; then
      echo "  sha256 on $h: OK"
    else
      ok=0
    fi
  fi
  if [ "$ok" = 1 ]; then
    READY+=("$h")
  elif [ "$h" = "$HOST" ]; then
    die "основной хост $h: заливка или проверка SHA-256 не прошла — манифесты нигде не тронуты"
  else
    echo "WARNING: mirror $h: files not ready, its manifest stays as it was" >&2
  fi
done

# ---- 3) манифест, ссылки, ротация — только там, где файлы на месте -------------------------------------------------------
PUBLISH_ARGS=(publish --kind "$KIND" --version "$VER")
[ -z "$HOLD_FLAG" ] || PUBLISH_ARGS+=(--hold)
[ -z "${FORCE_REPLACE:-}" ] || PUBLISH_ARGS+=(--force)
for h in "${READY[@]}"; do
  echo "==> publish on $h ($KIND $VER$([ -n "$HOLD_FLAG" ] && echo ', HOLD'))"
  if ! rtool "$h" "${PUBLISH_ARGS[@]}"; then
    [ "$h" = "$HOST" ] && die "основной хост $h: публикация не удалась"
    echo "WARNING: mirror $h: publish failed, continuing" >&2
  fi
  # как и раньше: файлы раздачи принадлежат www-data (в сухом прогоне пропускаем)
  [ -n "$DRY" ] || rsh "$h" "chown -R www-data:www-data '$REMOTE' 2>/dev/null || true"
done

if [ -n "$HOLD_FLAG" ]; then
  echo "==> HOLD: latest.json не менялся, кэш не чистим. Включить: scripts/upload_release_to_server.sh activate all $VER"
else
  purge_cf
fi
echo "==> done, $KIND v$VER $([ -n "$HOLD_FLAG" ] && echo 'staged (hold)' || echo 'live at https://pixellnet.com/download')"
