#!/usr/bin/env python3
"""Coverage gate for the testable core.

    python3 -I tools/check_coverage.py [RESULT_BUNDLE] [--min 90]

Reads line coverage from an Xcode result bundle (default build/ci/result.xcresult,
written by tools/test.sh) and fails when the aggregate coverage of every app
source NOT matched by `sonar.coverage.exclusions` in sonar-project.properties is
below the threshold. Using Sonar's own exclusion list keeps this gate and the
SonarQube gate measuring exactly the same files.

Exit codes: 0 pass, 1 below threshold, 2 bad input.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROPS = ROOT / "sonar-project.properties"
DEFAULT_MIN = 90.0
SOURCE_DIR = "VSVibe/"


def read_exclusions(props: Path) -> list[str]:
    """Return the sonar.coverage.exclusions globs."""
    for raw in props.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("sonar.coverage.exclusions="):
            value = line.split("=", 1)[1]
            return [g.strip() for g in value.split(",") if g.strip()]
    return []


def excluded(path: str, globs: list[str]) -> bool:
    """Sonar-style match: `**` spans directories."""
    return any(fnmatch.fnmatch(path, g) or fnmatch.fnmatch(path, g.replace("/**", "/*")) for g in globs)


def load_report(bundle: Path) -> dict[str, object]:
    """Run xccov on the bundle and return its JSON report."""
    out = subprocess.run(
        ["xcrun", "xccov", "view", "--report", "--json", str(bundle)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return json.loads(out)


def main() -> int:
    """Entry point."""
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("bundle", nargs="?", default=str(ROOT / "build/ci/result.xcresult"))
    parser.add_argument("--min", type=float, default=DEFAULT_MIN)
    args = parser.parse_args()

    bundle = Path(args.bundle)
    if not bundle.exists():
        print(f"error: result bundle not found: {bundle} (run tools/test.sh)", file=sys.stderr)
        return 2
    globs = read_exclusions(PROPS)
    if not globs:
        print("error: sonar.coverage.exclusions missing from sonar-project.properties", file=sys.stderr)
        return 2

    rows: list[tuple[str, int, int]] = []
    for target in load_report(bundle).get("targets", []):
        for entry in target.get("files", []):
            full = str(entry["path"])
            marker = f"/{SOURCE_DIR}"
            if marker not in full:
                continue
            rel = SOURCE_DIR + full.rsplit(marker, 1)[1]
            if excluded(rel, globs):
                continue
            rows.append((rel, int(entry["coveredLines"]), int(entry["executableLines"])))

    if not rows:
        print("error: no core files found in the coverage report", file=sys.stderr)
        return 2

    covered = sum(r[1] for r in rows)
    total = sum(r[2] for r in rows)
    pct = 100.0 * covered / total if total else 100.0
    print("Testable-core line coverage (files below the threshold):")
    for rel, cov, exe in sorted(rows):
        file_pct = 100.0 * cov / exe if exe else 100.0
        if file_pct < args.min:
            print(f"  {file_pct:6.1f}%  {cov:4d}/{exe:<4d}  {rel}")
    status = "OK" if pct >= args.min else "FAILED"
    print(f"Core coverage: {pct:.2f}% ({covered}/{total}), threshold {args.min:.0f}% -> {status}")
    return 0 if pct >= args.min else 1


if __name__ == "__main__":
    sys.exit(main())
