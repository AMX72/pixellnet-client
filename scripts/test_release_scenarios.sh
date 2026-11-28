#!/usr/bin/env bash
# T-027 / А2.5 — сухой прогон выпуска и отката на ВРЕМЕННОЙ папке, имитирующей сервер (primary + mirror). Сервер не нужен,
# ssh/scp/Cloudflare/GitHub не вызываются: DRY_RUN_DIR + ASSETS_DIR (см. upload_release_to_server.sh).
#
# Сценарии: 1 обычный выпуск (как раньше) · 2 выпуск моста · 3 выпуск нового (подготовка --hold, включение) · 4 откат только
# android_app · 5 откат только android · 6 защиты (заморозка, теги -rc, подмена файла) · 7 сервер, где уже лежит старый
# latest.json (восстановление состояния) и порог версии 0.1.106.
# Запуск: bash scripts/test_release_scenarios.sh      Код выхода 0 = все проверки PASS.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UP="$ROOT/scripts/upload_release_to_server.sh"
W=$(mktemp -d)
if [ -n "${KEEP_TMP:-}" ]; then echo "временная папка (KEEP_TMP): $W"; else trap 'rm -rf "$W"' EXIT; fi
pypath() { cygpath -m "$1" 2>/dev/null || echo "$1"; }

export MIN_APK_BYTES=1000 KEEP_LAST=3 RELEASE_NOW=2026-12-10T12:00:00Z
export DRY_RUN_DIR="$W/srv"
FAILED=0

mkassets() { # <каталог> <legacy|bridge|app> <версия> [publish]
  local d="$1" kind="$2" ver="$3" pub="${4:-live}" pre=pixellnet abi
  [ "$kind" = app ] && pre=pxllnet
  rm -rf "$d"; mkdir -p "$d"
  for abi in arm64-v8a armeabi-v7a x86_64; do
    { printf 'PK\003\004'; printf '%s %s %s ' "$kind" "$ver" "$abi"; head -c 1500 /dev/urandom; } > "$d/$pre-$ver-app-$abi-release.apk"
  done
  { printf 'PK\003\004'; head -c 3000 /dev/urandom; } > "$d/$pre-$ver-app-release.apk"   # универсальный: не раздаём
  { printf 'PK\003\004'; printf 'win %s ' "$ver"; head -c 1500 /dev/urandom; } > "$d/pixellnet-windows-x64-$ver.zip"
  { printf 'MZ'; printf 'setup %s ' "$ver"; head -c 1500 /dev/urandom; } > "$d/pixellnet-setup-$ver.exe"
  if [ "$kind" != legacy ]; then
    printf '{"kind":"%s","package":"x","version":"%s","publish":"%s"}\n' "$kind" "$ver" "$pub" > "$d/android-kind.json"
  fi
}

release() { # <версия> <kind> [аргументы скрипта, например --hold]   (заново создаёт файлы релиза)
  local ver="$1" kind="$2"; shift 2
  mkassets "$W/assets" "$kind" "$ver"
  echo "  \$ upload_release_to_server.sh $* v$ver   (kind=$kind)"
  ASSETS_DIR="$W/assets" bash "$UP" "$@" "v$ver" 2>&1 | sed 's/^/    | /'
}

admin() { # <аргументы>
  echo "  \$ upload_release_to_server.sh $*"
  bash "$UP" "$@" 2>&1 | sed 's/^/    | /'
}

expect_fail() { # <регулярка в сообщении> <команда...>
  local pat="$1"; shift
  local out rc=0
  out=$("$@" 2>&1) || rc=$?
  if [ "$rc" != 0 ] && printf '%s' "$out" | grep -Eq "$pat"; then
    echo "  PASS отказ, как и должно быть: $(printf '%s' "$out" | grep -E "$pat" | head -1 | cut -c1-150)"
  else
    echo "  FAIL ожидали отказ с '$pat', получили rc=$rc:"; printf '%s\n' "$out" | tail -5 | sed 's/^/      /'
    FAILED=1
  fi
}

