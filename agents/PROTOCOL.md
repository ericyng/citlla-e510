# Project agent protocol

The contract every project agent in `~/OpenCode` follows. A charter may narrow
it (fewer tiers, more prohibitions); nothing may widen it.

Machine role: **personal**. Nothing here touches work machines or work files.

## 1. One run, start to finish

1. **Read, in this order:** this file, your `charter.md`, `inbox.md`, the tail of
   `journal.md`, and your `knowledge/` index. Files beat memory: Eric and the
   other agent edit them between your runs, and a belief carried over is how a
   finished job stays "open" for three weeks.
2. **Check where you are.** The checkout's branch and `status --short` must be as
   the prompt says. If you are about to write code, you are in a worktree
   (§5); if you are about to write knowledge, you are on `main`.
3. **Do only what your tiers allow** (§3). Everything else is a proposal.
4. **Write knowledge** you actually used or corrected (§4).
5. **Report the six sections** (§2), always, even when the answer is "nothing
   changed".

## 2. The six sections

In this order, with these headings, no extras:

| section | contents |
| --- | --- |
| `Answer` | the direct answer to the task, one paragraph or a short list |
| `Did` / `Would do` | what you actually changed or ran; `Would do` in a dry-run, never the other one |
| `Proposes` | things needing Eric's yes, each one line, each also written to `inbox.md` |
| `Knowledge changes` | files you added, corrected or deleted under `knowledge/`, each with the reason |
| `Open questions` | what you could not settle, each also appended to `inbox.md` |
| `Sources` | `path:line`, commit SHAs, and the command with its output. Never "the docs say" |

A missing or empty section is fine; a misnamed one is a protocol failure, and
the caller will say so.

## 3. Tiers

Your charter lists the commands and files for each tier. The tiers mean:

- **T0 read** — anything in the repo, read-only.
- **T1 verify** — run the project's own gate. No install, no signing with a real
  identity, no launching the app unless the charter allows it.
- **T2 docs** — commit to `main`: your `agents/` files, `PROGRESS.md`,
  `README.md`, `docs/`. Approved in advance, no question needed.
- **T3 code** — a branch in a worktree, the gate on it, then **stop**. Report the
  diff as a proposal. Never merge.
- **T4 never** — listed explicitly in the charter; not a judgement call.

Anything the charter does not name is a proposal, not an improvisation.

## 4. Knowledge, journal, inbox

**`knowledge/`** holds what you would otherwise re-derive: architecture, build
and sign, testing, contracts, decisions, known issues. One claim per line or
short bullet, each with a source (`Scripts/build.sh:38`, `git show abc1234`,
`README.md:112`). An unsourced claim is deleted, not kept. Corrections are
edits; history stays in `decisions.md` and `journal.md`.

**`decisions.md`** is append-only: `## YYYY-MM-DD — <decision>`, then why, then
what it rules out. Never rewrite an older entry.

**`journal.md`** is append-only, one entry per run:

```
## YYYY-MM-DD live
- did: <what you ran or changed, with the gate result>
- found: <what you learned worth keeping>
- wrote: <knowledge files touched>
```

The heading is `## YYYY-MM-DD live` or `## YYYY-MM-DD dry-run`, nothing else —
the linter enforces it.

**`inbox.md`** has two sections:

```
## open questions
## proposals
```

Open questions are one line each, dated. Proposals are `### <title>`, then
`- Proposed YYYY-MM-DD`, then the one-line ask, then `- Status: waiting` —
updated to `approved`, `declined` or `dropped: <reason>` when it moves.

At most **2 new proposals in a day** and **6 waiting at once**. Past that, drop
the oldest with a reason instead of adding a seventh.

## 5. Where you work

- **Code (T3):** `git worktree add ../.agents/<agent>-<YYYY-MM-DD> -b agents/<agent>-<YYYY-MM-DD>`
  from the repo root, work there, run the gate there, report, stop. Removing the
  worktree is the caller's job once the branch is merged or rejected. Never
  touch the checkout Eric has open.
- **Knowledge and docs (T2):** the normal checkout, on `main`, committed and
  pushed. Small commits, message `agents(<agent>): <what changed>`.
- **Nothing else.** No writes outside `agents/`, `PROGRESS.md`, `README.md`,
  `docs/`, and a T3 worktree.

## 6. Push

- Push is allowed where the repo has a remote: `git push origin main` after a T2
  commit. If the push fails, say so in `Did` and leave the commit in place.
- A repo with no remote never gets one added by an agent.

## 7. Dry-run

`mode: dry-run` means: read everything, report everything, write nothing and
run nothing. `Did` becomes `Would do`, listing the exact commands you would have
run. No commits, no journal entry, no inbox change.
