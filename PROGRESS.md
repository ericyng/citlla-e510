# Progress

Last updated: 2026-11-09

Where the Citlla E510 app stands, what was learned about the mouse, and what is
next. `README.md` is the user-facing documentation; this file is the working
log.

## State

- Debug and Release builds are healthy; `Scripts/build.sh` runs tests, builds,
  verifies the bundle, installs and launches.
- 48 unit tests pass (config round-trip, action model, button naming, key codes,
  shortcut bindings, media-key decoding, receiver matching, and the diagram's
  nine callouts).
- Menu bar app (`LSUIElement`): menu bar icon, Settings (Mouse / Buttons /
  Permissions / About), Diagnostics, Button Tester.
- Current bindings in `~/Library/Application Support/CitllaE510/config.json`:
  buttons 1–2 pass through, 3 → Mission Control. Only buttons 1–3 are listed;
  the mouse never sends 4–8, and rows for them from older configs are trimmed
  on load. The real thumb buttons use the shortcut bindings instead
  (`⌃←` → Back, `⌃→` → Forward). Callout 9 is a shortcut binding too (`⌃⌘F`)
  and starts unbound.
- Three fixes landed, all confirmed live on 2026-11-08:
  1. **Mission Control / Show Desktop / Launchpad / App Exposé:** posting the
     matching keystrokes never works — see "System actions" below. They go
     through `DockControl` now.
  2. **Thumb buttons:** the receiver's keyboard interface sends `⌃←` / `⌃→`,
     not mouse buttons 4/5. `MouseKeyTagger` listens to the mouse's own HID
     reports on a background run loop so the tap only remaps keystrokes the
     mouse sent.
  3. **Grants:** Accessibility and Input Monitoring are held by the ad hoc
     signed build and survive rebuilds.

Confirmed by the tester: middle click shows and restores the desktop, and the
two thumb buttons go back/forward in Chrome.

Builds are re-signed ad hoc with `designated => identifier
"com.ericng.citllae510"` instead of the binary's cdhash, so later rebuilds keep
their TCC grants. `MouseKeyTagger` also waits for Input Monitoring before
touching the HID device (it used to retry every second and log a TCC denial each
time), and Settings → Permissions starts the event tap by itself when
Accessibility appears.

## What the app does now

| Area | Notes |
| --- | --- |
| Remapping | `CGEventTap` at the session level, head insert, suppresses the original button pair and runs the chosen action. Events it posts itself are stamped so they are not remapped twice. |
| Mouse keystrokes | `MouseKeyTagger` opens the receiver (any ID in `MouseReceiver.known`: `0x1EA7:0x66`, `0x32C2:0x12`; see FIX-THUMB-BUTTONS.md) read-only with `IOHIDManager` on a background run loop. Key-downs are recorded for 120 ms; the tap only acts when the mouse just sent that key. Modifier key-downs are matched before a sample is claimed, so `⌃`/`⌘` down does not steal the tag for the key after it. |
| Actions | macOS actions (Mission Control, Show Desktop, Launchpad, screenshot…), any keyboard shortcut, mouse clicks, open app / URL / shell command. Mission Control, App Exposé, Show Desktop and Launchpad go through the Dock; everything else is posted as events. |
| Settings → Mouse | The two renders cut from the manufacturer's diagram, next to the nine numbered callouts with the diagram's own wording. Callout 8 shows both thumb-button actions. Clicking a row opens the action editor. Fixed 860×720 window. |
| Settings → Buttons | Toggle, a **Mouse Keystrokes** section (`⌃←` / `⌃→` / `⌃⌘F`, all editable), and the three mouse buttons the hardware reports. |
| Test Buttons… | Listen-only tap at head insert: highlights and counts each diagram control as it is pressed, shows a raw log, and *Copy Report*. Mouse-sent keystrokes are labelled **Mouse key** and marked bindable; keyboard events are labelled separately. |
| Diagnostics | Raw HID reports from the receiver (needs Input Monitoring). |
| `--status` | Prints accessibility / input monitoring / tap state and exits. |
| `--snapshot` | Renders one of the app's own windows to PNG — the only way to check layout on this machine, which does not grant screen recording. |

## System actions

Symbolic hotkeys — ⌃↑, ⌃↓, F11, F4, ⌘Space, ⌃⌘Q — are matched by the
WindowServer against real HID events. Synthetic `CGEvent`s never trigger them,
whatever the event source (`.hidSystemState`, `.combinedSessionState`,
`.privateState`) or tap (`.cghidEventTap`, `.cgSessionEventTap`,
`.cgAnnotatedSessionEventTap`), with or without the event marker. `⌘⇧3` works
only because screenshots are handled by the screenshot service, not by a
symbolic hotkey.

