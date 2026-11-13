# Check Myself

The cat goes through its signature, permissions, T3 Code and the kittens, and says how it went in a bubble captioned "Self-check": "All good." or each problem with what to do about it. The same check runs once at launch and writes `health.json`, which `scripts/install.sh` waits for.

## Sub-features

- `check-good` is "All good. I checked my signature, permissions, T3 Code and the kittens."
- `check-connecting` is T3 not answering in time, as when a new build signs in again. The check gives T3 10 seconds (`t3Wait`), then says "I'm still connecting to T3 Code, so my agents can't run yet.", and doesn't call any kitten missing from T3 for it. Once T3 answers it checks again by itself, writes `health.json` again and, if you chose Check Myself, says how it went.
- `check-stuck` is T3 still not answering two minutes (`t3StuckAfter`) after that, when it says to answer a Keychain dialog if one's showing, or else to quit and reopen T3 Code. `testT3ThatNeverAnswersIsCalledStuckAfterAWhile` covers it, since a journey would take too long.

## How to get to it (user POV)

- Right-click the cat, or click the menu bar item, and choose Check Myself.

## Driving it with the demo

Preconditions:

- A fresh demo. Its permissions and kittens are all set up, so the only problem it can have is T3.

Journey: `journeys/check-myself.txt`.

- **Good.** `check`, which chooses Check Myself. `1-all-good/bubble.png` says "All good." under "Self-check".
- **Connecting.** `t3 stuck`, then `check`. `2-waiting/` has only `cat.png`, since nothing's said while T3 has time left. `3-connecting/bubble.png`, 12 seconds in, says "I'm still connecting to T3 Code, so my agents can't run yet. Give it a minute. I'll check again by myself once it answers." The output has `[demo] health.json would say T3 Code: I'm still connecting to T3 Code, so my agents can't run yet.`
- **Answered.** `t3 on`. The output has `[demo] health.json would say ok`, and `4-answered/bubble.png` says "All good." under "Self-check".

## Gotchas

- Demo mode writes no `health.json`, and prints a `[demo] health.json would say` line for each report instead. `testTheSelfCheckReportsEvenWhileSigningInToT3NeverFinishes` in `FlowTests` covers the report going out while T3 never answers.
- `t3 stuck` lasts until `t3 on`. Anything that asks T3 for a project waits on it till then, and then gets its answer.
