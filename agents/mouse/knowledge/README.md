# mouse knowledge — index

One file per topic, every claim sourced (`path:line`, commit SHA, or command
output). An unsourced claim is deleted, not kept.

Filled in phase 1. Planned files:

| file | holds |
| --- | --- |
| `architecture.md` | the session event tap, HID listener, `EventSink` seam, `MacroRunner`, `ActionFieldsView`, `ActiveAppMonitor`, section shell |
| `profiles-and-actions.md` | global map vs per-app profiles and precedence, chords, sequences, presets, the tester |
| `permissions.md` | Accessibility vs Input Monitoring, what each section needs, `--window`/TCC notes, receiver IDs |
| `gate-and-docs.md` | `Scripts/check.sh` flags, the `MainSection.available` render assertion, `docs/snapshots/` regeneration, what the count of tests/snapshots means |
| `build-and-sign.md` | `Scripts/build.sh` flags and defaults, XcodeGen, entitlements, `create-signing-identity.sh`, `~/OpenCode/signing.md` |
| `decisions.md` | append-only: dated decisions with reasons and what they rule out |
