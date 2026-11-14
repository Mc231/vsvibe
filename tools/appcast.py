#!/usr/bin/env python3
"""Release notes and Sparkle appcast helper (stdlib only).

    python3 -I tools/appcast.py notes VERSION [--changelog CHANGELOG.md] [--html]
    python3 -I tools/appcast.py update --appcast appcast.xml --version 0.2.0 \\
        --build 123 --url https://.../VSVibe-0.2.0.dmg --length 1234 \\
        --ed-signature BASE64 [--changelog CHANGELOG.md] [--min-system 15.0] \\
        [--pub-date "Sat, 14 Nov 2026 12:00:00 +0000"]

`notes` prints the `## [VERSION]` section of CHANGELOG.md (Keep a Changelog
format), as Markdown or converted to simple HTML. It fails when the section is
missing or empty, so a release cannot ship without notes.

`update` adds (or, for a re-run of the same version, replaces) one <item> in
the appcast, creating the file when it does not exist yet. A re-run keeps the
original pubDate, so an unchanged release rewrites an identical file. Items are kept
newest-first by build number (`sparkle:version`, which Sparkle compares).

Exit codes: 0 ok, 1 missing/invalid input.
"""

from __future__ import annotations

import argparse
import html
import re
import sys
import xml.etree.ElementTree as ET
from email.utils import formatdate
from pathlib import Path

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC_NS = "http://purl.org/dc/elements/1.1/"
ET.register_namespace("sparkle", SPARKLE_NS)
ET.register_namespace("dc", DC_NS)

DEFAULT_TITLE = "VSVibe"
DEFAULT_FEED_LINK = "https://mc231.github.io/vsvibe/appcast.xml"
DEFAULT_MIN_SYSTEM = "15.0"
LINK_REFERENCE = re.compile(r"^\[[^\]]+\]:\s*\S+")


class ReleaseError(Exception):
    """Invalid release input (missing notes, bad appcast, ...)."""


def sparkle(tag: str) -> str:
    """Qualified name in the Sparkle namespace."""
    return f"{{{SPARKLE_NS}}}{tag}"


# --- CHANGELOG ---------------------------------------------------------------


def changelog_section(text: str, version: str) -> str:
    """Return the body of the `## [version]` section, stripped.

    Raises ReleaseError when the section is missing or has no content.
    """
    header = re.compile(r"^##\s+\[" + re.escape(version) + r"\](\s|$)")
    lines = text.splitlines()
    start = next((i for i, line in enumerate(lines) if header.match(line)), None)
    if start is None:
        raise ReleaseError(f"CHANGELOG has no '## [{version}]' section")
    body: list[str] = []
    for line in lines[start + 1 :]:
        if line.startswith("## ") or LINK_REFERENCE.match(line):
            break
        body.append(line)
    section = "\n".join(body).strip()
    if not section:
        raise ReleaseError(f"CHANGELOG section '## [{version}]' is empty")
    return section


def _inline(text: str) -> str:
    """Escape, then render `code`, **bold**, *italic* and [links](url)."""
    out = html.escape(text, quote=True)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"(?<![*\w])\*([^*]+)\*(?![*\w])", r"<em>\1</em>", out)
    return re.sub(r"\[([^\]]+)\]\((https?://[^)\s]+)\)", r'<a href="\2">\1</a>', out)


def markdown_to_html(markdown: str) -> str:
    """Convert the small Markdown subset used in CHANGELOG.md to HTML.

    Supports `#`..`######` headings, `-`/`*` bullet lists (with wrapped
    continuation lines), paragraphs and the inline forms of `_inline`.
    """
    parts: list[str] = []
    paragraph: list[str] = []
    items: list[str] = []

    def flush() -> None:
        if paragraph:
            parts.append(f"<p>{_inline(' '.join(paragraph))}</p>")
            paragraph.clear()
        if items:
            parts.append("<ul>" + "".join(f"<li>{_inline(i)}</li>" for i in items) + "</ul>")
            items.clear()

    for raw in markdown.splitlines():
        line = raw.strip()
        heading = re.match(r"^(#{1,6})\s+(.*)$", line)
        bullet = re.match(r"^[-*]\s+(.*)$", line)
        if not line:
            flush()
        elif heading:
            flush()
            level = len(heading.group(1))
            parts.append(f"<h{level}>{_inline(heading.group(2))}</h{level}>")
        elif bullet:
            if paragraph:
                flush()
            items.append(bullet.group(1))
        elif items:
            items[-1] += " " + line
        else:
            paragraph.append(line)
    flush()
    return "\n".join(parts)


# --- appcast -----------------------------------------------------------------


def new_appcast(title: str = DEFAULT_TITLE, link: str = DEFAULT_FEED_LINK) -> ET.ElementTree:
    """An empty RSS 2.0 appcast with a single channel."""
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = title
    ET.SubElement(channel, "link").text = link
    ET.SubElement(channel, "description").text = f"{title} updates"
    ET.SubElement(channel, "language").text = "en"
    return ET.ElementTree(rss)


