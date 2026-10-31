# DogBar direct distribution

Notarized releases require an authorized Apple Developer Program team and its Developer ID Application identity. No public signing team is configured yet. The local DockWindow Dev self-signed certificate provides no Apple-verified public trust. An explicitly labelled [unnotarized preview](PreviewDistribution.md) is offered through a separate build and `landing/preview.json`. The strict notarized-release manifest, `landing/release.json`, intentionally remains unavailable.

Releases can be published by your own enrolled team or another team that explicitly authorizes distributing DogBar under its publisher identity. The team’s Account Holder controls Developer ID certificate issuance. Enrollment, team authorization, certificate issuance, and credential entry are owner actions. These scripts do not perform them, ask for secrets, export keys, alter trust, clear permissions, bypass quarantine, or disable Gatekeeper.

## One-time owner setup

1. Install full Xcode and select its command-line tools in Xcode Settings > Locations. Complete Xcode's first-launch setup. macOS 26 or later and an arm64-capable Swift toolchain are required. Releases target Apple Silicon and macOS 26.0 only.
2. After enrollment, use the account's Team ID. In Xcode Settings > Accounts, select the team and Manage Certificates, then create a **Developer ID Application** certificate. Alternatively, the Account Holder can follow [Apple's Developer ID certificate instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/) using a locally generated CSR in Keychain Access and install the issued certificate. Keep the corresponding private key in your local Keychain. Developer ID Installer, Apple Development, and a self-signed certificate are not substitutes.
3. Confirm the identity is valid using `security find-identity -v -p codesigning`. The certificate name must be `Developer ID Application: ... (YOURTEAMID)`. Multiple matching identities require an explicit `--identity` SHA-1 fingerprint from this command. The fingerprint is an identifier, not a secret. The release additionally verifies Apple's certificate anchor, Developer ID Application certificate OID, and TeamIdentifier on the actual artifact.
4. Create an app-specific password in your Apple Account. Store notarization credentials interactively in the local Keychain:

   ```sh
   xcrun notarytool store-credentials dogbar-notary
   ```

   Enter the Apple ID, app-specific password, and Team ID at Apple's prompts. The tool validates credentials by default. Do not use `--password`, environment exports, credential files in this repository, or assistant chat for secrets. Do not add `--sync` if you want credentials confined to the local Keychain. The release only receives the nonsecret profile name. A Keychain access dialog during signing must be handled locally by the owner.

## Build and independently verify

Run from the repository root. Replace `YOURTEAMID` with the actual ten-character Team ID. Choose a new numeric `MAJOR.MINOR.PATCH` version and an explicit increasing positive integer build number. These example values are instructions, not a claim that a release exists.

```sh
python3 Scripts/release.py preflight --team-id YOURTEAMID --keychain-profile dogbar-notary
Scripts/build-release.sh --team-id YOURTEAMID --keychain-profile dogbar-notary --version 1.0.0 --build 1
python3 Scripts/release.py verify --team-id YOURTEAMID --version 1.0.0 --build 1 --release-dir dist/DogBar-1.0.0-arm64
```

Use `python3 Scripts/release.py build` if preferred. Add `--identity FINGERPRINT` to preflight/build only when necessary. No dependencies are installed. Tests use Python's standard library:

```sh
python3 -m unittest discover -s Tests/ReleaseTests -v
```

The helper never calls `Scripts/build-app.sh`, installs or launches an app, quits a running process, or touches `~/Applications/DogBar.app`. It builds with `swift build -c release --triple arm64-apple-macosx26.0 --product DogBar --scratch-path ...` inside a new `dist/DogBar-<version>-arm64/` directory. Bundle display/name is DogBar and the distribution bundle is `DogBar.app`; identifier `dev.hristijan.dogbar` and executable `DogBar` match the development build, so permissions and settings carry across.

Release sequence:

1. Check Apple tools, one valid matching Developer ID Application identity, and the explicitly named Keychain profile. No identity or credentials means failure before the build.
2. Assemble a fresh app from the release executable, `Resources/Info.plist`, and `Resources/AppIcon.icns`. Override only release metadata, names, and the stable native identifiers. Use the existing entitlements, currently only Apple Events automation. An entitlement change stops the release for review. Never add `get-task-allow`, disable library validation, or allow unsigned executable memory to make notarization pass.
3. Sign with hardened runtime and Apple's secure timestamp. Verify with `codesign --verify --deep --strict` and an Apple-anchored Developer ID/Team ID requirement. Never sign with `--deep`. There is currently one native executable with Apple/system frameworks and no bundled nested code. New helpers, frameworks, plug-ins, or runtime resources require an explicit assembly/signing review before using this helper.
4. ZIP the app with `ditto`, submit using `notarytool --keychain-profile NAME --wait --output-format json`, require the actual status `Accepted`, record submission JSON and Apple's log, staple the app, validate its ticket, and assess it with Gatekeeper.
5. Create a compressed read-only UDZO DMG with `DogBar.app` and a symlink to `/Applications`. Sign the DMG with the same identity and secure timestamp. Submit the DMG separately, require `Accepted`, record its submission/log, staple, and validate it. Two notarizations intentionally allow the inner app to be stapled before packaging.
6. Verify the DMG signature, Apple anchor, Team ID, timestamp, stapled ticket, Gatekeeper's `Notarized Developer ID` source, image integrity, and UDZO format. Mount it read-only without opening Finder, recheck the contained app's version/build, arm64 architecture, entitlements, signature and ticket, then detach. Compute the final SHA-256 after stapling. Recheck the hash after verification. Only then write provenance and the ready manifest.

