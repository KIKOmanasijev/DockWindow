# Unnotarized DogBar previews

The owner has explicitly chosen to offer an experimental preview before Apple Developer enrollment. This is a separate path from `Scripts/release.py`, whose Developer ID and notarization checks stay strict.

Preview downloads must be labelled **Unnotarized preview** at the download action. A self-signed code signature binds the bundle to the existing DockWindow Dev certificate and detects modification. It does not establish an Apple-verified developer identity, prove functional quality, or replace notarization. Gatekeeper can block this app. No Apple Developer credentials, private-key export or trust changes are needed to package this preview.

## Build

From the repository root on a Mac with Xcode and an arm64-capable Swift toolchain:

```sh
python3 Scripts/build-preview.py --version 0.1.0-preview.1 --build 2
```

The default certificate fingerprint is the existing DockWindow Dev identity, `F6525801B1C563EA82693EBE71D63C6CA41538C6`. This is a public certificate identifier, not a private key. If that local identity is deliberately replaced, pass its new SHA-1 fingerprint using `--identity`. The tool requires that the named identity is actually available and rejects ad-hoc fallback. It searches signing-capable identities rather than valid-only identities because the local self-signed certificate is not trusted by Apple's policy.

Choose a new version for each published artifact, for example `0.1.0-preview.2`, and an increasing positive build number. The tool never overwrites an existing version directory, including failed output. Inspect or archive failed build diagnostics yourself before deciding how to retry. It never installs, quits or launches the development app and never changes its bundle or permissions.

The output directory is:

```text
dist/DogBar-0.1.0-preview.1-arm64/
  build/                                  isolated Swift build
  image/DogBar.app                         assembled preview app
  image/Applications                       /Applications shortcut
  image/Read Me.txt                        installation and preview disclosure
  DogBar-0.1.0-preview.1-arm64.dmg           compressed, read-only disk image
  provenance.json                         certificate fingerprint and final hash
  release.json                            explicit unnotarized preview metadata
```

The app retains identifier `com.dockwindow.app`, executable `DockWindow` and its existing settings keys. Its distribution bundle is `DogBar.app`. `CFBundleShortVersionString` is numeric (`0.1.0`); `DogBarPreviewVersion` carries the complete `0.1.0-preview.1` label. This keeps normal bundle-version metadata while marking the preview honestly.

The helper builds for Apple Silicon and macOS 14.0, checks exact entitlements, signs the app with hardened runtime and the existing self-signed certificate, and verifies the code signature against that certificate and bundle ID. It packages only the app, Applications shortcut and installation note. It signs the DMG, checks UDZO image integrity, mounts it read-only, verifies the contained app again, checks the installation note and Applications shortcut, then detaches it. SHA-256 is calculated after signing and must remain unchanged through verification. A success manifest is created only after those checks pass. There is no notarization submission, stapled ticket, Gatekeeper-success claim or website publication.

## Verify before staging

Use the SHA-256 printed after the successful build:

```sh
python3 Scripts/build-preview.py \
  --version 0.1.0-preview.1 --build 2 \
  --verify-dmg dist/DogBar-0.1.0-preview.1-arm64/DogBar-0.1.0-preview.1-arm64.dmg \
  --sha256 FINAL_SHA256
```

The expected hash must come from the build record or an independently known value. Local metadata is not proof of authenticity. Verification repeats signature, image, read-only mount and contained-app checks. It does not require access to the private signing key.

The manifest explicitly contains:

```json
{
  "available": true,
  "notarized": false,
  "channel": "preview",
  "signing": "self-signed",
  "version": "0.1.0-preview.1",
  "build": "2",
  "url": "/downloads/DogBar-0.1.0-preview.1-arm64.dmg",
  "sha256": "the final 64-character lowercase SHA-256",
  "architecture": "arm64",
  "minimumMacOS": "14.0"
}
```

## Host and download

After verification, copy only the DMG into the ignored `landing/downloads/` directory and copy the generated release.json to landing/preview.json and publish it with the static site. The notarized landing/release.json stays unchanged. The target public URL is `https://dogbar.hristijan.dev/downloads/DogBar-0.1.0-preview.1-arm64.dmg`. The build helper intentionally performs neither staging nor deployment. Keep versioned filenames immutable and include older advertised images in later deployments. Never upload the isolated Swift build, app staging directory, provenance, logs, Keychain items or credentials.

Serve downloads with `Content-Type: application/x-apple-diskimage`, attachment disposition and immutable caching. Serve both `preview.json` and `release.json` with `Cache-Control: no-store`. The website prefers a verified notarized release and otherwise accepts only an explicitly self-signed preview manifest. Before enabling a CTA, fetch the deployed artifact through HTTPS, compare its full SHA-256 with the build record, and verify that both hero and footer disclose its unnotarized preview status. The repository is private, so its release URLs cannot serve as anonymous public downloads.

The existing Developer ID tool must not stage this preview. Its refusal is intentional: preview metadata does not satisfy the notarized-release contract. Website support for an explicitly disclosed preview is a separate integration step.

## Installing a downloaded preview

Copy DogBar into Applications and try to open it. If macOS blocks it, review the source and signature first. Apple's macOS 27 guide describes **System Settings > Privacy & Security > Security > Open > Open Anyway**. The exception button appears after an opening attempt and is available for about an hour. macOS may require the user's login password. This is a per-app decision made by the user; the package does not change security settings automatically. See [Apple's macOS 27 instructions](https://support.apple.com/en-euro/guide/mac-help/mh40617/27/mac/27) and [Open apps safely](https://support.apple.com/102445).

After launch, grant Accessibility and Screen Recording in System Settings. Replacing a differently signed installation may require approving access again. A clean Mac or VM should test the actual downloaded, quarantined DMG through Finder under ordinary security settings. No quarantined download has been accepted merely because local signature verification passes.

## Tests

```sh
python3 -m unittest discover -s Tests/ReleaseTests -p test_preview.py -v
```

These standard-library fixture tests cover version and path validation, fixed identity selection, immutable outputs, signature requirements, exact entitlements, failure gating, read-only image inspection and cleanup. They do not sign a real artifact, establish Apple trust, or test installation on a fresh Mac. They have no database integration.
