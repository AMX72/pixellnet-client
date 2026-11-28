#!/usr/bin/env python3
"""Тесты плана сборок Android (scripts/ci_plan_android.py). Запуск: python3 scripts/test_ci_plan_android.py -v"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ci_plan_android as p  # noqa: E402

IDENT = p.read_properties(p.IDENTITIES_FILE)


def run(event, ref, variant=None, sbs=None, file_variant="legacy", publish="live"):
    env = {
        "EVENT_NAME": event,
        "REF": ref,
        "REF_NAME": ref.split("/", 2)[-1],
        "INPUT_VARIANT": variant or "",
        "INPUT_SIDE_BY_SIDE": "true" if sbs else "",
    }
    return p.plan(env, {"variant": file_variant, "publish": publish}, IDENT)


class PlanTests(unittest.TestCase):
    def test_feat_core5_keeps_old_behaviour(self):
        # feat/core-5.9.1 и любая обычная feat/** — как до T-027: один пакет .core5, метка «PIXELLNET β», без выпуска
        for br in ("feat/core-5.9.1", "feat/languages-0.1.106", "feat/key-switch-reconnect"):
            items = run("push", "refs/heads/" + br)
            self.assertEqual(len(items), 1, br)
            it = items[0]
            self.assertEqual((it["kind"], it["mode"], it["suffix"], it["label"]), ("legacy", "bridge", ".core5", "PIXELLNET β"))
            self.assertEqual(it["expect_package"], "com.pixellnet.vpn.core5")
            self.assertEqual(it["release"], "false")
            self.assertEqual(it["artifact"], "pixellnet-android-apk")

    def test_pair_branches(self):
        for br in ("feat/bridge-0.1.106", "feat/app-0.1.107", "feat/mig-test"):
            items = run("push", "refs/heads/" + br, file_variant="bridge", publish="hold")
            self.assertEqual([i["kind"] for i in items], ["bridge", "app"], br)
            self.assertEqual([i["expect_package"] for i in items], ["com.pixellnet.vpn.mig", "com.pxllnet.app.mig"])
            self.assertEqual([i["expect_cert"] for i in items], ["bridge", "app"])
            self.assertEqual([i["expect_label"] for i in items], ["PIXELLNET (старое) β", "PXLLNET β"])
            self.assertTrue(all(i["release"] == "false" and i["suffix"] == ".mig" for i in items))
            self.assertEqual(len({i["artifact"] for i in items}), 2)

    def test_pair_branch_regex_is_not_greedy(self):
        # feat/bridging-something и feat/application-x — не пара
        self.assertEqual(run("push", "refs/heads/feat/bridging-x")[0]["suffix"], ".core5")
        self.assertEqual(run("push", "refs/heads/feat/application-x")[0]["suffix"], ".core5")

    def test_rc_branch_no_suffix_no_release(self):
        it = run("push", "refs/heads/rc/0.1.106", file_variant="bridge")[0]
        self.assertEqual((it["kind"], it["suffix"], it["release"]), ("bridge", "", "false"))
        self.assertEqual(it["expect_package"], "com.pixellnet.vpn")
        it = run("push", "refs/heads/rc/0.1.107", file_variant="app")[0]
        self.assertEqual((it["kind"], it["expect_package"], it["release"]), ("app", "com.pxllnet.app", "false"))
        it = run("push", "refs/heads/rc/x", file_variant="legacy")[0]
        self.assertEqual(it["kind"], "bridge")

    def test_tag_uses_variant_file(self):
        it = run("push", "refs/tags/v0.1.106", file_variant="bridge", publish="hold")[0]
        self.assertEqual((it["kind"], it["release"], it["publish"], it["asset_prefix"]), ("bridge", "true", "hold", "pixellnet"))
        it = run("push", "refs/tags/v0.1.107", file_variant="app", publish="live")[0]
        self.assertEqual((it["kind"], it["release"], it["publish"], it["asset_prefix"]), ("app", "true", "live", "pxllnet"))
        self.assertEqual(it["expect_package"], "com.pxllnet.app")
        self.assertEqual((it["expect_cert"], it["expect_label"]), ("app", "PXLLNET"))
        it = run("push", "refs/tags/v0.1.105")[0]  # без файла = как раньше
        self.assertEqual((it["kind"], it["release"], it["suffix"], it["expect_package"]), ("legacy", "true", "", "com.pixellnet.vpn"))
        self.assertEqual((it["label"], it["expect_label"]), ("PIXELLNET", "PIXELLNET"))

    def test_rc_tag_builds_real_packages(self):
        it = run("push", "refs/tags/v0.1.106-rc1", file_variant="bridge")[0]
        self.assertEqual((it["suffix"], it["expect_package"]), ("", "com.pixellnet.vpn"))

    def test_dispatch(self):
        self.assertEqual([i["kind"] for i in run("workflow_dispatch", "refs/heads/main", variant="pair")], ["bridge", "app"])
        it = run("workflow_dispatch", "refs/heads/main", variant="app", sbs=True)[0]
        self.assertEqual((it["expect_package"], it["release"]), ("com.pxllnet.app.mig", "false"))
        it = run("workflow_dispatch", "refs/heads/main", variant="bridge")[0]
        self.assertEqual(it["expect_package"], "com.pixellnet.vpn")
        # auto + side_by_side на обычной ветке — как раньше (.core5)
        it = run("workflow_dispatch", "refs/heads/main", variant="auto", sbs=True)[0]
        self.assertEqual(it["suffix"], ".core5")
        # auto без side_by_side — как раньше: пакет без суффикса, без выпуска
        it = run("workflow_dispatch", "refs/heads/main", variant="auto")[0]
        self.assertEqual((it["suffix"], it["release"]), ("", "false"))

    def test_variant_file_validation(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf-8") as f:
            f.write("# c\nvariant=bridgee\n")
        try:
            with self.assertRaises(SystemExit):
                p.read_variant_file(f.name)
        finally:
            os.unlink(f.name)
        self.assertEqual(p.read_variant_file("/nonexistent/file"), {"variant": "legacy", "publish": "live"})


if __name__ == "__main__":
    unittest.main()
