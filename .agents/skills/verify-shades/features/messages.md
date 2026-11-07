# Messages

A window for everything the kittens are doing, laid out like Slack: Activity and Threads at the top, then #general and a channel for each kitten, then a DM with the cat. Each T3 session is a thread: a channel shows its parent with a reply bar, and clicking it opens the thread in a pane beside the channel. Messages are bubbles, yours on the right and each kitten's on the left in its colour. Typing in it sends only your words, and nothing in it looks at your screen. Any message's words can be selected and copied, and a theme from another app can dress the window.

## Sub-features

- `messages-activity` lists approvals, questions and inbox reports, then what each kitten has in progress, and counts what's waiting in the sidebar.
- `messages-threads` lists every thread you've written in, unread ones first, each with its channel, parent, latest reply and how many more.
- `messages-general` sends your words through the router. The cat's own answer is a plain message after yours, work it starts is a thread under your message, and words it sends on to a session are a reply there, also sent to #general.
- `messages-channel` shows a kitten's threads as parents with reply bars, bold when it's finished something you haven't seen and with a red count of what it's waiting on you for. Its box starts a new thread, which opens in the pane.
- `messages-thread` shows one thread in a pane beside the channel: its parent, how many replies, each reply, what it's waiting on, and a box that replies only into it, with "Also send to #channel" under it.
- `messages-shades` shows what you've asked the cat itself, each talk a thread, and its box goes through the router as #general's does, with the cat answering there.
- `messages-select` selects words in a message, which gives the window the keyboard without making Shades the active app, and ⌘C copies them as plain words.
- `messages-theme` dresses the window in a theme from T3 Code, Cursor, VS Code or iTerm2, picked from Theme at the bottom of the sidebar or dropped onto the window.

## How to get to it (user POV)

- Press ⌃⌘B, or choose Messages from the cat's menu.
- Click a row in the sidebar, such as Threads or a kitten's channel, to change what's showing.
- Click a thread's parent, its reply bar, or a "replied to a thread" line to open the thread beside the channel. ✕, or Esc in its box, closes it.
- Type in a box and press Return. Tick "Also send to #channel" first to show a reply in the channel too.
- Press in a message's words and drag, then ⌘C or right-click and Copy.
- Press **Theme** at the bottom of the sidebar and pick one, or drop a theme file onto the window.

## Driving it with the demo

Preconditions:

- A fresh demo. Messages starts at Activity, and Steve's "Rewrite the pricing copy" thread already has a reply also sent to his channel, "Keep the FAQ as it is for now.", which the demo puts in memory as it starts.

Journey: `journeys/messages.txt`, drawn in Opal Horizon.

