# Inbox

A kitten with `inbox: true` keeps its reports in one place instead of a bubble each. One bubble keeps count, such as "1 decision", and the inbox shows each row with Reply, Open in T3 and Done.

## Sub-features

- `inbox-arrive` sorts a finished run's report into a row, and the bubble counts it.
- `inbox-open` shows the rows under Needs you, Shipped and Also.
- `inbox-done` takes a row away without telling any agent.
- `inbox-reply` sends your own words to that row's thread.

## How to get to it (user POV)

- Click the inbox bubble, or choose Inbox from the cat's menu.
- Press a row's buttons.

## Driving it with the demo

Preconditions:

- A fresh demo, where the inbox is empty and Clawde is the kitten with an inbox.

Journey: `journeys/inbox.txt`.

- **Arrive.** `report decision`, then `wait 7`. `[demo] started demo-1 ... Below is the final report` is the sorting. `bubble.png` in `0-bubble` says "Inbox, 1 decision, Open".
- **Open.** `inbox`, then `wait 1`. `inbox.png` in `1-open` shows "Ship the login fix?" under Needs you, from "Clawde: Fix login", with Reply, Open in T3 and Done.
- **Done.** `inbox done`, then `wait 1`. `inbox.png` in `2-done` says "All clear. Nothing shipped or waiting on you."
- **Reply.** `inbox reply` opens the text box for the first row, and `submit <words>` on the next line sends them. This step isn't in the journey.

## Gotchas

- A finished run is read 5 seconds after it ends (`reportDelay`), and the demo takes 0.8 seconds more to read it. Draw any sooner and the inbox still says all clear.
- `report` also takes `shipped`, `note` and `long`.
- `inbox reply` opens the Ask box, which takes the keyboard without activating Shades until it closes, so keep `submit` on the very next line.
