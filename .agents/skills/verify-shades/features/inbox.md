# Inbox

A kitten with `inbox: true` keeps its reports in one place instead of a bubble each. One bubble keeps count, such as "1 decision", and the reports wait in Messages under Needs you, each with Reply or Ask, Open in T3 and Done.

## Sub-features

- `inbox-arrive` sorts a finished run's report into a row, and the bubble counts it.
- `inbox-open` shows the rows in Messages under Needs you, Shipped and Also.
- `inbox-reply` opens that row's thread on its own, and sends your own words there, marking that row and no other.
- `inbox-done` takes a row away without telling any agent.

## How to get to it (user POV)

- Click the inbox bubble's Open, press ⌃⌘M, or choose Messages from the cat's menu.
- Press a row's buttons.

## Driving it with the demo

Preconditions:

- A fresh demo, where the inbox is empty and Clawde is the kitten with an inbox.

Journey: `journeys/inbox.txt`.

- **Arrive.** `report decision`, then `wait 7`. `[demo] started demo-1 ... Below is the final report` is the sorting. `bubble.png` in `0-bubble` says "Inbox, 1 decision, Open".
- **Open.** `inbox`, then `wait 1`. `channels.png` in `1-open` shows Messages at Needs you, with "Ship the login fix?" from "Clawde · Fix login", and Reply, Done and Open in T3.
- **Reply.** `inbox reply`, then `wait 1`. `channels.png` in `2-reply` shows the "Fix login" thread on its own, with "‹ Clawde" and Open in T3 at the top and "In Fix login" over the box.
- **Send.** `send Go ahead`, then `wait 2`. `[demo] forwarded to demo-login with 0 attachments: Go ahead / --- / Passed on` shows only your words went to that thread. `channels.png` in `3-sent` shows "Go ahead" as your bubble, and Needs you has no count left.
- **Done.** `channel needs`, `inbox done`, then `wait 1`. `channels.png` in `4-done` shows Needs you with the row gone.

## Gotchas

- A finished run is read 5 seconds after it ends (`reportDelay`), and the demo takes 0.8 seconds more to read it. Draw any sooner and Needs you still says nothing needs you.
- `report` also takes `shipped`, `note` and `long`.
- `inbox reply` gives Messages' box the keyboard without bringing Shades to the front, the same as pressing Reply, so `active=true` shows until something else takes it. `front` still names your own app.
- The demo has no words for "Fix login", so its thread says its messages are in T3.
