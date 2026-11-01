# In-app updates (Sparkle 2)

DogBar updates itself with [Sparkle](https://sparkle-project.org/documentation/) 2.10.1, pinned exactly in `Package.swift` and `Package.resolved`. Upgrading Sparkle is a reviewed change: update both pins, `VERSION` in `Scripts/sparkle_packaging.py`, and the selector comments in `Sources/DogBar/UpdateController.swift` and `Sources/DogBarSparkleBridge`.

## What a user sees

- **Check for Updates…** (app and menu bar menus) and **Settings > General > Updates > Check Now** run Sparkle's standard update check.
- On DogBar's second launch, Sparkle asks once whether to check automatically. The answer can be changed later in Settings > General > Updates. Checks run about once a day.
- Updates never install silently. `SUAutomaticallyUpdate` and `SUAllowsAutomaticUpdates` are both off, so every update waits for **Install and Relaunch**. Sparkle then sends DogBar a normal quit event. `applicationShouldTerminate` restores the native Dock before the process exits, and the installer waits for that. If restoration fails, quitting is cancelled and the update stays pending.

## Trust model

| Check | Where |
| --- | --- |
| Feed is Ed25519-signed (`SURequireSignedFeed`), no fallback after failures (`SUSignedFeedFailureExpirationInterval` 0) | Sparkle |
| Archive is Ed25519-signed and verified before extraction (`SUVerifyUpdateBeforeExtraction`) | Sparkle |
| New app's code signature is valid and matches the installed app's | Sparkle |
| Download is `https://dogbar.hristijan.dev/downloads/DogBar-<version>-arm64.dmg`, build is higher than the installed build, channel matches, macOS floor ≥ 26 and ≤ this Mac, arm64 required | `UpdatePolicy` in DogBarCore |
| Feed URL is fixed by the bundle; a feed URL left in user defaults is cleared | `UpdateController` |

Update signing is independent of Apple code signing. The public key `PNudz/8nyHP1fR6ADTVhfXAciGkEoyOpTEgHkJ8Hb/0=` is in `Resources/Info.plist` and `Scripts/sparkle_packaging.py`. The private key exists only in the release Mac's login Keychain under the account `dev.hristijan.dogbar`, created with Sparkle's `generate_keys --account dev.hristijan.dogbar`. Never export it (`-x`), print it, copy it to CI or the web host, or paste it into chat. Losing it means every installed copy needs one more manual install. Keep a Keychain backup that you control.

A SHA-256 published next to the file on the same server does not authenticate the publisher. The Ed25519 signatures do, as long as the private key stays off the server.

### Self-signed builds and library validation

Self-signed code has no Team ID, so hardened-runtime library validation refuses to load a separately signed framework ("mapping process and mapped file (non-platform) have different Team IDs"). Previews and local builds are therefore signed with `Resources/DogBar-SelfSigned.entitlements`, which adds `com.apple.security.cs.disable-library-validation`. To limit the exposure:

- DogBar does not link Sparkle. Nothing outside Apple's system libraries is mapped at launch.
- Before loading `Contents/Frameworks/Sparkle.framework`, `UpdateController` requires it to be a real directory inside the bundle that satisfies `identifier "org.sparkle-project.Sparkle" and certificate leaf = H"<this app's own leaf certificate>"`, with strict validation of nested code. A substituted or re-signed framework is not loaded, and updates are disabled instead.
- Hardened runtime still blocks `DYLD_*` injection.

There is still a short window between that check and `dlopen`. Developer ID releases use `Resources/DogBar.entitlements`, keep library validation on, and are checked by `release.py`, which rejects the extra entitlement.

### Gatekeeper

The first install of a preview comes from a quarantined DMG and goes through Gatekeeper's **Open Anyway** flow (see [PreviewDistribution.md](PreviewDistribution.md)). Later updates are downloaded by the already-approved app. Sparkle's installer clears any quarantine attribute from the new bundle (`SUPlainInstaller`). That is upstream's design: it relies on the EdDSA signature and the matching code signature instead of a second Gatekeeper prompt. DogBar does not change system security settings. An unnotarized update therefore installs without a new Gatekeeper prompt. This is why the update key must stay private.

## Channels

The packaging scripts write `DogBarUpdateChannel` into the signed Info.plist. User defaults cannot change it.

| Build | `DogBarUpdateChannel` | Sees |
| --- | --- | --- |
| `Scripts/build-app.sh` / `run.sh` (local) | `preview` | preview and stable items |
| `Scripts/build-preview.py` | `preview` | preview and stable items |
| `Scripts/release.py` (Developer ID) | `stable` | stable items only |

Preview items carry `<sparkle:channel>preview</sparkle:channel>`. Stable items have no channel. `ota.py` rejects a preview-named archive without the preview channel, and `UpdatePolicy` rejects preview filenames on stable builds even if the feed is wrong. Choosing previews is explicit: you install a preview build. A stable build never moves to previews by itself.

Sparkle compares `CFBundleVersion` (the build number), which increases across both channels. It never offers an equal or lower build, so a downgrade cannot happen. Local builds keep the low base build number from `Resources/Info.plist`, so they are offered the newest published build.

## Publishing an update

All artifacts are immutable. Never rebuild, re-sign or replace a published version; publish the next one.

1. **Commit and build** from a clean tree (the preview builder refuses uncommitted source, resources or scripts):

   ```sh
   python3 Scripts/build-preview.py --version 0.1.0-preview.N --build B
   python3 Scripts/build-preview.py --version 0.1.0-preview.N --build B \
     --verify-dmg dist/DogBar-0.1.0-preview.N-arm64/DogBar-0.1.0-preview.N-arm64.dmg --sha256 SHA
   ```

   For a notarized release, use `release.py build` and `verify` as in [Distribution.md](Distribution.md).

2. **Write the release notes** to `Docs/ReleaseNotes/<version>.md`. They are embedded in the signed feed.

3. **Generate the signed appcast.** Allow the Keychain prompt for `generate_appcast` on the release Mac:

   ```sh
   python3 Scripts/ota.py appcast --channel preview --version 0.1.0-preview.N --build B \
     --sha256 SHA --notes Docs/ReleaseNotes/0.1.0-preview.N.md
   # Stable: --channel stable --team-id YOURTEAMID
   ```

   This repeats the channel's full DMG verification, then works in a new `dist/ota/DogBar-<version>-arm64/` directory. It starts from the published `landing/appcast.xml` after checking that file's signature, and runs Sparkle's `generate_appcast` (no deltas, all items kept). It then checks, with its own RFC 8032 Ed25519 implementation and the pinned public key, that:
   - the feed signature is valid;
   - the archive signature and length match;
   - the URL is the versioned same-origin path;
   - the channel, macOS floor and arm64 requirement are correct;
   - the build is higher than every existing item, and every published item is unchanged.

   The result is recorded in `ota.json`.

4. **Re-verify** with the independently known hash: `python3 Scripts/ota.py verify --dir dist/ota/DogBar-<version>-arm64 --sha256 SHA`.

5. **Tag and mirror on GitHub** as in [Releasing.md](Releasing.md).

6. **Stage**, then deploy `landing/`:

   ```sh
   python3 Scripts/ota.py stage --dir dist/ota/DogBar-<version>-arm64 --sha256 SHA
   ```

   This copies the DMG into `landing/downloads/` (no-clobber; existing bytes must match), then `preview.json` for previews, then `landing/appcast.xml` last. It refuses a feed that would drop or change a published item. Commit `landing/appcast.xml` and `landing/preview.json`. The DMG stays out of git.

7. **Check live**: download `https://dogbar.hristijan.dev/downloads/<archive>` and compare SHA-256, then fetch `https://dogbar.hristijan.dev/appcast.xml` and confirm it is byte-identical to the staged file (`no-store`, `application/rss+xml`).

If you deploy the feed before its DMG is live, clients get a failed download, not a wrong install. Still, deploy both together, with the archive first.

## Bridges

- **Previews up to 0.1.0-preview.5** have no Sparkle. Their Check for Updates reads `preview.json` and opens the verified DMG for a manual install. Staging a preview updates `preview.json`, so those users make one manual install. From then on they update in the app.
- **Developer ID transition.** Keep the same EdDSA key. Sparkle accepts a change of Apple signing identity when the EdDSA signature still verifies, but not a change of both at once. The first Developer ID build ships with the `stable` channel. Self-signed preview installs see it as a stable item and can update to it. Moving to a new certificate can require granting Accessibility and Screen Recording again. Test that on a clean Mac before publishing. Rotate the EdDSA key only later, in a separate Developer ID-signed DMG release.

## Manual acceptance (not automated)

Validate on a real Mac before announcing:

1. Install the previous build (for example preview.6 from its DMG, or a local `run.sh` build), launch it, and grant permissions.
2. Publish the next build (N+1) with the steps above.
3. In the installed app, choose Check for Updates. Confirm the dialog shows the new build and its notes, then choose Install and Relaunch.
4. Confirm the native Dock restores before quit, DogBar relaunches as build N+1 (About DogBar), permissions and settings are kept, and `codesign --verify --deep --strict ~/Applications/DogBar.app` passes.
5. Negative checks: cancel a download; tamper with a copy of the feed (it must be rejected); confirm an older or equal build is not offered.
