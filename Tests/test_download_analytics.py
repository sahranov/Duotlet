import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, MagicMock

spec = importlib.util.spec_from_file_location("analytics", Path(__file__).resolve().parents[1] / "scripts/download-analytics.py")
analytics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analytics)


def snapshot(count=3, asset_id=1, time="2026-09-20T06:17:00+00:00"):
    return {"captured_at": time, "assets": [
        {"id": asset_id, "release": "v1", "name": "Duotlet.dmg", "downloads": count,
         "created_at": "2026-09-18T00:00:00Z", "package": True},
        {"id": 9, "release": "v1", "name": "SHA256SUMS.txt", "downloads": 99,
         "created_at": "2026-09-18T00:00:00Z", "package": False}]}


class DownloadAnalyticsTests(unittest.TestCase):
    def test_first_observation_is_not_daily_growth(self):
        self.assertIsNone(analytics.increase(snapshot(), None))
        self.assertEqual(analytics.total(snapshot()), 3)

    def test_repeats_and_gaps_measure_observation_interval(self):
        self.assertEqual(analytics.increase(snapshot(5), snapshot(3)), 2)
        self.assertEqual(analytics.increase(snapshot(3), snapshot(3)), 0)

    def test_reset_removed_or_replaced_asset_is_unknown(self):
        self.assertIsNone(analytics.increase(snapshot(1), snapshot(3)))
        self.assertIsNone(analytics.increase(snapshot(5, asset_id=2), snapshot(3)))
        self.assertIsNone(analytics.increase({"assets": []}, snapshot(3)))

    def test_newly_published_asset_can_be_counted(self):
        old = snapshot()
        new = snapshot(4)
        extra = dict(new["assets"][0], id=2, downloads=2, created_at="2026-09-20T08:00:00Z")
        new["assets"].append(extra)
        self.assertEqual(analytics.increase(new, old), 3)
        extra["created_at"] = "2026-09-18T00:00:00Z"
        self.assertIsNone(analytics.increase(new, old))

    def test_history_and_csv_preserved(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            analytics.save("sahranov/Duotlet", path, snapshot())
            latest = snapshot(5, time="2026-09-21T06:17:00+00:00")
            latest["assets"][0]["name"] = "=bad|name.dmg"
            report = analytics.save("sahranov/Duotlet", path, latest)
            data = json.loads((path / "history.json").read_text())
            self.assertEqual(len(data["snapshots"]), 2)
            self.assertIn("+2", report)
            self.assertIn("&#124;", report)
            self.assertIn("'=bad|name.dmg", (path / "downloads.csv").read_text())
            with self.assertRaises(ValueError):
                analytics.save("sahranov/Duotlet", path, latest)

    def test_api_pagination(self):
        def response(data):
            handle = MagicMock()
            handle.__enter__.return_value.read.return_value = json.dumps(data)
            return handle
        with patch.object(analytics, "urlopen", side_effect=[response([{}] * 100), response([{}])]) as api:
            self.assertEqual(len(analytics.api_list("repos/example/project/releases")), 101)
            self.assertIn("page=2", api.call_args.args[0].full_url)

    def test_api_failure_does_not_write_history(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)
            analytics.save("sahranov/Duotlet", path, snapshot())
            original = (path / "history.json").read_bytes()
            with patch("sys.argv", ["analytics", "--output-dir", tmp]), patch.object(analytics, "urlopen", side_effect=OSError("API unavailable")):
                with self.assertRaises(OSError):
                    analytics.main()
            self.assertEqual((path / "history.json").read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
