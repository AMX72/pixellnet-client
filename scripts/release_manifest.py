#!/usr/bin/env python3
"""Манифест выпусков latest.json: состояние по секциям, публикация, откат (T-027 / А2.5, проект переезда §3.2, С-14).

Запускается НА СЕРВЕРЕ (и на зеркалах) скриптом scripts/upload_release_to_server.sh через ssh:
    python3 - --root /var/www/pixellnet-downloads <команда> ...  < release_manifest.py
и локально на временной папке в тестах (scripts/test_release_scenarios.sh). Только стандартная библиотека, Python 3.6+.

Секции latest.json (независимы, у каждой своя история и свой «текущий» снимок):
    android      мост 0.1.106 (старый пакет com.pixellnet.vpn); после выхода моста ЗАМОРОЖЕНА: другие выпуски её не двигают.
                 Формат как у старых клиентов: только ключи ABI (arm64, armv7, x86_64) -> {file, size, sha256}.
    android_app  новое приложение (com.pxllnet.app): package, version, ABI -> {file, size, sha256}
    migration    enabled, min_bridge_version, remind_every_launch_from (дата, с которой мост напоминает при каждом запуске, К-2)
    windows      zip, setup -> {file, size, sha256}
Верхний `version` = максимум версий текущих секций android/android_app/windows; пока в android лежит мост — НИКОГДА не ниже
MIN_TOP_VERSION (0.1.106), иначе клиенты 0.1.104/0.1.105 перестанут видеть мост. (До моста порога нет: клиент 0.1.105 не должен
видеть «0.1.106» поверх файлов 0.1.105.)

Состояние — <state-dir>/state.json (по умолчанию <root>.state, вне веб-каталога): все снимки секций (файлы + SHA-256),
указатель текущего снимка каждой секции, список замороженных секций, журнал. Манифест всегда собирается из текущих снимков.

Команды:
    publish --kind legacy|bridge|app --version X.Y.Z [--hold] [--no-windows] [--force] [--allow-downgrade]
    activate <секция|all> <версия>        сделать снимок текущим (для held-выпуска; all = все секции этой версии)
    rollback <секция> [<версия>|previous|none]   откат ОДНОЙ секции (none — только android_app: снять новое приложение)
    migration [--enabled true|false] [--min-bridge-version X] [--remind-from ДАТА | --remind-in-days N | --remind-clear]
    freeze|unfreeze <секция>
    rotate [--keep N]
    precheck [--kind K --version V] имя:sha256 ...   до заливки: правила выпуска (заморозка, версия не ниже текущей) и нет ли на
                              сервере файлов с теми же именами, но другим SHA-256 (защита от тихой перезаписи и от «сирот»)
    verify          файлы текущих секций на месте, размер и SHA-256 = манифесту; манифест = состоянию; version >= MIN_TOP_VERSION
    show
"""
import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import sys

for _stream in (sys.stdout, sys.stderr):  # русские сообщения не должны ломаться на консоли с другой кодировкой
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8", errors="replace")

try:
    import fcntl  # Linux (сервер, CI); на Windows блокировки нет — это только локальные тесты
except ImportError:  # pragma: no cover
    fcntl = None

BRIDGE_PACKAGE = "com.pixellnet.vpn"
APP_PACKAGE = "com.pxllnet.app"
MIN_TOP_VERSION = os.environ.get("MIN_TOP_VERSION", "0.1.106")
MIN_BRIDGE_VERSION = "0.1.106"
ABIS = ("arm64", "armv7", "x86_64")
SECTIONS = ("android", "android_app", "migration", "windows")
FILE_SECTIONS = ("android", "android_app", "windows")
SEMVER = re.compile(r"^\d+\.\d+\.\d+$")
MIN_APK_BYTES = int(os.environ.get("MIN_APK_BYTES", "0"))  # на сервере проверяет скрипт-обёртка; здесь можно ужесточить

ROTATION_GROUPS = [
    # (имя, шаблон, группа внутри шаблона = ABI)
    ("apk", re.compile(r"^pixellnet-(\d+\.\d+\.\d+)-(arm64|armv7|x86_64)\.apk$"), True),
    ("app-apk", re.compile(r"^pxllnet-(\d+\.\d+\.\d+)-(arm64|armv7|x86_64)\.apk$"), True),
    ("setup", re.compile(r"^pixellnet-setup-(\d+\.\d+\.\d+)\.exe$"), False),
    ("win-zip", re.compile(r"^pxl-win-v(\d+\.\d+\.\d+)\.zip$"), False),
]


