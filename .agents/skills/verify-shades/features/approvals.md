# Approvals

When an agent wants to run a command or touch a file, the cat comes over and the bubble asks, lit along its foot in that kitten's colour, with the command in a code block. Allow is the one violet button, at the right as in a macOS alert, with Deny beside it and Allow for this session apart at the left.

## Sub-features

- `approval-ask` shows which thread is asking and what it wants to run.
- `approval-answer` sends the answer to T3, and the bubble goes.

## How to get to it (user POV)

- The cat comes to you by itself when an agent asks.
- Press Allow, Deny or Allow for this session in the bubble, or answer it in The Kitty Litter.

## Driving it with the demo

Preconditions:

- A fresh demo, with nothing waiting.

Journey: `journeys/approvals.txt`.

- **Ask.** `approval command npm test`, then `wait 4`. `bubble.png` in `0-asked` shows "Steve Pawsniak: Tidy up the pricing page", "Wants to run this:", `npm test` in a code block, and Allow for this session, Deny and Allow, left to right.
- **A long command.** `approval command npm run build && npm test && npx playwright test --project=chromium --reporter=line --workers=4`, then `wait 4`. The command wraps only at spaces, so `--reporter=line` starts a line whole rather than splitting after `--`. What's selected and copied is the real text.
- **Allow.** `allow`, then `wait 1`. The output says `[demo] accept: npm test`, and `1-allowed` has no `bubble.png` because the bubble has gone.

## Gotchas

- The bubble only shows once the cat has run over, which takes a few seconds. `windows` says `state run` while it's on the way. With `--reduce-motion` the cat is there in a tick, as it is with Reduce Motion on.
- `approval` takes a kind first: `command`, `fileChange` or `fileRead`. The words after it are what's shown.
- `deny` and `session` answer the other two ways.
