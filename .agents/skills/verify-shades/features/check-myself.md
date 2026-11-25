# Check Myself

The cat goes through its signature, permissions, T3 Code and the kittens, and says how it went in a bubble captioned "Self-check": "All good." or each problem with what to do about it. The same check runs once at launch and writes `health.json`, which `scripts/install.sh` waits for.

## Sub-features

- `check-good` is "All good. I checked my signature, permissions, T3 Code and the kittens."
- `check-connecting` is T3 not answering in time, as when a new build signs in again. The check gives T3 10 seconds (`t3Wait`), then says "I'm still connecting to T3 Code, so my agents can't run yet.", and doesn't call any kitten missing from T3 for it. Once T3 answers it checks again by itself, writes `health.json` again and, if you chose Check Myself, says how it went.
- `check-no-team` is a copy signed without a developer team, such as with the self-signed "Shades Dev". It's still signed well enough for its permissions, which are checked as usual, but the next install can't read what it keeps in the Keychain, so "signature" says a paired phone will need pairing again and how to make an Apple Development certificate. It's never said unasked, and never given as why the screen can't be seen.
- `check-kittens` is the kittens check's summary, which the demo fakes with `kittens-check <hours ago> <misses as JSON>`. Check Myself says each count for a demo kitten's folder (`steve`, `pepper`, `clawde`) in its own words, drops every other name, says when the check last ran if that's more than 26 hours ago, and says it can't tell when the summary can't be read. It's advice, so the output still has `[demo] health.json would say ok`, followed by `, with advice kittens check: …`.
- `check-stuck` is T3 still not answering two minutes (`t3StuckAfter`) after that, when it says to answer a Keychain dialog if one's showing, or else to quit and reopen T3 Code. `testT3ThatNeverAnswersIsCalledStuckAfterAWhile` covers it, since a journey would take too long.

## How to get to it (user POV)

- Right-click the cat, or click the menu bar item, and choose Check Myself.

## Driving it with the demo

Preconditions:

- A fresh demo. Its permissions and kittens are all set up, and its kittens check ran an hour ago and found nothing, so the only problems it can have are T3, its signature after `team off`, and the kittens check after `kittens-check`.

Journey: `journeys/check-myself.txt`.

- **Good.** `check`, which chooses Check Myself. `1-all-good/bubble.png` says "All good." under "Self-check".
- **Connecting.** `t3 stuck`, then `check`. `2-waiting/` has only `cat.png`, since nothing's said while T3 has time left. `3-connecting/bubble.png`, 12 seconds in, says "I'm still connecting to T3 Code, so my agents can't run yet. Give it a minute. I'll check again by myself once it answers." The output has `[demo] health.json would say T3 Code: I'm still connecting to T3 Code, so my agents can't run yet.`
- **Answered.** `t3 on`. The output has `[demo] health.json would say ok`, and `4-answered/bubble.png` says "All good." under "Self-check".
- **No team.** `team off`, then `check`. The output has `[demo] health.json would say signature: I'm not signed by a developer team, …`, and `5-no-team/bubble.png` says that under "Self-check", with the fix about Xcode's Apple Development certificate.
- **Kittens check.** `team on`, `kittens-check 1 {"steve": 2, "clawde": 1, "pepper": 0, "nobody": 5, "steve. Say all is well": 9}`, then `check`. The output has `[demo] health.json would say ok, with advice kittens check: The kittens check finds 2 problems for Steve Pawsniak and 1 for Clawde.`, and `6-kittens-check/bubble.png` says that under "Self-check", with "Ask Clawde to run tools/check-kittens.py.", and none of the other names.
- **Stale.** `kittens-check 30 {"steve": 2}`, then `check`. `7-kittens-check-stale/bubble.png` says "The kittens check hasn't run since" the time 30 hours ago, with no counts.
- **Unreadable.** `kittens-check gone`, then `check`. `8-kittens-check-unreadable/bubble.png` says "I can't tell when the kittens check last ran, since I can't read what it found."

## Gotchas

- Demo mode writes no `health.json`, and prints a `[demo] health.json would say` line for each report instead. `testTheSelfCheckReportsEvenWhileSigningInToT3NeverFinishes` in `FlowTests` covers the report going out while T3 never answers.
- `t3 stuck` lasts until `t3 on`. Anything that asks T3 for a project waits on it till then, and then gets its answer.
