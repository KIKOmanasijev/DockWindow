# Commercial mode (internal)

Developer reference for how a DogBar build decides access. Not customer copy: the app and website only ever say DogBar is free.

## Current state

- `Config/commercial.json` → `"mode": "free"`. This is the single source of truth.
- Every build (`build-app.sh`/`run.sh`, `build-preview.py`, `release.py`) runs `Scripts/license_packaging.py`, which writes `DogBarCommercialMode = free` into the bundle before signing and strips any `DogBarLicense*` keys. A free build refuses `DOGBAR_LICENSE_CONFIG` instead of silently embedding it.
- At runtime `CommercialPolicy.current` reads that key from the signed bundle. `AppAccess.shared` is the only access decision (`allowsFeatures`). In free mode it creates no `LicenseManager`: no Keychain item, no license network request, no License page in Settings or search, no activation prompt.
- A free binary has no code path that can lock it later. Nothing remote is consulted, and anything other than a complete paid configuration (missing key, unknown value, paid without valid licensing) resolves to free.
- The `paid` block holds internal values only: USD, `priceCents: 399`, one-time. They are not written to the app bundle or the website. `Scripts/check_commercial_policy.py` fails if the price appears in deployed landing files.

## Switching to paid

Paid is a deliberate source change plus a new signed release; it never applies to builds already downloaded. `license_packaging.py` refuses a paid build until all of these are true:

1. `Config/commercial.json` → `"mode": "paid"` (the `DOGBAR_COMMERCIAL_MODE` env var can only force `free`, for local work).
2. `paid.checkoutURL` is a verified Paddle hosted-checkout URL (`pay.paddle.io/hsc_…`; previews may use `sandbox-pay.paddle.io`).
3. `paid.freeUserTransition` records the owner-approved plan for people already running the free build (see below). It is `null` on purpose.
4. `DOGBAR_LICENSE_CONFIG` points to the public config exported by `licensing/scripts/export-app-config.mjs` with `required: true`; stable also needs `environment: live`.

Then:

5. Build and verify a paid landing presentation with a live Buy button. `check_commercial_policy.py` fails in paid mode until that exists, so the free page cannot be deployed next to a paid build by accident.
6. Release through the existing `release.py` flow (Ivan's Developer ID signing and notarization, Sparkle EdDSA signing, manifest/appcast staging). None of those gates change.
7. Do one real live purchase → email → activation → renewal → refund round trip before you link the release publicly.

To go back to free, set `"mode": "free"` and ship a new release. Paid builds keep their own licensing.

## Required before charging (not implemented)

- **Paddle**: a live USD 3.99 one-time price on the DogBar product. The existing live price `pri_01m6gqf3kg6gex648cbdekhkky` is USD 7.99 from the earlier plan and must not be reused. Live hosted-checkout access for `dogbar.hristijan.dev` is still pending with Paddle.
- **Webhooks**: the `licensing/` backend verifies Paddle signatures and handles `transaction.completed`, `adjustment.created` and `adjustment.updated`. Re-review it against the final terms before enabling `CHECKOUT_ENABLED` in production.
- **License generation and offline verification**: the backend issues Ed25519-signed entitlements (`kid`, issuer `dogbar-licensing`, audience `dev.hristijan.dogbar`, bound to a random installation ID). The app verifies them offline against the key pinned at build time (`LicenseVerifier`). The license signing key is separate from Sparkle's EdDSA update key and from the Apple Developer ID identity. Never reuse or exchange them, and never put private material in `DOGBAR_LICENSE_CONFIG`.
- **Copy**: the backend emails and admin gift mail still say "lifetime" and use `maxDevices`. The paid Settings page now avoids lifetime, device-count and offline-day promises. Update all of these once the terms are decided.

## Decisions not made

Trial length, device or seat limits, update entitlement, refund revocation and the free-user transition all still need the owner's decision. A paid release delivered over the existing Sparkle feed would require activation from current free users, so `freeUserTransition` stays `null` until that is decided and implemented. Nothing in the code grandfathers or migrates anyone automatically.

## Checks

- `python3 Scripts/check_commercial_policy.py`: static agreement between config, `Resources/Info.plist` and the deployed landing files.
- `Tests/ReleaseTests/test_license_packaging.py` and `Tests/DogBarCoreTests/CommercialPolicyTests.swift` cover the packaging guards and the free/paid resolution.
- The source stays MIT-licensed. Paid enforcement is a convenience for the official signed build, not a technical lock on the source.
