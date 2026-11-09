# Citlla E510

A small macOS menu bar app that makes the extra buttons on a **CITLLA PRO MAX
E510** wireless mouse actually useful on a Mac.

macOS does not ship a way to remap the side buttons, thumb buttons, or other
extra buttons on third-party mice. Citlla E510 installs a session event tap,
lets you choose an action for each physical button, and replaces the original
button event with that action.

![Menu bar app](Icon/icon-256.png)

## Defaults

The CITLLA PRO MAX E510 does not report its extra buttons as ordinary mouse
buttons. Its receiver also presents a keyboard interface, and the two thumb
buttons send `⌃←` and `⌃→` as real keystrokes; the ninth control sends `⌃⌘F`.
Citlla E510 watches the mouse's own HID reports so it can tell those keystrokes
apart from the same shortcuts on your keyboard. Out of the box:

| Control | Default |
| --- | --- |
| Left, right and wheel click | Pass through |
| Rear thumb button (sends `⌃←`) | Back (`⌘[`) |
| Front thumb button (sends `⌃→`) | Forward (`⌘]`) |
| Ninth control (sends `⌃⌘F`) | Pass through (keeps the factory full-screen toggle) |
| Buttons 4–8 | Pass through (this mouse does not send them) |

You can bind a control to:

- macOS actions: Mission Control, App Exposé, Show Desktop, Launchpad,
  Spotlight, Screenshot, Lock Screen, Sleep Display, media keys, volume, and
  back/forward
- Any keyboard shortcut (press Record, then press the keys)
- A mouse click (left, right, middle)
- Open an app, open a URL, or run a shell command

Two of those actions cannot be driven from a button. **Spotlight** (`⌘Space`)
and **Lock Screen** (`⌃⌘Q`) are symbolic hotkeys: macOS only honours them for
a real key press and ignores anything an app synthesises, so a remapped button
cannot fire them. The action picker marks them "(not available)" and explains
the workaround (use the keyboard, or pick another action). Mission Control, App
Exposé, Show Desktop and Launchpad work because they are driven through the
Dock, and the media keys work because they are ordinary key events.

Open **Settings → Mouse** to see the mouse's nine controls laid out as they are
on the CITLLA diagram — each number is drawn on the render at the control it
labels — click a row to change its binding, and **Test Buttons…** in the menu
bar to see what each physical control actually sends.

## The mouse, as the manufacturer numbers it

The **Mouse** tab shows the two renders from the CITLLA box diagram next to the
nine numbered callouts, with the diagram's own titles. Each row is also the place
to change that control's binding.

| # | Control | Diagram says | On the Mac |
| --- | --- | --- | --- |
| 1 | Left Button | primary click | native |
| 2 | Right Button | secondary click | native |
| 3 | Smart Flying Scroll Wheel | scroll + middle click | scroll, button 3 |
| 4 | DPI Button | DPI presets | firmware only |
| 5 | Side Wheel | horizontal scroll | wheel tilt, not a button |
| 6 | Devices Switch Button | switch paired device | sends `⌘Tab` in the factory profile |
| 7 | Devices Indicators | 2.4G / BT1 / BT2 / DPI / low power LEDs | not a button |
| 8 | Forward / Back Buttons | the two thumb buttons | sends `⌃←` and `⌃→` |
| 9 | Return to Desktop / Full Screen | bottom-right thumb button | sends `⌃⌘F` (confirmed); remappable like the rest |

## Button tester

**Test Buttons…** in the menu bar opens a listen-only window: it shows the same
demo, highlights each control as you press it, prints how many times it was
seen, and keeps a raw event log of mouse buttons, wheel and tilt, keyboard
shortcuts and media keys. Keystrokes that came from the mouse are labelled
**Mouse key** and marked as bindable or not; keystrokes from your keyboard are
labelled separately and never trigger a remap. Nothing is suppressed while the
tester is open, so it is safe to leave open while you try things. **Copy Report**
puts a plain-text summary on the clipboard.

If a control shows up in the tester but is not one of the diagram's numbers, the
window calls it out under **Not on the diagram** — that is the signal that the
firmware sends something the remapper cannot bind directly.

## Requirements

- macOS 15 or later
- Xcode 27.1 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build and run

```sh
xcodegen generate
open CitllaE510.xcodeproj
```

Select the **CitllaE510** scheme and run. Or build from the command line:

```sh
xcodebuild \
  -project CitllaE510.xcodeproj \
  -scheme CitllaE510 \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

For a build without a signing identity (CI or a quick check):

```sh
xcodebuild \
  -project CitllaE510.xcodeproj \
  -scheme CitllaE510 \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

### Build script

`Scripts/build.sh` runs the unit tests, builds a Release app, checks the bundle,
installs it to `/Applications`, and launches it:

