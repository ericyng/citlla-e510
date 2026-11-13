# Architecture

How Citlla E510 is put together. Every claim has a source; fix the line number
rather than dropping the source.

## Shape

- Menu bar utility: `LSUIElement: YES` — `project.yml:30`. Starts in
  `.accessory`, grows a real window on demand (`README.md:318-320`).
- macOS 15+, Swift 6 language mode — `project.yml:5,11`.
- Bundle id `com.ericng.citllae510` — `project.yml:26`.
- The main window is a fixed 210 pt sidebar beside the detail pane
  (`8e15ba1` replaced the `NavigationSplitView` after its Liquid Glass sidebar
  could be pushed offscreen on tall sections —
  `CitllaE510/Views/MainWindowView.swift:12-23`), with eight sections in a fixed
  order: overview, buttons, actions, profiles, scrolling, advanced, permissions,
  about — `CitllaE510/Views/MainSection.swift:10-17`, `:49-51` (`available`).
- The tester and diagnostics are panes of **Advanced**, not separate windows
  (`PROGRESS.md:174-175`).

## The event tap

`CitllaE510/Services/EventTapService.swift` is `@MainActor`, an
`ObservableObject` (`:7-8`) holding the `CFMachPort` and its run-loop source.

- Tap is created at the **session** level, **head insert**, `.defaultTap` —
  `EventTapService.swift:71-73`.
- Watched event types: left/right/other mouse down+up, `scrollWheel`, `keyDown`,
  `keyUp`, and the system-defined type (`CGEventType` raw 14) —
  `EventTapService.swift:47-56`, raw value at `KeyCodeMap.swift:10-12`.
- Head insert is deliberate: the tester tap must see buttons the remapper
  swallows a moment later (`PROGRESS.md:295-297`).
- If the system disables the tap (timeout or user input) it re-enables itself —
  `EventTapService.swift:128-135`.
- `startIfNeeded()` is safe to call repeatedly and refuses to start without
  Accessibility — `EventTapService.swift:64-76`. The Permissions section relies
  on this to start the tap when the grant appears.

## Not remapping our own events

- Synthesized events carry `EventMarker.value` (`0x4349_544C_4C41_3531`,
  "CITLLA51") in `eventSourceUserData` — `KeyCodeMap.swift:4-7`.
- The tap returns any event carrying that marker untouched —
  `EventTapService.swift:137-139`.
- The real sink stamps every posted event — `ActionExecutor.swift:144,156,189,250`.
- Consequence: a new posting path that forgets the marker creates an infinite
  remap loop. `MacroRunner.swift:29` states the rule.

## Mouse buttons

- `CGEvent` button numbers are 0-based, HID usages 1-based; the tap adds 1 —
  `EventTapService.swift:177-178`.
- Resolution is `config.action(for: button, frontmostBundleID:)`, so an enabled
  profile wins over the global map — `EventTapService.swift:179-180`.
- A bound button swallows the click by returning `nil`; an unbound one passes
  through — `EventTapService.swift:180-190`.

## Mouse-sent keystrokes (the thumb buttons)

The E510's thumb buttons arrive as real `⌃←` / `⌃→` keystrokes, so telling them
apart from the keyboard needs the mouse's own HID reports:

- `MouseKeyTagger` opens the receiver read-only with `IOHIDManager` on a
  **background** run loop — `MouseKeyTagger.swift:32,132-140`.
- Attribution window is **120 ms** — `MouseKeyTagger.swift:44`.
- It must be a background loop: reports have to be recorded before the
  main-thread tap callback runs for the matching key event
  (`PROGRESS.md:298-300`).
- The tagger only starts once Input Monitoring is granted, so it no longer logs a
  TCC denial every second (`PROGRESS.md:150-152`).

## Receivers

Two E510 receiver revisions exist, with different IDs but the same interfaces —
`README.md:361-362`:

| vendor:product | name |
| --- | --- |
| `0x1EA7:0x66` | 2.4G Mouse |
| `0x32C2:0x12` | 2.4G Wireless Receiver |

`MouseReceiver.known` at `MouseReceiver.swift:32-35`; exact-pair
`IOHIDManager` matching dictionaries at `:37-41`. Diagnostics adds vendor-only
fallbacks; the tagger stays on exact IDs (`PROGRESS.md:333-336`).

## Frontmost app

`ActiveAppMonitor` caches the frontmost bundle id so the tap does a dictionary
lookup instead of touching `NSWorkspace` per event —
`ActiveAppMonitor.swift:4,12-14,19,32`; `EventTapService.swift:58-60`.
A `nil` value simply means no profile applies (`EventTapService.swift:15-18`).

## Scrolling

- Inversion happens **in place**: the same `CGEvent`'s delta fields are rewritten
  and handed back, so phase, momentum and timestamp survive and there is no
  re-post — `ScrollController.swift:19-24`, `EventTapService.swift:198-212`.
- Tilt (side wheel) fires once per **250 ms** quiet window —
  `ScrollController.swift:28`. A bound tilt swallows the gesture
  (`EventTapService.swift:208-211`).

## Chained actions

- Sequences are normalised on load: max **8** steps, max **500 ms** per wait,
  max **3000 ms** total — `MouseAction.swift:59-61`.
- `MacroRunner` runs them off the tap thread, logs what normalisation dropped,
  and stops early when the total cap would be exceeded —
  `MacroRunner.swift:61-72,138-144`.
- Turning remapping off must cancel a run already in flight, not just block new
  presses — `EventTapService.swift:141-151` (`MacroRunner.cancelAll()`), because
  remaining steps would otherwise post events for up to three seconds.

## System actions

Symbolic hotkeys never fire from synthetic events, whatever the source or tap —
`PROGRESS.md:180-188`. `DockControl` therefore asks the Dock:

| action | route |
| --- | --- |
| Mission Control | `CoreDockSendNotification("com.apple.expose.awake")` |
| Show Desktop | `CoreDockSendNotification("com.apple.showdesktop.awake")` |
| Launchpad | `CoreDockSendNotification("com.apple.launchpad.toggle")` |
| App Exposé | `AXShowExpose` on the frontmost app's Dock tile |

— `PROGRESS.md:190-198`. All four are toggles (`PROGRESS.md:202-206`).
Still unsolved: Spotlight and Lock Screen (`PROGRESS.md:208-210`).

## Snapshot rendering

`--snapshot` renders the app's own views with `cacheDisplay`, offscreen, needing
no screen-recording permission — `Scripts/check.sh:10-11`,
`PROGRESS.md:178,290-294`. It is the only layout check available on this machine.
It **falls back to Overview for an unknown section**, which is why the gate
asserts the reported `section=` (`check.sh:104-110`).

## What has no coverage

The watcher-equivalent risks here are real hardware: tilt sign, the 250 ms quiet
window, `NSOpenPanel` app picking, profile switching in a live app, and the Dock
icon. None can be proved offscreen — `PROGRESS.md:112-122`. See `gate-and-docs.md`.
