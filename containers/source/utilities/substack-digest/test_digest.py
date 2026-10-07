import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from datetime import datetime, timedelta, timezone

import digest

NOW = datetime(2026, 10, 7, 11, tzinfo=timezone.utc)
CONFIG = {"first_run_hours": 24, "overlap_hours": 48, "timezone": "America/Los_Angeles", "folder": "/Substack Daily", "local_retention_days": 30}


def post(identifier, date=NOW):
    return {"id": identifier, "publication_id": 1, "post_date": date.isoformat(), "title": "A title", "canonical_url": "https://example.substack.com/p/article"}


class DigestTests(unittest.TestCase):
    def test_subscription_metadata_cannot_add_recommendations(self):
        result = digest.subscription_publications({"subscriptions": [{"publication_id": 1}], "publications": [{"id": 1}, {"id": 999}]})
        self.assertEqual([p["id"] for p, _ in result], [1])
        with self.assertRaises(ValueError):
            digest.subscription_publications({"subscriptions": [], "publications": []})

    def test_archive_pagination_overlap_dates_and_no_article_cap(self):
        calls = []
        def get(url, params):
            calls.append(params["offset"])
            return {0: [post(i) for i in range(20)], 20: [post(i) for i in range(19, 39)], 40: [post(40, NOW - timedelta(days=5))]}[params["offset"]]
        items = list(digest.archive_posts(get, {"id": 1, "subdomain": "example"}, NOW - timedelta(days=1), NOW))
        self.assertEqual(len(items), 39)
        self.assertEqual(calls, [0, 20, 40])

    def test_stuck_pagination_and_wrong_publication_fail(self):
        with self.assertRaises(ValueError):
            list(digest.archive_posts(lambda *a: [post(1)], {"id": 1, "subdomain": "example"}, NOW, NOW))
        with self.assertRaises(ValueError):
            list(digest.archive_posts(lambda *a: [post(1)], {"id": 2, "subdomain": "example"}, NOW, NOW))

    def test_failed_upload_reuses_outbox_and_does_not_advance_cutoff(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = Path(tmp)
            collected = []
            def collect(since, until, delivered):
                collected.append((since, until))
                return [{"post": post(1)}]
            def render(articles, config, title, path):
                path.write_bytes(b"fixture PDF")
            def fail(*args):
                raise RuntimeError("upload unavailable")
            with self.assertRaises(RuntimeError):
                digest.run(CONFIG, data, collect, render, fail, NOW)
            self.assertEqual(digest.timestamp(json.loads((data / "state.json").read_text())["cutoff"]), NOW - timedelta(days=1))
            self.assertTrue((data / "pending.json").exists())
            uploaded = []
            digest.run(CONFIG, data, collect, render, lambda pdf, folder: uploaded.append(pdf.read_bytes()), NOW + timedelta(days=1))
            self.assertEqual(len(collected), 1)
            self.assertEqual(uploaded, [b"fixture PDF"])
            state = json.loads((data / "state.json").read_text())
            self.assertEqual(state["cutoff"], NOW.isoformat())
            self.assertIn("1", state["delivered"])
            self.assertFalse((data / "pending.json").exists())

    def test_first_failure_freezes_initial_boundary(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = Path(tmp)
            def fail(*args):
                raise RuntimeError("network")
            with self.assertRaises(RuntimeError):
                digest.run(CONFIG, data, fail, fail, fail, NOW)
            captured = []
            digest.run(CONFIG, data, lambda since, *a: captured.append(since) or [], fail, fail, NOW + timedelta(days=3))
            self.assertEqual(captured, [NOW - timedelta(days=1)])

    def test_empty_interval_does_not_upload_and_next_run_overlaps(self):
        with tempfile.TemporaryDirectory() as tmp:
            data = Path(tmp)
            def forbidden(*args):
                self.fail("Empty digest should neither render nor upload")
            digest.run(CONFIG, data, lambda *a: [], forbidden, forbidden, NOW)
            cutoffs = []
            digest.run(CONFIG, data, lambda since, *a: cutoffs.append(since) or [], forbidden, forbidden, NOW + timedelta(days=1))
            self.assertEqual(cutoffs, [NOW - timedelta(hours=48)])

    def test_existing_upload_is_never_replaced(self):
        with patch.object(digest, "rmapi", side_effect=[None, [{"visibleName": "daily", "type": "DocumentType"}]]) as client:
            digest.deliver(Path("daily.pdf"), "/Substack Daily")
            self.assertEqual([c.args[0] for c in client.call_args_list], ["mkdir", "ls"])


if __name__ == "__main__":
    unittest.main()
