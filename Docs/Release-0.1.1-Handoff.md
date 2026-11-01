# 0.1.1 release handoff

Prepared version: **0.1.1**, **build 8**. Confirm these are still unused before building; build 7 was published as 0.1.0. No 0.1.1 artifact or OTA item has been published by this preparation.

## Ivan: build and notarize

Hristijan's Mac has no valid Developer ID identity for team `DD94BC69WN`. Build on Ivan's release Mac with the existing Developer ID Application identity and his own local notarization profile. GitHub collaborator access alone does not provide signing credentials.

Pull the prepared commit from main into a clean checkout, record its SHA, and use the existing scripts:

```sh
git pull --ff-only origin main
git status --short
git rev-parse HEAD
python3 Scripts/release.py preflight --team-id DD94BC69WN --keychain-profile dogbar-notary
python3 Scripts/release.py build --team-id DD94BC69WN --keychain-profile dogbar-notary --version 0.1.1 --build 8
python3 Scripts/release.py verify --team-id DD94BC69WN --version 0.1.1 --build 8 --release-dir dist/DogBar-0.1.1-arm64
```

Use Ivan's actual profile name if it differs from `dogbar-notary`. These scripts embed and sign Sparkle and the onboarding resources, notarize/staple both the app and DMG, and write `release.json` and `provenance.json` only after verification. Do not use the older manual packaging flow that produced 0.1.0 without Sparkle.

Return the exact DMG, `release.json`, `provenance.json`, final SHA-256, source SHA and successful verification output. Keep all three files in `dist/DogBar-0.1.1-arm64/`. Never re-sign or modify the DMG after its final hash.

## Hristijan: sign the OTA feed and publish

Use the existing Sparkle private key in the login Keychain under `dev.hristijan.dogbar`. Ivan does not need it if Hristijan signs the feed. Neither person needs the other's Apple password or private keys for this division of work.

After receiving and independently verifying Ivan's exact artifact, set the full known hash (not a placeholder) in the following commands:

```sh
python3 Scripts/ota.py appcast --channel stable --team-id DD94BC69WN --version 0.1.1 --build 8 --sha256 "$DOGBAR_RELEASE_SHA256" --notes Docs/ReleaseNotes/0.1.1.md
python3 Scripts/ota.py verify --dir dist/ota/DogBar-0.1.1-arm64 --sha256 "$DOGBAR_RELEASE_SHA256"
python3 Scripts/release.py stage --team-id DD94BC69WN --version 0.1.1 --build 8 --release-dir dist/DogBar-0.1.1-arm64
python3 Scripts/ota.py stage --dir dist/ota/DogBar-0.1.1-arm64 --sha256 "$DOGBAR_RELEASE_SHA256"
```

Tag the exact source SHA Ivan built, upload that same DMG and its checksum to the prepared GitHub draft, and publish it only after artifact acceptance. Commit the staged release manifest and signed appcast, then deploy landing with its ignored downloads directory included. Keep all older download files available. Do not create a fabricated manifest or unsigned appcast while waiting for Ivan.

Verify live DMG hashes against the build record and GitHub mirror; verify the live feed is byte-identical to the signed local file. Test Check for Updates → Install and Relaunch from an older Sparkle-enabled build. Verify the native Dock is restored on quit, settings survive, and the installed app reports version 0.1.1/build 8 with a valid signature.

Public 0.1.0 and preview 5 have no Sparkle, so users need one manual 0.1.1 install before future OTA updates. Publishing a feed cannot retrofit an updater into those installed apps.
