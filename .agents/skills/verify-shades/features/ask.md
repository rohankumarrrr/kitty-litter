# Ask

You ask the cat something about what's on your screen. The router either answers in the bubble, passes your words to a kitten or a session that has the context, or hands real work to the frontier agent, and the bubble says which.

## Sub-features

- `ask-answer` streams an answer into the bubble, with Open in T3 and Copy.
- `ask-kitten` passes your words to a kitten, and the bubble says "<kitten> has this."
- `ask-handoff` starts the frontier agent, and the bubble says "<model> has this."
- `ask-session` passes a follow-up to the session it carries on from.
- `ask-rewrite` rewrites the selected text, and the bubble offers Replace, which puts it in place of the selection, or copies it if the selection has moved.

## How to get to it (user POV)

- Click the cat, type in the Ask box and press Return.
- Hold the talk key and say it.
- Press the Ask shortcut, or choose Ask... from the cat's menu.

## Driving it with the demo

Preconditions:

- A fresh demo, with no bubble showing.

Journey: `journeys/ask.txt`.

- **Answer.** Ask about the page. `ask What's on this page?`, then `wait 4`. `[demo] started demo-1` shows the router prompt, and `bubble.png` in `1-answered` shows the pricing answer with Open in T3 and Copy.
- **To a kitten.** Ask about a resume. `ask I need help with my resume`, then `wait 3`. `[demo] carried on in demo-1` is the router's turn, then `[demo] started demo-2 ... I need help with my resume / --- / Shades, the user's desktop cat, gave you this` is Steve's new thread with your words first. `bubble.png` in `2-to-a-kitten` says "Steve Pawsniak has this."
- **Hand-off.** Ask for a fix. `ask Fix the buy button`, then `wait 3`. `[demo] started demo-3 ... You were started from the user's desktop cat` is the frontier agent. `bubble.png` in `3-handed-off` says "Opus has this."
- **Rewrite.** Journey: `journeys/rewrite.txt`. `select <text>` stands for text you've selected, then `ask Tighten this`, then `wait 5`. `bubble.png` in `1-rewritten` shows the shorter text with Replace, Open in T3 and Copy. `replace` presses Replace, and `[demo] would replace the selection with: ...` is the write. Then a second rewrite, `select` alone to click somewhere else, and `replace` again: `[demo] the selection moved, so nothing was replaced`, and `bubble.png` in `3-copied` says it's copied instead.
- **Follow-up.** `ask What you said, can you follow up?`, then `wait 4`. `[demo] forwarded to demo-research ... What you said, can you follow up? / --- / Passed on` shows it went to the newest running session, Compare pixel fonts. This step isn't in the journey.

## Gotchas

- `ask` with words skips the Ask box and sends a screen with no picture, so `with 0 attachments` is expected. `ask` alone opens the Ask box, which takes the keyboard without activating Shades until it closes, so a person typing elsewhere could type into it. Follow it with `submit <words>` or `esc` on the next line.
- A streamed answer takes about 1.4 seconds to start and 35 milliseconds a word. Draw too early and the bubble is half written.
- Each `ask` after the first carries on in the same router thread, which is why later router turns print `carried on in`.
- Replace waits 0.7 seconds before it takes a click, so it shows dim in a picture drawn sooner than that. The `replace` command doesn't wait.
- The fake T3 gives every folder the same project, `demo-project`, so the output can't show which folder a thread started in.