# chk <primary|mirror> "<что проверяем>" "<python-выражение: m = манифест, ex(имя) = файл есть, sha(имя), link(имя) = на что указывает ссылка>"
chk() {
  python3 -I -X utf8 - "$(pypath "$DRY_RUN_DIR/$1/www")" "$2" "$3" <<'PY' || FAILED=1
import hashlib, json, os, sys
D, desc, expr = sys.argv[1:4]
m = json.load(open(os.path.join(D, "latest.json"), encoding="utf-8"))
def ex(n): return os.path.exists(os.path.join(D, n))
def sha(n): return hashlib.sha256(open(os.path.join(D, n), "rb").read()).hexdigest()
def link(n):
    p = os.path.join(D, n)
    if os.path.islink(p): return os.path.basename(os.readlink(p))
    h = sha(n)  # копия вместо симлинка (Windows без прав): ищем файл с тем же содержимым
    for f in sorted(os.listdir(D)):
        q = os.path.join(D, f)
        if f != n and not f.startswith(".") and os.path.isfile(q) and not os.path.islink(q) and sha(f) == h:
            return f
def abi_only(sec): return set(m[sec]) <= {"arm64", "armv7", "x86_64"}
ok = bool(eval(expr))
print(("  PASS " if ok else "  FAIL ") + desc)
sys.exit(0 if ok else 1)
PY
}
both() { chk primary "$1 [primary]" "$2"; chk mirror "$1 [mirror]" "$2"; }

show() { # <primary|mirror>
  python3 -I -X utf8 - "$(pypath "$DRY_RUN_DIR/$1/www")" <<'PY'
import json, os, sys
D = sys.argv[1]
m = json.load(open(os.path.join(D, "latest.json"), encoding="utf-8"))
print("    latest.json: version=%s schema=%s published_at=%s" % (m["version"], m.get("schema"), m.get("published_at")))
for sec in ("android", "android_app", "migration", "windows"):
    if sec not in m:
        print("      %-11s —" % sec); continue
    v = m[sec]
    if sec == "migration":
        print("      %-11s %s" % (sec, json.dumps(v, ensure_ascii=False)))
    else:
        extra = {k: x for k, x in v.items() if not isinstance(x, dict)}
        files = {k: x["file"] for k, x in v.items() if isinstance(x, dict) and "file" in x}
        print("      %-11s %s %s" % (sec, extra or "", files))
print("    files: " + " ".join(sorted(f for f in os.listdir(D) if not f.startswith("."))))
PY
}
state() { # <primary|mirror>: снимки секций и заморозка из release_manifest.py show
  python3 -X utf8 "$ROOT/scripts/release_manifest.py" --root "$(pypath "$DRY_RUN_DIR/$1/www")" show | sed -n '1,/манифест, как он/p' | sed '$d' | sed 's/^/    state: /'
}
heading() { echo; echo "================ $* ================"; }
sha_of() { python3 -I -c "import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$(pypath "$DRY_RUN_DIR/primary/www/$1")"; }

# ============================================================================================================================
heading "1. ОБЫЧНЫЙ ВЫПУСК (как раньше): 0.1.102 … 0.1.105, ротация «хранить 3»"
for v in 0.1.102 0.1.103 0.1.104 0.1.105; do release "$v" legacy | tail -4; done
show primary
both "версия 0.1.105, секции только android и windows" "m['version']=='0.1.105' and 'android_app' not in m and 'migration' not in m and 'android' in m and 'windows' in m"
both "android — формат старых клиентов: только ключи ABI" "abi_only('android') and set(m['android'])=={'arm64','armv7','x86_64'}"
both "android.arm64: файл, размер, SHA-256 совпадают с диском" "m['android']['arm64']['file']=='pixellnet-0.1.105-arm64.apk' and m['android']['arm64']['sha256']==sha('pixellnet-0.1.105-arm64.apk')"
both "ссылка latest ведёт на 0.1.105" "link('pixellnet-latest-arm64.apk')=='pixellnet-0.1.105-arm64.apk' and link('pixellnet-setup-latest.exe')=='pixellnet-setup-0.1.105.exe'"
both "ротация: 0.1.102 удалена, 0.1.103-0.1.105 на месте" "not ex('pixellnet-0.1.102-arm64.apk') and not ex('pxl-win-v0.1.102.zip') and all(ex('pixellnet-0.1.%s-arm64.apk'%v) for v in ('103','104','105'))"
both "универсальный APK не раздаётся" "not any('app-release' in f for f in os.listdir(D))"

