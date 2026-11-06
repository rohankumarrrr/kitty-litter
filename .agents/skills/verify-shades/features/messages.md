# Messages

A window for everything the kittens are doing: what needs you pinned at the top, what they've finished, a group chat that goes through the router, a DM with each kitten, and what kittens say to each other. Typing in it sends only your words, and nothing in it looks at your screen.

## Sub-features

- `messages-needs-you` lists approvals, questions and inbox reports, then what each kitten has in progress.
- `messages-done` lists what each kitten has finished, only when you open it.
- `messages-everyone` sends your words through the router, and whoever takes them answers there.
- `messages-dm` carries on in the kitten's latest thread.
- `messages-between` shows what kittens said to each other, for reading only.

## How to get to it (user POV)

- Choose Messages from the cat's menu.
- Click a row in the sidebar, such as Done or a kitten, to change what's showing.
- Type in the box at the bottom and press Return.

## Driving it with the demo

Preconditions:

- A fresh demo. Messages starts at Needs you.

Journey: `journeys/messages.txt`.

- **Open.** `channels`, then `wait 1`. `channels.png` in `0-needs-you` shows Needs you, with In progress for Steve Pawsniak, Pepper and Clawde.
- **Everyone.** `channel everyone`, then `send I need help with my resume`, then `wait 4`. `[demo] started demo-1 ... You are Shades` is the router with 0 attachments, and `[demo] started demo-2 ... I need help with my resume / ---` is Steve's new thread. `channels.png` in `1-everyone` shows your message at the bottom of Everyone and the box empty again.
- **DM.** `channel steve`, then `send How did the interview prep go?`, then `wait 2`. `[demo] forwarded to demo-tidy with 0 attachments: How did the interview prep go? / --- / Passed on` shows your words went to Steve's latest thread and nothing else. `channels.png` in `2-dm` shows it at the bottom of Steve's DM, under "In Tidy up the pricing page".
- **Done.** `channel done`, then `wait 1`. `channels.png` in `3-done` shows each kitten's finished threads, such as Steve's "Rewrite the pricing copy" with "PR #12 open".
- **Between kittens.** `channel` doesn't select these rows yet. The canned pictures from `swift run shades --demo --channels-image <folder>` cover them, drawn from canned data in light and dark.

## Gotchas

- `channel` takes `needs`, `done`, `everyone` or the start of a kitten's name, such as `steve`.
- The window is live, so a row under the real pointer can draw highlighted. That's where the mouse is, not a bug.
- `send` is the same as typing in the box and pressing Return, and it never takes the keyboard. The box beeps and sends nothing when there's nowhere to send, such as in Needs you before pressing Reply.
- Messages reads the canned transcripts when it opens. Draw before `wait 1` and it can still say it's reading.
- The window opens where it was last left. Its frame in `windows` can be on another display.
