# Releasing VSVibe (one-time setup)

A pushed `vX.Y.Z` tag runs `.gitea/workflows/release.yml` on the self-hosted
runner. It builds, signs with **Developer ID**, notarizes and staples a DMG,
publishes it as a **GitHub Release** asset and adds it to the **Sparkle
appcast** on `gh-pages` (`https://mc231.github.io/vsvibe/appcast.xml`), from
which installed copies update themselves. Team: **Volodymyr Shyrochuk
(M3FHKUJ7Z3)**.

Everything below is done once by the owner. CI never reads the login keychain:
each run imports the certificate into a temporary keychain under
`$RUNNER_TEMP` and deletes it (and every key file) at the end.

## 1. Developer ID Application certificate → `.p12`

On the Mac that has the certificate (create it in Xcode → Settings → Accounts →
Manage Certificates → **+** → Developer ID Application if it does not exist):

1. Keychain Access → login → My Certificates → expand
   **Developer ID Application: Volodymyr Shyrochuk (M3FHKUJ7Z3)** (certificate
   *with* its private key) → right-click → **Export…** → `.p12`, set a strong
   password.
2. Base64 it for the Gitea secret (no line breaks):

   ```sh
   base64 -i DeveloperID.p12 | tr -d '\n' | pbcopy
   ```

Keep the `.p12` somewhere safe outside the repo (`*.p12` is git-ignored).

## 2. App Store Connect API key (notarization)

1. https://appstoreconnect.apple.com → **Users and Access → Integrations → App
   Store Connect API** → Team Keys → **+**, role **Developer**.
2. Download `AuthKey_<KEYID>.p8` (only downloadable once). Note the **Key ID**
   and the **Issuer ID** (top of the page).
3. `base64 -i AuthKey_<KEYID>.p8 | tr -d '\n' | pbcopy`

## 3. Sparkle EdDSA key

Already generated (`generate_keys --account vsvibe`): the public key is
`SUPublicEDKey` in `project.yml`, the private key is in the login keychain
(account `vsvibe`) and exported to `.secrets/sparkle_ed25519.key` (git-ignored,
mode 600).

- **Back it up** (password manager / offline). If it is lost, already-installed
  copies can never accept another update.
- Never commit it, never print it. To re-export or import on another Mac, use
  Sparkle's tool (path: `scripts/sparkle-tool.sh generate_keys`):
  `generate_keys --account vsvibe -x <file>` / `-f <file>`.

## 4. GitHub token

github.com → Settings → Developer settings → **Fine-grained token**, resource
owner Mc231, repository **Mc231/vsvibe** only, permission **Contents: Read and
write** (creates releases, uploads the DMG, pushes `gh-pages`). Pick an
expiry and put a reminder to rotate it.

## 5. Gitea secrets (repository `vsvibe` → Settings → Actions → Secrets)

| Secret | Value |
| --- | --- |
| `DEVELOPER_ID_P12_BASE64` | base64 of the `.p12` (step 1) |
| `DEVELOPER_ID_P12_PASSWORD` | its export password |
| `ASC_API_KEY_ID` | App Store Connect Key ID (step 2) |
| `ASC_API_ISSUER_ID` | App Store Connect Issuer ID |
| `ASC_API_KEY_P8_BASE64` | base64 of `AuthKey_<KEYID>.p8` |
| `SPARKLE_ED_PRIVATE_KEY` | contents of `.secrets/sparkle_ed25519.key` (one line) |
| `GH_RELEASE_TOKEN` | the fine-grained token (step 4) |

Paste the Sparkle key without echoing it, e.g.
`pbcopy < .secrets/sparkle_ed25519.key`.

## 6. GitHub Pages (once the repository is public)

The first release creates the `gh-pages` branch with `appcast.xml`. Then:
GitHub → repository Settings → **Pages** → Source **Deploy from a branch**,
branch `gh-pages`, folder `/ (root)`. Check that
`https://mc231.github.io/vsvibe/appcast.xml` serves the file. Until Pages is on,
installed apps find no updates (harmless). CI ignores the `gh-pages` branch.

## Cutting a release

1. Add a `## [X.Y.Z]` section to `CHANGELOG.md` (the release fails without it;
   it becomes the GitHub release notes and the in-app update notes).
2. Commit to `main`, then `git tag vX.Y.Z && git push origin main vX.Y.Z`
   (to GitHub). The version comes from the tag; the build number
   (`CFBundleVersion`, which Sparkle compares) is `git rev-list --count HEAD`.
3. Watch the "Release" run in Gitea. A re-run of the same tag is safe: the
   release asset and the appcast item are replaced, not duplicated.

## Local builds

```sh
scripts/build-dmg.sh              # ad-hoc signed DMG (build/VSVibe.dmg)
NOTARIZE=1 scripts/build-dmg.sh   # Developer ID + notarized, needs the identity
                                  # in a keychain and either ASC_API_KEY_PATH /
                                  # ASC_API_KEY_ID / ASC_API_ISSUER_ID or a
                                  # `vsvibe-notary` notarytool keychain profile
```

Sign a DMG for Sparkle by hand:

```sh
"$(scripts/sparkle-tool.sh sign_update)" --ed-key-file .secrets/sparkle_ed25519.key build/VSVibe.dmg
```