def die(msg):
    sys.stderr.write("ERROR: %s\n" % msg)
    sys.exit(1)


def say(msg):
    sys.stdout.write(msg + "\n")


def now():
    return os.environ.get("RELEASE_NOW") or datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def vtuple(v):
    if not SEMVER.match(v):
        die("версия %r не вида X.Y.Z" % v)
    return tuple(int(x) for x in v.split("."))


def snap_key(section, ver):
    if section == "migration":
        return (int(ver[1:]),)
    return vtuple(ver)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def file_entry(root, name, min_bytes=0):
    path = os.path.join(root, name)
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        die("файл %s отсутствует или пуст в %s" % (name, root))
    size = os.path.getsize(path)
    if min_bytes and size < min_bytes:
        die("файл %s слишком мал (%d < %d байт)" % (name, size, min_bytes))
    return {"file": name, "size": size, "sha256": sha256_file(path)}


def apk_name(kind, ver, abi):
    if kind == "legacy":
        return "pixellnet-%s-%s.apk" % (ver, abi)
    if kind == "bridge":
        return "pixellnet-bridge-%s-%s.apk" % (ver, abi)  # вне шаблона ротации (см. ROTATION_GROUPS)
    if kind == "app":
        return "pxllnet-%s-%s.apk" % (ver, abi)
    die("неизвестный kind %r" % kind)


def abi_entries(root, kind, ver):
    out = {}
    for abi in ABIS:
        name = apk_name(kind, ver, abi)
        if abi == "arm64":
            out[abi] = file_entry(root, name, MIN_APK_BYTES)
        elif os.path.isfile(os.path.join(root, name)):
            out[abi] = file_entry(root, name, MIN_APK_BYTES)
    return out


def build_android_data(root, kind, ver):
    return abi_entries(root, kind, ver)


def build_app_data(root, ver):
    data = {"package": APP_PACKAGE, "version": ver}
    data.update(abi_entries(root, "app", ver))
    return data


def build_windows_data(root, ver):
    return {
        "zip": file_entry(root, "pxl-win-v%s.zip" % ver),
        "setup": file_entry(root, "pixellnet-setup-%s.exe" % ver),
    }


def file_entries(data):
    """Все записи с файлами внутри данных секции."""
    return [v for v in data.values() if isinstance(v, dict) and "file" in v]


# ---------------------------------------------------------------- состояние

def empty_state():
    return {"schema": 1, "current": {}, "frozen": [], "sections": {s: {} for s in SECTIONS}, "log": []}


class Locked(object):
    def __init__(self, state_dir):
        self.path = os.path.join(state_dir, ".lock")
        self.fh = None

    def __enter__(self):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        self.fh = open(self.path, "a")
        if fcntl:
            fcntl.flock(self.fh, fcntl.LOCK_EX)
        return self

    def __exit__(self, *a):
        if self.fh:
            if fcntl:
                fcntl.flock(self.fh, fcntl.LOCK_UN)
            self.fh.close()


def state_path(sd):
    return os.path.join(sd, "state.json")


def load_state(root, sd):
    p = state_path(sd)
    if os.path.isfile(p):
        with open(p, encoding="utf-8") as f:
            st = json.load(f)
        for s in SECTIONS:
            st["sections"].setdefault(s, {})
        return st
    return bootstrap(root)


def save_state(st, sd):
    os.makedirs(sd, exist_ok=True)
    p = state_path(sd)
    if os.path.isfile(p):
        shutil.copy2(p, p + ".bak")
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(st, f, indent=2, ensure_ascii=False, sort_keys=True)
    os.replace(tmp, p)


def log(st, action, **kw):
    entry = {"at": now(), "action": action}
    entry.update(kw)
    st["log"].append(entry)
    del st["log"][:-200]