Output contains the DMG, staged app, isolated Swift build, notary ZIP, logs, `provenance.json`, and `release.json`. Only the DMG is public. Logs include submission IDs but no credential values. Review Apple's log warnings. Failed runs preserve their isolated diagnostics and produce no successful release manifest. Submission/network failures stop the pipeline. An existing version directory is never overwritten, even after failure. Inspect and archive a failed directory outside `dist` yourself before retrying that unreleased version, or choose a new version. Do not delete an already published version to rebuild it. No automatic destructive cleanup is performed.

## Stage for the website, then publish separately

After verification and functional acceptance, explicitly stage:

```sh
python3 Scripts/release.py stage --team-id YOURTEAMID --version 1.0.0 --build 1 --release-dir dist/DogBar-1.0.0-arm64
```

This command copies to a temporary candidate, checks its hash against local build provenance, requires both recorded submissions to be `Accepted`, and independently revalidates the actual candidate's Apple signature, Team ID, Gatekeeper results, stapled DMG and app tickets, image integrity and inner app metadata. The local JSON is not trust proof. Verify/stage do not require a signing key or notarization profile, but Apple validation may need network access and can fail if trust or notarization is revoked. Supply the intended Team ID independently; do not obtain it from an untrusted artifact.

Only approved bytes enter `landing/downloads/DogBar-<version>-arm64.dmg`, followed by an atomic replacement of `landing/release.json`. Different bytes cannot overwrite an existing versioned filename. Identical staging is idempotent after full validation. A version older than the currently advertised version is rejected. Run only one release/staging operation at a time, and finish staging before deploying the landing directory. Keep older versioned DMGs available. Do not deploy temporary candidate folders, logs, the ZIP, or `dist`. No helper commits, pushes, or deploys anything.

Deploy the static landing site to Vercel separately after staging the verified release. Use the same-origin public path `https://dogbar.hristijan.dev/downloads/DogBar-<version>-arm64.dmg`. The website never links to GitHub release assets or redirects downloads there; the GitHub release is a mirror of the same bytes (see [Releasing.md](Releasing.md)). Never embed GitHub credentials. Ensure the Vercel project's static root and file-size limits support the actual DMG before deployment. Serve the DMG as `application/x-apple-diskimage` with an attachment filename, immutable caching for versioned files, and revalidation/no-cache for `release.json`. Do not apply immutable caching to the manifest.

The UI contract is exactly:

```json
{"available":false,"version":null,"url":null,"sha256":null,"architecture":"arm64","minimumMacOS":"26.0","notarized":false}
```

On success, `available` and `notarized` become true, `version` is the validated release version, `url` is exactly `/downloads/DogBar-<version>-arm64.dmg`, and `sha256` is 64 lowercase hexadecimal characters. Hero and footer should consume the same manifest and enable downloads only for a valid ready response. Treat fetch failures, malformed/unsafe paths, or incomplete fields as unavailable. Do not invent a download URL, set notarized true for a demo, or fall back to an off-site asset. Initial public UI remains gated until a genuine release is staged.

After deployment, download over HTTPS, compare SHA-256 using `shasum -a 256`, and test the downloaded quarantined DMG/app through Finder on a fresh supported Mac or clean VM. Do not strip quarantine to make a test pass. Confirm the app copies into Applications and launches under default security settings. This manual acceptance step remains necessary even when command-line checks pass.

## What the checks mean

Code signing binds contents to an Apple-issued developer identity and detects modification. A secure timestamp authenticates signing time. Notarization is Apple's automated security check and ticket issuance. Stapling carries a ticket with the app/image for offline checking. HTTPS protects delivery; SHA-256 detects a byte mismatch against the advertised value. A checksum served from the same compromised origin does not independently establish publisher identity.

None of these proves functional quality, performance, accessibility behavior, or compatibility of private APIs. DogBar's private API usage, native Dock restoration, permissions, supported macOS behavior, and current functional/performance acceptance must be evaluated separately. Notarization is not App Store review or an endorsement of private API use.

## Verified Apple references

Commands were checked against local `codesign(1)`, `spctl(8)`, `security find-identity -h`, `swift build --help`, `ditto -h`, `hdiutil create/attach/imageinfo -help`, and `xcrun notarytool submit/store-credentials/log --help` on 2026-10-30. `stapler` prints usage on invalid/missing arguments; use its `staple` and `validate` subcommands. This macOS prints a deprecation warning for hdiutil in favor of diskutil image commands; hdiutil remains supported locally and is used here as requested. The implementation keeps stdout separate from successful-tool warning text when parsing JSON and image format.

- [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple: Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Apple: Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)
- [Apple TN2206: Code signing and disk image Gatekeeper assessment](https://developer.apple.com/library/archive/technotes/tn2206/)
- [Apple DTS: Testing a notarised product and preliminary checks](https://developer.apple.com/forums/topics/code-signing-topic)

No notarized artifact can be produced until the owner supplies the genuine Apple identity and locally stored notarization credentials. The separate preview download does not satisfy this guide's notarized-release checks.