So `DockControl` asks the Dock instead:

| Action | Route |
| --- | --- |
| Mission Control | `CoreDockSendNotification("com.apple.expose.awake")` |
| Show Desktop | `CoreDockSendNotification("com.apple.showdesktop.awake")` |
| Launchpad / Apps | `CoreDockSendNotification("com.apple.launchpad.toggle")` |
| App Exposé | `AXShowExpose` action on the frontmost app's Dock tile |

`CoreDockSendNotification` is in ApplicationServices on macOS 26+;
`CoreDock.framework` no longer exists. `com.apple.expose.front.awake` is still
in the Dock's binary but does nothing, hence the accessibility route for App
Exposé, which matches tiles on bundle URL first because two tiles can share a
name. All four are toggles: a second press closes what the first opened. They
also close if another app activates while they are open, so they look like they
"flash and disappear" when sent from a freshly launched probe — the running app
does not activate, so it is fine.

Still unmatched by any route: **Spotlight** (⌘Space) and **Lock Screen**
(⌃⌘Q). Both are symbolic hotkeys and neither has a working Dock or private
notification path found so far.

## What the diagram says about the mouse

The diagram is `Design/citlla-diagram.png` (1500×1500). Its blue badges
(`#0075F9`) were located by exact-colour connected components and the numerals
were read by template matching against the badge 1–9 glyphs:

| # | Control | Diagram text | Reality on the Mac |
| --- | --- | --- | --- |
| 1 | Left Button | primary click | button 1 |
| 2 | Right Button | secondary click | button 2 |
| 3 | Smart Flying Scroll Wheel | scroll + middle click | scroll, button 3 |
| 4 | DPI Button | DPI presets | firmware only, sends nothing |
| 5 | Side Wheel | horizontal scroll | arrives as a wheel tilt, not a button |
| 6 | Devices Switch Button | switch paired device | factory profile sends `⌘Tab` |
| 7 | Devices Indicators | 2.4G / BT1 / BT2 / DPI / low power | LEDs, not a button |
| 8 | Forward / Back Buttons | the two thumb buttons | sends `⌃←` and `⌃→` (not buttons 4/5) |
| 9 | Return to Desktop / Full Screen | bottom-right thumb button | sends `⌃⌘F` (confirmed by HID trace) |

The receiver also sends one consumer key (`NX_KEYTYPE_SOUND_UP`, key type 0)
from a control that is not yet matched to a diagram number. The mouse interface
in the HID descriptor declares Button usages 1–8 only (`hidutil list` shows two
`2.4G Mouse` interfaces, primary usage 6 and 2), so callout 9 cannot be a mouse
button. A live HID trace of pressing it confirmed the factory chord: usage
`0xE3` (left ⌘), usage `0xE0` (left ⌃), then keyboard usage `9` (F) — i.e.
`⌃⌘F`. Callout 9 therefore has a default `ShortcutBinding` row like the thumb
buttons; it starts unbound, which leaves the factory full-screen toggle working.
Row 6 (`⌘Tab`) has no binding row yet. Tilt is not handled at all.

The renders in `Assets.xcassets/Mouse/` are produced by
`Scripts/extract-assets.swift`; it keys out the studio background, erodes away
the callout leader lines and the floor strip, keeps the largest blob, dilates
back and writes 1x + 2x images. Re-run it if the diagram changes.

The diagram's nine callout arrows were traced too (the leader lines are the
light blue `#7EC8EE` strokes, ending in small arrowheads). Each arrow tip is
the control's real position on the render, and those points are stored as
normalised `MouseControl.badgePoint` values so the UI can print the number on
the mouse itself. The top crop was also widened to `225,575 540×780`: the old
`485`-wide rect cut roughly 30 px off the right of the mouse and clipped the
bottom. The current output is 530×767 (top) and 320×753 (side), both with no
opaque pixels on their edges.

## Open threads

1. **Spotlight and Lock Screen.** Both are symbolic hotkeys, so nothing the app
   posts reaches them (see "System actions"). Spotlight needs a private
   entry point (`Spotlight.app` refuses to launch, `spotlight://` does nothing,
   `com.apple.expose.front.awake`-style notifications do not exist for it).
   Lock Screen could fall back to `pmset displaysleepnow` plus "require
   password immediately", or to whichever `SAC*` lock call still exists.
