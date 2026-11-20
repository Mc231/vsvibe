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
- **Custom aliases** — register, edit and remove existing shell commands from
  **Aliases & Claude Hooks…** in the app menu. Set an optional Claude config
  directory for hooks and usage tracking; saved aliases also appear in the
  project editor. Define the command itself in your shell first.
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

All non-UI logic is covered by unit tests in `VSVibeTests/`, with a gate of at
least 90% line coverage over every file not in `sonar.coverage.exclusions`.

## Code quality and CI

```sh
tools/lint.sh             # SwiftLint, every rule, --strict
tools/test.sh             # clean build + tests + core coverage gate (>= 90%)
tools/lint.sh --analyze   # swiftlint analyze on that build (unused code)
tools/sonar_scan.sh       # SonarQube "VSVibe strict" gate (localhost:9000)
```

CI runs on Gitea Actions (`.gitea/workflows/`) through a pull-mirror of the
GitHub repo:
- **every push:** lint, tests and coverage;
- **`main`:** additionally the Sonar gate and an ad-hoc signed DMG artifact;
- **`v*` tags:** a notarized DMG artifact.

## Packaging

`scripts/build-dmg.sh` builds a Release archive and packages it into a
drag-to-Applications DMG at `build/VSVibe.dmg`:

```sh
scripts/build-dmg.sh              # ad-hoc signed
NOTARIZE=1 scripts/build-dmg.sh   # Developer ID signed + notarized + stapled
```

See [`scripts/NOTARIZE.md`](scripts/NOTARIZE.md) for the one-time
notarization setup.

## Session restore, remote projects and auto-update

- [Session restore](docs/session-restore.md): panes reopen on launch and each
  Claude pane resumes its own conversation (Settings → General).
- [Remote projects](docs/remote-projects.md): a project on another machine;
  its panes `ssh` in, `cd` to the remote folder and run Claude (or any command)
  there, and restore resumes each pane's conversation. With the hooks installed
  on the host (from the project editor), notifications, token usage and the git
  branch come over ssh too.
- [Auto-update and releases](docs/auto-update-and-releases.md): Sparkle 2
  updates (Settings → Updates, "Check for Updates…") and the notarized release
  pipeline triggered by a `vX.Y.Z` tag.

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
  Remote/                remote (SSH) projects: ssh line, launch plan, remote hooks/events/usage/branch
  Terminal/              SwiftTerm hosting, shell/command resolution
  UI/                    SwiftUI views: sidebar, tiling grid, pane chrome, stats
  Util/                  small helpers (debounce, logging, editor registry, ...)
VSVibeTests/             unit tests for the testable core
scripts/                 DMG build and notarization
tools/                   lint, test/coverage gate and Sonar scan wrappers
.gitea/workflows/        CI (lint, tests, Sonar, DMG) and notarized release
project.yml              XcodeGen project definition
```

## Data locations

- App state and stats: `~/Library/Application Support/VSVibe/`
  (`state.json`, `stats.json`, `aliases.json`)
- Hook script and event log: `~/.vsvibe/` (`hooks/claude-notify.sh`,
  `events.jsonl`)

## License

© 2026 Volodymyr Shyrochuk. All rights reserved.
