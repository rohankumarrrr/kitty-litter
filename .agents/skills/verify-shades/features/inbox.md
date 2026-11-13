# Inbox

A kitten with `inbox: true` keeps its reports in one place instead of a bubble each. One bubble says whose and what about, such as "Clawde needs a decision on “Fix login”.", and the reports wait in The Kitty Litter in Activity, each with Reply or Ask, Open in T3 and Done.

## Sub-features

- `inbox-arrive` sorts a finished run's report into a row, and the bubble counts it.
- `inbox-open` shows the rows in The Kitty Litter's Activity under Waiting on you, Shipped and Also.
- `inbox-reply` opens that row's thread beside its channel, and sends your own words there, marking that row and no other.
- `inbox-done` takes a row away without telling any agent.
- `inbox-scheduled` opens a report from a run a schedule started with the kitten's words in it, and takes your reply.

## How to get to it (user POV)

- Click the inbox bubble's Open, press ⌃⌘B, or choose The Kitty Litter from the cat's menu.
- Press a row's buttons.

## Driving it with the demo

Preconditions:

- A fresh demo, where the inbox is empty and Clawde is the kitten with an inbox.

Journey: `journeys/inbox.txt`.

- **Arrive.** `report decision`, then `wait 7`. `[demo] started demo-1 ... Below is the final report` is the sorting. `bubble.png` in `0-bubble` says "The Kitty Litter" over "Clawde needs a decision on “Fix login”.", with Open drawn as a button, the same as Open after a hand-off.
- **Open.** `inbox`, then `wait 1`. `channels.png` in `1-open` shows The Kitty Litter at Activity, with "Ship the login fix?" from "Clawde · Fix login", and Reply, Done and Open in T3.
- **Reply.** `inbox reply`, then `wait 1`. `channels.png` in `2-reply` shows the "Fix login" thread in the pane beside #clawde, with Open in T3 and ✕ at the top and "Replies in Fix login" over the box.
- **Send.** `send Go ahead`, then `wait 2`. `[demo] forwarded to demo-login with 0 attachments: Go ahead / --- / Passed on` shows only your words went to that thread. `channels.png` in `3-sent` shows "Go ahead" as your bubble in the pane, and Activity has no count left.
- **Done.** `channel activity`, `inbox done`, then `wait 1`. `channels.png` in `4-done` shows Activity with the row gone.
- **Scheduled.** `report scheduled`, `wait 7`, `inbox reply`, then `wait 1`. A schedule starts "Clawde: Morning check" and it files a decision. `channels.png` in `5-scheduled` shows #clawde with the "Morning check" thread in the pane beside it, Clawde's report, "Two packages have updates...", as its parent without the schedule's prompt, and "Replies in Morning check" over the box. Nobody else is in it.
- **Reply to it.** `send Go ahead`, then `wait 2`. `[demo] forwarded to demo-morning with 0 attachments: Go ahead` shows only your words went to that thread. `channels.png` in `6-scheduled-sent` shows "Go ahead" under the report in the pane.

## Gotchas

- A finished run is read 5 seconds after it ends (`reportDelay`), and the demo takes 0.8 seconds more to read it. Draw any sooner and Activity still says nothing needs you.
- `report` also takes `shipped`, `note`, `long` and `scheduled`.
- `inbox reply` gives The Kitty Litter's box the keyboard without bringing the app to the front, the same as pressing Reply, so `active=true` shows until something else takes it. `front` still names your own app.
- The demo has no words for "Fix login", so its thread says its messages are in T3.
