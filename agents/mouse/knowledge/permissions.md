# Permissions

Two TCC grants, what breaks without each, and the one trap that makes a shell
report lie.

## Accessibility — required

- Needed to create the event tap: `startIfNeeded()` returns early unless
  `AXIsProcessTrusted()` — `EventTapService.swift:69-76`,
  `PermissionManager.swift:7-8`.
- The app asks once (`hasPromptedForAccessibility`) and links to the right pane —
  `EventTapService.swift:70-75`, `PermissionManager.swift:12-14,38-39`.
- The app starts the tap **by itself** as soon as Accessibility appears in
  Settings; **Permissions → Restart Event Tap** is the manual fallback —
  `README.md:343-345`.

## Input Monitoring — required for the thumb buttons only

- Checked with `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` and requested with
  `IOHIDRequestAccess` — `PermissionManager.swift:18,35`.
- Requested when the tap starts if it is missing — `EventTapService.swift:96-99`.
- Without it, ordinary mouse buttons and wheel clicks still work; the thumb
  buttons are left exactly as macOS delivers them. Diagnostics uses the same
  permission — `README.md:354-357`.
- The tagger waits for the grant before touching the HID device, instead of
  retrying every second and logging a denial each time — `PROGRESS.md:150-152`.

## The trap: a shell run borrows the terminal's TCC identity

- `AXIsProcessTrusted()` reports the truth for the `open`-launched app. Running
  the binary from a terminal borrows the **terminal's** identity, so `--status`
  from a shell can say *trusted* while the app itself is not —
  `PROGRESS.md:303-305`.
- The only trustworthy reading is the app's own launch log —
  `accessibility=true inputMonitoring=Granted` (`PROGRESS.md:286-289`).
- Likewise, each Xcode `Run` is a different app from the `/Applications` copy as
  far as TCC is concerned — `README.md:330-333`.

## Why grants survive rebuilds

Depends on the signature, not on the permission code — see `build-and-sign.md`.
With the local certificate the designated requirement is
`identifier "com.ericng.citllae510" and certificate root = H"…"`, so rebuilds,
reinstalls and path moves all match the existing grant —
`README.md:288-293`, `PROGRESS.md:138-139`.

Ad hoc is the weak form: `designated => identifier "com.ericng.citllae510"` —
**any** bundle claiming that id matches — `README.md:298-302`.

## What an agent must never do

- Never grant, request or click through a permission prompt.
- Never launch the built app: the tap takes over the real mouse.
- Never run `tccutil reset`, or launch a probe that opens Dock modes.

Resetting is a one-time human step after switching to the certificate —

```sh
tccutil reset Accessibility com.ericng.citllae510
tccutil reset ListenEvent com.ericng.citllae510
```

— `README.md:304-310`.

## Dock-expose probes: the `open -n -g` rule

If a probe must be launched (human-driven, not agent-driven), it needs
`open -n -g -a … --args …`: `-n` forces a second instance so arguments are
honoured, `-g` keeps it from activating. Without `-g`, the activation closes
whatever Dock expose mode the probe just opened, which reads as "the notification
does not work" — `PROGRESS.md:306-309`.
