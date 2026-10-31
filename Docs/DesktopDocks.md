# Independent desktop Docks

Each normal desktop has its own ordered pin profile. Pinning, unpinning, dragging a pin, and importing the native Dock affect only the desktop currently hosting DogBar's Dock. Finder is removable and reorderable. As with other apps, an unpinned Finder can still appear as a running app while it has eligible windows. Dragging a running app off the Dock hides it only in that desktop's session.

On first migration, the existing global pin list is copied independently to every desktop in the available Space catalog. Finder is included once to preserve the previous visible Dock. The original `pinnedApps.v1` data remains untouched as a backup. Profiles are saved under `desktopPins.v2`. Settings' older `pinnedApps` property is a legacy value, not the active pin store.

A desktop discovered afterward copies the previously selected desktop's pins once. Subsequent changes are independent. Re-importing macOS's Dock explicitly replaces only the selected profile. Global preference reset continues preserving pins.

## Identity and persistence

Normal Space UUIDs identify profiles independently of desktop numbering, reordering, and display arrangement. The single unnamed macOS default desktop uses a dedicated stable identity. If there are multiple unnamed defaults, an unambiguous display default uses the display identifier. Ambiguous unnamed Spaces receive distinct boot-scoped keys; they survive app restarts within that boot, but are deliberately not guessed across reboots. If even the boot identity is unavailable, those ambiguous keys are process-scoped. macOS provides no universally reliable public Space identity contract.

Profiles remain saved when a desktop disappears or its display disconnects. If identity is temporarily unavailable, the last visible pin list can remain displayed, but pin mutations and re-import are disabled until the desktop is resolved. Existing saved data is not attached arbitrarily to another Space. Fullscreen Spaces do not create independent pin profiles.

The default all-display window scope remains separate: running apps can come from every connected display's active desktop, while persistent pins belong to the desktop hosting the Dock. New-window creation keeps its local target. App-wide actions such as Quit and Hide retain macOS's app-wide behavior.

Cross-desktop menu actions are cancelled when the profile changes. A drag begun on another profile cannot update the newly selected profile. Transient running-app order and removals are maintained separately per desktop during the session; pin order persists across application restarts.