def bootstrap(root):
    """Первого состояния нет: берём то, что уже лежит в latest.json (до моста это обычный выпуск «как раньше»)."""
    st = empty_state()
    path = os.path.join(root, "latest.json")
    if not os.path.isfile(path):
        return st
    with open(path, encoding="utf-8") as f:
        m = json.load(f)
    ver = str(m.get("version", "")).lstrip("v")
    if not SEMVER.match(ver):
        return st
    if m.get("android"):
        st["sections"]["android"][ver] = {"version": ver, "kind": "legacy", "saved_at": now(), "data": m["android"]}
        st["current"]["android"] = ver
    if m.get("windows"):
        st["sections"]["windows"][ver] = {"version": ver, "kind": "windows", "saved_at": now(), "data": m["windows"]}
        st["current"]["windows"] = ver
    if m.get("android_app"):
        av = str(m["android_app"].get("version", ver))
        st["sections"]["android_app"][av] = {"version": av, "kind": "app", "saved_at": now(), "data": m["android_app"]}
        st["current"]["android_app"] = av
    if m.get("migration"):
        st["sections"]["migration"]["r1"] = {"version": "r1", "kind": "settings", "saved_at": now(), "data": m["migration"]}
        st["current"]["migration"] = "r1"
    log(st, "bootstrap", note="состояние восстановлено из существующего latest.json (версия %s)" % ver)
    return st


def cur_snap(st, sec):
    v = st["current"].get(sec)
    return st["sections"][sec][v] if v else None


def sorted_versions(st, sec):
    return sorted(st["sections"][sec], key=lambda v: snap_key(sec, v))


def set_current(st, sec, ver, why):
    prev = st["current"].get(sec)
    if ver is None:
        st["current"].pop(sec, None)
    else:
        st["current"][sec] = ver
        if st["sections"][sec][ver].get("kind") == "bridge" and "android" not in st["frozen"] and sec == "android":
            st["frozen"].append("android")
            log(st, "freeze", section="android", note="после выхода моста секция android заморожена")
    log(st, why, section=sec, from_version=prev, to_version=ver)


# ---------------------------------------------------------------- манифест, ссылки, ротация

def top_version(st):
    """max версий текущих секций; пока в секции android лежит мост — не ниже MIN_TOP_VERSION (0.1.106).

    До выхода моста порог не действует: иначе клиент 0.1.105 увидит «0.1.106» поверх файлов 0.1.105 и будет «обновляться» на себя.
    """
    vs = []
    for sec in ("android", "android_app", "windows"):
        s = cur_snap(st, sec)
        if s:
            vs.append(s["version"])
    android = cur_snap(st, "android")
    if android and android["kind"] == "bridge":
        vs.append(MIN_TOP_VERSION)
    return max(vs, key=vtuple) if vs else "0.0.0"


def assemble(st, published_at=None):
    m = {"version": top_version(st), "schema": 2, "published_at": published_at or now()}
    for sec in ("android", "android_app", "migration", "windows"):
        s = cur_snap(st, sec)
        if s:
            m[sec] = s["data"]
    return m


def write_manifest(root, sd, st):
    path = os.path.join(root, "latest.json")
    os.makedirs(sd, exist_ok=True)
    if os.path.isfile(path):
        shutil.copy2(path, os.path.join(sd, "latest.prev.json"))
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(assemble(st), f, indent=2, ensure_ascii=False)
    os.replace(tmp, path)
    return path


def put_link(root, name, target):
    link = os.path.join(root, name)
    tmp = os.path.join(root, ".%s.tmp" % name)
    for p in (tmp,):
        if os.path.lexists(p):
            os.remove(p)
    try:
        os.symlink(target, tmp)
    except (OSError, NotImplementedError, AttributeError):  # Windows без прав на симлинки: только локальные тесты
        shutil.copy2(os.path.join(root, target), tmp)
    os.replace(tmp, link)


def desired_links(root, st):
    links = {}
    app = cur_snap(st, "android_app")
    android = cur_snap(st, "android")
    if app and "arm64" in app["data"]:
        links["pixellnet-latest-arm64.apk"] = app["data"]["arm64"]["file"]
    elif android and android["kind"] == "legacy":
        links["pixellnet-latest-arm64.apk"] = android["data"]["arm64"]["file"]
    elif android and android["kind"] == "bridge":
        # нового приложения нет (не выпущено или снято): «последний APK» остаётся последним обычным выпуском до моста
        for v in reversed(sorted_versions(st, "android")):
            s = st["sections"]["android"][v]
            if s["kind"] == "legacy" and os.path.isfile(os.path.join(root, s["data"]["arm64"]["file"])):
                links["pixellnet-latest-arm64.apk"] = s["data"]["arm64"]["file"]
                break
    win = cur_snap(st, "windows")
    if win:
        links["pixellnet-setup-latest.exe"] = win["data"]["setup"]["file"]
        links["pixellnet-windows-latest.zip"] = win["data"]["zip"]["file"]
    return links


