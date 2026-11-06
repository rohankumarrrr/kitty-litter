# Approvals

When an agent wants to run a command or touch a file, the cat comes over and the bubble asks, with Deny, Allow and Allow for this session.

## Sub-features

- `approval-ask` shows which thread is asking and what it wants to run.
- `approval-answer` sends the answer to T3, and the bubble goes.

## How to get to it (user POV)

- The cat comes to you by itself when an agent asks.
- Press Deny, Allow or Allow for this session in the bubble, or answer it in Messages.

## Driving it with the demo

Preconditions:

- A fresh demo, with nothing waiting.

Journey: `journeys/approvals.txt`.

- **Ask.** `approval command npm test`, then `wait 4`. `bubble.png` in `0-asked` shows "Steve Pawsniak: Tidy up the pricing page", "Wants to run this:", `npm test`, and the three buttons.
- **Allow.** `allow`, then `wait 1`. The output says `[demo] accept: npm test`, and `1-allowed` has no `bubble.png` because the bubble has gone.

## Gotchas

- The bubble only shows once the cat has run over, which takes a few seconds. `windows` says `state run` while it's on the way.
- `approval` takes a kind first: `command`, `fileChange` or `fileRead`. The words after it are what's shown.
- `deny` and `session` answer the other two ways.
