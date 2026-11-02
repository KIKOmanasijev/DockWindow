# DogBar 0.1.2 — signing and OTA handoff

**Version: 0.1.2 · build: 9 · Apple team: DD94BC69WN.** Previous stable release is 0.1.1/build 8. Confirm no newer build has been published before starting. The GitHub release is a private draft; do not publish it yet.

## Ivan: build the exact draft source

Use Xcode 27.2 (the new SDK is needed for the native Settings appearance), your existing Developer ID Application identity and local notarization Keychain profile. Start with a clean checkout; do not discard local edits.

```sh
git fetch origin main
# Resolve the draft's pinned source SHA instead of building a moving main branch.
gh release view v0.1.2 --json targetCommitish --jq .targetCommitish
git switch --detach "$(gh release view v0.1.2 --json targetCommitish --jq .targetCommitish)"
git status --short
xcodebuild -version
python3 Scripts/release.py preflight --team-id DD94BC69WN --keychain-profile dogbar-notary
python3 Scripts/release.py build --team-id DD94BC69WN --keychain-profile dogbar-notary --version 0.1.2 --build 9
python3 Scripts/release.py verify --team-id DD94BC69WN --version 0.1.2 --build 9 --release-dir dist/DogBar-0.1.2-arm64
```

Use the actual notarization profile name if it differs. The scripts sign the bundled Sparkle helpers and app, notarize/staple the app and DMG, and verify signatures, tickets, metadata and packaged resources. Keep the same bundle ID, Apple team and Sparkle public key.

Upload the exact final DMG and checksum to the existing draft, without replacing any published assets:

```sh
(cd dist/DogBar-0.1.2-arm64 && shasum -a 256 DogBar-0.1.2-arm64.dmg > DogBar-0.1.2-arm64.dmg.sha256)
gh release upload v0.1.2 dist/DogBar-0.1.2-arm64/DogBar-0.1.2-arm64.dmg dist/DogBar-0.1.2-arm64/DogBar-0.1.2-arm64.dmg.sha256
```

Also return the final SHA-256, source SHA, `release.json`, `provenance.json` and successful verification output to Hristijan. No Apple password, code-signing private key or Sparkle key transfer is needed. Leave the release a draft.

## Hristijan: verify, sign OTA, stage and publish

Keep received files together in `dist/DogBar-0.1.2-arm64/`. If Ivan supplies only the DMG, create an honest imported-artifact record using the independently known final hash; do not invent notarization submission records:

```sh
python3 Scripts/release.py import --team-id DD94BC69WN --version 0.1.2 --build 9 --release-dir dist/DogBar-0.1.2-arm64 --sha256 "$DOGBAR_RELEASE_SHA256"
```

If build records are supplied instead, use `release.py verify` above. Then use the existing Sparkle key in Hristijan's login Keychain (account `dev.hristijan.dogbar`):

```sh
python3 Scripts/ota.py appcast --channel stable --team-id DD94BC69WN --version 0.1.2 --build 9 --sha256 "$DOGBAR_RELEASE_SHA256" --notes Docs/ReleaseNotes/0.1.2.md
python3 Scripts/ota.py verify --dir dist/ota/DogBar-0.1.2-arm64 --sha256 "$DOGBAR_RELEASE_SHA256"
python3 Scripts/release.py stage --team-id DD94BC69WN --version 0.1.2 --build 9 --release-dir dist/DogBar-0.1.2-arm64
python3 Scripts/ota.py stage --dir dist/ota/DogBar-0.1.2-arm64 --sha256 "$DOGBAR_RELEASE_SHA256"
```

Commit and push the staged manifest and signed feed. Deploy `landing/` with the ignored versioned downloads included; preserve the existing 0.1.1 feed item and all older downloads. Verify the live DMG matches Ivan's final hash and the live signed feed is byte-identical to the local feed. Only then publish the GitHub draft as a stable latest release (`--draft=false`, `--prerelease=false`, then `--latest` if separate calls are needed).

Finally test a real 0.1.1 → 0.1.2 Install and Relaunch: native Dock restoration on quit, version/build 0.1.2/9, retained settings and permissions, and valid installed signature. A signed feed alone is not proof that installation/relaunch works. Do not rebuild or modify an already published version.
