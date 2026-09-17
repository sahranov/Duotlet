import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from release_metadata import validate_release, version_tuple


class ReleaseMetadataTests(unittest.TestCase):
    def test_versions_are_numeric(self):
        self.assertGreater(version_tuple("0.10.0"), version_tuple("0.9.9"))

    def test_rejects_non_stable_or_apple_incompatible_versions(self):
        for version in ["v1.0.0", "1.0", "1.0.0-beta", "1.02.3", "-1.0.0", "0.0.0", "1.100.0"]:
            with self.subTest(version=version), self.assertRaises(ValueError):
                version_tuple(version)

    def test_rejects_duplicate_and_rollback(self):
        releases = [{"tag_name": "v0.3.0", "draft": False, "prerelease": False}]
        for version in ["0.2.0", "0.3.0"]:
            with self.subTest(version=version), self.assertRaises(ValueError):
                validate_release(version, releases)
        validate_release("0.4.0", releases)

    def test_drafts_and_development_releases_do_not_advance_stable(self):
        validate_release("0.2.0", [
            {"tag_name": "v0.3.0", "draft": True},
            {"tag_name": "dev", "prerelease": True},
        ])

    def test_unknown_stable_tag_does_not_silently_allow_rollback(self):
        with self.assertRaises(ValueError):
            validate_release("0.2.0", [{"tag_name": "release-1"}])

if __name__ == "__main__":
    unittest.main()
