"""Tests for tools/homebrew_cask.py (python3 -I -m unittest discover -s tools -p 'test_*.py')."""

from __future__ import annotations

import contextlib
import hashlib
import io
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import homebrew_cask  # noqa: E402

DIGEST = "ab" * 32


class RenderTests(unittest.TestCase):
    def test_pins_version_and_checksum(self) -> None:
        cask = homebrew_cask.render("0.3.0", DIGEST.upper())

        self.assertIn('cask "vsvibe" do', cask)
        self.assertIn('version "0.3.0"', cask)
        self.assertIn(f'sha256 "{DIGEST}"', cask)
        self.assertIn("releases/download/v#{version}/VSVibe-#{version}.dmg", cask)
        self.assertIn('app "VSVibe.app"', cask)
        self.assertIn("auto_updates true", cask)
        self.assertIn("depends_on macos: :sequoia", cask)
        self.assertIn('"~/Library/Preferences/com.shyrochuk.vsvibe.plist"', cask)
        self.assertTrue(cask.endswith("end\n"))

    def test_is_deterministic(self) -> None:
        self.assertEqual(homebrew_cask.render("1.2.3", DIGEST), homebrew_cask.render("1.2.3", DIGEST))

    def test_rejects_bad_input(self) -> None:
        for version, digest in [("v0.3.0", DIGEST), ("0.3", DIGEST), ("0.3.0", "xyz"), ("0.3.0", DIGEST + "0")]:
            with self.subTest(version=version, digest=digest), self.assertRaises(homebrew_cask.CaskError):
                homebrew_cask.render(version, digest)


class CliTests(unittest.TestCase):
    def test_checksums_the_dmg_and_writes_the_cask(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            dmg = Path(tmp) / "VSVibe-0.3.0.dmg"
            dmg.write_bytes(b"not really a dmg")
            out = Path(tmp) / "Casks" / "vsvibe.rb"

            code = homebrew_cask.run(["--version", "0.3.0", "--dmg", str(dmg), "--out", str(out)])

            self.assertEqual(code, 0)
            expected = hashlib.sha256(b"not really a dmg").hexdigest()
            self.assertEqual(out.read_text(encoding="utf-8"), homebrew_cask.render("0.3.0", expected))

    def test_writes_to_stdout(self) -> None:
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            code = homebrew_cask.run(["--version", "0.3.0", "--sha256", DIGEST, "--out", "-"])

        self.assertEqual(code, 0)
        self.assertEqual(stdout.getvalue(), homebrew_cask.render("0.3.0", DIGEST))

    def test_reports_errors(self) -> None:
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            bad_version = homebrew_cask.run(["--version", "x", "--sha256", DIGEST, "--out", "-"])
            missing_dmg = homebrew_cask.run(["--version", "0.3.0", "--dmg", "/nonexistent.dmg", "--out", "-"])

        self.assertEqual((bad_version, missing_dmg), (1, 1))
        self.assertIn("error:", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