# ============================================================================================================================
heading "2. ВЫПУСК МОСТА 0.1.106 (kind=bridge, публикация сразу)"
release 0.1.106 bridge | tail -6
show primary
state primary
both "версия 0.1.106; android = файлы моста вне шаблона ротации" "m['version']=='0.1.106' and m['android']['arm64']['file']=='pixellnet-bridge-0.1.106-arm64.apk' and abi_only('android')"
both "windows 0.1.106 тоже обновился" "m['windows']['zip']['file']=='pxl-win-v0.1.106.zip'"
both "нового приложения в манифесте нет" "'android_app' not in m and 'migration' not in m"
both "latest.apk НЕ уехал на мост (остался на обычном 0.1.105)" "link('pixellnet-latest-arm64.apk')=='pixellnet-0.1.105-arm64.apk'"
both "все три файла моста на диске" "all(ex('pixellnet-bridge-0.1.106-%s.apk'%a) for a in ('arm64','armv7','x86_64'))"
ANDROID_BRIDGE_SHA=$(sha_of pixellnet-bridge-0.1.106-arm64.apk)
admin show | grep -E "заморожены" || true

# ============================================================================================================================
heading "3. ВЫПУСК НОВОГО ПРИЛОЖЕНИЯ 0.1.107 (kind=app): подготовка --hold, потом включение"
expect_fail "без опубликованного android_app" bash "$UP" migration --enabled true
release 0.1.107 app --hold | tail -6
both "HOLD: манифест не тронут (версия 0.1.106, нового приложения нет)" "m['version']=='0.1.106' and 'android_app' not in m and m['windows']['zip']['file']=='pxl-win-v0.1.106.zip'"
both "HOLD: файлы нового приложения уже на сервере" "ex('pxllnet-0.1.107-arm64.apk') and ex('pxllnet-0.1.107-armv7.apk') and ex('pxllnet-0.1.107-x86_64.apk')"
both "HOLD: ссылка latest.apk не двинулась" "link('pixellnet-latest-arm64.apk')=='pixellnet-0.1.105-arm64.apk'"
admin activate all 0.1.107 | tail -8
show primary
both "версия 0.1.107; android_app: пакет, версия, ABI" "m['version']=='0.1.107' and m['android_app']['package']=='com.pxllnet.app' and m['android_app']['version']=='0.1.107' and m['android_app']['arm64']['file']=='pxllnet-0.1.107-arm64.apk' and set(m['android_app'])=={'package','version','arm64','armv7','x86_64'}"
both "android (мост) заморожен и не изменился" "m['android']['arm64']['file']=='pixellnet-bridge-0.1.106-arm64.apk' and m['android']['arm64']['sha256']==sha('pixellnet-bridge-0.1.106-arm64.apk')"
both "latest.apk -> новое приложение" "link('pixellnet-latest-arm64.apk')=='pxllnet-0.1.107-arm64.apk'"
both "windows 0.1.107" "m['windows']['zip']['file']=='pxl-win-v0.1.107.zip'"
admin migration --enabled true --min-bridge-version 0.1.106 --remind-in-days 14 | tail -3
both "migration: enabled, min_bridge_version, дата срока К-2 (+14 дней)" "m['migration']=={'enabled': True, 'min_bridge_version': '0.1.106', 'remind_every_launch_from': '2026-12-24T12:00:00Z'}"
release 0.1.108 app | tail -4
both "выпуск 0.1.108: android_app 0.1.108, мост и migration не тронуты" "m['version']=='0.1.108' and m['android_app']['version']=='0.1.108' and m['android']['arm64']['file']=='pixellnet-bridge-0.1.106-arm64.apk' and m['migration']['enabled'] is True"
echo "  — повтор той же заливки (те же файлы) идемпотентен:"
ASSETS_DIR="$W/assets" bash "$UP" v0.1.108 2>&1 | tail -2 | sed 's/^/    | /'
both "после повтора всё то же" "m['version']=='0.1.108' and m['android_app']['version']=='0.1.108'"
admin verify | tail -3

