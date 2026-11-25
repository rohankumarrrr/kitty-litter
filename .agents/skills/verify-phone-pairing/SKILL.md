---
name: verify-phone-pairing
description: Check every order in which pairing codes, a phone's key, page loads and the Mac's answers can happen, by running the phone page's own script in JavaScriptCore against the real PhoneLink and PhoneDoor inside swift test, so a phone is paired only while the Mac takes its key and every code you give it reaches the Mac. Use for any change to PhonePage.script's start, pair, pairing, the hashchange listener or the pair form, or to PhoneDoor or PhoneLink's /hello, /pair and /events.
---

# Verify phone pairing

## What it proves

A phone whose key the Mac takes never loses it, whatever code it's handed. A phone whose key the Mac refuses ends up asking for a code, with no key kept and nothing kittens said still showing. Every code you give the page, by scanning it into a tab that's open, opening it as a new page, or typing it, reaches the Mac. A code never stays in the page's address once the page has read it.

The harm it guards against: a paired phone logged out by an old pairing link, as before #123, a code scanned into the tab that's already open doing nothing and leaving "That code didn't work" up, as before #120, and a phone that keeps a key the Mac no longer takes.

## How

`Tests/ShadesTests/PhonePairingModelTests.swift` loads the real `PhonePage.script` into `PhoneScript` (`Tests/ShadesTests/PhoneScript.swift`) with no key, on the list of places, while the Mac shows a code. The Mac is the real `PhoneLink`, so every answer to `/hello`, `/pair`, `/events` and `/act` comes from `PhoneLink.respond` and the real `PhoneDoor`. Only what a stream carries is made up, from the real `PhoneView`. `walkEveryOrder` in `Tests/ShadesTests/PhoneModel.swift` tries every order of these events, four deep, replaying each order from a fresh page and skipping orders that end where another already did:

| Event | What it stands for in the code |
|---|---|
| the Mac shows a new code | `PhoneDoor.openPairing`, as Pair Phone… does. Once |
| you scan the code showing into the page that's open | `location.hash` changing to `#pair=…`, which the page's `hashchange` listener reads. Once |
| you scan an old code into the page that's open | The same, with a code that was shown and then used or replaced, or one from before this Mac's codes, such as an old link. Once |
| you open the code showing as a new page | The page loading with `#pair=…`, keeping its storage. Once |
| you type the code showing, or a wrong code, and press Pair | The pair form's submit. Each once, while the page asks for a code |
| the Mac restarts as a build that can't read its pairing | A new `PhoneLink` whose keys are empty, every stream ended. Once |
| the Mac answers the page's first or second waiting request | One answer, so another event can come between a request and what it leads to |
| the Mac answers everything waiting, in order | A Mac that answers at once |
| the page's request doesn't get through | A network error on the oldest waiting request. Once |
| N seconds pass | The page's next timer, such as its retry after it couldn't reach the Mac. Once |

After every event it checks that a key the Mac took before the event is still taken after it, that a page asking for a code shows nothing else (`top`, `head`, `rows`, `box`, `search`, `found` all hidden), that the page threw nothing, and that no code is left in the address once the page has nothing more to do. Then the Mac answers everything at once for 30 seconds. After that, the page holds a key the Mac takes and shows the places, or it holds no key and asks for one. Every code you gave it was sent to `/pair`, and a key the Mac took is still taken.

## Run it

```bash
swift test --filter PhonePairingModelTests
```

Run `swift` on its own, with no pipe and no `cd`. It takes about 15 seconds and passes with `Executed 3 tests, with 0 failures`. The walk sees about 2,000 states.

## Proving it can fail

| Broken on purpose | What failed |
|---|---|
| `PhonePage.swift` from before #120 (`git show 6259772b^:Sources/Shades/Phone/PhonePage.swift`), with no `hashchange` listener | The walk: "1. you scan the code showing into the page that's open. Then: the code stays in the page's address". `testACodeScannedIntoThePageAlreadyOpenPairsItAfterOneThatDidntWork`: "it's paired" was false |
| `PhonePage.swift` from before #123 (`git show 03e5f120^:…`), which drops its key whenever a code doesn't work | The walk: "1. you scan the code showing into the page that's open 2. you scan an old code into the page that's open 3. the Mac answers the page's /pair with 200. Then, with the network fine from here on: the page lost a key the Mac takes". `testAnOldPairingLinkLeavesAPairedPhonePaired`: "the page lost a key the Mac takes" |
| Today's `pairing()` without `localStorage.removeItem('shades.key')` | "1. you scan the code showing … 2. the Mac answers the page's /pair with 200 3. the Mac restarts as a build that can't read its pairing … Then: the page keeps a key the Mac refuses" |

To repeat one, copy the old `PhonePage.swift` over the current one, run the command, and restore it with `git checkout Sources/Shades/Phone/PhonePage.swift`.

## Reading a failure

A failure prints the shortest order that breaks it, as numbered steps in the words above, then what was wrong. If the page does what `docs/kittens.md` says about pairing and the model disagrees, that's a modeling error: fix the model and say why in the pull request. Otherwise it's a bug, so fix the code and don't weaken the check. A change here touches a guardrail, so it also gets the interrogate round `AGENTS.md`'s work rules ask for.

## What it leaves out

- **Codes running out.** Ten minutes and five wrong tries are `PhoneTests`' `testGuessingUsesTheCodeUpAndItRunsOut`, on the real `PhoneDoor`.
- **Search.** What a page found going with its pairing is checked apart from this, in `PhoneTests`.
- **The stream.** Pairing only needs the stream to open. Every order of a stream's events is `verify-phone-stream`.
- **Bounds.** Two codes, one of each event above, four events deep, which holds both bugs it replays.

## Sync

**Sync commit:** the commit that adds this skill. `git log -1 --format=%h -- .agents/skills/verify-phone-pairing` finds it, and `git diff <that> -- Sources/Shades/Phone/PhonePage.swift Sources/Shades/Phone/PhoneLink.swift Sources/Shades/Phone/PhoneDoor.swift` shows what has changed since. Move it forward only after reading those changes and confirming the events above still describe them.