2. **Horizontal scroll/tilt.** The side wheel still arrives as a scroll event
   and is not remapped. `EventTapService` would need to swallow `scrollWheel`
   deltas for the tilt axis.
3. **Unidentified consumer key.** The receiver sends `NX_KEYTYPE_SOUND_UP` from
   a control that is not one of the nine diagram buttons. Consumer bindings are
   implemented (`ShortcutBinding.source == .consumer`), but nothing in the UI
   creates one yet; a "learn from tester" button would make it assignable.
4. **Diagram hotspots.** The numbered badges now sit on the renders at the
   manufacturer's callout points (`MouseControl.badgePoint`), but the renders
   are still not clickable; the legend remains the interactive surface. Making
   the badges hit targets is the next step.

Resolved: the Buttons tab no longer lists buttons 4–8 (the hardware never sends
them, and old configs are trimmed on load), and the stale "Citlla E510 Self
Signed" certificate was deleted from the login keychain.

## Verification notes

- **Live, 2026-11-09, Release build on macOS 27.0.1:** the event tap and HID
  listener both started, `Button 3 triggered Mission Control` fired on every
  middle click (Mission Control opened), and `Mouse key ⌃Left Arrow/⌃Right
  Arrow triggered Back/Forward` fired on every thumb press (both navigated the
  right way). The app's own launch log reported `accessibility=true
  inputMonitoring=Granted`, which is the only trustworthy reading - `--status`
  from a shell borrows the terminal's TCC identity.
- The app's windows cannot be inspected through AX: for a `MenuBarExtra` app,
  `AXWindows` returns proxy elements that resolve back to the application
  element. `--snapshot` plus OCR (`Vision`) of the PNG works instead. Composite
  the PNG onto white first: tabs without an opaque list background come out
  transparent.
- The tester tap is at head insert so it still sees buttons the remapper
  swallows a moment later. It is listen-only and uses `peekKeyPress()`, so it
  cannot suppress anything or steal an attribution sample from the remapper.
- The HID listener must run on a **background** run loop: reports have to be
  recorded before the main-thread `CGEvent` tap callback runs for the matching
  key event.
- `CGEventSourceStateID` is private `-1`, combined session `0`, HID system `1`.
  Real HID events are state `1`; the older tester labels were inverted.
- `AXIsProcessTrusted()` reports the truth for the `open`-launched app; running
  the binary from a terminal borrows the terminal's TCC identity, so `--status`
  from a shell can say *trusted* while the app itself is not.
- Probes must be launched with `open -n -g -a … --args …`: `-n` forces a second
  instance so the arguments are honoured, and `-g` keeps it from activating.
  Without `-g` the activation closes whatever Dock expose mode the probe just
  opened, which reads as "the notification does not work".
- Dock state is visible in `log stream --predicate 'process == "Dock"'`:
  `[com.apple.dock:missioncontrol] Changing from mode …` and
  `Toggle Expose Mode: …`. Launchpad logs
  `[com.apple.dock:spotlight] Sending .launchAppsBrowsing` instead.

## Session log

- `0377507` `--status` probe and stale-grant documentation
- `b65ede4` real Settings window, AppKit-managed windows, first-run prompt
- `9e327f3` unit tests and `Scripts/build.sh`
- `95fbbce` diagram-based mouse map, button tester, asset extraction, snapshots
- `0161699` tap recovery when Accessibility is granted after launch
- `307e340` tester tap at head insert
- today: HID attribution for mouse keystrokes, real modifier events for system
  shortcuts, shortcut bindings + editor, tester source fixes
- today: system actions moved to the Dock (`DockControl`) after finding that
  synthetic events never trigger symbolic hotkeys; App Exposé via `AXShowExpose`
- today: callout numbers drawn on the mouse renders (`badgePoint` from the
  diagram's arrow tips), top crop widened so the artwork is no longer clipped,
  Spotlight and Lock Screen marked "(not available)" in the action picker
- today: `--snapshot --scale N` renders the windows at N device pixels per point;
  the 2x renders live in `docs/screenshots/` and are shown in the README
- today: receiver matching moved from one hard-coded pair to `MouseReceiver.known`
  (`0x1EA7:0x66` and `0x32C2:0x12`), so both E510 receiver revisions remap;
  Diagnostics adds vendor-only fallbacks, the tagger stays on exact IDs, and the
  About tab lists the supported receivers
- today: Buttons tab lists only the three buttons the mouse reports; older
  configs drop their 4–8 rows on load (`ButtonBinding.retiredButtons`). Deleted
  the stale "Citlla E510 Self Signed" certificate, and regenerated the docs
  screenshots at 2x from the installed build