```sh
Scripts/build.sh              # test, build, install, launch
Scripts/build.sh --debug      # same, but a Debug build
Scripts/build.sh --no-tests   # skip the tests
Scripts/build.sh --no-install # build and verify only
Scripts/build.sh --no-launch  # install without launching
Scripts/build.sh --dest DIR   # install somewhere else
Scripts/build.sh --sign ID    # sign with a keychain identity (see below)
```

The script stops if a copy is already running, so quit it (or stop it in Xcode)
before installing.

With no signing identity it re-signs ad hoc, but with a designated requirement
that names the bundle (`designated => identifier "com.ericng.citllae510"`)
instead of pinning the binary. TCC matches that requirement, so Accessibility
and Input Monitoring grants survive later rebuilds. A plain ad hoc signature
pins the cdhash, which is why a rebuild used to drop the grants.

Signing with a real identity also works and is the way to go if you have one:

```sh
Scripts/build.sh --sign "Apple Development: you@example.com (TEAMID)"
```

The app is a menu bar utility (`LSUIElement`), so it has no Dock icon and does
not open a window by itself. Look for the mouse icon in the menu bar.

Because that is easy to miss, the app opens its **Settings** window on first run,
and again on any launch where Accessibility has not been granted yet. After that
it stays out of the way: closing the window leaves the app running in the menu
bar, and **Quit Citlla E510** in the menu bar is the way to stop it.

### Running from Xcode

Each `Run` launches a new copy out of DerivedData, which is a different app from
the copy in `/Applications` as far as TCC is concerned, so a grant made to one
does not apply to the other. Grant the copy you actually run, and prefer the
`/Applications` build from `Scripts/build.sh` over Xcode runs.

## Permissions

### Accessibility (required)

Button remapping needs **System Settings → Privacy & Security → Accessibility**.
The app asks for it on first launch and links to the right pane. If Citlla E510
is not listed, add it manually or drag the app from Finder into the list.

The app starts the event tap by itself as soon as Accessibility appears in
Settings, so there is usually nothing else to click. **Settings → Permissions →
Restart Event Tap** is there if the status still says the event tap is inactive.

### Input Monitoring (required for the thumb buttons)

The mouse sends its two thumb buttons as real keystrokes (`⌃←` and `⌃→`). To
tell those apart from the same shortcuts on your keyboard, Citlla E510 reads the
mouse's own HID reports. That requires **System Settings → Privacy & Security →
Input Monitoring**.

Without it, ordinary mouse buttons and wheel clicks still work, but the thumb
buttons are left exactly as macOS delivers them. The **Diagnostics** window uses
the same permission. The app asks for it on first launch and
**Settings → Permissions** shows the current state.

## How it works

The CITLLA receiver enumerates as `2.4G Mouse` with:

- Vendor ID `0x1EA7`
- Product ID `0x0066`
- A mouse interface (usage page `0x01`, usage `0x02`) with an 8-button report
  (`Report ID 2`)
- A consumer-control collection
- A vendor-defined collection on page `0xFFB5`
- A keyboard interface used by the receiver

The app creates a `CGEventTap` at the session level. On mouse down it maps the
CGEvent button number (0-based) to the HID button number (1-based), looks up the
binding, suppresses the original down/up pair, and runs the action. Events the
app posts itself are stamped with a marker so the tap never remaps them twice.

The thumb buttons are not mouse buttons: they arrive as real key events on the
receiver's keyboard interface. So does the ninth control, as `⌃⌘F`. A read-only
`IOHIDManager` listener on a background thread records each key the mouse sends,
and the tap only acts on a mapped trigger (`⌃←`, `⌃→`, `⌃⌘F`) when that listener
saw the mouse send the key within the last 120 ms. The same shortcuts on your
keyboard still behave normally.