def update_links(root, st):
    for name, target in sorted(desired_links(root, st).items()):
        put_link(root, name, target)
        say("  link %s -> %s" % (name, target))


def protected_files(root, st):
    prot = set()
    for sec in FILE_SECTIONS:
        vs = sorted_versions(st, sec)
        cur = st["current"].get(sec)
        keep_versions = set()
        if cur:
            keep_versions.add(cur)
            before = [v for v in vs if snap_key(sec, v) < snap_key(sec, cur)]
            if before:
                keep_versions.add(before[-1])  # цель отката «previous»
        if vs:
            keep_versions.add(vs[-1])  # самый новый (в том числе подготовленный и ещё не включённый)
        if sec == "android":
            keep_versions.update(v for v in vs if st["sections"][sec][v]["kind"] == "bridge")  # мост не ротируется никогда
        for v in keep_versions:
            for e in file_entries(st["sections"][sec][v]["data"]):
                prot.add(e["file"])
    for n in os.listdir(root):
        p = os.path.join(root, n)
        if os.path.islink(p):
            prot.add(os.path.basename(os.readlink(p)))
    for target in desired_links(root, st).values():
        prot.add(target)
    return prot


def rotate(root, st, keep):
    prot = protected_files(root, st)
    groups = {}
    for n in os.listdir(root):
        p = os.path.join(root, n)
        if os.path.islink(p) or not os.path.isfile(p):
            continue
        for gname, rx, by_abi in ROTATION_GROUPS:
            m = rx.match(n)
            if m:
                key = (gname, m.group(2) if by_abi else "")
                groups.setdefault(key, []).append((vtuple(m.group(1)), n))
                break
    removed = []
    for key, items in sorted(groups.items()):
        items.sort()
        for _, n in items[:-keep] if keep > 0 else []:
            if n in prot:
                continue
            os.remove(os.path.join(root, n))
            removed.append(n)
            say("  rotated: %s" % n)
    return removed


def finalize(root, sd, st, keep, action):
    """Живые изменения: ссылки, затем манифест (последним), затем состояние, затем ротация."""
    update_links(root, st)
    path = write_manifest(root, sd, st)
    save_state(st, sd)
    rotate(root, st, keep)
    say("  latest.json -> version %s (%s)" % (top_version(st), action))
    return path


# ---------------------------------------------------------------- проверка снимков

def verify_entries(root, data, label):
    problems = []
    for e in file_entries(data):
        p = os.path.join(root, e["file"])
        if not os.path.isfile(p):
            problems.append("%s: нет файла %s" % (label, e["file"]))
        elif os.path.getsize(p) != e["size"]:
            problems.append("%s: размер %s = %d, в манифесте %d" % (label, e["file"], os.path.getsize(p), e["size"]))
        elif sha256_file(p) != e["sha256"]:
            problems.append("%s: SHA-256 %s не совпал с манифестом" % (label, e["file"]))
    return problems


# ---------------------------------------------------------------- команды

def args_paths(a):
    root = os.path.abspath(a.root)
    sd = os.path.abspath(a.state_dir) if a.state_dir else root.rstrip("/\\") + ".state"
    return root, sd


def sections_of(kind, no_windows=False):
    secs = ["android" if kind in ("legacy", "bridge") else "android_app"]
    if not no_windows:
        secs.append("windows")
    return secs


def check_publish_rules(st, kind, ver, allow_downgrade=False, no_windows=False):
    """Правила выпуска — те же до заливки файлов (precheck) и при публикации."""
    vtuple(ver)
    if kind == "bridge" and vtuple(ver) < vtuple(MIN_BRIDGE_VERSION):
        die("мост не может быть ниже %s (получено %s)" % (MIN_BRIDGE_VERSION, ver))
    if "android" in sections_of(kind, no_windows) and "android" in st["frozen"] and kind != "bridge":
        die("секция android заморожена (вышел мост): выпуск %s её не двигает. Нужен именно выпуск моста "
            "или явное `unfreeze android`" % ver)
    for sec in sections_of(kind, no_windows):
        cur = st["current"].get(sec)
        if cur and vtuple(ver) < vtuple(cur) and not allow_downgrade:
            die("версия %s ниже текущей %s в секции %s (Android не ставит меньший versionCode). "
                "Для отката — команда rollback; для публикации старой версии — --allow-downgrade" % (ver, cur, sec))


