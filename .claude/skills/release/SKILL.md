---
name: release
description: Cut a VSVibe release - pick the version, write the CHANGELOG section, run the local gates, push main, wait for Gitea CI, push the vX.Y.Z tag, watch the notarized release run and verify the GitHub Release, the Sparkle appcast and Gatekeeper. Use when the user asks to release, ship, publish, tag or bump a VSVibe version, or asks why a release / auto-update failed.
---

# Releasing VSVibe

A pushed `vX.Y.Z` tag on GitHub (`Mc231/vsvibe`, public) is the whole trigger.
Gitea pull-mirrors GitHub and runs `.gitea/workflows/release.yml` on the
self-hosted macOS runner: tests, Developer ID signing, notarization, stapling,
Sparkle EdDSA signature, GitHub Release with the DMG, and a new `<item>` in
`appcast.xml` on `gh-pages` (served by GitHub Pages at
`https://mc231.github.io/vsvibe/appcast.xml`). Installed copies pick it up via
Sparkle. Background: `docs/auto-update-and-releases.md`; one-time setup:
`scripts/NOTARIZE.md`.

**Pushing to `main` and pushing a tag are outward-facing: get the user's OK
for the version before pushing the tag.** A published version is final.

## Facts to rely on

- **Version comes from the tag** (`v0.3.0` → `MARKETING_VERSION=0.3.0`). The
  `MARKETING_VERSION` in `project.yml` is only the local default; keep it equal
  to the version being released so local builds look right.
- **Build number = `git rev-list --count HEAD`** of the tagged commit. Sparkle
  compares this, so a release must be tagged on a commit *after* the previous
  release's commit (always true when tagging the tip of `main`).
- **`CHANGELOG.md` must contain `## [X.Y.Z]` with content**, or the release job
  fails immediately. Its body becomes the GitHub Release notes and the HTML
  shown in Sparkle's update window. Check it with
  `python3 tools/appcast.py notes X.Y.Z`.
- Tag format is strictly `vX.Y.Z` (no `-beta`: there is only a production
  channel).
- Signing identity: **Developer ID Application: Volodymyr Shyrochuk
  (M3FHKUJ7Z3)**, expires **2027-12-14**. Gitea secrets used by the job:
  `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD`, `ASC_API_KEY_ID`,
  `ASC_API_ISSUER_ID`, `ASC_API_KEY_P8_BASE64`, `SPARKLE_ED_PRIVATE_KEY`,
  `GH_RELEASE_TOKEN`. Local copies: `.secrets/` (git-ignored); backups in
  `~/pet/secure/vsvibe/`. Never print any of them.
- The runner has **capacity 1 and is shared with other repos**: runs often sit
  `queued` for a long time. That is not a failure.

## Procedure

1. **Pick the version** (semver): patch for fixes, minor for features. Confirm
   it with the user. Make sure the tag does not exist yet:
   `git ls-remote --tags origin vX.Y.Z` must print nothing.

2. **CHANGELOG**: move the relevant `## [Unreleased]` entries into a new
   `## [X.Y.Z] - YYYY-MM-DD` section (Keep a Changelog: `### Added`,
   `### Changed`, `### Fixed`, `### Removed`). Write for users, not commits.
   Plain Markdown only (headings, bullets, bold, inline code, links): that is
   what `tools/appcast.py` converts to HTML.

3. **Bump the local default** `MARKETING_VERSION` in `project.yml` to `X.Y.Z`,
   then `xcodegen generate`.

4. **Local gates** (same as CI; all must pass):

   ```sh
   tools/lint.sh && tools/test.sh && tools/lint.sh --analyze \
     && python3 -m unittest discover -s tools -p 'test_*.py' \
     && python3 tools/appcast.py notes X.Y.Z >/dev/null
   ```

   Optional but cheap insurance before the first release after signing or
   pipeline changes: a full local notarized build (uses the login-keychain
   Developer ID identity and the App Store Connect key from `~/.secrets.zsh`):

   ```sh
   zsh -ic 'source ~/.secrets.zsh; NOTARIZE=1 \
     ASC_API_KEY_PATH="${APP_STORE_CONNECT_API_KEY_PATH/#\~/$HOME}" \
     ASC_API_KEY_ID="$APP_STORE_CONNECT_API_KEY_ID" \
     ASC_API_ISSUER_ID="$APP_STORE_CONNECT_API_ISSUER_ID" \
     scripts/build-dmg.sh'
   ```

5. **Commit and push `main`** ("Release X.Y.Z"), then trigger a mirror sync so
   CI starts now:

   ```sh
   zsh -ic 'source ~/.secrets.zsh; python3 ~/.claude/skills/gitea-sonar-setup/scripts/gitea_setup.py --owner Volodya --repo vsvibe'
   ```

