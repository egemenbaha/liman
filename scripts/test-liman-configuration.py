#!/usr/bin/env python3
"""Verify fork identity, update isolation and retained notices without publishing."""
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("configure_updates", ROOT / "scripts/configure-updates.py")
configuration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(configuration)

class ForkConfigurationTests(unittest.TestCase):
    def test_disabled_configuration_removes_inherited_trust(self):
        for filename in ("Updates.plist", "Updates.public.plist"):
            with self.subTest(filename=filename), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "Info.plist"
                info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
                inherited = ("SUFeedURL", "SUPublicEDKey", "NashiPublicUpdateRepository", "NashiSuggestedGitHubRepository", "NashiLocalUpdateFeed")
                info.update({key: "fixture" for key in inherited})
                path.write_bytes(plistlib.dumps(info))
                configuration.apply_configuration(path, ROOT / "Configuration" / filename, {})
                actual = plistlib.loads(path.read_bytes())
                self.assertTrue(actual["LimanLocalOnly"])
                self.assertFalse(actual["SUEnableAutomaticChecks"])
                self.assertTrue(actual["SURequireSignedFeed"])
                self.assertTrue(actual["SUVerifyUpdateBeforeExtraction"])
                self.assertFalse(any(key in actual for key in inherited))

    def test_distinct_bundle_identity(self):
        info = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleIdentifier"], "local.liman.filetoolkit")
        self.assertEqual(info["CFBundleName"], "Liman")
        self.assertEqual(info["CFBundleExecutable"], "Liman")
        self.assertNotIn("SUPublicEDKey", info)

    def test_upstream_license_and_notices_unchanged(self):
        revision = "295c74f79f0313e89ad1542fe39e8fd4c64c88b2"
        for name in ("LICENSE", "Resources/THIRD-PARTY-NOTICES.txt", "windows/THIRD-PARTY-NOTICES.txt"):
            with self.subTest(name=name):
                original = subprocess.check_output(["git", "show", f"{revision}:{name}"], cwd=ROOT)
                self.assertEqual(original, (ROOT / name).read_bytes())

    def test_no_publishing_workflow_enabled(self):
        files = list((ROOT / ".github/workflows").glob("*"))
        self.assertEqual([p.name for p in files], ["liman-security.yml"])
        text = files[0].read_text()
        self.assertNotIn("contents: write", text)
        self.assertNotIn("pull_request_target", text)

if __name__ == "__main__":
    unittest.main()
