"""Exercise actual macOS code requirements across two builds, without touching TCC."""
import importlib.util
import os
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("identity", ROOT / "scripts/verify-install-identity.py")
identity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(identity)


class InstallIdentityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="duotlet-signature-")
        self.addCleanup(self.temp.cleanup)
        self.previous = self.make_app("previous", "1")
        self.updated = self.make_app("updated", "2")

    def make_app(self, name, version, identifier="app.duotlet.SignatureRegression", signing_identity="-"):
        app = Path(self.temp.name) / (name + ".app")
        macos = app / "Contents/MacOS"
        macos.mkdir(parents=True)
        shutil.copyfile("/usr/bin/true", macos / "Fixture")
        (macos / "Fixture").chmod(0o755)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": identifier, "CFBundleExecutable": "Fixture",
            "CFBundlePackageType": "APPL", "CFBundleVersion": version,
        }))
        signed = subprocess.run(["/usr/bin/codesign", "--force", "--timestamp=none", "--sign", signing_identity, str(app)],
                                text=True, capture_output=True)
        if signed.returncode:
            raise ValueError(signed.stderr.strip())
        return app

    def test_unchanged_build_satisfies_previous_identity(self):
        copy = Path(self.temp.name) / "copy.app"
        shutil.copytree(self.previous, copy)
        identity.verify_continuity(self.previous, copy)

    def test_rebuild_no_longer_matches_permission_identity(self):
        with self.assertRaisesRegex(ValueError, "requirement"):
            identity.verify_continuity(self.previous, self.updated)

    def test_install_rejects_ad_hoc_even_for_first_install(self):
        with self.assertRaisesRegex(ValueError, "Ad-hoc"):
            identity.verify_install(self.updated)

    def test_install_does_not_replace_previous(self):
        before = (self.previous / "Contents/_CodeSignature/CodeResources").read_bytes()
        with self.assertRaises(ValueError):
            identity.verify_install(self.updated, self.previous)
        self.assertEqual(before, (self.previous / "Contents/_CodeSignature/CodeResources").read_bytes())
        identity.verify_continuity(self.previous, self.previous)

    def test_bundle_rename_is_not_an_update(self):
        renamed = self.make_app("renamed", "2", "app.duotlet.Other")
        with self.assertRaisesRegex(ValueError, "bundle identifier"):
            identity.verify_continuity(self.previous, renamed)

    def test_build_refuses_ad_hoc_install_before_compiling(self):
        environment = dict(os.environ, SIGN_IDENTITY="-", SWIFT="/usr/bin/false",
                           DUOTLET_BUNDLE=str(self.previous))
        result = subprocess.run(["bash", str(ROOT / "build.sh"), "--run"],
                                env=environment, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Installation requires SIGN_IDENTITY", result.stderr)
        identity.verify_continuity(self.previous, self.previous)

    @unittest.skipUnless(os.environ.get("DUOTLET_TEST_SIGNING_IDENTITY"), "No signing identity configured")
    def test_real_signed_rebuild_preserves_identity(self):
        signer = os.environ["DUOTLET_TEST_SIGNING_IDENTITY"]
        previous = self.make_app("signed-previous", "1", signing_identity=signer)
        updated = self.make_app("signed-updated", "2", signing_identity=signer)
        identity.verify_install(updated, previous)


if __name__ == "__main__":
    unittest.main()