def cmd_publish(a):
    root, sd = args_paths(a)
    ver = a.version
    with Locked(sd):
        st = load_state(root, sd)
        check_publish_rules(st, a.kind, ver, a.allow_downgrade, a.no_windows)
        new = {}
        if a.kind in ("legacy", "bridge"):
            new["android"] = (a.kind, build_android_data(root, a.kind, ver))
        else:
            new["android_app"] = ("app", build_app_data(root, ver))
        if not a.no_windows:
            new["windows"] = ("windows", build_windows_data(root, ver))
        for sec, (kind, data) in new.items():
            old = st["sections"][sec].get(ver)
            if old and old["data"] != data and not a.force:
                die("версия %s секции %s уже сохранена с другими файлами (SHA-256 не совпал). Это подмена файла? "
                    "Если так и задумано — --force" % (ver, sec))
            st["sections"][sec][ver] = {"version": ver, "kind": kind, "saved_at": now(), "data": data}
            say("  snapshot %s %s (%s): %s" % (sec, ver, kind, ", ".join(e["file"] for e in file_entries(data))))
        if a.hold:
            log(st, "stage", sections=sorted(new), version=ver, kind=a.kind)
            save_state(st, sd)
            say("  HOLD: файлы и снимки сохранены, latest.json и ссылки НЕ тронуты. Включить: activate all %s" % ver)
            return
        for sec in new:
            set_current(st, sec, ver, "publish")
        finalize(root, sd, st, a.keep, "publish %s %s" % (a.kind, ver))


def resolve_target(st, sec, target):
    cur = st["current"].get(sec)
    vs = sorted_versions(st, sec)
    if target == "none":
        if sec not in ("android_app", "migration"):
            die("none разрешён только для android_app (снять новое приложение) и migration")
        return None
    if target in (None, "previous"):
        cands = [v for v in vs if cur is None or snap_key(sec, v) < snap_key(sec, cur)]
        if sec == "android" and "android" in st["frozen"]:
            cands = [v for v in cands if st["sections"][sec][v]["kind"] == "bridge"]
        if not cands:
            die("у секции %s нет более раннего снимка для отката" % sec)
        return cands[-1]
    if target not in st["sections"][sec]:
        die("у секции %s нет снимка %s (есть: %s)" % (sec, target, ", ".join(vs) or "—"))
    return target


def cmd_switch(a):
    root, sd = args_paths(a)
    with Locked(sd):
        st = load_state(root, sd)
        if a.section == "all":
            if a.cmd != "activate" or not a.target:
                die("activate all <версия>")
            secs = [s for s in FILE_SECTIONS if a.target in st["sections"][s]]
            if not secs:
                die("нет ни одной секции со снимком %s" % a.target)
            for s in secs:
                switch_one(root, st, s, a.target, a.force, a.cmd)
        else:
            if a.section not in SECTIONS:
                die("секция %r не из %s" % (a.section, ", ".join(SECTIONS)))
            if a.cmd == "activate" and not a.target:
                die("activate <секция> <версия>")
            switch_one(root, st, a.section, a.target, a.force, a.cmd)
        if not st["current"].get("android_app"):
            mig = cur_snap(st, "migration")
            if mig and mig["data"].get("enabled"):
                data = dict(mig["data"])
                data["enabled"] = False
                rev = add_migration_rev(st, data, "migration-auto-off")
                say("  migration %s: enabled -> false (нового приложения в манифесте больше нет, мосту нечего предлагать)" % rev)
        finalize(root, sd, st, a.keep, a.cmd)
    for p in verify_all(root, sd, st):
        say("  WARNING: " + p)


def switch_one(root, st, sec, target, force, action):
    ver = resolve_target(st, sec, target)
    if ver is not None:
        snap = st["sections"][sec][ver]
        if sec == "android" and snap["kind"] == "legacy" and "android" in st["frozen"] and not force:
            die("откат секции android на выпуск ДО моста (%s) вернёт старым клиентам старый пакет; нужен --force" % ver)
        problems = verify_entries(root, snap["data"], "%s %s" % (sec, ver)) if sec in FILE_SECTIONS else []
        if problems:
            die("откат/включение %s %s невозможно: %s" % (sec, ver, "; ".join(problems)))
    set_current(st, sec, ver, action)
    say("  %s: %s -> %s" % (sec, st["log"][-1].get("from_version"), ver))


