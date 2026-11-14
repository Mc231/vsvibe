# Changelog

All notable changes to VSVibe are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

A release tag `vX.Y.Z` publishes the `## [X.Y.Z]` section below as its GitHub
release notes and in the in-app update dialog; the release fails if the section
is missing.

## [Unreleased]

## [0.2.0]

### Added

- **Automatic updates** (Sparkle 2): VSVibe checks for new versions in the
  background, shows the release notes and offers Install Update, Remind Me
  Later or Skip This Version. "Check for Updates…" is in the app menu, and the
  new Settings window has an Updates tab to turn automatic checks and automatic
  downloads on or off.
- **Session restore**: open panes come back after the app relaunches (on by
  default, can be turned off in Settings). When it is off, installing an update
  asks before closing running sessions.
- Developer ID signed, notarized release DMGs published on GitHub Releases.

### Changed

- Strict quality gates: every SwiftLint rule, compiler warnings as errors,
  at least 90% unit-test coverage of the core logic, unused-code checks
  (Periphery) and a SonarQube quality gate, all enforced in CI.

## [0.1.0]

### Added

- First version: multiple Claude Code / terminal panes per project folder, live
  git branch, token usage and hook activity per pane, per-project statistics.
