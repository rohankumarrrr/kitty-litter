# Ask

You ask the cat something about what's on your screen. The router either answers in the bubble, passes your words to a kitten or a session that has the context, or hands real work to the frontier agent, and the bubble says which.

## Sub-features

- `ask-answer` streams an answer into the bubble, a black card lit along its foot in Shades' hue, with Copy and Open in T3 at its right.
- `ask-long` opens a long answer at its start, with its last line fading out to show there's more, and the system's scroll bar. The top fades instead once you scroll to its end.
- `ask-kitten` passes your words to a kitten, and the bubble says "<kitten> has this."
- `ask-handoff` starts the frontier agent, and the bubble says "<model> has this."
- `ask-session` passes a follow-up to the session it carries on from.
- `ask-rewrite` rewrites the selected text, and the bubble offers Replace, which puts it in place of the selection, or copies it if the selection has moved.
- `ask-point` answers where something is, and the cat runs to it and sits on it until the answer goes. If it can't find the spot, the bubble says so and the cat stays put.

## How to get to it (user POV)

- Click the cat, type in the Ask box and press Return.
- Hold the talk key and say it.
- Press the Ask shortcut, or choose Ask... from the cat's menu.

## Driving it with the demo

Preconditions:

- A fresh demo, with no bubble showing.

Journey: `journeys/ask.txt`.

- **Answer.** Ask about the page. `ask What's on this page?`, then `wait 4`. `[demo] started demo-1` shows the router prompt, and `bubble.png` in `1-answered` shows the pricing answer with Copy and Open in T3.
- **To a kitten.** Ask about a resume. `ask I need help with my resume`, then `wait 3`. `[demo] carried on in demo-1` is the router's turn, then `[demo] started demo-2 ... I need help with my resume / --- / Shades, the user's desktop cat, gave you this` is Steve's new thread with your words first. `bubble.png` in `2-to-a-kitten` says "Steve Pawsniak has this."
- **Long answer.** Journey: `journeys/long-answer.txt`. `ask Give me a long answer about this page`, then `wait 14`. `bubble.png` in `0-done` shows the answer's first lines and its last line fading out. There's no demo command to scroll it, so the faded top at its end is in `testALongAnswerOpensAtItsStartAndShowsThereIsMoreBelow`.
- **Fix on The Kitty Litter.** Journey `journeys/fix-own-window.txt`. With The Kitty Litter open under the demo's marked spot, the middle of the screen, `fix` and `submit` print `[demo] told demo-1 the marked spot is on The Kitty Litter's own window` after `[demo] started demo-1`. `messages` closes it, and the next fix prints no such line. It reads the real desktop: another copy's window over the middle of the screen, such as a second demo's bubble, is another app's, so no line prints, and if `windows` still says `channels ... visible=true` after `messages`, it was behind something and came forward, so the second fix isn't elsewhere. The demo's pick has no overlay, so looking past the real picker's overlay, which a click still reaches just after it's gone, and past the cat, is `OwnWindowTests`. The line itself, outside `<screen>` and never taken as your words, is `testAFixMarkedOnOurOwnWindowSaysSoOutsideTheScreenAndTheirWords` in `PromptsTests`.
- **Hand-off.** Ask for a fix. `ask Fix the buy button`, then `wait 3`. `[demo] started demo-3 ... You were started from the user's desktop cat` is the frontier agent. `bubble.png` in `3-handed-off` says "Opus has this."
- **Rewrite.** Journey: `journeys/rewrite.txt`. `select <text>` stands for text you've selected, then `ask Tighten this`, then `wait 5`. `bubble.png` in `1-rewritten` shows the shorter text with Copy, Open in T3 and Replace, the one violet button, at the right. `replace` presses Replace, and `[demo] would replace the selection with: ...` is the write. Then a second rewrite, `select` alone to click somewhere else, and `replace` again: `[demo] the selection moved, so nothing was replaced`, and `bubble.png` in `3-copied` says it's copied instead.
- **Point.** Journey: `journeys/pointing.txt`. `ask`, `wait 0.5`, then `submit Where's the free trial button?` and `wait 6`. `bubble.png` in `1-pointed` shows the answer with no `POINT:` line, and `windows` puts the cat on top of the demo's Start free trial button, which sits 62% across and 55% down the main display. `esc` sends it home. `submit Where's the logo?` points at an item the screen doesn't have, so `bubble.png` in `2-cant-point` says "I couldn't find it on screen to point at." and the cat stays home. `submit Where's the share button?` points at Safari's Share button, just under the menu bar, where there's no room above it, so `windows` puts the cat underneath it instead of on top.
- **Every state of the cat's windows.** Journey: `journeys/cat-windows.txt`, about 90 seconds. It draws the bubble thinking, answering, with a long answer, a rewrite, a hand-off, an approval and two, a question, a report, the inbox and each error, the Ask box empty, typed into, talked into and with a dropped file, and the pill, each into its own folder in `.verify/shades/cat-windows/`. `journeys/fades.txt` prints each window's `alpha=` a few hundredths of a second after it comes and goes. Run it as it is, then with `--reduce-motion`, where every `alpha=` is 1.00 and the bubble's gone at once.
- **Follow-up.** `ask What you said, can you follow up?`, then `wait 4`. `[demo] forwarded to demo-research ... What you said, can you follow up? / --- / Passed on` shows it went to the newest running session, Compare pixel fonts. This step isn't in the journey.

## Gotchas

- `ask` with words skips the Ask box and sends a screen with no picture or anything to point at, so `with 0 attachments` is expected, and pointing needs `ask` then `submit`. The Ask box opens only after its look at the screen, so put `wait 0.5` between them. `ask` alone opens the Ask box, which takes the keyboard without activating The Kitty Litter until it closes, so a person typing elsewhere could type into it. Follow it with `submit <words>` or `esc` on the next line.
- A streamed answer takes about 1.4 seconds to start and 35 milliseconds a word. Draw too early and the bubble is half written.
- Each `ask` after the first carries on in the same router thread, which is why later router turns print `carried on in`.
- Replace waits 0.7 seconds before it takes a click, so it shows dim in a picture drawn sooner than that. The `replace` command doesn't wait.
- The fake T3 gives every folder the same project, `demo-project`, so the output can't show which folder a thread started in.