def _build_number(item: ET.Element) -> int:
    value = item.findtext(sparkle("version"), default="")
    if not value:
        enclosure = item.find("enclosure")
        value = enclosure.get(sparkle("version"), "") if enclosure is not None else ""
    try:
        return int(value)
    except ValueError:
        return -1


def make_item(
    *,
    version: str,
    build: int,
    url: str,
    length: int,
    ed_signature: str,
    notes_html: str,
    min_system: str = DEFAULT_MIN_SYSTEM,
    pub_date: str | None = None,
) -> ET.Element:
    """One appcast <item> for a DMG release."""
    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {version}"
    ET.SubElement(item, "pubDate").text = pub_date or formatdate(usegmt=True)
    ET.SubElement(item, sparkle("version")).text = str(build)
    ET.SubElement(item, sparkle("shortVersionString")).text = version
    ET.SubElement(item, sparkle("minimumSystemVersion")).text = min_system
    ET.SubElement(item, "description").text = notes_html
    ET.SubElement(
        item,
        "enclosure",
        {
            "url": url,
            "length": str(length),
            "type": "application/octet-stream",
            sparkle("edSignature"): ed_signature,
        },
    )
    return item


def upsert_item(tree: ET.ElementTree, item: ET.Element) -> None:
    """Insert `item`, replacing any item with the same short version or build.

    Items stay sorted newest-first by build number, after the channel metadata.
    """
    channel = tree.getroot().find("channel")
    if channel is None:
        raise ReleaseError("appcast has no <channel>")
    short = item.findtext(sparkle("shortVersionString"))
    build = _build_number(item)
    for old in channel.findall("item"):
        if old.findtext(sparkle("shortVersionString")) == short or _build_number(old) == build:
            channel.remove(old)
    children = list(channel)
    index = len(children)
    for position, child in enumerate(children):
        if child.tag == "item" and _build_number(child) < build:
            index = position
            break
    channel.insert(index, item)


def existing_pub_date(tree: ET.ElementTree, version: str) -> str | None:
    """pubDate of the item already listing `version`, kept on a re-run."""
    for item in tree.getroot().iter("item"):
        if item.findtext(sparkle("shortVersionString")) == version:
            return item.findtext("pubDate")
    return None


def write_appcast(tree: ET.ElementTree, path: Path) -> None:
    """Pretty-print `tree` to `path` with an XML declaration."""
    ET.indent(tree, space="  ")
    tree.write(path, encoding="utf-8", xml_declaration=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write("\n")


def load_appcast(path: Path) -> ET.ElementTree:
    """Parse an existing appcast, or start a new one when the file is absent."""
    if not path.exists():
        return new_appcast()
    try:
        return ET.parse(path)
    except ET.ParseError as error:
        raise ReleaseError(f"{path}: invalid XML ({error})") from error


# --- CLI ---------------------------------------------------------------------


def _version(value: str) -> str:
    if not re.fullmatch(r"\d+\.\d+\.\d+", value):
        raise argparse.ArgumentTypeError(f"expected X.Y.Z, got {value!r}")
    return value


def build_parser() -> argparse.ArgumentParser:
    """Command-line interface."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    notes = sub.add_parser("notes", help="print a CHANGELOG section")
    notes.add_argument("version", type=_version)
    notes.add_argument("--changelog", type=Path, default=Path("CHANGELOG.md"))
    notes.add_argument("--html", action="store_true", help="convert the section to HTML")

    update = sub.add_parser("update", help="add or replace an appcast item")
    update.add_argument("--appcast", type=Path, required=True)
    update.add_argument("--version", type=_version, required=True)
    update.add_argument("--build", type=int, required=True)
    update.add_argument("--url", required=True)
    update.add_argument("--length", type=int, required=True)
    update.add_argument("--ed-signature", required=True)
    update.add_argument("--changelog", type=Path, default=Path("CHANGELOG.md"))
    update.add_argument("--min-system", default=DEFAULT_MIN_SYSTEM)
    update.add_argument("--pub-date")
    return parser


def run(argv: list[str]) -> int:
    """Entry point; returns the process exit code."""
    args = build_parser().parse_args(argv)
    try:
        if not args.changelog.exists():
            raise ReleaseError(f"{args.changelog} not found")
        section = changelog_section(args.changelog.read_text(encoding="utf-8"), args.version)
        if args.command == "notes":
            print(markdown_to_html(section) if args.html else section)
            return 0
        if not args.url.startswith("https://"):
            raise ReleaseError("--url must be an https URL")
        if args.length <= 0 or args.build <= 0:
            raise ReleaseError("--length and --build must be positive")
        tree = load_appcast(args.appcast)
        item = make_item(
            version=args.version,
            build=args.build,
            url=args.url,
            length=args.length,
            ed_signature=args.ed_signature,
            notes_html=markdown_to_html(section),
            min_system=args.min_system,
            pub_date=args.pub_date or existing_pub_date(tree, args.version),
        )
        upsert_item(tree, item)
        write_appcast(tree, args.appcast)
    except ReleaseError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(f"appcast: {args.appcast} now lists {args.version} (build {args.build})")
    return 0


if __name__ == "__main__":
    sys.exit(run(sys.argv[1:]))
