---
name: verify-phone-stream
description: Check every order in which the phone page's stream, what you send from it, and the Mac letting go can happen, by running the page's own script in JavaScriptCore against a stand-in Mac inside swift test, so nothing you send is lost silently or sent twice and the page always gets a live stream back. Use for any change to PhonePage.script's listen, request, act, revive or the box's send, to PhoneLink's watch, perform or letting go, or to PhoneStream's pings.
---

# Verify the phone stream

## What it proves

What you send from your phone reaches the Mac exactly once if the network is fine from when you press send. If the network fails after you press it, your words either reach the Mac once or stay in your box. The page never says something changed when nothing had. However the connection dies, once the network is fine again the page ends up on one live stream with no error showing.

The harm it guards against: words you sent that silently never arrive, arrive twice, or bring up "That's changed since" however often you try, as before #109, and a page stuck on what it last showed after the lock screen, as before #108.

## How

`Tests/ShadesTests/PhoneStreamModelTests.swift` loads the real `PhonePage.script` into `PhoneScript` (`Tests/ShadesTests/PhoneScript.swift`), a JavaScriptCore page with a stand-in browser, on a thread's page that's open and live. `walkEveryOrder` in `Tests/ShadesTests/PhoneModel.swift` then tries every order of these events, five deep, replaying each order from a fresh page and skipping orders that end where another already did:

| Event | What it stands for in the code |
|---|---|
| you send "Ship it" | Typing in `#words` and pressing the arrow, `$('box').onsubmit`, then `act` and `request` |
| the Mac answers the page's /hello, /events, seen or send | Each waiting request, in any order. The stand-in follows `PhoneLink.respond`: `watch` closes the page's older streams and holds Messages, `perform` says 503 while nothing holds it and takes the rest through the real `PhoneAsk.action` |
| the connection under the page's stream goes dead | An iPhone after the lock screen, another app or a new network: the page hears nothing more on it, and the Mac doesn't know yet. At most twice |
| the Mac notices the dead connection and closes its end | `PhoneStream.close` after a failed write, then `onClose` |
| 20 seconds pass with no stream, and the Mac lets go | `letting` in `PhoneLink.watch` after `phoneGrace`, then `forget`. The page's clock moves the 20 seconds with it |
| something changes and the Mac sends it | `PhoneLink.publish` sending a view on each live stream. At most once more |
| N seconds pass | The page's next timer fires: the 5-second quiet check, the 3-second check after a send, the 10-second wait after a 503, or a retry. Each live stream pings first, as `PhoneStream` does every 10 seconds. At most three times |
| you leave the page and come back | `visibilitychange`, which marks the thread seen and revives a stream quiet for 15 seconds |

The Mac answers time passing only once every request is answered, so it's never slower than the page's own timers.

After every event it checks that the Mac got what you sent at most once, that the page doesn't say "That's changed since", that the page reads at most one stream, and that the page threw nothing. Then it lets the network be fine for 60 seconds: the Mac notices every dead connection, answers every request, and pings every live stream. After that, what you sent is on the Mac once and out of your box, unless the network went wrong after you pressed send and your words are still in the box. The page is on one live stream, with nothing in its banner.

Swift and `swift test` were chosen over TLA+ because the question is whether the page's real script mishandles some order of a few events. This runs that script, needs no browser or Java, and runs in CI with everything else.

## Run it

```bash
swift test --filter PhoneStreamModelTests
```

Run `swift` on its own, with no pipe and no `cd`. It takes about seven seconds and passes with `Executed 3 tests, with 0 failures`. The walk sees about 800 states.

## Proving it can fail

| Broken on purpose | What failed |
|---|---|
| `PhonePage.swift` from before #108 (`git show 1afe65e4^:Sources/Shades/Phone/PhonePage.swift`), with no quiet check | "1. the connection under the page's stream goes dead … Then, with the network fine from here on: the page isn't listening on a live stream" |
| `PhonePage.swift` from before #109 (`git show 1afe65e4:…`), which gives up on a 503 | "1. the connection … goes dead 2. the Mac notices … 3. 20 seconds pass … and the Mac lets go 4. you send … Then: the Mac has [] of what you sent, though the network was fine from when you pressed send" |
| The same page, with the stand-in Mac saying 409 for nobody looking, as `PhoneLink.perform` did before #109 | "1. you send … 2–4. the connection dies, the Mac notices and lets go. Then: the page says it changed, though nothing had" |

To repeat one, copy the old `PhonePage.swift` over the current one, run the command, and restore it with `git checkout Sources/Shades/Phone/PhonePage.swift`.

Removing `if (began < sent) listen();` from `request` breaks nothing here. With the Mac's 20 seconds of grace and the page's 10-second wait, the 25-second quiet check always starts a stream in time, so that line only makes a send go sooner.

## Reading a failure

A failure prints the shortest order that breaks it, as numbered steps in the words above, then what was wrong. Step through it with `PhoneScript` in a test of your own, which can stop after any step and read the page with `phone.read`. If the code does what `docs/kittens.md` says under the phone's stream and the model disagrees, that's a modeling error, so fix the stand-in Mac and say why in the pull request. Otherwise it's a bug, so fix the code and don't weaken the check.

## What it leaves out

- **Layout and taps.** `PhoneScript` has no CSS or layout. `PressPhoneTests` runs the page in WebKit for those.
- **Pairing.** The stand-in Mac admits the phone's key. What happens when it doesn't is pairing's to check.
- **A slow Mac.** Time only passes while nothing waits on the Mac, so a request the Mac takes more than the page's timers to answer isn't tried. The 10-second wait after a 503 running out is left out with it.
- **The real `PhoneLink`.** The stand-in follows its rules, as the table says, but the real one needs a socket. `PhoneServerTests` checks its 503, its grace and its closing a page's older streams over loopback.
- **Bounds.** One send, two dead connections, one more update, three waits, one trip away, five events deep from a live page, which holds the longest bug it replays.

## Sync

**Sync commit:** the commit that adds this skill. `git log -1 --format=%h -- .agents/skills/verify-phone-stream` finds it, and `git diff <that> -- Sources/Shades/Phone/PhonePage.swift Sources/Shades/Phone/PhoneLink.swift Sources/Shades/Phone/PhoneServer.swift Sources/Shades/App/AppController.swift` shows what has changed since. Move it forward only after reading those changes and confirming the events above still describe them.