# ============================================================================================================================
heading "4. ОТКАТ ТОЛЬКО android_app (0.1.108 -> 0.1.107, затем снять совсем, затем вернуть)"
WIN_ZIP_BEFORE=$(sha_of pxl-win-v0.1.108.zip)
admin rollback android_app | tail -4
show primary
both "android_app 0.1.107, остальное нетронуто (мост, windows 0.1.108, migration)" "m['android_app']['version']=='0.1.107' and m['android']['arm64']['file']=='pixellnet-bridge-0.1.106-arm64.apk' and m['windows']['zip']['file']=='pxl-win-v0.1.108.zip' and m['migration']['enabled'] is True"
both "верхний version не ниже 0.1.106 (здесь 0.1.108 от windows)" "tuple(map(int,m['version'].split('.')))>=(0,1,106)"
both "latest.apk -> 0.1.107" "link('pixellnet-latest-arm64.apk')=='pxllnet-0.1.107-arm64.apk'"
admin rollback android_app none | tail -5
both "новое приложение снято: секции android_app нет, мост на месте, migration авто-выключен" "'android_app' not in m and m['android']['arm64']['file']=='pixellnet-bridge-0.1.106-arm64.apk' and m['migration']['enabled'] is False"
both "latest.apk вернулся на последний обычный выпуск" "link('pixellnet-latest-arm64.apk')=='pixellnet-0.1.105-arm64.apk'"
both "версия не ниже 0.1.106 и без android_app" "tuple(map(int,m['version'].split('.')))>=(0,1,106)"
admin activate android_app 0.1.108 | tail -3
admin migration --enabled true --remind-in-days 14 | tail -2
both "вернули: android_app 0.1.108, migration включён" "m['android_app']['version']=='0.1.108' and m['migration']['enabled'] is True and link('pixellnet-latest-arm64.apk')=='pxllnet-0.1.108-arm64.apk'"
[ "$(sha_of pxl-win-v0.1.108.zip)" = "$WIN_ZIP_BEFORE" ] && echo "  PASS файл Windows за всё время не менялся" || { echo "  FAIL файл Windows изменился"; FAILED=1; }

# ============================================================================================================================
heading "5. ОТКАТ ТОЛЬКО android (мост): выпуск исправленного моста 0.1.109 -> откат на мост 0.1.106"
release 0.1.109 bridge | tail -4
both "android = мост 0.1.109, android_app и migration не тронуты" "m['android']['arm64']['file']=='pixellnet-bridge-0.1.109-arm64.apk' and m['android_app']['version']=='0.1.108' and m['migration']['enabled'] is True and m['version']=='0.1.109'"
admin rollback android | tail -3
show primary
both "android снова мост 0.1.106 (тот же SHA-256), android_app 0.1.108, windows 0.1.109, migration — как были" "m['android']['arm64']['file']=='pixellnet-bridge-0.1.106-arm64.apk' and m['android']['arm64']['sha256']=='$ANDROID_BRIDGE_SHA' and m['android_app']['version']=='0.1.108' and m['windows']['zip']['file']=='pxl-win-v0.1.109.zip' and m['migration']['enabled'] is True"
both "верхний version не ниже 0.1.106" "tuple(map(int,m['version'].split('.')))>=(0,1,106)"
both "latest.apk -> новое приложение 0.1.108" "link('pixellnet-latest-arm64.apk')=='pxllnet-0.1.108-arm64.apk'"
expect_fail "ДО моста" bash "$UP" rollback android 0.1.105
echo "  — ротация с KEEP_LAST=1: мост и ссылки целы, лишние обычные выпуски удаляются"
KEEP_LAST=1 bash "$UP" rotate 2>&1 | grep -c rotated | sed 's/^/    удалено файлов (primary+mirror): /' || true
both "после ротации KEEP=1: файлы моста 0.1.106 и 0.1.109 на месте" "all(ex('pixellnet-bridge-%s-%s.apk'%(v,a)) for v in ('0.1.106','0.1.109') for a in ('arm64','armv7','x86_64'))"
both "после ротации KEEP=1: цель latest.apk и файлы откатных снимков на месте" "ex('pxllnet-0.1.108-arm64.apk') and ex('pxllnet-0.1.107-arm64.apk') and ex('pixellnet-0.1.105-arm64.apk') and not ex('pixellnet-0.1.103-arm64.apk')"
admin verify | tail -3

