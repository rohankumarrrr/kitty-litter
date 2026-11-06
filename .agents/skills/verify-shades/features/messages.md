# Messages

A window for everything the kittens are doing: what needs you pinned at the top, what they've finished, a group chat that goes through the router, a DM with each kitten, and what kittens say to each other. Messages are bubbles, yours on the right and each kitten's on the left in its colour. A kitten's threads show together, each under its title and project, and any one of them opens on its own, like a thread in Slack. Typing in it sends only your words, and nothing in it looks at your screen. Any message's words can be selected and copied, and a theme from another app can dress the window.

## Sub-features

- `messages-needs-you` lists approvals, questions and inbox reports, then what each kitten has in progress.
- `messages-done` lists what each kitten has finished, only when you open it.
- `messages-everyone` sends your words through the router, and whoever takes them answers there.
- `messages-shades` shows what you've asked the cat itself, from the router's own threads, and its box goes through the router as Everyone's does, with the cat answering there.
- `messages-dm` shows every thread of a kitten's under its title and project, and its box starts a new topic, which opens on its own.
- `messages-thread` shows one thread on its own, with its project at the top, and its box replies only into that thread.
- `messages-between` shows what kittens said to each other, for reading only.
- `messages-select` selects words in a message, which gives the window the keyboard without making Shades the active app, and ⌘C copies them as plain words.
- `messages-theme` dresses the window in a theme from T3 Code, Cursor, VS Code or iTerm2, picked from Theme at the bottom of the sidebar or dropped onto the window.

## How to get to it (user POV)

- Press ⌃⌘B, or choose Messages from the cat's menu.
- Click a row in the sidebar, such as Done or a kitten, to change what's showing.
- Click a thread's title, or hover a message and press Reply, to open that thread. "‹" at the top goes back.
- Type in the box at the bottom and press Return.
- Press in a message's words and drag, then ⌘C or right-click and Copy.
- Press **Theme** at the bottom of the sidebar and pick one, or drop a theme file onto the window.

## Driving it with the demo

Preconditions:

- A fresh demo. Messages starts at Needs you.

Journey: `journeys/messages.txt`.

- **Open.** `channels`, then `wait 1`. `channels.png` in `0-needs-you` shows Needs you, with In progress for Shades, Steve Pawsniak, Pepper and Clawde.
- **Everyone.** `channel everyone`, then `send I need help with my resume`, then `wait 4`. `[demo] started demo-1 ... You are Shades` is the router with 0 attachments, and `[demo] started demo-2 ... I need help with my resume / ---` is Steve's new thread. `channels.png` in `1-everyone` shows your message at the bottom of Everyone and the box empty again.
- **New topic.** `channel steve`, then `send How did the interview prep go?`, then `wait 2`. `[demo] started demo-3 with 0 attachments: How did the interview prep go? / ---` is a new thread for Steve with only your words. `channels.png` in `2-new-topic` shows that topic open on its own, with "‹ Steve Pawsniak" and its title at the top and "In How did the interview prep go?" over the box.
- **Thread.** `channel steve`, `thread`, `wait 1`, then `send Make the checkout button bigger too`, then `wait 2`. `thread` opens the last thread in the conversation, the same as clicking its title. `[demo] forwarded to demo-3 with 0 attachments: Make the checkout button bigger too / --- / Passed on` shows your words went into that thread and nothing else. `channels.png` in `3-thread` shows both your bubbles in that thread.
- **Done.** `back`, `channel done`, then `wait 1`. `channels.png` in `4-done` shows each kitten's finished threads, such as Steve's "Rewrite the pricing copy" with "PR #12 open".
- **Shades.** Journey `journeys/shades.txt`. `channel shades`, `send hello`, `wait 4`. `[demo] started demo-1 with 0 attachments: You are Shades` is the router, and `1-hello` shows "To me, without looking at your screen" over the box, your "hello" and the cat's "Hi. I'm a cat. What's up?" under it. `send I need help with my resume` carries on in `demo-1`, then `[demo] started demo-2 ... I need help with my resume / ---` is Steve's new thread, and `2-resume` shows "I passed that to the kitten it's for." `3-everyone` shows none of the cat's answers from Shades.
- **Select and copy.** Journey `journeys/select.txt`. `highlight the new grid` does what dragging over those words does, and prints `key=true front=<your app>`. `copy` says where ⌘C would go, without copying, so your pasteboard is left alone: `copy goes to nothing` before, then `copy goes to ChannelTextView with [the new grid] types=["NSStringPboardType"]`. `1-highlighted` shows the words picked out in Steve's last bubble.
- **Themes.** Journey `journeys/themes.txt`. `themes` prints what Theme offers, each app's themes under it, from made-up files the demo writes in a temporary folder. `colors Cursor/Opal Horizon` picks one from that list, and `colors <file>` is the same as dropping that file. `1-opal` shows the window dark, your bubbles in a violet tint and Steve's still in his own colour, and `themes` then marks Cursor and Opal Horizon. `colors T3 Code/Paper` gives a light window in `3-paper`. `colors Package.swift` changes nothing, and the cat says "That isn't a theme I can read." `colors shades` goes back to Shades' own.
- **Between kittens.** `channel` doesn't select these rows yet. The canned pictures from `swift run shades --demo --channels-image <folder>` cover them, and threads on their own, drawn from canned data in light and dark.

## Gotchas

- `theme light|dark|system` is the system's appearance, and `colors` is Messages' theme. A theme picked in the demo isn't saved.
- `highlight` gives Messages the keyboard, as pressing in words does, so `windows` says `channels ... key=true` and `active=true` afterwards. The app in front stays yours.
- `channel` takes `needs`, `done`, `everyone`, `shades` or the start of a kitten's name, such as `steve`. `thread` only works in a conversation, and `back` goes from a thread to its conversation.
- `messages` is the same as ⌃⌘B, so a second one closes the window. `channels` only opens it.
- The window is live, so a row under the real pointer can draw highlighted. That's where the mouse is, not a bug.
- `send` is the same as typing in the box and pressing Return, and it never takes the keyboard. The box beeps and sends nothing when there's nowhere to send, such as in Needs you, or in a new topic before T3 has started its thread.
- Messages reads the canned transcripts when it opens. Draw before `wait 1` and it can still say it's reading.
- The window opens where it was last left. Its frame in `windows` can be on another display.
