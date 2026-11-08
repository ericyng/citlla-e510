# Citlla E510

A small macOS menu bar app that makes the extra buttons on a **CITLLA PRO MAX
E510** wireless mouse actually useful on a Mac.

macOS does not ship a way to remap the side buttons, thumb buttons, or other
extra buttons on third-party mice. Citlla E510 installs a session event tap,
lets you choose an action for each physical button, and replaces the original
button event with that action.

![Menu bar app](Icon/icon-256.png)

## Defaults

The mouse reports **8 buttons** in its HID report descriptor. Out of the box:

| Button | Default |
| --- | --- |
| 1 (left) | Pass through |
| 2 (right) | Pass through |
| 3 (wheel click) | Pass through |
| 4 (rear side button) | Back (`⌘[`) |
| 5 (front side button) | Forward (`⌘]`) |
| 6–8 | Pass through (assign your own) |

You can bind buttons to:

- macOS actions: Mission Control, App Exposé, Show Desktop, Launchpad,
  Spotlight, Screenshot, Lock Screen, Sleep Display, media keys, volume, and
  back/forward
- Any keyboard shortcut (press Record, then press the keys)
- A mouse click (left, right, middle)
- Open an app, open a URL, or run a shell command

Open **Settings → Buttons** to change a binding. The menu bar icon opens the app;
**Diagnostics** shows raw HID events from the receiver.

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
before installing. It also warns when the build is ad hoc signed, because that
invalidates an existing Accessibility grant.

Signing with a real identity keeps the code signature stable across rebuilds,
which means macOS keeps the Accessibility grant:

```sh
Scripts/build.sh --sign "Apple Development: you@example.com (TEAMID)"
```

With no identity available, the alternative is to install to `/Applications` and
re-grant Accessibility from System Settings after each rebuild.

The app is a menu bar utility (`LSUIElement`), so it has no Dock icon and does
not open a window by itself. Look for the mouse icon in the menu bar.

Because that is easy to miss, the app opens its **Settings** window on first run,
and again on any launch where Accessibility has not been granted yet. After that
it stays out of the way: closing the window leaves the app running in the menu
bar, and **Quit Citlla E510** in the menu bar is the way to stop it.

### Running from Xcode

Each `Run` launches a new copy out of DerivedData, and an ad-hoc signature
changes with every rebuild, so an existing Accessibility grant silently stops
applying. If the menu says *Accessibility permission is required* even though
the toggle is on, remove Citlla E510 from the Accessibility list, add it back,
then press **Restart Event Tap**. Granting the copy built into `/Applications`
instead of the DerivedData build avoids this.

## Permissions

### Accessibility (required)

Button remapping needs **System Settings → Privacy & Security → Accessibility**.
The app asks for it on first launch and links to the right pane. If Citlla E510
is not listed, add it manually or drag the app from Finder into the list.

After granting access, open **Settings → Permissions → Restart Event Tap** if
the status still says the event tap is inactive. macOS may also need the app to
be relaunched once after a rebuild.

### Input Monitoring (optional)

The **Diagnostics** window can read raw HID reports so you can identify buttons
that are not in the default list. That requires **Input Monitoring**. Remapping
itself works with Accessibility alone.

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

A binding is system-wide: it applies to every mouse that reports the same button
number, not only the CITLLA.

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

Delete that file (or use **Reset Defaults** in Settings) to start over.

## Limitations

- The event tap remaps mouse buttons globally; there is no per-device filter.
- Left and right click can be remapped, but doing so can make normal clicking
  awkward. The defaults leave them alone.
- Horizontal scroll/tilt (`AC Pan`) is not remapped in this version.
- DPI, polling-rate, and Bluetooth/2.4G mode switches are firmware features and
  are not software-remappable.
- The app is not sandboxed. Event taps and HID access are not compatible with
  the App Sandbox.
- A local build is signed ad hoc. If you rebuild or move the app, macOS may ask
  for Accessibility permission again.

## Troubleshooting

**The menu bar icon is there, but buttons do nothing.**
Open Settings → Permissions. Accessibility must say *Granted* and the event tap
must say *active*. Press **Restart Event Tap**.

**The app does not appear in Accessibility.**
Drag `CitllaE510.app` from Finder into the Accessibility list, or use the `+`
button and select it from DerivedData.

**A permission grant seems stale after rebuilding.**
Reset it and grant it again:

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
  Models/       Config, button bindings, action model
  Services/     Event tap, action execution, HID monitor, permissions, windows
  Views/        Menu bar, settings, action editor, diagnostics
  Utilities/    Key-code names, event marker, --status probe
CitllaE510Tests/  Unit tests for the model layer (run by Scripts/build.sh)
Scripts/      build.sh: test, build, install
```

Run `xcodegen generate` after adding files or editing `project.yml`. Tests run
with `Scripts/build.sh` or:

```sh
xcodebuild -project CitllaE510.xcodeproj -scheme CitllaE510 \
  -configuration Debug -destination 'platform=macOS' test
```

The icon source is in `Icon/`; run `Icon/build.sh` to regenerate the asset
catalog.
