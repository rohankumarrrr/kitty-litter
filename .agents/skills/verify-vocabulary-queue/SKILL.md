---
name: verify-vocabulary-queue
description: Check every order in which vocabulary lists can be set, taken and loaded, against the real VocabularyQueue inside swift test, so the speech recognizer never loads two lists at once and the newest list always wins. Use for any change to VocabularyQueue, or to ParakeetVoiceEngine's setVocabulary, applyVocabulary, queueVocabulary, drainVocabulary or nextVocabulary.
---

# Verify the vocabulary queue

## What it proves

The recognizer loads one vocabulary list at a time. Once nothing is loading, the newest list set is the one loaded, and `applyVocabulary` returns only once its list, or a newer one, has loaded.

The harm it guards against: the app crashing when new projects change the vocabulary, as before #104, when every list started its own load and two reached the recognizer at once.

## How

`Tests/ShadesVoiceTests/VocabularyQueueModelTests.swift` runs the real `VocabularyQueue` from `Sources/ShadesVoice/Speech/VocabularyQueue.swift`, the part of `ParakeetVoiceEngine` that decides whether a list starts a drain or joins the one running, and what a drain takes next. `explore` in `Tests/TestSupport/Explorer.swift` tries every order of these steps:

| Step | What it stands for in the code |
|---|---|
| "Project 1" is set, "Project 2" is set | `setVocabulary`: `queueVocabulary` calls `add` under the engine's lock, starting a drain if none runs |
| "Project 3" is set | `applyVocabulary`, which does the same and then waits for the drain it got back |
| the first, second or third drain takes the next list | A drain `Task` reaching the top of `drainVocabulary`'s loop and calling `next` under the lock. The `Task` runs whenever Swift gets to it, so this is a step of its own |
| the recognizer finishes loading for a drain | `recognizer.setVocabulary` returning, which sends the drain back to the top of its loop |

Each step is one hold of the engine's lock or one await, as in the code.

After every step it checks that no more than one list is loading, that once no drain is running the newest list set is the last one loaded, and that once the drain `applyVocabulary` waits on has finished, its list or a newer one has loaded. It explores every reachable state, about 300 of them.

## Run it

```bash
swift test --filter VocabularyQueue
```

Run `swift` on its own, with no pipe and no `cd`. It takes well under a second and passes with `Executed 3 tests, with 0 failures`. The third test, `VocabularyQueueTests`, runs the real engine with 50 lists set at once, which checks the engine uses the queue.

## Proving it can fail

| Broken on purpose | What failed |
|---|---|
| `add` without `if let drain { return drain }`, so each list starts its own drain, as each `setVocabulary` started its own load before #104 | `testASecondListWhileTheFirstIsLoadingWaitsForIt`: "the recognizer loads [["Project 1"], ["Project 2"]] at once, which crashed the app". The walk: "1. "Project 1" is set 2. "Project 3" is set 3. the first drain takes the next list 4. the second drain takes the next list. Then: applyVocabulary returned before ["Project 3"] or anything newer loaded". `VocabularyQueueTests` found 5 loads at once |

## Reading a failure

A failure prints the shortest order of steps that breaks it. If the engine does what `docs/voice.md` says under Vocabulary and the model disagrees, fix the model and say why in the pull request. Otherwise it's a bug, so fix the code and don't weaken the check.

## What it leaves out

- **The engine's plumbing.** That `queueVocabulary` and `nextVocabulary` call `add` and `next` under the lock, and that `drainVocabulary` loops until `next` gives nothing, is read, not explored. `VocabularyQueueTests` runs it.
- **What loading does.** The recognizer and the cleanup pipeline are left out. Only when a load starts and ends matters here.
- **Bounds.** Three lists, each set once, which is enough for two drains to overlap and for a list to be replaced while it waits.

## Sync

**Sync commit:** the commit that adds this skill. `git log -1 --format=%h -- .agents/skills/verify-vocabulary-queue` finds it, and `git diff <that> -- Sources/ShadesVoice/Speech/VocabularyQueue.swift Sources/ShadesVoice/ParakeetVoiceEngine.swift` shows what has changed since. Move it forward only after reading those changes and confirming the steps above still describe them.
