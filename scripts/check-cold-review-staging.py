#!/usr/bin/env python3
"""Regression checks for live-source staging, isolation and per-spawn archives (#98)."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class StagingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.run = Path(self.tmp.name).resolve() / "run"
        self.cp = self.run / "checkpoints"
        self.ctx = self.cp / "01-context"
        self.ctx.mkdir(parents=True)
        for name, raw in {"spec.md": b"spec v1", "plan.md": b"plan v1",
                          "state.json": b"{}", "slice.md": b"slice v1"}.items():
            (self.run / name).write_bytes(raw)
        self.files = {"bundle.md": [str(self.run / n) for n in ("spec.md", "plan.md")],
                      "state.json": [str(self.run / "state.json")],
                      "log-slice.md": [str(self.run / "slice.md")]}

    def stage(self, spawn="01-1", action="stage", success=True, mode="routine"):
        (self.cp / "01-review-sources.json").write_text(json.dumps({"files": self.files}))
        p = subprocess.run([sys.executable, str(ROOT / "scripts/stage-cold-review.py"),
                            str(ROOT), str(self.run), str(self.ctx), "01", spawn,
                            "bundle.md", mode, action], capture_output=True, text=True)
        self.assertEqual(p.returncode, 0 if success else 1, p.stderr)
        return p.stderr

    def test_rebuilds_sources_preserves_previous_round_and_removes_stale_files(self):
        self.stage()
        first = self.cp / "01-1-reviewer-context"
        old = (first / "bundle.md").read_bytes()
        (self.run / "plan.md").write_text("plan revised by human")
        (self.run / "state.json").write_text('{"revision":2}')
        (self.run / "slice.md").write_text("slice v2")
        (self.ctx / "obsolete.md").write_text("old artifact")
        self.stage("01-2")
        expected = b"spec v1\nplan revised by human"
        self.assertEqual((self.ctx / "bundle.md").read_bytes(), expected)
        self.assertEqual((self.ctx / "artifact.sha256").read_text(),
                         hashlib.sha256(expected).hexdigest() + "  bundle.md\n")
        self.assertEqual((self.ctx / "state.json").read_text(), '{"revision":2}')
        self.assertFalse((self.ctx / "obsolete.md").exists())
        self.assertEqual((first / "bundle.md").read_bytes(), old)
        self.assertEqual((self.cp / "01-1-log-slice.md").read_bytes(), b"slice v1")
        self.assertEqual((self.cp / "01-2-log-slice.md").read_bytes(), b"slice v2")
        self.assertEqual([p.name for p in self.ctx.glob("*log-slice*")], ["log-slice.md"])

    def test_resume_keeps_the_consumed_packet_when_sources_change(self):
        self.stage()
        (self.run / "spec.md").write_text("changed while Task in flight")
        self.stage(action="resume")
        self.assertEqual((self.ctx / "bundle.md").read_bytes(), b"spec v1\nplan v1")
        (self.ctx / "state.json").write_text('{"changed":true}')
        self.assertIn("archived packet mismatch", self.stage(action="resume", success=False))

    def test_reused_spawn_cannot_overwrite_archive(self):
        self.stage()
        (self.run / "slice.md").write_text("changed")
        self.assertIn("already exists", self.stage(success=False))
        self.assertEqual((self.cp / "01-1-log-slice.md").read_bytes(), b"slice v1")

    def test_missing_source_fails_before_archive_or_packet_replacement(self):
        (self.ctx / "sentinel").write_text("keep")
        (self.run / "plan.md").unlink()
        self.stage(success=False)
        self.assertTrue((self.ctx / "sentinel").exists())
        self.assertFalse((self.cp / "01-1-reviewer-context").exists())

    def test_staged_source_and_archive_sources_are_refused(self):
        self.stage()
        self.files["bundle.md"] = [str(self.ctx / "bundle.md")]
        self.assertIn("staged copy", self.stage("01-2", success=False))
        self.files["bundle.md"] = [str(self.cp / "01-1-reviewer-context/bundle.md")]
        self.assertIn("prior review archive", self.stage("01-2", success=False))

    def test_derived_slice_names_and_full_history_are_refused(self):
        for name in ("log-slice.01-1.md", "old-LOG-SLICE.md", "nested/log-slice.md",
                     "log.md", "transcript.md", "01-verdict.md", "../escape"):
            with self.subTest(name=name):
                self.files[name] = [str(self.run / "slice.md")]
                self.stage(success=False)
                del self.files[name]

    def test_integration_evidence_is_fresh_and_not_an_artifact(self):
        self.stage(success=False, mode="integration")
        (self.run / "gate.json").write_text('{"gates":[]}')
        self.files["integration-results.json"] = [str(self.run / "gate.json")]
        self.files["gate-output/test.log"] = [str(self.run / "slice.md")]
        self.stage(mode="integration")
        self.assertNotIn("gate-output", (self.ctx / "artifacts.sha256").read_text())
        self.assertTrue((self.cp / "01-1-reviewer-context/gate-output/test.log").exists())
        self.stage("01-2", success=False)  # routine cannot inherit integration evidence

    def test_symlink_source_and_unsafe_context_are_refused(self):
        (self.run / "plan.md").unlink()
        (self.run / "plan.md").symlink_to(self.run / "spec.md")
        self.stage(success=False)
        self.ctx = self.run
        self.stage(success=False)


if __name__ == "__main__":
    unittest.main()
