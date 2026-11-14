#!/usr/bin/env python3
"""Unit tests for tools/appcast.py.

    python3 -I -m unittest discover -s tools -p 'test_*.py'
"""

from __future__ import annotations

import contextlib
import io
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import appcast  # noqa: E402  (path set up above)

CHANGELOG = """# Changelog

## [Unreleased]

## [0.2.0] - 2026-11-14

### Added

- **Auto-updates** via `Sparkle`, see [docs](https://example.com/a?b=1&c=2).
- A wrapped bullet that
  continues here.

Some *closing* words <script>.

## [0.1.0]

- First.

[0.2.0]: https://github.com/Mc231/vsvibe/releases/tag/v0.2.0
"""

LAST = """## [0.3.0]
- Newest.

[0.3.0]: https://example.com
"""


def item_args(version: str, build: int, signature: str = "sig") -> dict[str, object]:
    return {
        "version": version,
        "build": build,
        "url": f"https://github.com/Mc231/vsvibe/releases/download/v{version}/VSVibe-{version}.dmg",
        "length": 1000 + build,
        "ed_signature": signature,
        "notes_html": f"<p>{version}</p>",
        "pub_date": "Sat, 14 Nov 2026 12:00:00 GMT",
    }


class ChangelogTests(unittest.TestCase):
    def test_extracts_section_until_next_heading(self) -> None:
        section = appcast.changelog_section(CHANGELOG, "0.2.0")
        self.assertTrue(section.startswith("### Added"))
        self.assertIn("continues here.", section)
        self.assertNotIn("0.1.0", section)
        self.assertNotIn("First.", section)

    def test_stops_at_link_references(self) -> None:
        self.assertEqual(appcast.changelog_section(LAST, "0.3.0"), "- Newest.")

    def test_missing_section_fails(self) -> None:
        with self.assertRaisesRegex(appcast.ReleaseError, r"no '## \[9.9.9\]'"):
            appcast.changelog_section(CHANGELOG, "9.9.9")

    def test_version_is_matched_exactly(self) -> None:
        with self.assertRaises(appcast.ReleaseError):
            appcast.changelog_section("## [0.2.01]\n- x\n", "0.2.0")
        with self.assertRaises(appcast.ReleaseError):
            appcast.changelog_section("## [0x2x0]\n- x\n", "0.2.0")

    def test_empty_section_fails(self) -> None:
        with self.assertRaisesRegex(appcast.ReleaseError, "empty"):
            appcast.changelog_section(CHANGELOG, "Unreleased")

    def test_repository_changelog_has_a_release_section(self) -> None:
        text = (Path(__file__).resolve().parent.parent / "CHANGELOG.md").read_text(encoding="utf-8")
        self.assertIn("Automatic updates", appcast.changelog_section(text, "0.2.0"))


class MarkdownTests(unittest.TestCase):
    def test_converts_headings_lists_paragraphs_and_inline(self) -> None:
        out = appcast.markdown_to_html(appcast.changelog_section(CHANGELOG, "0.2.0"))
        self.assertIn("<h3>Added</h3>", out)
        self.assertIn("<li><strong>Auto-updates</strong> via <code>Sparkle</code>", out)
        self.assertIn('<a href="https://example.com/a?b=1&amp;c=2">docs</a>', out)
        self.assertIn("<li>A wrapped bullet that continues here.</li>", out)
        self.assertIn("<p>Some <em>closing</em> words &lt;script&gt;.</p>", out)
        self.assertNotIn("<script>", out)

    def test_bullet_after_paragraph_starts_a_list(self) -> None:
        self.assertEqual(appcast.markdown_to_html("Intro\n- one\n* two"), "<p>Intro</p>\n<ul><li>one</li><li>two</li></ul>")

    def test_non_http_links_stay_text(self) -> None:
        self.assertEqual(appcast.markdown_to_html("[x](javascript:alert(1))"), "<p>[x](javascript:alert(1))</p>")


class AppcastTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tree = appcast.new_appcast()

    def items(self) -> list[ET.Element]:
        return self.tree.getroot().findall("channel/item")

    def short_versions(self) -> list[str | None]:
        return [i.findtext(appcast.sparkle("shortVersionString")) for i in self.items()]

    def test_item_carries_every_sparkle_field(self) -> None:
        item = appcast.make_item(**item_args("0.2.0", 42, "ED=="))  # type: ignore[arg-type]
        self.assertEqual(item.findtext("title"), "Version 0.2.0")
        self.assertEqual(item.findtext(appcast.sparkle("version")), "42")
        self.assertEqual(item.findtext(appcast.sparkle("shortVersionString")), "0.2.0")
        self.assertEqual(item.findtext(appcast.sparkle("minimumSystemVersion")), "15.0")
        self.assertEqual(item.findtext("description"), "<p>0.2.0</p>")
        enclosure = item.find("enclosure")
        assert enclosure is not None
        self.assertEqual(enclosure.get("length"), "1042")
        self.assertEqual(enclosure.get(appcast.sparkle("edSignature")), "ED==")
        self.assertTrue(enclosure.get("url", "").endswith("/v0.2.0/VSVibe-0.2.0.dmg"))

    def test_default_pub_date_is_rfc822(self) -> None:
        args = item_args("0.2.0", 1)
        args["pub_date"] = None
        item = appcast.make_item(**args)  # type: ignore[arg-type]
        self.assertRegex(item.findtext("pubDate") or "", r"^\w{3}, \d{2} \w{3} \d{4} [\d:]{8} GMT$")

    def test_inserts_newest_first_after_metadata(self) -> None:
        for version, build in (("0.2.0", 10), ("0.4.0", 30), ("0.3.0", 20)):
            appcast.upsert_item(self.tree, appcast.make_item(**item_args(version, build)))  # type: ignore[arg-type]
        self.assertEqual(self.short_versions(), ["0.4.0", "0.3.0", "0.2.0"])
        channel = self.tree.getroot().find("channel")
        assert channel is not None
        self.assertEqual([c.tag for c in list(channel)[:4]], ["title", "link", "description", "language"])

    def test_rerun_of_same_version_replaces_item(self) -> None:
        appcast.upsert_item(self.tree, appcast.make_item(**item_args("0.2.0", 10, "old")))  # type: ignore[arg-type]
        appcast.upsert_item(self.tree, appcast.make_item(**item_args("0.2.0", 11, "new")))  # type: ignore[arg-type]
        self.assertEqual(len(self.items()), 1)
        enclosure = self.items()[0].find("enclosure")
        assert enclosure is not None
        self.assertEqual(enclosure.get(appcast.sparkle("edSignature")), "new")

    def test_items_with_unparsable_build_sort_last(self) -> None:
        channel = self.tree.getroot().find("channel")
        assert channel is not None
        ET.SubElement(channel, "item")
        appcast.upsert_item(self.tree, appcast.make_item(**item_args("0.2.0", 5)))  # type: ignore[arg-type]
        self.assertEqual(self.short_versions(), ["0.2.0", None])

    def test_build_read_from_enclosure_attribute(self) -> None:
        legacy = ET.Element("item")
        ET.SubElement(legacy, "enclosure", {appcast.sparkle("version"): "7"})
        self.assertEqual(appcast._build_number(legacy), 7)  # noqa: SLF001

    def test_missing_channel_fails(self) -> None:
        with self.assertRaises(appcast.ReleaseError):
            appcast.upsert_item(ET.ElementTree(ET.Element("rss")), ET.Element("item"))


class CliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = tempfile.TemporaryDirectory()
        self.root = Path(self.dir.name)
        self.changelog = self.root / "CHANGELOG.md"
        self.changelog.write_text(CHANGELOG, encoding="utf-8")
        self.appcast = self.root / "appcast.xml"

    def tearDown(self) -> None:
        self.dir.cleanup()

    def run_cli(self, *argv: str) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = appcast.run(list(argv))
        return code, out.getvalue(), err.getvalue()

    def update(self, version: str = "0.2.0", build: str = "12", url: str | None = None) -> tuple[int, str, str]:
        return self.run_cli(
            "update",
            "--appcast", str(self.appcast),
            "--changelog", str(self.changelog),
            "--version", version,
            "--build", build,
            "--url", url or f"https://example.com/VSVibe-{version}.dmg",
            "--length", "2048",
            "--ed-signature", "SIG==",
            "--pub-date", "Sat, 14 Nov 2026 12:00:00 GMT",
        )

    def test_notes_markdown_and_html(self) -> None:
        code, out, _ = self.run_cli("notes", "0.2.0", "--changelog", str(self.changelog))
        self.assertEqual(code, 0)
        self.assertTrue(out.startswith("### Added"))
        code, out, _ = self.run_cli("notes", "0.2.0", "--changelog", str(self.changelog), "--html")
        self.assertEqual(code, 0)
        self.assertTrue(out.startswith("<h3>Added</h3>"))

    def test_notes_missing_section_or_file_fails(self) -> None:
        code, _, err = self.run_cli("notes", "1.0.0", "--changelog", str(self.changelog))
        self.assertEqual(code, 1)
        self.assertIn("no '## [1.0.0]'", err)
        code, _, err = self.run_cli("notes", "0.2.0", "--changelog", str(self.root / "missing.md"))
        self.assertEqual(code, 1)
        self.assertIn("not found", err)

    def test_bad_version_is_rejected(self) -> None:
        with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
            appcast.run(["notes", "v0.2.0"])

    def test_update_creates_then_is_idempotent(self) -> None:
        self.assertEqual(self.update()[0], 0)
        first = self.appcast.read_text(encoding="utf-8")
        self.assertTrue(first.startswith("<?xml version='1.0' encoding='utf-8'?>"))
        self.assertIn('xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"', first)
        self.assertIn("<sparkle:version>12</sparkle:version>", first)
        self.assertIn("&lt;h3&gt;Added&lt;/h3&gt;", first)
        self.assertEqual(self.update()[0], 0)
        self.assertEqual(self.appcast.read_text(encoding="utf-8"), first)

    def test_rerun_without_pub_date_keeps_the_original(self) -> None:
        base = ["update", "--appcast", str(self.appcast), "--changelog", str(self.changelog),
                "--version", "0.2.0", "--build", "12", "--url", "https://example.com/a.dmg",
                "--length", "1", "--ed-signature", "S"]
        self.assertEqual(self.run_cli(*base)[0], 0)
        first = self.appcast.read_text(encoding="utf-8")
        self.assertEqual(self.run_cli(*base)[0], 0)
        self.assertEqual(self.appcast.read_text(encoding="utf-8"), first)

    def test_update_rejects_bad_input(self) -> None:
        self.assertEqual(self.update(url="http://example.com/x.dmg")[0], 1)
        self.assertEqual(self.update(build="0")[0], 1)
        self.assertEqual(self.update(version="1.0.0")[0], 1)
        self.assertFalse(self.appcast.exists())

    def test_update_rejects_invalid_xml(self) -> None:
        self.appcast.write_text("<rss><channel>", encoding="utf-8")
        code, _, err = self.update()
        self.assertEqual(code, 1)
        self.assertIn("invalid XML", err)


if __name__ == "__main__":
    unittest.main()
