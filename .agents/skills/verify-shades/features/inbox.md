# Inbox

A kitten with `inbox: true` keeps its reports in one place instead of a bubble each. One bubble says whose and what about, such as "Clawde needs a decision on “Fix login”.", and the reports wait in The Kitty Litter in Activity, each with Reply or Ask, Open in T3 and Done.

## Sub-features

- `inbox-arrive` sorts a finished run's report into a row, and the bubble counts it.
- `inbox-open` shows the rows in The Kitty Litter's Activity under Waiting on you, Shipped and Also.
- `inbox-reply` opens that row's thread beside its channel, and sends your own words there, marking that row and no other.
- `inbox-done` takes a row away without telling any agent.
- `inbox-asks` files what a kitten without an inbox needs you to do, and leaves the rest of its report to the bubble.
- `inbox-scheduled` opens a report from a run a schedule started with the kitten's words in it, and takes your reply.
- `inbox-change` shows a settings change a kitten asked for as a card with Shades' look at it, and Allow and Deny.
- `inbox-ask` shows what a kitten asks your yes for, in the form or read from a decision in plain words, and sends only The Kitty Litter's note on Allow or Deny.

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
- **Send.** `send Go ahead`, then `wait 2`. `[demo] forwarded to demo-login with 0 attachments, to steer: Go ahead / --- / Passed on` shows only your words went to that thread. `channels.png` in `3-sent` shows "Go ahead" as your bubble in the pane, and Activity has no count left.
- **Done.** `channel activity`, `inbox done`, then `wait 1`. `channels.png` in `4-done` shows Activity with the row gone.
- **Scheduled.** `report scheduled`, `wait 7`, `inbox reply`, then `wait 1`. A schedule starts "Clawde: Morning check" and it files a decision. `channels.png` in `5-scheduled` shows #clawde with the "Morning check" thread in the pane beside it, Clawde's report, "Two packages have updates...", as its parent without the schedule's prompt, and "Replies in Morning check" over the box. Nobody else is in it.
- **Reply to it.** `send Go ahead`, then `wait 2`. `[demo] forwarded to demo-morning with 0 attachments, to steer: Go ahead` shows only your words went to that thread. `channels.png` in `6-scheduled-sent` shows "Go ahead" under the report in the pane.

Journey: `journeys/inbox-asks.txt`.

- **Asks.** `report asks`, then `wait 7`. Pepper, who has no inbox, finishes "Tidy the budget" with a report that asks you to run a command. `[demo] started ... Below is the final report` is the sorting, with no summary after it. The output has one `[demo] notified:` line for Pepper needing you, and none saying it finished. `bubble.png` in `0-bubble` shows "Pepper: Tidy the budget" over the demo's report, "Moved the pricing page...", as it was written, since it's short.
- **Open.** `inbox`, then `wait 1`. `channels.png` in `1-open` shows Activity with "Run git pull in your checkout yourself, since the sandbox can't." from "Pepper · Tidy the budget" under Waiting on you, and nothing under Shipped.

Journey: `journeys/inbox-change.txt`.

- **Asks.** `report change`, then `wait 8`. Clawde finishes "Fix the install" with two `shades-request` blocks. The output has the sorting, then two `[demo] started ... A kitten, one of the user's AI agents, asked for a change` lines, one look at each request, then two `[demo] notified: Clawde needs a decision` lines. The demo's home folder is a throwaway one in the temporary folder, made fresh each run, so nothing real is changed.
- **Cards.** `inbox`, then `wait 1`. `channels.png` in `0-cards` shows Activity with a count of 2. The first card, "Clawde · Fix the install", starts with **This widens what agents can do.** and two lines adding device tools to `permissions.allow`, then "Makes `~/.t3/worktrees/app/t3-demo/.claude/settings.local.json`:" over the new file with `+` on each line, "Clawde's reason: ...", "I looked into it. ..." in the reply's place, and Deny, Allow and Open in T3. Under it, the second card says "This widens what agents can do." and that it adds `Bash(swift build)` to `permissions.allow`, since Claude Code can't read the file while it has the comma, over a `-` and a `+` line for the comma.
- **Allow.** `card Allow`, then `wait 2`. It presses the first card's Allow. The output has `[demo] took back 1 notification` and `[demo] forwarded to demo-settings with 0 attachments, to queue: --- / The Kitty Litter wrote this, not the user`. `channels.png` in `1-allowed` shows only the comma's card left, with a count of 1, and the new file is in the demo's home folder.
- **Deny.** `card Deny`, then `wait 2`. The output has another forward to queue, saying they pressed Deny, and `channels.png` in `2-denied` shows no card left under Waiting on you. The comma is still in the demo's `shades/.claude/settings.json`.

Journey: `journeys/inbox-ask.txt`.

- **Asks.** `report ask`, `wait 8`, `report plain`, then `wait 8`. "Clawde: Invite the tester" finishes with a `shades-request` block holding an `ask`, and "Clawde: Tidy the docs" with a decision in plain words. The output has a look at the ask, `A kitten, one of the user's AI agents, asked for the user's yes`, and a reading of the decision, `A kitten, one of the user's AI agents, finished some work and needs something`, and a `[demo] notified:` line for each.
- **Cards.** `inbox`, then `wait 1`. `channels.png` in `0-cards` shows "Clawde · Tidy the docs" starting "**If you allow it, Clawde will:** Merge pull request #12 in the site's repo, which tidies the docs.", then "Its report said:" and the decision in quotes, "I looked into it. ..." in the reply's place, and Deny, Allow, Reply and Open in T3. Under it, "Clawde · Invite the tester" starts "**If you allow it, Clawde will:** Email the invite to tester@example.com.", then its reason in quotes and Shades' look, with Deny, Allow and Open in T3.
- **Allow.** `card Allow`, then `wait 2`. It presses the first card's Allow. The output has `[demo] forwarded to demo-docs with 0 attachments, to queue: --- / The Kitty Litter wrote this, not the user`, and `1-allowed` shows only the invite's card left.
- **Deny.** `card Deny`, then `wait 2`. The output has a forward to `demo-invite`, and `2-denied` shows "Nothing needs you."

## Gotchas

- A finished run is read 5 seconds after it ends (`reportDelay`), and the demo takes 0.8 seconds more to read it. Draw any sooner and Activity still says nothing needs you.
- `report` also takes `shipped`, `note`, `long`, `scheduled` and `asks`.
- `inbox reply` gives The Kitty Litter's box the keyboard without bringing the app to the front, the same as pressing Reply, so `active=true` shows until something else takes it. `front` still names your own app.
- The demo has no words for "Fix login", so its thread says its messages are in T3.
