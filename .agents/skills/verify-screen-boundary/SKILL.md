---
name: verify-screen-boundary
description: Check that nothing from the person's screen can reach the thread of a Shades kitten with `seesScreen false`, by running the real routing code over every route and kitten setting inside `swift test`. Use for any change to routing, prompts, Messages, the inbox, summaries, kittens, the router's folder (`RouterBlock`), or anything else that decides what Shades sends to T3 and where.
---

# Verify the screen boundary

**The promise.** Nothing that came from the person's screen reaches the thread of a kitten with `seesScreen: false`.

**The harm.** That kitten is the one that can change the rules every kitten works by, so a page on the screen could steer it.

## Run it

```bash
swift test --filter ScreenBoundaryTests
```

It takes about 10 seconds. Run `swift` on its own, with no pipe and no `cd`, since only that form is let out of this repo's sandbox. A pass prints `Executed 5 tests, with 0 failures`. The known findings below show as `XCTExpectFailure: matcher accepted` lines, and that's a pass.

## Does a change touch it?

Rerun it for a change to any of these, and to anything new that calls `backend.start`, `backend.followUp`, `backend.forward` or `backend.answer`:

| Covered | Where |
|---|---|
| Passing your words to a kitten or a session | `give`, `forward` and `traceIsClear` in `Sources/Shades/App/AppController+Routing.swift` |
| Ask, its router turn and hand-off | `runQuickTurn`, `finish`, `handOff` and `startFrontier` in `AppController+Ask.swift`, and `sendFix` in `AppController+Fix.swift` |
| Dropping onto the cat | `dropped` and `beginAsk(dropped:)` in `AppController+Ask.swift`, and `droppedName` in `Sources/ShadesCore/Context.swift` |
| Messages | `send`, `route` and `answer` in `AppController+Channels.swift` |
| Inbox replies, summaries and sorting | `reply` in `AppController+Inbox.swift`, `words(for:)`, `summaryPrompt` and `summarize` in `AppController+Reports.swift` |
| Who a thread belongs to | `KittenBoard.belongs` in `Sources/Shades/App/KittenBoard.swift`, and `Kitten.workspace` in `Sources/ShadesCore/Kitten.swift` |
| What the prompts carry | `forKitten`, `forwarded` and `passedOn` (`screenLeftOut`) in `Sources/ShadesCore/Prompts.swift` |
| The router's tools | `RouterBlock.allowed`, `denied` and `settings` in `Sources/ShadesCore/RouterBlock.swift` |
| Where a thread with no project starts, and its first title | `projectID(for:)` and `title(for:)` in `Sources/ShadesT3/T3Backend.swift` |

**Sync commit:** `405ef0c`. The check was last confirmed to describe the covered code at that commit. `git diff --stat 405ef0c -- Sources/Shades/App/AppController+Routing.swift Sources/Shades/App/AppController+Ask.swift Sources/Shades/App/AppController+Fix.swift Sources/Shades/App/AppController+Channels.swift Sources/Shades/App/AppController+Inbox.swift Sources/Shades/App/AppController+Reports.swift Sources/Shades/App/KittenBoard.swift Sources/ShadesCore/Kitten.swift Sources/ShadesCore/Prompts.swift Sources/ShadesCore/RouterBlock.swift Sources/ShadesT3/T3Backend.swift` shows what has changed since. Move the commit forward only after reading those changes and confirming the routes and cast below still describe them.

## How it works

`Tests/ShadesTests/ScreenBoundaryTests.swift` builds the real `AppController` with the fakes in `Tests/ShadesTests/Fakes.swift`. Every part of the fake screen (app, window, URL, selected text, page text and picture), and of the fake dropped file, carries the word `5ad1`, and so does the agent text that could quote it: reports, inbox rows and the router's own words. After each run it reads everything sent to the fake T3, and works out where each prompt went from the project or thread it was sent to.

