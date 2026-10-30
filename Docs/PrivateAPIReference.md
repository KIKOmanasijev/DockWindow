# Private API and reference UI research

Research date: 2026-10-30. Scope: source inspection and read-only symbol/space-query checks. No app launch, build, database access, git operation, or focus event injection was performed. Read the complete authoritative attachment before researching. This file contains independently written findings, not copied implementation code.

## Sources pinned for reproducibility

- AltTab: [`c500294bdb01186011a5c64a412b04cef9931bef`](https://github.com/lwouis/alt-tab-macos/tree/c500294bdb01186011a5c64a412b04cef9931bef).
- DockDoor: [`3044142c907b9cdd49917628847a04970450a8e6`](https://github.com/ejbills/DockDoor/tree/3044142c907b9cdd49917628847a04970450a8e6).
- CGSInternal headers: [`c4f6f559d624dc1cfc2bf24c8c19dbf653317fcf`](https://github.com/NUIKit/CGSInternal/tree/c4f6f559d624dc1cfc2bf24c8c19dbf653317fcf). These are community reverse-engineered declarations, not Apple ABI guarantees.

References below use the exact files and line ranges at these commits. Upstream HEAD can move. Source files were fetched over HTTPS into `/tmp/dockwindow-research`, outside the repository. Upstream comments describing tests are upstream evidence, not tests performed for DockWindow.

## Corrections the implementation needs

1. **One `CGSCopySpacesForWindows` call for all windows cannot produce per-window membership.** Its result is a flat union of space IDs. The specification's single-call mapping requirement is incompatible with this API. Use singleton queries, or invert one windows-in-space query per Space. Never attach the aggregate result to every window or zip it against the input.
2. **Use a 64-bit space mask when matching the current reference implementations.** AltTab declares `Int`, DockDoor declares `UInt64`. The specification's `Int32` does not match either current binding. Both use value 7. Connection IDs are 32 bits; space IDs are 64 bits.
3. **Remote token scans are incomplete discovery, not a proof that an app has no windows.** Fixed IDs 0 through 999 miss high and sparse IDs. Time budgets cannot interrupt an AX IPC already in flight.
4. **The focus byte sequence has changed upstream.** Current AltTab posts a down event only at a far positive window-relative coordinate. Current DockDoor posts a down/up pair at (-1, -1). Prefer the current AltTab approach for evaluation on macOS 27, and manually test for unwanted clicks and resizing.
5. **A 0x200 focus mode means user generated.** It is not independently an assurance that only the target window moves or that no Space changes. The window ID, key-window record, Space scope, and app behavior all matter.
6. **No source establishes a universal new-window-on-this-Space guarantee.** App Space assignments, fullscreen behavior, app-specific commands and reopen behavior can defeat activation plus Cmd+N. Verify resulting membership and report failure rather than claiming success.

## ABI facts and runtime loading

Authoritative AltTab declarations for the required subset are in [SkyLight.framework.swift, lines 9-85 and 108-133](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/macos/api-wrappers/SkyLight.framework.swift#L9-L133) and [ApplicationServices.HIServices.framework.swift, lines 1-13 and 33-37](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/macos/api-wrappers/ApplicationServices.HIServices.framework.swift#L1-L37).

The following is ABI notation, not upstream implementation code. CF references are opaque C pointers. `CGError`, `AXError`, and `OSStatus` have signed 32-bit representations. `pid_t` is signed 32-bit. `CGWindowID` is unsigned 32-bit. Use `@convention(c)` function pointers from `dlsym`, not Swift calling-convention guesses.

| Symbol | C ABI shape | Evidence and cautions |
| --- | --- | --- |
| `CGSMainConnectionID`, alias `SLSMainConnectionID` | `uint32_t (void)` in current AltTab | AltTab lines 11, 24-25. Older CGSInternal calls this signed `int`, the same 32-bit ABI width. |
| `CGSGetActiveSpace` | `uint64_t (uint32_t connection)` | Not declared in the inspected AltTab file. Verified against CGSInternal `CGSSpace.h`, line 104. Prefer per-display current Space parsing. |
| `CGSCopyManagedDisplaySpaces` | `CFArrayRef (uint32_t connection)` | AltTab lines 43-44. DockDoor permits NULL. Model NULL safely. |
| `CGSManagedDisplayGetCurrentSpace` | `uint64_t (uint32_t connection, CFStringRef display)` | AltTab lines 68-69; `ScreenUuid` is the CF string display identifier. |
| `CGSCopySpacesForWindows` | `CFArrayRef (uint32_t connection, 64-bit mask, CFArrayRef windowIDs)` | AltTab uses signed `Int` mask; DockDoor uses unsigned `UInt64`. Mask 7 agrees. Returns nullable flat array of CFNumbers. |
| `_AXUIElementGetWindow` | `AXError (AXUIElementRef element, uint32_t *outWindowID)` | Check success and nonzero ID. Descendant elements can yield their containing window's ID too. |
| `_AXUIElementCreateWithRemoteToken` | `AXUIElementRef (CFDataRef token)` | Nullable retained result. AltTab and DockDoor use `takeRetainedValue()`. |
| `GetProcessForPID` | `OSStatus (pid_t pid, ProcessSerialNumber *outPSN)` | PSN has two consecutive UInt32 fields, high then low. Check zero status. |
| `_SLPSSetFrontProcessWithOptions` | `CGError (ProcessSerialNumber *psn, uint32_t windowID, uint32_t mode)` | Modes: 0x100 all windows, 0x200 user generated, 0x400 no windows. |
| `SLPSPostEventRecordTo` | `CGError (ProcessSerialNumber *psn, uint8_t *record)` | Record has no length argument. Correct allocation is essential. |

DockDoor corroborates these declarations in [Utilities/PrivateApis.swift, lines 39-122](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/Utilities/PrivateApis.swift#L39-L122). Its raw-pointer PSN callback binding is useful if a Swift-defined PSN struct is not representable in a C function type. Keep the raw pointer inside the wrapper and explicitly preserve the two-UInt32 layout.

Load SkyLight at `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight`. Resolve AX and process functions via ApplicationServices, whose HIServices symbols are re-exported, or load its HIServices subframework. Keep handles alive while pointers are used. Treat missing symbols as unavailable, never force-unwrap them. For runtime CF-returning pointers, wrap Copy/Create ownership explicitly with `Unmanaged` and consume the +1 result exactly once. Borrow input arguments for the duration of a call.

A read-only `ctypes` symbol lookup on this host resolved every symbol in the table, including both main-connection aliases. It also resolved `CGSCopyWindowsWithOptionsAndTags`. Symbol presence verifies neither a stable ABI nor successful focus/capture behavior. No focus routine was invoked.

## Remote token discovery

Exact evidence: [AltTab AXUIElement.swift, lines 215-300](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/macos/api-wrappers/AXUIElement.swift#L215-L300), [AltTab SchedulingPolicy.swift, lines 243-280](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/util/SchedulingPolicy.swift#L243-L280), and [DockDoor Extensions/AXUIElement.swift, lines 117-160](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/Extensions/AXUIElement.swift#L117-L160).

The token is **20 bytes**, packed without alignment padding:

| Offset | Size | Value |
| --- | --- | --- |
| 0 | 4 | signed process ID |
| 4 | 4 | zero |
| 8 | 4 | integer 0x636f636f |
| 12 | 8 | unsigned 64-bit AX element ID |

Use native little-endian bytes on the supported Macs. The magic integer's actual byte order is `6f 63 6f 63`; do not insert the ASCII bytes of “coco” in written order. An ordinary Swift struct with a UInt64 final field can introduce padding at offset 12 and a 24-byte size. Construct byte storage with explicit offsets instead. AX element IDs are not CGWindowIDs.

Recommended independent algorithm:

- Read the application's published windows, focused window, and main window first. Deduplicate by validated CGWindowID. AltTab's `windowsIncludingKeyAndMain()` at lines 213-218 accounts for incomplete current-Space window lists.
- Find missing WindowServer window IDs for each PID, then scan once for the whole missing set. Do not scan separately for each window.
- Maintain one 20-byte buffer per scan and replace the element-ID bytes. Validate returned objects before adoption. A matching CGWindowID alone is insufficient: require role `AXWindow`, an allowed subrole, and the usual size/WindowServer checks. Descendants can otherwise masquerade as roots.
- Use a monotonic time budget, such as AltTab's 250 ms, checked before every AX IPC. Run on an isolated background queue. Apply a short messaging timeout and backoff for unresponsive apps. One IPC may exceed the scan deadline by its timeout.
- Preserve a per-process resume cursor between slices when pursuing still-missing IDs. Reset it on PID generation changes and periodically rescan earlier ranges when inventory changes. Do not cache an absent range forever.
- Stop when all targeted roots are found, app termination invalidates the task, or the budget expires. Publish partial discovery rather than blocking UI or mislabeling unknown windows as absent.

DockDoor's 0..<1000 scan and two-error early exit are bounded, but are not complete for long-lived apps. Current AltTab explicitly moved to time-bounded UInt64 traversal. No finite scan guarantees discovery of arbitrary high, sparse IDs. A 250 ms scan for every app at every 1.5 s poll cannot meet the idle CPU target. Restrict scanning to gaps and lifecycle recovery, not the cheap membership timer.

## Exact-window focus record

Evidence: [AltTab SkyLight.framework.swift, lines 135-194](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/macos/api-wrappers/SkyLight.framework.swift#L135-L194); [DockDoor WindowUtil.swift, lines 2008-2028](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/Utilities/Window%20Management/WindowUtil.swift#L2008-L2028); [CGSInternal CGSEvent.h, lines 207-220](https://github.com/NUIKit/CGSInternal/blob/c4f6f559d624dc1cfc2bf24c8c19dbf653317fcf/CGSEvent.h#L207-L220).

Allocate **0x100 zeroed bytes**, while declaring a **0xf8-byte record** inside the buffer. Upstream documents out-of-bounds encoder reads with an exactly 0xf8-byte allocation on recent macOS.

| Offset | Encoded width | Current AltTab value |
| --- | --- | --- |
| 0x04 | 32-bit record length | 0x000000f8, achieved by setting byte 0x04 in the zeroed buffer |
| 0x08 | event type | 1, left mouse down; remaining bytes zero |
| 0x20 | 16-byte CGPoint | two native CGFloat/Double values: (300000, 300000) |
| 0x3a | 1 byte | 0x10; meaning remains undocumented |
| 0x3c | 4 bytes | target CGWindowID |
| other bytes | remaining storage | zero |

Current AltTab posts **only mouse down**. DockDoor posts types 1 then 2 using (-1, -1). Older implementations also used 0xff coordinate bytes, which encode NaNs. AltTab's current comments report that NaNs can become (0, 0) and click app content, that near-edge negative coordinates can resize windows on macOS 27, and that down alone still makes the target key on their tested system. These are observed workarounds, not supported Apple contracts. Do not describe 0x3a as a known semantic flag or claim the synthetic event has zero possible side effects.

Suggested service sequence: restore minimized state, unhide, obtain PSN, call front-process with window ID and 0x200, post the current key record, then AX raise/main fallback as needed. Validate success, handle stale AX elements, and recheck focused-window identity asynchronously. The current AltTab focus pipeline is more elaborate: [Window.swift, lines 410-596](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/switcher/state/Window.swift#L410-L596) includes origin-Space bookkeeping and `SLSSpaceSetFrontPSN` restoration to reduce cross-Space bleed. Do not adopt that additional symbol casually or claim the specification's shorter pipeline has the same guarantees.

For current-desktop Dock clicks, choose a window confirmed on that display's current Space immediately before focus. Cross-Space targets are legitimate only for all-desktop scope. Public activate plus raise is a degraded fallback that can switch desktops. The `workspaces-auto-swoosh` preference is an undocumented mitigation, not a complete prohibition on app-driven or assigned-Space movement.

## Space membership and polling

Evidence: [AltTab Spaces.swift, lines 31-49 and 67-79](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/switcher/state/Spaces.swift#L31-L79), [AltTab CGSCallScheduler.swift, lines 74-99](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/macos/CGSCallScheduler.swift#L74-L99), and [DockDoor CGWindowID.swift, lines 17-20](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/Extensions/CoreGraphics/CGWindowID.swift#L17-L20).

Read-only runtime check on this host: sampled existing WindowServer windows, queried singleton memberships, then queried the same two IDs together. Singleton results were `[1]` and `[3, 1]`; the batch result was `[3, 1]`. This confirms union behavior for the sample and demonstrates lost association. No windows or Spaces were changed. Do not depend on array order, deduplication details, or exact empty-result behavior across OS versions.

Two correct approaches:

- Simple baseline: query each retained window with `[NSNumber(windowID)]`, mask 7, off-main. Coalesce calls, preserve last membership while minimized or while a query fails, and measure cost at realistic window counts.
- Faster reference approach: query managed topology once, then use `CGSCopyWindowsWithOptionsAndTags` once per Space and invert to `[windowID: Set<spaceID>]`. AltTab uses connection UInt32, owner `Int` (zero), spaces CFArray, options `Int`, and pointers to two `Int` tag values (zero). Its invisible bits are 1, 2, and 4 combined when invisible windows are included. See [SkyLight.framework.swift, lines 46-64](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/macos/api-wrappers/SkyLight.framework.swift#L46-L64). A missing window may still need a singleton fallback.

Neither approach satisfies a literal one-CGS-call-per-membership-poll requirement with the specified symbols. Measure the real cost; do not fake membership to meet an artificial call count. A newer private query iterator exists upstream, but adding it introduces additional ABI research and is not necessary for the initial correct implementation.

Parse `Display Identifier`, `Current Space`, `Spaces`, and `id64` defensively, with `ManagedSpaceID` fallback where present. When separate Spaces are off, the identifier may be literal `Main`, so per-display topology is unavailable and the shared current Space must be used. Managed dictionary `type == 4` for fullscreen must not be confused with CGSInternal's different `CGSSpaceTypeFullscreen == 1` enum. The latter is a different API's encoding.

Empty membership is not proof of destruction. Minimized windows, inactive native tabs, stale IDs, and transient topology changes need different handling. AltTab explicitly notes empty results can also mean a nonexistent ID. Preserve known state on query failure and corroborate disappearance against lifecycle and inventory data.

## Native Dock Accessibility integration

Evidence: [DockDoor DockObserver.swift, lines 288-337](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/Utilities/DockObserver.swift#L288-L337), [lines 580-620](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/Utilities/DockObserver.swift#L580-L620), [lines 689-728](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/Utilities/DockObserver.swift#L689-L728), and [ActiveAppIndicatorCoordinator.swift, lines 120-146](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/Utilities/ActiveAppIndicator/ActiveAppIndicatorCoordinator.swift#L120-L146).

Find running `com.apple.dock`, make its AX application element, and find its child with role `AXList`. Register `kAXSelectedChildrenChangedNotification` on that list. On notification, read `AXSelectedChildren`, select the first item, and require subrole `AXApplicationDockItem` for app previews. This notification reflects selection and must be interpreted with current mouse position, not assumed to be a pure pointer-enter event. Read AX position/size and convert Quartz top-left coordinates carefully for multiple displays.

Map icons through `AXURL` to app bundle URL and bundle identifier. Title matching is a fallback, since app names are localized and can collide. Multiple instances of one app require PID-aware disambiguation. Treat non-app items such as folders and Trash separately.

Keep the observer and refcon alive, install its run-loop source on the dedicated observer thread, remove subscriptions on teardown, and recreate after Dock restart, including the intentional `killall Dock` used by hiding/restoration. A successful initial subscription is not permanent health. The upstream restart/health handling is worth studying, but its main-thread AX work must not be reproduced because the DockWindow specification forbids it.

`AXStatusLabel` is explicitly defined by AltTab in HIServices wrapper line 17. It is an opportunistic badge string, not a guaranteed badge API with reliable change notifications. Poll on a low-frequency background schedule, cache results, and tolerate empty/unavailable labels. `AXChildrenChanged`/selection notifications can invalidate an item cache, but do not guarantee badge changes. No reference justifies scraping arbitrary third-party app Dock context menus.

## DockDoor visual measurements

These values describe the pinned current source, not an exact reconstruction of the user's screenshots. DockDoor's defaults and design have evolved. Prefer the explicit DockWindow specification wherever it differs, including 320x200 switcher thumbnails, 160-point preview height, 20-point preview header icon, 16-point switcher icon, three traffic lights, and about 26/20-point panel radii.

| Element | Current DockDoor source measurement | Source |
| --- | --- | --- |
| Preview image default | 300 x 187.5 pt | `consts.swift` 30-31 |
| Global spacing multiplier | 0.7 | `consts.swift` 34 |
| Uniform radii | base 20; card 24.2; image 18.2; container 34 at default multiplier | `consts.swift` 81-82; `Components/dockStyle.swift` 4-30 |
| Grid/container spacing | item 24; content inset 20 before global scaling; transparent outer room 24 | `BaseHoverContainer.swift` 4-12 and 82 |
| Default hover header | 24-point app icon, subheadline medium text; top 12 and leading 20 before global scaling | `SharedHoverAppTitle.swift` 21-34 and 82 |
| Traffic-light buttons | 17 x 17 hit frame, 13-point bold glyph, 6-point spacing, 4-point row padding, default scale 1 | `Traffic Light Buttons.swift` 14-21, 58, 95-107 |
| Traffic-light count | configurable; current defaults include quit plus close/minimize/fullscreen | `consts.swift` 217; do not copy this extra control into the requested three-button design |
| Material pill | additional horizontal 8, vertical 5 padding, capsule, 1.5-point primary stroke at opacity 0.1 | `Components/MaterialPill.swift` 3-12 |
| Switcher icon | automatic 35 pt with subtitle, 20 without; configurable clamp 16...64 | `WindowPreview.swift` 221-227 |
| Switcher header | app primary label, secondary title, trailing 8; title default is subheadline | `WindowPreview.swift` 609-636; `consts.swift` 1210 onward |
| Header/image gap | 4 pt; toolbar horizontal inset 3 with uniform radii | `WindowPreview.swift` 795-837; `dockStyle.swift` 39-41 |
| Image/card styling | image clipped to continuous rounded rect; card border 1.75 at primary opacity 0.1 | `WindowPreview.swift` 271, 848-854 |
| Selected card | accent fill at default opacity 0.4, accent border 2.5 pt | `consts.swift` 177; `WindowPreview.swift` 855-879 |
| Hover panel layout | bottom Dock default one row, side Dock maximum two columns | `consts.swift` 252-253 |
| Shadows | optional, currently off by default; configured radius 8, opacity 0.2 | `consts.swift` 184-186; `BaseHoverContainer.swift` 64-73 |

UI source links: [consts.swift](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/consts.swift), [WindowPreview.swift](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/Views/Hover%20Window/WindowPreview.swift), [BaseHoverContainer.swift](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/Views/Hover%20Window/Shared%20Components/BaseHoverContainer.swift), [Traffic Light Buttons.swift](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/Views/Hover%20Window/Shared%20Components/Traffic%20Light%20Buttons.swift), [SharedHoverAppTitle.swift](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/Views/Hover%20Window/Shared%20Components/SharedHoverAppTitle.swift), [dockStyle.swift](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/Components/dockStyle.swift), [MaterialPill.swift](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/Components/MaterialPill.swift).

Current DockDoor uses configurable Liquid Glass/frosted/clear backgrounds, not invariably `.hudWindow`. [BlurView.swift, lines 84-113](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/Components/BlurView.swift#L84-L113) selects glass on macOS 26+ and material fallback otherwise. Its `MaterialBlurView` at lines 468-480 configures NSVisualEffectView behind-window blending and active state. Do not copy its private glass variants, shader code, or dependencies. The specified old-SDK `.hudWindow`/`.popover` approximation behind the background-provider abstraction is appropriate. Compiler-version guards are only a practical proxy for SDK availability, not proof that a separately selected SDK includes `NSGlassEffectView`.

## Capture and cross-Space limitations

Apple's [desktop-independent window filter](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(desktopindependentwindow:)) captures a specified window; [SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager) provides single-frame capture. These APIs do not promise a current image for every minimized, protected, or other-Space window. Enumerating with `onScreenWindowsOnly: false` increases discovery scope, but does not itself guarantee renderability, current content, or a retained SCWindow object remaining valid after lifecycle changes.

Local SDK header check: Xcode 16.4's ScreenCaptureKit headers declare `SCScreenshotManager.captureImage` in `SCScreenshotManager.h:32`, `ignoreShadowsSingleWindow` in `SCStream.h:317`, and `capturesShadowsOnly` in `SCStream.h:327`, all available on macOS 14.0. The requested capture path and these shadow controls fit the deployment target without a newer SDK. This does not enable the newer Liquid Glass APIs.

The reference apps' broader capture results must not be attributed to the requested public capture path. DockDoor's [WindowUtil.swift, lines 519-555](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/Utilities/Window%20Management/WindowUtil.swift#L519-L555) uses private `CGSHWCaptureWindowList`, with explicit transparency and Space-transition clipping rejection. AltTab declares that same private capture API at SkyLight lines 27-35. DockWindow should retain the requested ScreenCaptureKit implementation, not silently substitute this private capture API to mimic source behavior.

Cache successful captures before minimize/Space transitions, show cache immediately, and retain it on capture failure. Fall back to the app icon if no valid cached image exists. Avoid accepting a blank/transparent result as a fresh successful thumbnail. Use bounded concurrent work and cancel/coalesce obsolete requests. Capture failure must not remove the tracked window or change its count. Stop visible refresh work when panels close. Cached thumbnails are snapshots, not continuous live streams, even with a one-second refresh timer.

User verification still needed: minimized and hidden windows, protected content, fullscreen Spaces, separate Spaces on/off, multiple displays including negative origins and mixed scales, Stage Manager, stale AX elements, high AX IDs, no-permission operation, secure input/event taps, and arbitrary app new-window behavior. Source inspection and symbol existence do not establish the performance budgets or “never switches desktops” guarantee.

## Licensing boundary

The specification identifies both references as GPL-3.0. License files are [AltTab LICENCE.md](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/LICENCE.md) and [DockDoor LICENSE](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/LICENSE). Keep implementation independently authored from API facts, byte-layout observations, behavioral requirements and separately designed types. Do not paste implementation bodies, gradients/shaders, assets, comments, helper abstractions or copied tests. Numeric API constants and signatures in this document describe interoperability facts. References and attribution alone do not grant permission to copy GPL implementation into a differently licensed project. This is an engineering boundary, not a legal determination. No closed-source DockDoor Pro binary was accessed.
