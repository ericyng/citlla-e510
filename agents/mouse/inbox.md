# mouse inbox

Open questions and proposals. Format in `../PROTOCOL.md` §4; caps are 2 new
proposals a day and 6 waiting at once.

## open questions

- 2026-11-11 — Is `check.sh:114`'s grep string (`no window to snapshot`) a real
  bug or intentional? `Snapshot.swift:75` prints `no window content to snapshot`,
  so the documented skip can never fire. Exit 3 only happens when
  `window.contentView` is nil (`Snapshot.swift:74-77`), which is
  near-unreachable, so this is latent rather than active. — resolved
  2026-11-12: a real bug, fixed on branch `agents/mouse-2026-11-12`
  (`4a792e6`), awaiting Eric; `main` still has the mismatch.
- 2026-11-12 — Should `check.sh --docs` keep publishing `tester.png`? It is
  byte-identical to `main-advanced.png` (both `83d822f…`), so `docs/snapshots/`
  holds nine files for eight distinct images. Dropping the copy would be a code
  change (`check.sh:135-142`) and the file would then need deleting from `docs/`.
- 2026-11-12 — Should `snap()` test the render's exit status instead of grepping
  its log for a string? `check.sh:102,114` treats "skip" as "stderr/stdout
  contains `no window to snapshot`", while `Snapshot.swift:76` (on `main`) is
  already `exit(3)`. The strings agree after `4a792e6`, but the exit code is the
  stabler contract; changing this is beyond the one-string fix.

## proposals

### Fix the unreachable "no window to snapshot" skip in `check.sh`

- Proposed 2026-11-11
- `check.sh:114` greps for `no window to snapshot`, `Snapshot.swift:75` prints
  `no window content to snapshot`, so the skip at `check.sh:114-117` is dead and
  the case would be reported as a hard failure. Change one string.
- Status: awaiting Eric — branch `agents/mouse-2026-11-12` (`4a792e6`), gate
  `--no-snapshots` exit 0, 137 tests, not pushed, not merged.

### Refresh `docs/snapshots/` — every render predates the current window

- Proposed 2026-11-12
- `docs/snapshots/*.png` was last written by `check.sh --docs` at `44177d6`
  (2026-11-09). Since then `8e15ba1` (2026-11-10) replaced the
  `NavigationSplitView` sidebar with a fixed 210 pt `HStack` and `821e0df`
  (2026-11-11) added the **New Chord** / **New Sequence** buttons to Actions, so
  all eight `main-*` renders and `tester.png` show a window that no longer
  exists. Approve `Scripts/check.sh --docs` on `main` (it renders, and the
  tester pane's `.onAppear` may start a listen-only tap) plus an
  `agents(mouse): refresh docs/snapshots` commit; an agent must not run it.
- Status: waiting
