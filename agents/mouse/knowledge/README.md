# mouse knowledge — index

One file per topic, every claim sourced (`path:line`, commit SHA, or command
output). An unsourced claim is deleted, not kept.

Filled in phase 1 (2026-11-11). Files:

| file | holds |
| --- | --- |
| `architecture.md` | event tap at session/head insert, the `EventMarker` rule, button and key handling, `MouseKeyTagger`, receiver IDs, frontmost-app cache, in-place scroll rewriting, sequence caps, Dock routes, snapshot rendering |
| `profiles-and-actions.md` | resolution order and precedence, own-bundle exclusion, action kinds, chords, sequence limits, presets, tester, tilt |
| `permissions.md` | Accessibility vs Input Monitoring, the shell-borrows-TCC trap, why grants survive rebuilds, what an agent must never do |
| `gate-and-docs.md` | `check.sh` flags and order, the `MainSection.available` assertion, `build.sh` unsafe defaults, what green proves, the docs pipeline |
| `build-and-sign.md` | three signing paths, the designated requirement, certificate script, bundle verification, entitlements, never-launch rule |
| `decisions.md` | append-only: dated decisions with reasons and what they rule out |
| `known-issues.md` | stale `PROGRESS.md` claims, hardware-only checks, open product threads, environment traps |

Every claim carries a `path:line`, commit SHA or command. If a citation is wrong,
fix it — do not soften the claim.