- **Activity.** `channels`, `colors Cursor/Opal Horizon`. `channels.png` in `0-activity` shows Activity, with In progress for Shades, Steve Pawsniak, Pepper and Clawde, and the sidebar's Activity, Threads, Channels and Direct messages.
- **#general.** `channel general`, then `send I need help with my resume`, then `wait 4`. `[demo] started demo-1 ... You are Shades` is the router with 0 attachments, and `[demo] started demo-2 ... I need help with my resume / ---` is Steve's new session with only your words. `1-general` shows your message in #general, the parent of that thread. `thread resume` prints `thread demo-2` and `2-general-thread` shows it open beside #general, headed "Thread · #general · I need help with my resume", with "Also send to #general" under its box.
- **A kitten's channel.** `channel steve`. `3-channel` shows each of Steve's threads as a parent with its reply bar, such as "5 replies  Last reply …" under "Rewrite the pricing copy…" with Steve's and Clawde's cats and your square, Pepper's ask as the parent of a thread in Steve's channel, and "replied to a thread: Rewrite the pricing copy…" over "Keep the FAQ as it is for now."
- **New thread.** `send How did the interview prep go?`, then `wait 2`. `[demo] started demo-3 with 0 attachments: How did the interview prep go? / ---` is a new session for Steve with only your words. `4-new-thread` shows it open in the pane.
- **Reply.** `send Make the checkout button bigger too`, then `wait 2`. With a thread open, `send` goes into its box. `[demo] forwarded to demo-3 with 0 attachments: Make the checkout button bigger too / --- / Passed on` shows your words went into that thread and nothing else. `5-reply` shows "1 reply" under its parent and both your bubbles in the pane.
- **Also send.** `channel steve`, `thread pricing copy`, `also on`, `send Keep the testimonials as they are`, `wait 2`. `also Also send to #steve-pawsniak on` says the box was ticked, and `[demo] forwarded to demo-steve-copy ... Keep the testimonials as they are / --- / Passed on` is the same as any reply. `6-also-sent` shows it at the bottom of the thread and in the channel under "replied to a thread". `back` closes the pane, and `7-channel-again` shows the channel on its own with both replies also sent.
- **Threads.** `channel threads`. `8-threads` lists each thread you've written in, with its channel, parent, latest reply and "N more replies".
- **Waiting.** `approval command swift test`, then `channel activity`. `[demo] notified: Steve Pawsniak needs an approval`, and `9-activity` shows the approval under Waiting on you, with a red 1 on Activity and on #steve-pawsniak, which is bold.
- **Shades.** Journey `journeys/shades.txt`. `channel shades`, `send hello`, `wait 4`. `[demo] started demo-1 with 0 attachments: You are Shades` is the router, and `1-hello` shows "To me, without looking at your screen" over the box, your "hello" and the cat's "Hi. I'm a cat. What's up?" under it, and the demo's two earlier talks as threads above. `send I need help with my resume` carries on in `demo-1`, then `[demo] started demo-2 ... I need help with my resume / ---` is Steve's new session, and `2-resume` shows "I passed that to the kitten it's for." `3-everyone` is #general, with none of the cat's answers from its DM, and Steve's session as a thread under "I need help with my resume".
- **Select and copy.** Journey `journeys/select.txt`. `highlight the new grid` does what dragging over those words does, and prints `key=true front=<your app>`. `copy` says where ⌘C would go, without copying, so your pasteboard is left alone: `copy goes to nothing` before, then `copy goes to ChannelTextView with [the new grid] types=["NSStringPboardType"]`. `1-highlighted` shows the words picked out in Steve's reply, in the "pricing page" thread's pane.
- **Themes.** Journey `journeys/themes.txt`. `themes` prints what Theme offers, each app's themes under it, from made-up files the demo writes in a temporary folder. `colors Cursor/Opal Horizon` picks one from that list, and `colors <file>` is the same as dropping that file. `1-opal` shows the window dark, your bubbles in a violet tint and Steve's still in his own colour, and `themes` then marks Cursor and Opal Horizon. `colors T3 Code/Paper` gives a light window in `3-paper`. `colors Package.swift` changes nothing, and the cat says "That isn't a theme I can read." `colors shades` goes back to Shades' own.
- **Reopen.** Journey `journeys/reopen.txt`. It opens Steve's channel with the pricing copy thread beside it, hides Messages the way ⌃⌘B does, and opens it again. `1-reopened` is drawn straight away and shows the same channel and thread, with no note that it's reading.
- **Speed.** Journey `journeys/perf.txt`. `busy` adds hundreds of made-up threads, with threads of hundreds of messages, and `perf` times what you'd feel from inside the app: closing Messages and opening it again (`reopen`, whose `reading=false` and `rows=` say it showed the channel rather than a note that it's reading), switching to each place, opening a long thread in the pane beside its channel (`open-thread`), going from it to another (`switch-thread`) and closing it (`close-thread`), scrolling that long thread 40 points at a time, a message arriving, a refresh with nothing new, typing, resizing and changing theme. Each line is `perf <step> median=… p95=… max=…`, and switching lines say how many rows the place has and how many are views in the window (`rows=` and `inWindow=`). Run it with `swift run -c release`, since the app you install is a release build. The demo's T3 answers at once, so for how long real reads take, run `swift run shades --channels-check`, which reads your real T3 once, closes and opens again a second later, and prints only counts and milliseconds: `first words`, `reopened and shown` and `reopened and caught up`. `scroll <points>` moves the place that's showing the way scrolling would, up when it's negative, so pictures can show older rows coming in as you go up.
- **Canned pictures.** `swift run shades --demo --channels-image <folder>` draws every place and a thread in the pane from canned data, in light and dark, including a thread from #general that's waiting on you, Threads with an unread thread, and the narrowest window with a thread open.

## Gotchas

- `theme light|dark|system` is the system's appearance, and `colors` is Messages' theme. A theme picked in the demo isn't saved.
- `highlight` gives Messages the keyboard, as pressing in words does, so `windows` says `channels ... key=true` and `active=true` afterwards. The app in front stays yours.
- `channel` takes `activity`, `threads`, `general`, `shades` or the start of a kitten's name, such as `steve`, and closes any thread that's open. `thread` opens the newest thread the place shows, or with words, the newest whose parent has them, and prints its ID. `back` closes the pane, the same as its ✕. `also on|off` ticks "Also send to #channel" under an open thread's box.
- `messages` is the same as ⌃⌘B, so a second one closes the window. `channels` only opens it.
- The window is live, so a row under the real pointer can draw highlighted. That's where the mouse is, not a bug.
- `send` is the same as typing in a box and pressing Return: the open thread's, or the place's when no thread is open. It never takes the keyboard. The box beeps and sends nothing when there's nowhere to send, such as in a new thread before T3 has started it. Activity and Threads have no box.
- Messages reads the canned transcripts when it opens. Draw before `wait 1` and it can still say it's reading.
- The window opens where it was last left. Its frame in `windows` can be on another display.