- **New threads** (`testNoNewThreadOfAScreenlessKittenGetsYourScreen`). Routes `Give`: Ask to a kitten, Everyone to a kitten, a new topic in a DM, a hand-off from Ask and from Everyone, a fix, and a dropped file going to a kitten or handed off. Cast: Clawde, who never sees the screen, in its own folder or another project. Steve, who does or doesn't, in his own folder, another project, Clawde's folder or Clawde's project. Frontier mode with and without full access. That's 352 runs. A prompt with `5ad1` fails if it went to a folder or project of any screenless kitten, or to a thread whose title starts with one's name and a colon. That title is the one Shades gave, or the first line, which is what T3 starts with.
- **Existing threads** (`testNoThreadThatIsOrMightBeAScreenlessKittensGetsYourScreen`). Routes `Pass`: Ask carrying on in a thread, Everyone carrying on in one, a reply in a thread opened on its own in Messages, Reply or Ask on an inbox row, answering the thread's question in Messages, and a dropped file carrying on in a thread. Talking while you type in Messages' box goes through the same box, so it takes these routes too. Thread: every runtime mode and an unknown one, in Clawde's folder, Clawde's project, elsewhere or no project, titled `Clawde:` or not, and started by you, a Clawde thread, a thread titled for Clawde, two steps from Clawde, a helper you started, an unknown agent, a thread that can't be read, or a loop. That's 3,840 runs. Whether the thread is or might be Clawde's comes from how it was set up (`Destination.mightBeScreenless`), not from the app, so the app can't mark its own homework.
- **Every run** also fails if anything but Ask looked at the screen, a drop included, or if the router ran anywhere but its own folder. Each test also fails if the screen never reached anywhere it's allowed, since then it couldn't tell when it's there.
- **The router's tools** (`testTheRouterHasNoToolThatReachesAnotherThread`). The router reads your screen first. Every tool in `waysToAnotherThread` (T3's tools that put text where another thread reads it, the shell, file writes, `SendMessage`, scheduled prompts, and names for tools that don't exist yet) must be turned away by its hook, and each T3 one denied outright as well, which holds if hooks are off. Each tool it lets through must be in `onlyRead`.
- **Sessions that only write words** (`testSessionsThatOnlyWriteWordsRunWhereTheyCantSendAny`). A summary and the inbox's sorting read reports that quote the screen, and must run in the router's folder like the router.
- **Threads named for a screenless kitten** (`testANewThreadNamedForAScreenlessKittenGetsNoScreen`). A hand-off the router titles `Clawde: ...`, and your words starting `Clawde:` given to Steve, each start a thread that counts as Clawde's, so neither may carry the screen.

It's tests on the real code rather than a model, because the question is where text can go, not what order things happen in. That way CI runs it on every pull request, and it can't drift from the code. The one order question is a kitten's `kitten.json` changing while your words are on their way. That's the same as a thread started just before the change, which `docs/kittens.md` already leaves out under "Earlier setups", so it gets no TLA+ model.

## Reading a failure

Each failure names the route, the setup and where the screen went, such as `askThread to a thread in clawdeFolder, started by you, mode autoAcceptEdits, Clawde in /k/clawde: the screen reached thread w`. Turn it into steps in the code's words: which function sent what, to where, and which check let it through.

- **A real leak** is a route that sends `5ad1` somewhere `docs/kittens.md` says it can't go ("What's enforced"). That's an access gap. Report it with those steps, and fix it in its own pull request without asking, unless the fix gives anything more access. Leave the check failing until then, or mark it with a scoped `XCTExpectFailure` that names the gap, as below. Don't weaken the check to make it pass.
- **A modeling error** is the test disagreeing with the promise as `docs/kittens.md` states it, such as a new kind of thread setup it doesn't know, or a tool it lists that can't actually carry text. Fix the test, and say why in the pull request.

## Changing what it covers

- A new way to send your words, such as a new `MessageTarget` or a new caller of `give`, `forward` or `reply`, gets a case in `Give` or `Pass` and a branch in `World.run`.
- A new kind of thing that stands in for the screen, like a dropped file, carries `5ad1` in every part, and gets the routes that reach a kitten.
- A new way a thread can count as a kitten's gets a case in `Destination` and in `World.add`, and in `mightBeScreenless`.
- A new T3 or Claude Code tool that can put text where a thread reads it goes in `waysToAnotherThread`.
- A new session that only writes words, like a summary, goes in `testSessionsThatOnlyWriteWordsRunWhereTheyCantSendAny`.

## Proving it can fail

Each property was seen failing on a broken copy of the code it guards, then the copy was dropped:

| Broken on purpose | What failed |
|---|---|
| `give` without `kitten.seesScreen` | Nothing, because `sharesWithScreenless` already counts the kitten itself. That's not a break, and it's why the next row drops both |
| `give` without `kitten.seesScreen` and `sharesWithScreenless`, still leaving the screen out with full access | New threads, 27 failures, each an Ask to a kitten without full access |
| `forward` without `isClearOfScreenlessKittens` | Existing threads, every one that is or might be Clawde's and runs in an ordinary mode |
| `traceIsClear` treating `.unknown` as clear | Existing threads, 4 failures, all started by an unknown agent |
| `RouterBlock.denied` without `mcp__t3-code` | The router's tools, 13 failures |
| `RouterBlock.allowed` with `Monitor` | The router's tools, 2 failures |
| A Messages new topic calling `startLook` | New threads, 64 failures, "something other than Ask looked at the screen" |
| `give` passing a drop on where the screen would be left out | New threads, 54 failures, each `dropKitten` to a screenless kitten's folder |
| `forward` passing a drop on where the screen would be left out | Existing threads, every `dropThread` to one that is or might be Clawde's |

After a change to the check, break one of these again and confirm it still fails.

## Known findings

Each is marked in its test with a scoped `XCTExpectFailure`. When one is fixed, remove that, and the test must pass without it.

**Summaries and sorting run where T3's tools work,** so a report that quotes a page could steer them into another thread:

1. You ask about a page. `runQuickTurn` sends `Prompts.quick` with the page in `<screen>`, and the router replies `HANDOFF:`.
2. `handOff` starts the frontier agent in T3's scratch folder with `Prompts.frontier`, page included. Its final report quotes the page.
3. `reportOn` reads that report. `words(for:)`, or `file` for a kitten with an inbox, builds `Prompts.summary` or `Prompts.sortReport` and calls `summarize`.
4. `summaryPrompt` sets no `projectID`, so `T3Backend.projectID(for:)` starts it in a scratch folder with no `.claude/settings.json`.
5. T3 allows its own tools in every thread, so the summary model can call `t3_thread_send` with that quote into a thread in Clawde's folder. Only "Don't use any tools" in the prompt stands in the way, which is what stood in the router's way before its own folder.

**A new thread named for a screenless kitten still gets your screen.** `KittenBoard.belongs` counts a thread titled `Clawde: ...` as Clawde's wherever it runs:

1. You ask about a page, and the router, which a page can steer, replies `HANDOFF: Clawde: Tighten the rules`.
2. `handOff` passes that task to `startFrontier` as the title, and the frontier agent starts in T3's scratch folder with your screen in `Prompts.frontier`.
3. Or you ask `Clawde: tighten the rules` and the router replies `KITTEN: 2`. `give` gives Steve no title, so `T3Backend.title(for:)` starts the thread as `Clawde: tighten the rules`, with your screen in `Prompts.forKitten`. `sharesWithScreenless` checks the folder, but with an empty title.
4. Either thread now counts as Clawde's. A file dropped onto the cat takes the same two routes, since it travels as the screen does. Its reports go to Clawde's inbox, and a reply in that thread from Clawde's DM can carry on in it, so work that read the page looks like Clawde's.

## What it leaves out

- **Agents that work.** The frontier agent, and kittens that see the screen, can start or message any thread with T3's tools. `docs/kittens.md` lists that under "Asking someone else", and only T3 can fix it.
- **Real T3 and Claude Code.** The backend is a fake. That Claude Code reads a `mcp__t3-code` deny rule as every T3 tool, and runs the hook, is assumed from its docs. `RouterBlockTests` runs the hook command itself.
- **Titles T3 rewrites.** T3 replaces the first line with a title of its own once it has read the thread, which the fake can't show. The check goes by the title Shades starts it with.
- **Approvals.** Allow and Deny send T3 a decision and no words.
- **Private apps.** A snapshot of an app on the privacy list carries nothing, which `PrivacyTests` and `PromptsTests` cover.
- **A kitten finding a copy itself.** That's the screen block in the kitten's folder, covered by `ScreenBlockTests` and `ThreadReadFilterTests`.
- **Talking.** Hold-to-talk calls the same `ask(_:capture:)` as the Ask box, which `FlowTests.testTalkingGoesThroughAskWithNoPanel` shows.
