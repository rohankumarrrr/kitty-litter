---
name: verify-waiting-on-you
description: Check that a row stays in The Kitty Litter's Waiting on you only while its thread is still stopped on the person, and that waiting-on-you.json records every row that came and went, by trying every order of thread events against the real Inbox inside swift test. Use for any change to Inbox.file, flag, ask, follow, markReplied, remove, clear, withdraw, WaitingRecord, or the thread fields they read (lastRunStartedAt, lastWordsFromYouAt, settledAt, pullRequest).
---

# Verify Waiting on you

**The promise.** A row is in Waiting on you only while its thread is stopped on the person: it asked, and nothing since has moved it on without them. Every row that comes into Waiting on you is in `waiting-on-you.json` while it waits, and leaves it with how and when.

**The harm.** A row that stays after its thread moved on tells the person to answer something that no longer needs them. That was the feed the audit found: rows brought back by a note from a turn they didn't start, and rows left behind after their pull request merged. A row that goes too early loses a real ask.

## Run it

```bash
swift test --filter WaitingOnYouModelTests
```

Run `swift` on its own, with no pipe and no `cd`. It takes about 7 seconds and passes with `Executed 3 tests, with 0 failures`.

## How it works

`Tests/ShadesCoreTests/WaitingOnYouModelTests.swift` walks every sequence of up to six events from a start where threads `a` and `b` are both mid-run, and applies each one to the real `Inbox` the way `AppController.threadsChanged` and `file` do: it updates the thread as T3 would list it, calls `Inbox.follow`, and files the report.

| Event | What it stands for in the code |
|---|---|
| `a ends with decision`, `decisionHeld`, `note`, `shipped`, `failed` | A turn ending and `Inbox.file` filing what the sorter said. `decisionHeld` ends it while it watches its open pull request, `turnEnded` |
| `a is woken by something else` | A run starting with `latestRunStartedAt` later than the row, such as a check waking it |
| `you write to a in T3` | `latestUserAuthoredMessageAt`, then a run starting |
| `you reply to a's row`, then `your reply reaches a` or `fails` | `reply` in `AppController+Inbox.swift`: `markReplied(at:)`, then the run, or `markReplied(at: nil)` |
| `a settles`, `a's pull request merges`, `a is archived` | `settledAt`, `pullRequests` state, the thread leaving the list |
| `you press Done on a's row` | `remove(because: .done)` |

`b` only ends with a decision and gets woken, so the check also sees one thread's events leave the other's rows alone.

After every event it checks:

- **Rows match the threads.** Each thread has exactly one row waiting on you when the reference says it's stopped on you, and none otherwise. The reference, `Expected`, is the rule written plainly: a decision or failure stops it on you. Shipped, a turn you didn't start, settling, its pull request merging, archiving or Done clear that. Your words dim the row, and the next note answers you only if your words started that turn.
- **The record matches the rows.** The rows open in `inbox.record` are exactly the rows waiting on you, none is open twice, and none left before it came.

## Proving it can fail

| Broken on purpose | What failed |
|---|---|
| `Inbox.follow` returning at once | All three tests: the exhaustive walk on its first paths, such as "a ends with decision, a is woken by something else: a has 1 rows waiting on you, but it's not stopped on you", and both replays |
| The note path in `Inbox.file` keeping the thread's open decision | Nothing here, since `follow` closes the row as the turn starts. `InboxTests.testFilingRules` catches it, which covers T3 not sending a run's start |

The two replays are the audit's bugs: `testTheReRaiseFromTheAuditIsCaught` (a note from a turn you didn't start brought back a row you'd replied to) and `testAStaleRowFromTheAuditIsCaught` (a row stayed after its pull request merged).

## Reading a failure

A failure prints the path, such as `a ends with decision, you reply to a's row, your reply reaches a, a ends with note, a is woken by something else, a ends with note: a has 1 rows waiting on you, but it's not stopped on you`. Read it with the pstack `statechart` skill if you have it, or step through the events in the table. If the code did what the rule in `docs/kittens.md` ("How long a row waits") says and `Expected` disagrees, that's a modeling error: fix `Expected` and say why in the pull request. Otherwise it's a bug, so fix the code, and don't weaken the check.

## What it leaves out

- **Who started the thread.** Which threads file rows at all is `WaitingOnYouTests` in `Tests/ShadesTests`, through the real `AppController`.
- **Request cards.** Standing rows never follow their thread. `StaleRequestTests` covers when they go.
- **Timing within T3.** It assumes a run's start and the words that started it reach the app in the same list, as T3 sends them together.
- **Bounds.** Two threads, six events. The rules are per thread, so a longer path only repeats these steps.

## Sync

**Sync commit:** the commit that adds this skill. `git log -1 --format=%h -- .agents/skills/verify-waiting-on-you` finds it, and `git diff <that> -- Sources/ShadesCore/Inbox.swift Sources/ShadesCore/WaitingRecord.swift Sources/Shades/App/AppController+Agents.swift Sources/Shades/App/AppController+Inbox.swift` shows what has changed since. Move it forward only after reading those changes and confirming the events above still describe them.