def add_migration_rev(st, data, why):
    n = max([int(v[1:]) for v in st["sections"]["migration"]] or [0]) + 1
    rev = "r%d" % n
    st["sections"]["migration"][rev] = {"version": rev, "kind": "settings", "saved_at": now(), "data": data}
    set_current(st, "migration", rev, why)
    return rev


def cmd_migration(a):
    root, sd = args_paths(a)
    with Locked(sd):
        st = load_state(root, sd)
        cur = cur_snap(st, "migration")
        data = dict(cur["data"]) if cur else {"enabled": False, "min_bridge_version": MIN_BRIDGE_VERSION, "remind_every_launch_from": None}
        if a.enabled is not None:
            on = a.enabled == "true"
            if on and not st["current"].get("android_app") and not a.force:
                die("migration.enabled=true без опубликованного android_app: мосту нечего предложить (--force, если нужно)")
            data["enabled"] = on
        if a.min_bridge_version:
            vtuple(a.min_bridge_version)
            data["min_bridge_version"] = a.min_bridge_version
        if a.remind_clear:
            data["remind_every_launch_from"] = None
        if a.remind_from:
            d = datetime.datetime.strptime(a.remind_from[:10], "%Y-%m-%d")
            data["remind_every_launch_from"] = d.strftime("%Y-%m-%dT00:00:00Z")
        if a.remind_in_days is not None:
            t = datetime.datetime.strptime(now(), "%Y-%m-%dT%H:%M:%SZ") + datetime.timedelta(days=a.remind_in_days)
            data["remind_every_launch_from"] = t.strftime("%Y-%m-%dT%H:%M:%SZ")
        rev = add_migration_rev(st, data, "migration")
        say("  migration %s: %s" % (rev, json.dumps(data, ensure_ascii=False)))
        finalize(root, sd, st, a.keep, "migration")


def cmd_precheck(a):
    """Файлы с такими именами уже на сервере с ДРУГИМ SHA-256? Тогда заливка их перезапишет (подмена или другая сборка той же версии)."""
    root, sd = args_paths(a)
    if a.kind and a.version:
        check_publish_rules(load_state(root, sd), a.kind, a.version, a.allow_downgrade)
    bad = []
    for pair in ([] if a.replace_ok else a.expect):
        name, _, want = pair.rpartition(":")
        p = os.path.join(root, name)
        if os.path.isfile(p) and sha256_file(p) != want:
            bad.append(name)
    if bad:
        die("на сервере уже лежат другие файлы с теми же именами (SHA-256 не совпал): %s. Перезаписывать нельзя: это подмена "
            "или другая сборка той же версии, а манифест может на них ссылаться. Если так и задумано — FORCE_REPLACE=1" % ", ".join(bad))
    say("  precheck OK: %d файл(ов) новые или те же" % len(a.expect))


def cmd_freeze(a):
    root, sd = args_paths(a)
    with Locked(sd):
        st = load_state(root, sd)
        if a.cmd == "freeze" and a.section not in st["frozen"]:
            st["frozen"].append(a.section)
        elif a.cmd == "unfreeze" and a.section in st["frozen"]:
            st["frozen"].remove(a.section)
        log(st, a.cmd, section=a.section)
        save_state(st, sd)
        say("  frozen: %s" % (", ".join(st["frozen"]) or "—"))


def cmd_rotate(a):
    root, sd = args_paths(a)
    with Locked(sd):
        st = load_state(root, sd)
        removed = rotate(root, st, a.keep)
        say("  rotate: удалено %d" % len(removed))


