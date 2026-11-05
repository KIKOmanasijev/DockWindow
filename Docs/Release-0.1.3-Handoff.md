# DogBar 0.1.3 — signing and OTA handoff

**Version: 0.1.3 · build: 10 · Apple team: DD94BC69WN.** The previous stable release is 0.1.1 (build 8). The 0.1.2 draft was never signed and is superseded; do not build it. The GitHub release v0.1.3 is a private draft. Do not publish it yet.

## What is in it

Everything from the 0.1.2 candidate (new Settings, Agent Activity Beta, Dock refinements and fixes), plus the free build guard: every build is stamped `DogBarCommercialMode = free`, and no licensing code runs. See [CommercialMode.md](CommercialMode.md). The user-facing notes are [ReleaseNotes/0.1.3.md](ReleaseNotes/0.1.3.md). Uncommitted local Dock work (callout menu, login items) is **not** included.

Validation on the preparation Mac (Xcode 27.2), from a clean `git archive` of the source:

- `swift build -c release --product DogBar --triple arm64-apple-macosx26.0` passed.
- `license_packaging.fields('stable')` returns `{'DogBarCommercialMode': 'free'}`.
- `python3 Scripts/check_commercial_policy.py` passes in the working tree, which matches the deployed website.
- No test suites were run for this candidate. The 0.1.2 handoff records the last full-suite results and the known failures.

Before publishing, manually check the items listed in the 0.1.2 handoff: Agent Activity hooks and notes, Dock glass, Reduce Motion, screen changes, and a real 0.1.1 → 0.1.3 Install and Relaunch.

Ivan needs no Sparkle private key. He builds and notarizes, then returns the exact final bytes and records. Hristijan signs the OTA feed **after** receiving and verifying that DMG.

## Ivan: build the exact draft source

Use Xcode 27.2, your Developer ID Application identity and your notarization Keychain profile. Start from a clean checkout; do not discard local edits. **Do not set `DOGBAR_LICENSE_CONFIG`.** This is a free build: packaging refuses it and stops before compiling. Earlier licensing notes told you to set it; ignore them.

```sh
git fetch origin main
git switch --detach "$(gh release view v0.1.3 --json targetCommitish --jq .targetCommitish)"
git status --short
unset DOGBAR_LICENSE_CONFIG DOGBAR_COMMERCIAL_MODE
xcodebuild -version
python3 Scripts/release.py preflight --team-id DD94BC69WN --keychain-profile dogbar-notary
python3 Scripts/release.py build --team-id DD94BC69WN --keychain-profile dogbar-notary --version 0.1.3 --build 10
python3 Scripts/release.py verify --team-id DD94BC69WN --version 0.1.3 --build 10 --release-dir dist/DogBar-0.1.3-arm64
/usr/libexec/PlistBuddy -c "Print :DogBarCommercialMode" dist/DogBar-0.1.3-arm64/image/DogBar.app/Contents/Info.plist   # expect: free
```

If your notarization profile has a different name, use that. Keep the same bundle ID, Apple team and Sparkle public key. Upload the exact final DMG and its checksum to the draft. Do not replace any published assets:

```sh
(cd dist/DogBar-0.1.3-arm64 && shasum -a 256 DogBar-0.1.3-arm64.dmg > DogBar-0.1.3-arm64.dmg.sha256)
gh release upload v0.1.3 dist/DogBar-0.1.3-arm64/DogBar-0.1.3-arm64.dmg dist/DogBar-0.1.3-arm64/DogBar-0.1.3-arm64.dmg.sha256
```

Send Hristijan the final SHA-256, the source SHA, `release.json`, `provenance.json` and the verification output. Leave the release as a draft.

## Hristijan: verify, sign OTA, stage and publish

Same steps as the 0.1.2 handoff, with the new version:

```sh
python3 Scripts/release.py import --team-id DD94BC69WN --version 0.1.3 --build 10 --release-dir dist/DogBar-0.1.3-arm64 --sha256 "$DOGBAR_RELEASE_SHA256"   # only if Ivan sent just the DMG
python3 Scripts/ota.py appcast --channel stable --team-id DD94BC69WN --version 0.1.3 --build 10 --sha256 "$DOGBAR_RELEASE_SHA256" --notes Docs/ReleaseNotes/0.1.3.md
python3 Scripts/ota.py verify --dir dist/ota/DogBar-0.1.3-arm64 --sha256 "$DOGBAR_RELEASE_SHA256"
python3 Scripts/release.py stage --team-id DD94BC69WN --version 0.1.3 --build 10 --release-dir dist/DogBar-0.1.3-arm64
python3 Scripts/ota.py stage --dir dist/ota/DogBar-0.1.3-arm64 --sha256 "$DOGBAR_RELEASE_SHA256"
python3 Scripts/check_commercial_policy.py
```

Commit and push the staged manifest and signed feed. Deploy `landing/` with the versioned downloads included, keeping the 0.1.1 feed item and all older DMGs. Check that the live DMG matches Ivan's hash and the live feed matches the local one byte for byte. Then publish the draft as the latest stable release. Finally, test a real 0.1.1 → 0.1.3 update. Never rebuild or modify a version that has been published.
