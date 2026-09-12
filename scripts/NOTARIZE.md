# Notarizing VSVibe

One-time setup so `NOTARIZE=1 scripts/build-dmg.sh` produces a notarized,
Gatekeeper-friendly DMG. Team: **Volodymyr Shyrochuk (M3FHKUJ7Z3)**.

## 1. Create a "Developer ID Application" certificate

Easiest via Xcode (you must be the team's Account Holder — you are, for a
personal account):

1. Xcode → **Settings… → Accounts**.
2. Select your Apple ID → pick the **Volodymyr Shyrochuk** team → **Manage Certificates…**.
3. Click **+** → **Developer ID Application**.
4. It appears in your login keychain with its private key.

Verify:

```sh
security find-identity -v -p codesigning | grep "Developer ID Application"
```

## 2. Create an App Store Connect API key (for notarytool)

1. https://appstoreconnect.apple.com → **Users and Access → Integrations →
   App Store Connect API**.
2. Generate a key with the **Developer** role (or higher).
3. Download the `AuthKey_XXXXXXXXXX.p8` (downloadable **once** — keep it safe,
   outside the repo).
4. Note the **Key ID** (on the key row) and the **Issuer ID** (top of the page).

## 3. Store the credentials in the keychain

```sh
xcrun notarytool store-credentials "vsvibe-notary" \
  --key   /path/to/AuthKey_XXXXXXXXXX.p8 \
  --key-id   YOUR_KEY_ID \
  --issuer   YOUR_ISSUER_ID
```

This saves a reusable profile named `vsvibe-notary` — the script references it.

## 4. Build a notarized DMG

```sh
NOTARIZE=1 scripts/build-dmg.sh
```

The script signs with Developer ID + hardened runtime, builds the DMG, submits
to Apple, waits, staples the ticket, and verifies. The result runs on any Mac
with a normal double-click.