def verify_all(root, sd, st):
    problems = []
    for sec in FILE_SECTIONS:
        s = cur_snap(st, sec)
        if s:
            problems += verify_entries(root, s["data"], "%s %s" % (sec, s["version"]))
    path = os.path.join(root, "latest.json")
    if not os.path.isfile(path):
        problems.append("нет latest.json")
    else:
        with open(path, encoding="utf-8") as f:
            disk = json.load(f)
        want = assemble(st, disk.get("published_at"))
        if disk != want:
            problems.append("latest.json на диске не равен собранному из состояния (правили руками?)")
        android = cur_snap(st, "android")
        if android and android["kind"] == "bridge" and vtuple(str(disk.get("version", "0.0.0"))) < vtuple(MIN_TOP_VERSION):
            problems.append("верхний version %s ниже %s при мосте в секции android" % (disk.get("version"), MIN_TOP_VERSION))
    for name, target in desired_links(root, st).items():
        p = os.path.join(root, name)
        if not os.path.exists(p):
            problems.append("ссылка %s не ведёт на существующий файл" % name)
        elif os.path.isfile(os.path.join(root, target)) and sha256_file(p) != sha256_file(os.path.join(root, target)):
            problems.append("ссылка %s ведёт не на %s" % (name, target))
    return problems


def cmd_verify(a):
    root, sd = args_paths(a)
    st = load_state(root, sd)
    problems = verify_all(root, sd, st)
    for p in problems:
        sys.stderr.write("VERIFY FAIL: %s\n" % p)
    if problems:
        sys.exit(1)
    say("verify OK: версия %s, секции: %s" % (top_version(st), ", ".join("%s=%s" % (s, v) for s, v in sorted(st["current"].items()))))


def cmd_show(a):
    root, sd = args_paths(a)
    st = load_state(root, sd)
    say("root: %s\nstate: %s\nзаморожены: %s" % (root, sd, ", ".join(st["frozen"]) or "—"))
    for sec in SECTIONS:
        parts = []
        for v in sorted_versions(st, sec):
            mark = "*" if st["current"].get(sec) == v else " "
            parts.append("%s%s[%s]" % (mark, v, st["sections"][sec][v]["kind"]))
        say("  %-12s %s" % (sec, " ".join(parts) or "—"))
    say("манифест, как он будет собран сейчас:")
    say(json.dumps(assemble(st), indent=2, ensure_ascii=False))


def build_parser():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--root", required=True, help="каталог раздачи (на сервере /var/www/pixellnet-downloads)")
    ap.add_argument("--state-dir", help="каталог состояния (по умолчанию <root>.state)")
    ap.add_argument("--keep", type=int, default=int(os.environ.get("KEEP_LAST", "3")), help="сколько версий хранить при ротации")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("publish")
    p.add_argument("--kind", required=True, choices=["legacy", "bridge", "app"])
    p.add_argument("--version", required=True)
    p.add_argument("--hold", action="store_true")
    p.add_argument("--no-windows", action="store_true")
    p.add_argument("--force", action="store_true")
    p.add_argument("--allow-downgrade", action="store_true")
    p.set_defaults(fn=cmd_publish)

    for name in ("activate", "rollback"):
        p = sub.add_parser(name)
        p.add_argument("section")
        p.add_argument("target", nargs="?")
        p.add_argument("--force", action="store_true")
        p.set_defaults(fn=cmd_switch)

    p = sub.add_parser("migration")
    p.add_argument("--enabled", choices=["true", "false"])
    p.add_argument("--min-bridge-version")
    p.add_argument("--remind-from")
    p.add_argument("--remind-in-days", type=int)
    p.add_argument("--remind-clear", action="store_true")
    p.add_argument("--force", action="store_true")
    p.set_defaults(fn=cmd_migration)

    for name in ("freeze", "unfreeze"):
        p = sub.add_parser(name)
        p.add_argument("section", choices=list(SECTIONS))
        p.set_defaults(fn=cmd_freeze)

    p = sub.add_parser("precheck")
    p.add_argument("--kind", choices=["legacy", "bridge", "app"])
    p.add_argument("--version")
    p.add_argument("--allow-downgrade", action="store_true")
    p.add_argument("--replace-ok", action="store_true", help="перезапись файлов с другим SHA-256 разрешена (FORCE_REPLACE=1)")
    p.add_argument("expect", nargs="+", help="имя:sha256")
    p.set_defaults(fn=cmd_precheck)

    sub.add_parser("rotate").set_defaults(fn=cmd_rotate)
    sub.add_parser("verify").set_defaults(fn=cmd_verify)
    sub.add_parser("show").set_defaults(fn=cmd_show)
    return ap


def main(argv=None):
    a = build_parser().parse_args(argv)
    a.fn(a)


if __name__ == "__main__":
    main()
