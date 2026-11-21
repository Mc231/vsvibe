# Changelog

All notable changes to VSVibe are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

A release tag `vX.Y.Z` publishes the `## [X.Y.Z]` section below as its GitHub
release notes and in the in-app update dialog; the release fails if the section
is missing.

## [Unreleased]

### Added

- Install with Homebrew: `brew install --cask mc231/tap/vsvibe`. Every release
  now updates the cask in the `Mc231/homebrew-tap` tap automatically.

### Fixed

- Copying text from a pane running Claude Code: Claude tracks the mouse, so a
  plain drag never selected anything. Hold **Option** while dragging to select
  (as in iTerm), then ⌘C. Right-click a pane for Copy / Paste / Select All.

## [0.3.0] - 2026-11-20

### Added

- Remote (SSH) projects: *File → New Remote Project…* (or the network button
  in the sidebar) adds a project that lives on another machine. Its panes `ssh`
  to the host, change to the remote folder and run Claude, an alias such as
  `claudework`, any other command or just a shell there. Claude panes resume
  their own conversation when VSVibe restores them, without hooks.
- Remote panes are as informative as local ones: "needs input" / "finished"
  notifications, token usage and the git branch now come from the remote host
  over ssh. Install or update the Claude hooks on the host from the project
  editor (*Install Hooks on <host>*, with a status line); they go into the
  Claude config dir of the project's command, including a remote
  `CLAUDE_CONFIG_DIR` alias, and keep your other hooks. Needs ssh to log in
  without a prompt (keys or agent) and bash on the host.

## [0.2.1] - 2026-11-15

### Fixed

- Launch commands defined as aliases or functions in `~/.zshrc` (or
  `~/.bashrc`) are no longer reported as "not installed". VSVibe now asks your
  interactive shell, and a shell that takes too long to answer never causes a
  false warning.
- Token usage is shown per pane: each pane follows its own Claude
  conversation, so two panes in one project no longer show the same numbers,
  and a conversation run with another alias or account is counted correctly.
  The numbers switch to the new conversation after `/clear`.

### Added

- When a project's launch command is a shell alias for another Claude account
  (`CLAUDE_CONFIG_DIR=…`), the project editor says so and offers **Register**,
  which adds it as a VSVibe alias and installs its hooks in one click.
- *Aliases & Claude Hooks…* lists project launch commands that aren't
  registered yet, with the Claude account each one uses and a **Register**
  button.
- On launch, VSVibe offers to install or update the Claude hooks when they are
  missing or outdated (notifications and session restore need them), with
  **Not Now** and **Don't Ask Again**.

### Changed

- The hook status flags a registered alias whose Claude config folder doesn't
  exist yet, or that Claude Code hasn't used yet, and tells you to run that
  command once and log in. Installing hooks for such an alias creates the
  folder and its `settings.json`, which Claude Code reads on first run.

## [0.2.0]

### Added

- **Automatic updates** (Sparkle 2): VSVibe checks for new versions in the
  background, shows the release notes and offers Install Update, Remind Me
  Later or Skip This Version. "Check for Updates…" is in the app menu, and the
  new Settings window has an Updates tab to turn automatic checks and automatic
  downloads on or off.
- **Session restore**: open panes come back after the app relaunches (on by
  default, can be turned off in Settings). When it is off, installing an update
  asks before closing running sessions. Each Claude pane resumes its own
  conversation with the alias (Claude config dir / account) that ran it; click
  **Update Hooks** in *Aliases & Claude Hooks…* once after updating.
- Developer ID signed, notarized release DMGs published on GitHub Releases.

### Changed

- Strict quality gates: every SwiftLint rule, compiler warnings as errors,
  at least 90% unit-test coverage of the core logic, unused-code checks
  (Periphery) and a SonarQube quality gate, all enforced in CI.

## [0.1.0]

### Added

- First version: multiple Claude Code / terminal panes per project folder, live
  git branch, token usage and hook activity per pane, per-project statistics.
