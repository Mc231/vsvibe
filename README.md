# VSVibe

VSVibe is a native macOS app for running and monitoring several Claude Code
(or other terminal) sessions side by side, one or more panes per project
folder. It shows live per-pane state such as the current git branch, Claude
token usage and hook activity, and keeps persistent per-project statistics.

Requires macOS 15.0 or later.

## Features

- **Multiple panes per project** — open as many terminal panes as you like for
  each project folder, tiled in a grid. Terminals are powered by
  [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).
- **Project sidebar with labels** — group projects under one or more labels;
  the sidebar renders a collapsible section per label plus an "Ungrouped"
  bucket.
- **Live git branch** — read from `.git/HEAD` without spawning a process, with
  an on-demand branch switcher.
- **Git changes review** — choose **Review Git Changes…** from a project's
  context menu or a pane's options menu. Select Base and Compare branches
  (local or cached remote refs), then review changed files and colored diffs.
  Compare from the common ancestor or directly between branch tips; this is
  read-only and excludes uncommitted edits. Large file previews are capped at
  512 KB, and renames appear as an added and a deleted file.
- **Claude usage tracking** — live token usage and cost per session, parsed
  from Claude Code transcripts.
- **Hook notifications** — install Claude Code `Stop` / `Notification` /
  `SubagentStop` hooks from inside the app and get notified when a session
  needs attention.
- **Per-project statistics** — pane lifecycle, hook activity and token usage
  are persisted per day and shown in a stats sheet.
- **Open in editor** — jump to the project in Xcode, Android Studio,
  IntelliJ IDEA, WebStorm and others.

## Requirements

- macOS 15.0+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Building

The Xcode project is generated from `project.yml` and is not checked in.
Regenerate it whenever you add, remove or rename a source file:

```sh
xcodegen generate
xcodebuild -project VSVibe.xcodeproj -scheme VSVibe -configuration Debug build
```

Or open `VSVibe.xcodeproj` in Xcode after generating it.

## Testing

```sh
xcodegen generate
xcodebuild -project VSVibe.xcodeproj -scheme VSVibe -enableCodeCoverage YES test
```

All non-UI logic (`Model/`, `Store/`, `Stats/`, `Usage/`, `Git/`, `Util/`) is
covered by unit tests in `VSVibeTests/`, targeting at least 90% line coverage.

## Packaging

`scripts/build-dmg.sh` builds a Release archive and packages it into a
drag-to-Applications DMG at `build/VSVibe.dmg`:

```sh
scripts/build-dmg.sh              # ad-hoc signed
NOTARIZE=1 scripts/build-dmg.sh   # Developer ID signed + notarized + stapled
```

See [`scripts/NOTARIZE.md`](scripts/NOTARIZE.md) for the one-time
notarization setup.

## Project layout

```
VSVibe/
  AppEnvironment.swift   composition root, injected into the SwiftUI environment
  Model/                 folders, labels, sessions, persisted state
  Store/                 FolderStore, SessionManager, app paths
  Stats/                 per-project statistics model, store and transcript scanner
  Usage/                 live Claude token-usage tracking
  Git/                   branch reading (.git/HEAD) and on-demand git operations
  Notifications/         Claude hook installer, event watcher and coordinator
  Terminal/              SwiftTerm hosting, shell/command resolution
  UI/                    SwiftUI views: sidebar, tiling grid, pane chrome, stats
  Util/                  small helpers (debounce, logging, editor registry, ...)
VSVibeTests/             unit tests for the testable core
scripts/                 DMG build and notarization
project.yml              XcodeGen project definition
```

## Data locations

- App state and stats: `~/Library/Application Support/VSVibe/`
  (`state.json`, `stats.json`)
- Hook script and event log: `~/.vsvibe/` (`hooks/claude-notify.sh`,
  `events.jsonl`)

## License

© 2026 Volodymyr Shyrochuk. All rights reserved.
