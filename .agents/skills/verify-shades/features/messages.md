# Messages

A window for everything the kittens are doing: what needs you pinned at the top, what they've finished, a group chat that goes through the router, a DM with each kitten, and what kittens say to each other. Messages are bubbles, yours on the right and each kitten's on the left in its colour. A kitten's threads show together, each under its title and project, and any one of them opens on its own, like a thread in Slack. Typing in it sends only your words, and nothing in it looks at your screen.

## Sub-features

- `messages-needs-you` lists approvals, questions and inbox reports, then what each kitten has in progress.
- `messages-done` lists what each kitten has finished, only when you open it.
- `messages-everyone` sends your words through the router, and whoever takes them answers there.
- `messages-dm` shows every thread of a kitten's under its title and project, and its box starts a new topic, which opens on its own.
- `messages-thread` shows one thread on its own, with its project at the top, and its box replies only into that thread.
- `messages-between` shows what kittens said to each other, for reading only.

## How to get to it (user POV)

- Press ⌃⌘M, or choose Messages from the cat's menu.
- Click a row in the sidebar, such as Done or a kitten, to change what's showing.
- Click a thread's title, or hover a message and press Reply, to open that thread. "‹" at the top goes back.
- Type in the box at the bottom and press Return.

## Driving it with the demo

Preconditions:

- A fresh demo. Messages starts at Needs you.

Journey: `journeys/messages.txt`.

- **Open.** `channels`, then `wait 1`. `channels.png` in `0-needs-you` shows Needs you, with In progress for Shades, Steve Pawsniak, Pepper and Clawde.
- **Everyone.** `channel everyone`, then `send I need help with my resume`, then `wait 4`. `[demo] started demo-1 ... You are Shades` is the router with 0 attachments, and `[demo] started demo-2 ... I need help with my resume / ---` is Steve's new thread. `channels.png` in `1-everyone` shows your message at the bottom of Everyone and the box empty again.
- **New topic.** `channel steve`, then `send How did the interview prep go?`, then `wait 2`. `[demo] started demo-3 with 0 attachments: How did the interview prep go? / ---` is a new thread for Steve with only your words. `channels.png` in `2-new-topic` shows that topic open on its own, with "‹ Steve Pawsniak" and its title at the top and "In How did the interview prep go?" over the box.
- **Thread.** `channel steve`, `thread`, `wait 1`, then `send Make the checkout button bigger too`, then `wait 2`. `thread` opens the last thread in the conversation, the same as clicking its title. `[demo] forwarded to demo-3 with 0 attachments: Make the checkout button bigger too / --- / Passed on` shows your words went into that thread and nothing else. `channels.png` in `3-thread` shows both your bubbles in that thread.
- **Done.** `back`, `channel done`, then `wait 1`. `channels.png` in `4-done` shows each kitten's finished threads, such as Steve's "Rewrite the pricing copy" with "PR #12 open".
- **Between kittens.** `channel` doesn't select these rows yet. The canned pictures from `swift run shades --demo --channels-image <folder>` cover them, and threads on their own, drawn from canned data in light and dark.

## Gotchas

- `channel` takes `needs`, `done`, `everyone` or the start of a kitten's name, such as `steve`. `thread` only works in a conversation, and `back` goes from a thread to its conversation.
- `messages` is the same as ⌃⌘M, so a second one closes the window. `channels` only opens it.
- The window is live, so a row under the real pointer can draw highlighted. That's where the mouse is, not a bug.
- `send` is the same as typing in the box and pressing Return, and it never takes the keyboard. The box beeps and sends nothing when there's nowhere to send, such as in Needs you, or in a new topic before T3 has started its thread.
- Messages reads the canned transcripts when it opens. Draw before `wait 1` and it can still say it's reading.
- The window opens where it was last left. Its frame in `windows` can be on another display.