# ============================================================================================================================
heading "6. ЗАЩИТЫ"
mkassets "$W/assets" legacy 0.1.110
expect_fail "заморожена" env ASSETS_DIR="$W/assets" bash "$UP" v0.1.110
both "отказ случился ДО заливки: файлов 0.1.110 на серверах нет" "not ex('pixellnet-0.1.110-arm64.apk') and not ex('pxl-win-v0.1.110.zip')"
expect_fail "не вида vX.Y.Z" bash "$UP" v0.1.110-rc1
expect_fail "не вида vX.Y.Z" bash "$UP" v0.1.110-beta
mkassets "$W/assets" bridge 0.1.109   # тот же выпуск моста, те же имена файлов, другие байты (подмена)
expect_fail "SHA-256 не совпал" env ASSETS_DIR="$W/assets" bash "$UP" v0.1.109
both "после отказа файлы моста 0.1.109 на сервере не перезаписаны (манифест ссылается на них же в истории)" "ex('pixellnet-bridge-0.1.109-arm64.apk') and m['windows']['zip']['sha256']==sha('pxl-win-v0.1.109.zip')"
mkassets "$W/assets" app 0.1.108
expect_fail "ниже текущей" env ASSETS_DIR="$W/assets" bash "$UP" v0.1.108
mkassets "$W/assets" app 0.1.111
rm "$W/assets/pixellnet-setup-0.1.111.exe"
echo "  \$ неполный релиз (нет Windows-установщика) -> ждём вторую платформу, ничего не трогаем"
ASSETS_DIR="$W/assets" bash "$UP" v0.1.111 2>&1 | grep -E "incomplete" | sed 's/^/    | /'
both "после неполного релиза 0.1.111 манифест прежний" "m['version']=='0.1.109' and not ex('pxllnet-0.1.111-arm64.apk')"
mkassets "$W/assets" app 0.1.112
printf 'MZ-not-an-apk' > "$W/assets/pxllnet-0.1.112-app-arm64-v8a-release.apk"
expect_fail "нет сигнатуры PK|слишком мал" env ASSETS_DIR="$W/assets" bash "$UP" v0.1.112
mkassets "$W/assets" app 0.1.113
printf '{"kind":"oops"}' > "$W/assets/android-kind.json"
expect_fail "не разобран" env ASSETS_DIR="$W/assets" bash "$UP" v0.1.113

# ============================================================================================================================
heading "7. СЕРВЕР, где уже лежит старый latest.json (состояния ещё нет) и порог 0.1.106"
export DRY_RUN_DIR="$W/srv2"
WWW="$DRY_RUN_DIR/primary/www"; mkdir -p "$WWW"
python3 -I -X utf8 - "$(pypath "$WWW")" <<'PY'
import hashlib, json, os, sys
D = sys.argv[1]
def put(name, data):
    open(os.path.join(D, name), "wb").write(data)
    return {"file": name, "size": len(data), "sha256": hashlib.sha256(data).hexdigest()}
m = {"version": "0.1.105", "published_at": "2026-11-27T11:58:00Z",
     "android": {"arm64": put("pixellnet-0.1.105-arm64.apk", b"PK\x03\x04old-arm64" * 200),
                 "armv7": put("pixellnet-0.1.105-armv7.apk", b"PK\x03\x04old-armv7" * 200),
                 "x86_64": put("pixellnet-0.1.105-x86_64.apk", b"PK\x03\x04old-x86" * 200)},
     "windows": {"zip": put("pxl-win-v0.1.105.zip", b"PK\x03\x04winzip" * 200),
                 "setup": put("pixellnet-setup-0.1.105.exe", b"MZsetup" * 200)}}
json.dump(m, open(os.path.join(D, "latest.json"), "w"), indent=2)
print("  подготовлен старый latest.json версии 0.1.105 (как писал прежний скрипт)")
PY
DRY_MIRRORS="" release 0.1.106 bridge | tail -3
chk primary "состояние восстановлено из старого манифеста: android был 0.1.105 (обычный), стал мост 0.1.106" "m['version']=='0.1.106' and m['android']['arm64']['file']=='pixellnet-bridge-0.1.106-arm64.apk' and ex('pixellnet-0.1.105-arm64.apk')"
DRY_MIRRORS="" admin rollback windows 0.1.105 | tail -2
chk primary "откат ТОЛЬКО windows на 0.1.105: версия всё равно не ниже 0.1.106, android не тронут" "m['version']=='0.1.106' and m['windows']['zip']['file']=='pxl-win-v0.1.105.zip' and m['android']['arm64']['file']=='pixellnet-bridge-0.1.106-arm64.apk'"
echo "  — маркер publish=hold внутри релиза (так будут идти теги этой ветки, .github/android-release-variant):"
mkassets "$W/assets" app 0.1.107 hold
DRY_MIRRORS="" ASSETS_DIR="$W/assets" bash "$UP" v0.1.107 2>&1 | grep -E "kind=|HOLD|staged" | sed 's/^/    | /'
chk primary "маркер hold: файлы нового приложения на сервере, манифест и ссылки не тронуты" "ex('pxllnet-0.1.107-arm64.apk') and m['version']=='0.1.106' and 'android_app' not in m and link('pixellnet-latest-arm64.apk')=='pixellnet-0.1.105-arm64.apk'"
DRY_MIRRORS="" admin verify | tail -2

echo
if [ "$FAILED" = 0 ]; then echo "ИТОГ: все проверки PASS"; else echo "ИТОГ: ЕСТЬ FAIL"; exit 1; fi
