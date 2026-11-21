#!/usr/bin/env python3
"""Homebrew cask for VSVibe (stdlib only).

    python3 -I tools/homebrew_cask.py --version 0.3.0 --dmg VSVibe-0.3.0.dmg \\
        --out Casks/vsvibe.rb
    python3 -I tools/homebrew_cask.py --version 0.3.0 --sha256 HEX --out -

Writes `Casks/vsvibe.rb` for the tap github.com/Mc231/homebrew-tap, so
`brew install --cask mc231/tap/vsvibe` installs the notarized DMG of the
GitHub Release `vVERSION`. The release workflow runs this after publishing a
release and pushes the result to the tap. The output only depends on the
version and the DMG's SHA-256, so re-running a release rewrites the same file.

Exit codes: 0 ok, 1 invalid input.
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path

VERSION = re.compile(r"^\d+\.\d+\.\d+$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
BUNDLE_ID = "com.shyrochuk.vsvibe"

TEMPLATE = """\
cask "vsvibe" do
  version "{version}"
  sha256 "{sha256}"

  url "https://github.com/Mc231/vsvibe/releases/download/v#{{version}}/VSVibe-#{{version}}.dmg"
  name "VSVibe"
  desc "Run and monitor multiple Claude Code and terminal sessions"
  homepage "https://vshyrochuk.com/vsvibe/"

  livecheck do
    url "https://mc231.github.io/vsvibe/appcast.xml"
    strategy :sparkle, &:short_version
  end

  auto_updates true
  depends_on macos: :sequoia

  app "VSVibe.app"

  zap trash: [
    "~/Library/Application Support/VSVibe",
    "~/Library/Caches/{bundle_id}",
    "~/Library/HTTPStorages/{bundle_id}",
    "~/Library/Preferences/{bundle_id}.plist",
    "~/Library/Saved Application State/{bundle_id}.savedState",
  ]
end
"""


class CaskError(Exception):
    """Invalid version or checksum."""


def render(version: str, sha256: str) -> str:
    """The cask file for `version` whose DMG has the given SHA-256."""
    if not VERSION.match(version):
        raise CaskError(f"version must be X.Y.Z, got {version!r}")
    digest = sha256.lower()
    if not SHA256.match(digest):
        raise CaskError("sha256 must be 64 hex characters")
    return TEMPLATE.format(version=version, sha256=digest, bundle_id=BUNDLE_ID)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Write the VSVibe Homebrew cask.")
    parser.add_argument("--version", required=True)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--dmg", type=Path, help="DMG to checksum")
    source.add_argument("--sha256", help="SHA-256 of the DMG")
    parser.add_argument("--out", required=True, help="cask path, or - for stdout")
    return parser


def run(argv: list[str]) -> int:
    args = build_parser().parse_args(argv)
    try:
        sha256 = file_sha256(args.dmg) if args.dmg else args.sha256
        cask = render(args.version, sha256)
    except (CaskError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    if args.out == "-":
        sys.stdout.write(cask)
    else:
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(cask, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(run(sys.argv[1:]))
