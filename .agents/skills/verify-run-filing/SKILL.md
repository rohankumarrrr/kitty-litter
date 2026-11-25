---
name: verify-run-filing
description: Check every order in which a kitten's T3 run can start, end, leave something running and be read by Shades, against the real thread list and inbox code, so no ended run is lost, filed twice, or filed as done while what it waits on still works. Use for any change to T3ThreadList's status or turnEnded, Inbox.owes or Inbox.file, or how the app files what the inbox is owed.
---

# Verify run filing

## What it proves

Every run a kitten ends reaches the inbox once, and is never filed as done while a pull request it watches or a reviewer it started still works.

The harm it guards against: a kitten's question or decision never reaches you, as when #131 found a kitten watching its pull request silent until the pull request merged, or reaches you as finished while a reviewer is still working, as 4abf1cd4 fixed.

## How

`Tests/ShadesT3Tests/RunFilingModelTests.swift` builds a small world (one kitten thread, its run number, whether it's running, what its turn left running, whether a reviewer works) and lets `explore` in `Tests/TestSupport/Explorer.swift` try every order of these steps, up to 9 deep and 2 runs:

- T3 starts a run, the run starts a reviewer, the reviewer hands back.
- The turn ends with nothing left running, watching its pull request (an `awaited` background task), or leaving a dev server listed (one that isn't awaited).
- What it left running stops.
- Shades reads the thread list and files what the inbox is owed.

Each state is turned into real T3 shell JSON and read by the real `T3ThreadList.agentThreads`, and filing goes through the real `Inbox.owes` and `Inbox.file`. Exploration is breadth first, so a counterexample is the shortest order that breaks the property, written as numbered steps in these words.

Swift and `swift test` were chosen over TLA+ because the question is whether the real code mishandles some order of a few events. This runs that code, needs no Java, and runs in CI with everything else.

## Run it

```bash
swift test --filter RunFilingModelTests
```

It takes well under a second. It also fails if the exploration stops at the depth limit before reaching every state, so raising the runs or adding a step can't quietly check less.

## Reading a failure

The message is the shortest order that breaks a property, then what went wrong, such as:

```
1. T3 starts a run
2. the turn ends watching its pull request
Then: run 1 ended, and Shades read the list, but its report never reached the inbox
```

- If the steps can happen in T3 and the code really does what the message says, it's a bug in the code. Fix the code, not the model.
- If a step can't happen in T3, or the model's filing step no longer matches `fileOwedReports` and `reportOn`, the model is wrong. Fix the model and say why in the commit.

## What it doesn't cover

- One kitten thread with at most one reviewer, and 2 runs.
- The app's filing is mirrored from `AppController.fileOwedReports` and the early return in `reportOn`, not run through `AppController`, so timing between tasks isn't explored, and nor is reading the report or sorting it.
- `AgentWatch`'s notifications, restarts, and the inbox's `since`.

## Coverage

| Covered | Where |
|---|---|
| Thread status and `turnEnded` from T3's shells | `Sources/ShadesT3/T3ThreadList.swift`: `agentThreads(summaries:questions:)`, `isWaitingOnWork(_:)` |
| What's owed and filing once | `Sources/ShadesCore/Inbox.swift`: `owes(_:)`, `file(_:from:at:id:)` |
| When the app files | Mirrored from `Sources/Shades/App/AppController+Inbox.swift` `fileOwedReports()` and the early return in `Sources/Shades/App/AppController+Reports.swift` `reportOn(_:failed:)` |

Last confirmed against the code at commit `adf04449`. When any covered function changes after that, read it against the model, change the model if the change was intended, run the check, and only then move this commit forward.

## It has caught

- #131's bug. With `isWaitingOnWork` counting any background task and `turnEnded` always false, as at 157df070, it fails in 2 steps: a run starts, and its turn ends watching its pull request, so its report never reaches the inbox.
- 4abf1cd4's bug. With `isWaitingOnWork` always false, as before 4abf1cd4, it fails in 3 steps: the run is filed as done while what it waits on still works.