For Mission Control, App Exposé, Show Desktop and Launchpad the app asks the
Dock to do it (`CoreDockSendNotification`, and the `AXShowExpose` accessibility
action on the frontmost app's Dock tile for App Exposé). Posting the matching
keystrokes does not work: the WindowServer matches its own shortcuts against
real HID events, so synthetic ones are ignored whatever their source or tap.
The four Dock actions are toggles - pressing the same button again closes them.

A binding is system-wide: it applies to every mouse that reports the same button
number, not only the CITLLA. Mouse-sent keystrokes are attributed by the HID
listener, so they stay specific to the CITLLA receiver (VID `0x1EA7`,
PID `0x0066`).

## Diagnostics

Open **Citlla E510 → Diagnostics** from the menu bar. Press the mouse buttons and
watch the event log:

- `Button` (usage page `0x09`) events show `usage N`; that `N` is the button
  number to configure.
- `Consumer` (`0x0C`) and `Vendor` (`0xFFB5`) events are extra controls the
  firmware exposes. Some of these can be bound through a keyboard shortcut or a
  system action, but they may not appear as normal mouse buttons.

If a physical button produces no HID event at all, it is handled inside the
mouse firmware (for example DPI or Bluetooth pairing) and cannot be remapped by
software.

## Config file

Bindings are stored at:

```
~/Library/Application Support/CitllaE510/config.json
```

`bindings` holds the mouse buttons, and `shortcutBindings` holds the keys the
mouse sends (`⌃←`, `⌃→`, and any media key you add later). Delete that file (or
use **Reset Defaults** in Settings) to start over.

## Limitations

- The event tap remaps mouse buttons globally; there is no per-device filter.
- Keystroke attribution is tied to the CITLLA receiver (VID `0x1EA7`,
  PID `0x0066`). A control that sends a keystroke from a different device would
  be treated as normal keyboard input.
- Left and right click can be remapped, but doing so can make normal clicking
  awkward. The defaults leave them alone.
- Horizontal scroll/tilt (`AC Pan`) is not remapped in this version.
- DPI, polling-rate, and Bluetooth/2.4G mode switches are firmware features and
  are not software-remappable.
- The app is not sandboxed. Event taps and HID access are not compatible with
  the App Sandbox.
- A local build is signed ad hoc with an identifier-based designated
  requirement, so rebuilds keep their grants. Moving the app to a different path
  still counts as a different app to TCC.

## Troubleshooting

**The menu bar icon is there, but buttons do nothing.**
Open Settings → Permissions. Accessibility must say *Granted* and the event tap
must say *active*. Press **Restart Event Tap**.

**Middle click does nothing, or the thumb buttons do nothing.**
Middle click needs Accessibility, and the thumb buttons need Input Monitoring as
well, because this mouse sends them as `⌃←` / `⌃→` keystrokes. Both cards in
Settings → Permissions must say *Granted*. Builds made before the stable ad hoc
requirement was added pinned the binary, so a grant from one of those builds is
stale; remove Citlla E510 from both privacy lists and add it again once.

**The app does not appear in Accessibility.**
Drag `CitllaE510.app` from Finder into the Accessibility list, or use the `+`
button and select it from DerivedData.

**A permission grant seems stale after rebuilding.**
Builds from `Scripts/build.sh` keep their grants. For an older or differently
signed copy, reset it and grant it again:

```sh
tccutil reset Accessibility com.ericng.citllae510
```

**Diagnostics says it cannot open the mouse.**
Grant Input Monitoring and reopen the Diagnostics window.

**Xcode prints `connection to service named com.apple.linkd.autoShortcut`.**
Harmless. `linkd` is an OS service that backs Shortcuts and App Intents; macOS
27 beta logs the failed lookup when a SwiftUI app is launched from Xcode. This
app registers no App Intents, the message never reaches the unified log when the
app is launched from Finder, and remapping is unaffected. Ignore it.

**Check the real permission/tap state.**
The app can report what the process is actually allowed to do and then exit:

```sh
CitllaE510.app/Contents/MacOS/CitllaE510 --status
```

It prints (and writes to `~/Library/Application Support/CitllaE510/status.txt`)
whether Accessibility is trusted, whether Input Monitoring is granted, and
whether a session event tap can be created.

## Development

```
CitllaE510/
  Models/       Config, button bindings, action model, the diagram's callouts
  Services/     Event tap, actions, HID monitor, permissions, windows, tester
  Views/        Menu bar, settings, mouse map, tester, action editor, diagnostics
  Utilities/    Key-code names, event marker, --status probe
  Assets.xcassets/Mouse/  Renders extracted from the manufacturer's diagram
CitllaE510Tests/  Unit tests for the model layer (run by Scripts/build.sh)
Scripts/      build.sh: test, build, install
             extract-assets.swift: diagram -> asset catalog
Design/       The manufacturer's diagram the renders and callouts come from
```

The two mouse renders in `Assets.xcassets/Mouse/` are cut out of
`Design/citlla-diagram.png` by `Scripts/extract-assets.swift`, which keys out the
studio background, drops the callout leader lines and the floor strip, and writes
1x and 2x images. Rerun it after replacing the diagram:

```sh
swift Scripts/extract-assets.swift Design/citlla-diagram.png
```

The app can snapshot one of its own windows, which is handy when you cannot take
a screenshot (this machine does not grant screen recording):

```sh
CitllaE510.app/Contents/MacOS/CitllaE510 --snapshot ~/Desktop/settings.png --tab mouse
CitllaE510.app/Contents/MacOS/CitllaE510 --snapshot ~/Desktop/tester.png --window tester
```

Run `xcodegen generate` after adding files or editing `project.yml`. Tests run
with `Scripts/build.sh` or:

```sh
xcodebuild -project CitllaE510.xcodeproj -scheme CitllaE510 \
  -configuration Debug -destination 'platform=macOS' test
```

The icon source is in `Icon/`; run `Icon/build.sh` to regenerate the asset
catalog.
