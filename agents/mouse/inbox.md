# mouse inbox

Open questions and proposals. Format in `../PROTOCOL.md` §4; caps are 2 new
proposals a day and 6 waiting at once.

## open questions

- 2026-11-11 — Is `check.sh:114`'s grep string (`no window to snapshot`) a real
  bug or intentional? `Snapshot.swift:75` prints `no window content to snapshot`,
  so the documented skip can never fire. Exit 3 only happens when
  `window.contentView` is nil (`Snapshot.swift:74-77`), which is
  near-unreachable, so this is latent rather than active.

## proposals

### Fix the unreachable "no window to snapshot" skip in `check.sh`

- Proposed 2026-11-11
- `check.sh:114` greps for `no window to snapshot`, `Snapshot.swift:75` prints
  `no window content to snapshot`, so the skip at `check.sh:114-117` is dead and
  the case would be reported as a hard failure. Change one string.
- Status: waiting
