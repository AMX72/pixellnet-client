#!/usr/bin/env python3
"""План сборок Android для .github/workflows/build-android.yml (T-027 / А2.5).

Читает окружение (EVENT_NAME, REF, REF_NAME, INPUT_VARIANT, INPUT_SIDE_BY_SIDE),
файл .github/android-release-variant и android/pixellnet-identities.properties,
печатает в stdout строки для $GITHUB_OUTPUT: `matrix=<json>`.
Человеческая сводка — в stderr (и в шаг Summary).

Правила (по порядку):
  1. workflow_dispatch с явным variant (bridge | app | pair) — как просили; pair = мост + новое, обе пробные копии .mig.
  2. тег v*            — один пакет: тот, что записан в .github/android-release-variant (по умолчанию legacy = как до моста).
  3. ветка rc/**       — один пакет без суффикса («как настоящий»), без выпуска и без заливки.
  4. ветка feat/bridge-*, feat/app-*, feat/mig-* — ПАРА β: com.pixellnet.vpn.mig + com.pxllnet.app.mig.
  5. прочие feat/** (и dispatch с side_by_side) — как раньше: com.pixellnet.vpn.core5, «PIXELLNET β».
  6. остальное         — как раньше: com.pixellnet.vpn без суффикса, без выпуска.
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
VARIANT_FILE = os.path.join(ROOT, ".github", "android-release-variant")
IDENTITIES_FILE = os.path.join(ROOT, "android", "pixellnet-identities.properties")
PAIR_BRANCH = re.compile(r"^feat/(bridge|app|mig)(-|$)")
KINDS = ("legacy", "bridge", "app")


def read_properties(path):
    props = {}
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            props[k.strip()] = v.strip()
    return props


def read_variant_file(path=VARIANT_FILE):
    cfg = {"variant": "legacy", "publish": "live"}
    if os.path.isfile(path):
        cfg.update(read_properties(path))
    if cfg["variant"] not in KINDS:
        raise SystemExit("android-release-variant: variant=%r, ожидалось одно из %s" % (cfg["variant"], KINDS))
    if cfg["publish"] not in ("live", "hold"):
        raise SystemExit("android-release-variant: publish=%r, ожидалось live или hold" % cfg["publish"])
    return cfg


def entry(kind, suffix, release, publish, identities):
    """Одна сборка. kind: legacy | bridge | app."""
    mode = "app" if kind == "app" else "bridge"  # режим Gradle (pixellnetMode); legacy = bridge по умолчанию
    base_package = identities[mode + ".package"]
    if kind == "legacy":
        # «как раньше»: метка PIXELLNET (в .core5 — «PIXELLNET β»); без явной метки Gradle поставил бы «PIXELLNET (старое)» моста
        label = "PIXELLNET β" if suffix else "PIXELLNET"
    else:
        label = ""  # метку по режиму считает Gradle
    # метка, которую должен показать aapt в готовом APK (сверяет scripts/ci_verify_apk.sh)
    expect_label = label or (identities[mode + ".label"] + (" β" if suffix else ""))
    if kind == "legacy":
        artifact = "pixellnet-android-apk"  # имя не меняем: на него могут ссылаться старые скрипты
        ident = "legacy" + (suffix.replace(".", "-") if suffix else "")
    else:
        ident = kind + (suffix.replace(".", "-") if suffix else "")
        artifact = "pixellnet-android-" + ident
    return {
        "id": ident,
        "kind": kind,
        "mode": mode,
        "suffix": suffix,
        "label": label,
        # Имена файлов в GitHub Release: мост — как раньше (старый клиент ходит за ними по имени, это его запасной путь),
        # новое приложение — своё имя, чтобы не перепутать.
        "asset_prefix": "pxllnet" if kind == "app" else "pixellnet",
        "artifact": artifact,
        "release": "true" if release else "false",
        "publish": publish,
        "expect_cert": mode,  # какой отпечаток ждём в APK: bridge = v2, app = v3
        "expect_package": base_package + suffix,
        "expect_label": expect_label,
    }


def plan(env, variant_cfg, identities):
    event = env.get("EVENT_NAME", "")
    ref = env.get("REF", "")
    name = env.get("REF_NAME", "")
    dispatch_variant = (env.get("INPUT_VARIANT") or "auto").strip()
    side_by_side = (env.get("INPUT_SIDE_BY_SIDE") or "").strip().lower() == "true"
    file_kind = variant_cfg["variant"]
    publish = variant_cfg["publish"]
    is_tag = ref.startswith("refs/tags/v")

    def pair():
        return [
            entry("bridge", ".mig", False, "live", identities),
            entry("app", ".mig", False, "live", identities),
        ]

    if event == "workflow_dispatch" and dispatch_variant != "auto":
        if dispatch_variant == "pair":
            return pair()
        if dispatch_variant not in ("bridge", "app"):
            raise SystemExit("INPUT_VARIANT=%r не понят" % dispatch_variant)
        return [entry(dispatch_variant, ".mig" if side_by_side else "", False, "live", identities)]
    if is_tag:
        return [entry(file_kind, "", True, publish, identities)]
    if ref.startswith("refs/heads/rc/"):
        return [entry(file_kind if file_kind != "legacy" else "bridge", "", False, "live", identities)]
    if ref.startswith("refs/heads/feat/") and PAIR_BRANCH.match(name):
        return pair()
    if ref.startswith("refs/heads/feat/") or side_by_side:
        return [entry("legacy", ".core5", False, "live", identities)]
    return [entry("legacy", "", False, "live", identities)]


def main():
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    cfg = read_variant_file()
    identities = read_properties(IDENTITIES_FILE)
    items = plan(os.environ, cfg, identities)
    matrix = {"include": items}
    print("matrix=" + json.dumps(matrix, ensure_ascii=True, separators=(",", ":")))
    lines = ["План сборки Android (%d):" % len(items)]
    for it in items:
        lines.append(
            "  - %s: пакет %s, режим Gradle %s, суффикс '%s', выпуск=%s, публикация=%s, отпечаток=%s"
            % (it["id"], it["expect_package"], it["mode"], it["suffix"], it["release"], it["publish"], it["expect_cert"])
        )
    text = "\n".join(lines)
    sys.stderr.write(text + "\n")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("```\n" + text + "\n```\n")


if __name__ == "__main__":
    main()