6. **Wait for CI on that commit** (lint, build/tests/coverage, Sonar gate).
   Use the workflow *runs* endpoint, not `actions/tasks` (tasks only lists jobs
   a runner already picked up, so queued runs are invisible there):

   ```sh
   zsh -ic 'source ~/.secrets.zsh; curl -s -H "Authorization: token $GITEA_TOKEN" \
     "http://localhost:3001/api/v1/repos/Volodya/vsvibe/actions/runs?limit=5"' \
     | python3 -c "import json,sys;[print(r['id'],r['status'],r.get('conclusion'),r['head_sha'][:7],r['path']) for r in json.load(sys.stdin)['workflow_runs']]"
   ```

   A newer push to the same branch cancels the older run (`cancelled` is
   expected then). Poll in a background loop; don't sleep in the foreground.
   The `gitea` skill can also read job logs.

7. **Tag and push** (annotated, on the CI-green tip of `main`), then sync the
   mirror again:

   ```sh
   git fetch origin && test "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)"
   git tag -a vX.Y.Z -m "VSVibe X.Y.Z" && git push origin vX.Y.Z
   ```

   A `release.yml@refs/tags/vX.Y.Z` run appears in the runs list. Notarization
   usually takes 2-10 minutes once the job is running.

8. **Verify** (all of it; report each result):

   ```sh
   gh release view vX.Y.Z -R Mc231/vsvibe --json assets,isDraft,isPrerelease
   curl -s https://mc231.github.io/vsvibe/appcast.xml | grep -E 'shortVersionString|sparkle:version'
   ```

   Then download the DMG as a user would and let Gatekeeper judge it (work in
   the scratchpad, never `/tmp`):

   ```sh
   curl -sSL -o "$D/v.dmg" https://github.com/Mc231/vsvibe/releases/download/vX.Y.Z/VSVibe-X.Y.Z.dmg
   xattr -w com.apple.quarantine "0081;$(printf %x $(date +%s));Safari;" "$D/v.dmg"
   spctl -a -t open --context context:primary-signature -v "$D/v.dmg"   # Notarized Developer ID
   M=$(hdiutil attach -nobrowse -readonly "$D/v.dmg" | awk -F'\t' '/\/Volumes/{print $NF}')
   spctl -a -vv "$M/VSVibe.app"; xcrun stapler validate "$M/VSVibe.app"
   /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' -c 'Print CFBundleVersion' "$M/VSVibe.app/Contents/Info.plist"
   hdiutil detach -quiet "$M"
   ```

   Expected: `source=Notarized Developer ID`, stapler OK, version `X.Y.Z`, build
   = commit count, and the appcast's newest item matches. GitHub Pages can take
   a minute or two to serve the new appcast.

9. **Tell the user** the release URL, the build number, and whether the
   auto-update path can be tried ("Check for Updates…" in the previous version).

## When it fails

| Symptom | Cause / fix |
| --- | --- |
| Job fails at the CHANGELOG step | No/empty `## [X.Y.Z]` section. Add it, push `main`, delete and re-push the tag *only if nothing was published yet* (no GitHub Release exists). |
| "no Developer ID identity" / import fails | `DEVELOPER_ID_P12_*` secrets wrong or the certificate expired (2027-12-14). New certificate: CSR → developer.apple.com (Account Holder only; the API refuses) → new `.p12` → update both secrets and `~/pet/secure/vsvibe/`. |
| Notarization `Invalid` | Read the log: `xcrun notarytool log <id> --key … --key-id … --issuer …`. Usually an unsigned nested binary or missing hardened runtime: fix `scripts/build-dmg.sh` (inside-out signing) and reproduce locally with step 4's notarized build. |
| GitHub Release or `gh-pages` push fails | `GH_RELEASE_TOKEN` expired or lacks Contents: write. Re-run the job from the Gitea UI after fixing: the release step re-uploads with `--clobber` and the appcast update is idempotent. |
| App doesn't offer the update | Check the appcast URL serves the new item, that its `sparkle:version` (build) is higher than the installed build, and the installed app's `SUFeedURL`. EdDSA mismatch means `SPARKLE_ED_PRIVATE_KEY` doesn't match `SUPublicEDKey` in `project.yml`: never rotate that key, installed apps can't follow. |
| Run stuck in `queued` | Runner busy with other repos (`grep 'repo is' ~/gitea/act_runner/runner.err | tail`). Wait. |

**Never re-release a published version** (users may already have it and
Sparkle caches by build): fix forward with the next patch version.
