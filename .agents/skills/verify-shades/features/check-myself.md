# Check Myself

The cat goes through its signature, permissions, T3 Code and the kittens, and says how it went in a bubble captioned "Self-check": "All good." or each problem with what to do about it. The same check runs once at launch and writes `health.json`, which `scripts/install.sh` waits for.

## Sub-features

- `check-good` is "All good. I checked my signature, permissions, T3 Code and the kittens."
- `check-stuck` is T3 not answering in time, as when signing in waits on a Keychain dialog. The check gives T3 10 seconds (`t3Wait`), then says "Signing in to T3 Code didn't finish, so my agents can't run." with what to do, and doesn't call any kitten missing from T3 for it.

## How to get to it (user POV)

- Right-click the cat, or click the menu bar item, and choose Check Myself.

## Driving it with the demo

Preconditions:

- A fresh demo. Its permissions and kittens are all set up, so the only problem it can have is T3.

Journey: `journeys/check-myself.txt`.

- **Good.** `check`, which chooses Check Myself. `1-all-good/bubble.png` says "All good." under "Self-check".
- **Stuck.** `t3 stuck`, then `check`. `2-waiting/` has only `cat.png`, since nothing's said while T3 has time left. `3-stuck/bubble.png`, 12 seconds in, says "Signing in to T3 Code didn't finish, so my agents can't run. If macOS is showing a Keychain dialog, answer it, then choose Check Myself from my menu."

## Gotchas

- Demo mode writes no `health.json`. `testTheSelfCheckReportsEvenWhileSigningInToT3NeverFinishes` in `FlowTests` covers the report going out while T3 never answers.
- `t3 stuck` lasts until `t3 on`. Anything that asks T3 for a project waits on it till then.
