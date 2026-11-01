# Releasing DogBar

How a new DogBar version goes out. The website ([dogbar.hristijan.dev](https://dogbar.hristijan.dev/#get)) is the main download and serves its own copy of each DMG. [GitHub Releases](https://github.com/KIKOmanasijev/DockWindow/releases) is a mirror of the same bytes, plus release notes and a checksum. The website never links to GitHub; its download checks accept only same-origin `/downloads/` files.

Building and verifying are covered in detail by [PreviewDistribution.md](PreviewDistribution.md) (self-signed previews, available now) and [Distribution.md](Distribution.md) (notarized releases, once enrolled in the Apple Developer Program). This page is the checklist around them.

## Versions and tags

| Channel | Version | Git tag | GitHub release |
| --- | --- | --- | --- |
| Self-signed preview | `0.1.0-preview.N` | `v0.1.0-preview.N` | Pre-release |
| Notarized release | `1.0.0` | `v1.0.0` | Latest |

- The build number (`--build`) always increases, across both channels.
- A published version is never rebuilt or replaced. If something is wrong, publish the next version.
- The DMG is always named `DogBar-<version>-arm64.dmg`.

## Checklist

1. **Start clean.** On an up-to-date `main` with no uncommitted changes, run:

   ```sh
   swift test
   python3 -m unittest discover -s Tests/ReleaseTests -v
   ```

   Add the version's changes to the release notes you will publish (step 6).

2. **Build.**
   - Preview: `python3 Scripts/build-preview.py --version 0.1.0-preview.2 --build 3`
   - Notarized: the `release.py preflight`, `build-release.sh` and `release.py verify` steps in [Distribution.md](Distribution.md).

3. **Verify.** Run the build tool's verification with the SHA-256 it printed (`--verify-dmg … --sha256 …` for previews, `release.py verify` for notarized builds). Then download the DMG onto a clean Mac or VM, install it the normal way and check the app starts, asks for permissions and switches windows.

4. **Tag the commit you built.**

   ```sh
   git tag -a v0.1.0-preview.2 -m "DogBar 0.1.0 preview 2"
   git push origin v0.1.0-preview.2
   ```

5. **Write the checksum file.**

   ```sh
   cd dist/DogBar-0.1.0-preview.2-arm64
   shasum -a 256 DogBar-0.1.0-preview.2-arm64.dmg > DogBar-0.1.0-preview.2-arm64.dmg.sha256
   ```

6. **Publish the GitHub release.**

   ```sh
   gh release create v0.1.0-preview.2 \
     DogBar-0.1.0-preview.2-arm64.dmg DogBar-0.1.0-preview.2-arm64.dmg.sha256 \
     --verify-tag --prerelease \
     --title "DogBar 0.1.0 preview 2" --notes-file notes.md
   ```

   - Previews use `--prerelease`. Notarized releases use `--latest` instead.
   - Never replace a published file (`gh release upload --clobber`). Publish a new version instead.
   - Preview notes must start with: *Unnotarized, self-signed preview for Apple Silicon Macs on macOS 26 or later.* Then list what changed, the install steps from the README (including System Settings → Privacy & Security → Open Anyway) and the SHA-256.

7. **Update the website.**
   - Generate and verify the signed appcast (`Scripts/ota.py appcast` and `verify`, see [Updates.md](Updates.md)).
   - Preview: `Scripts/ota.py stage` copies the DMG into `landing/downloads/` (ignored by git, but uploaded with the site), updates `landing/preview.json`, then `landing/appcast.xml` last. Notarized: run `release.py stage` for `landing/release.json`, then `ota.py stage` for the feed. Keep older DMGs in `landing/downloads/`.
   - Commit `landing/appcast.xml` and the manifest, then deploy the `landing/` folder.

8. **Check the live download.** Download the DMG from the website and from GitHub and confirm both have the SHA-256 from the build record:

   ```sh
   curl -sL https://dogbar.hristijan.dev/downloads/DogBar-0.1.0-preview.2-arm64.dmg | shasum -a 256
   gh release download v0.1.0-preview.2 -p '*.dmg' -O - | shasum -a 256
   ```

   Then confirm the website's download buttons show the new version.

## Notes

- **Bundle ID change.** `0.1.0-preview.1` was built as DockWindow (`com.dockwindow.app`). Later builds are `dev.hristijan.dogbar`, so the first update from it asks for Accessibility and Screen Recording again and starts with default settings. Say so in that release's notes.
- **Signing keys stay on your Mac.** Previews are signed with the local `DockWindow Dev` certificate. Don't export its private key to CI.
- **Later, once notarizing:** steps 2–6 can move into a GitHub Actions workflow that runs on a macOS runner when a `v*` tag is pushed. It needs the Developer ID certificate and an App Store Connect API key as repository secrets. A Homebrew cask is worth adding after notarized releases exist.

## Proposed signed release and OTA rollout

Before the first notarized release, choose the long-term publishing team. A friend's authorized team can sign DogBar, but its name and Team ID become the signing identity. Keep `dev.hristijan.dogbar` stable. Moving from the local self-signed identity to Developer ID can require fresh privacy grants; test that migration on a separate Mac. Do not borrow an Apple Account password.

The Account Holder creates a Developer ID Application certificate. Notarization credentials are separate from the code-signing private key. Apple documents these steps in [Developer ID](https://developer.apple.com/developer-id/) and [custom notarization workflows](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow). Team access differs between Individual and Organization memberships.

A production automation pipeline should run only on a reviewed release tag, such as `v0.2.0`, on a macOS runner with the selected Xcode version. Validate tag/version/build metadata against the exact checkout; do not rebuild another commit. Require approval through a protected GitHub release environment before exposing signing credentials. Pin third-party Actions to reviewed commit SHAs. Never expose signing secrets to pull-request jobs.

Recommended sequence:

1. Build and run release acceptance checks against that commit.
2. Import the Developer ID identity into an ephemeral CI Keychain. Use protected environment secrets for the encrypted certificate, its password, notarization key, and OTA signing key. Remove the temporary Keychain and credential files at job completion.
3. Sign the app with hardened runtime and secure timestamp. Sign any nested framework/helpers first, then the outer app. Submit to Apple's notary service, require Accepted, and staple/validate tickets.
4. Package, sign, notarize and verify the DMG using the existing release gates. Calculate SHA-256 after stapling. Keep versioned files immutable.
5. Create a draft GitHub Release with the exact DMG, checksum and release notes. Preview tags are prereleases; stable tags are stable releases.
6. Upload those exact bytes to the website's versioned download path. Download them back and verify the hash.
7. Publish the GitHub release, then publish the website manifest and OTA feed last. Users should never see an update until its artifact is reachable and verified.

In-app updates use Sparkle 2 with a signed appcast at `https://dogbar.hristijan.dev/appcast.xml`. [Updates.md](Updates.md) covers the trust model, channels, key custody, the publish sequence (`Scripts/ota.py appcast`, `verify`, `stage`), the one manual bridge from pre-OTA previews and the Developer ID transition. The CI pipeline above is still a proposal. Update signing stays on the release Mac until it moves to a protected environment secret.
