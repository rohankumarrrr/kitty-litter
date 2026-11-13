# Notifications

Each new approval, question or decision in Activity posts one macOS notification that says only who and what kind: who in its title, such as "Steve Pawsniak", and what in its body, such as "Needs an approval", grouped by thread in Notification Center. The demo prints them as one line, such as "Steve Pawsniak needs an approval". With **When a session finishes** on in Settings, a finished session posts one too, such as "Steve Pawsniak finished". Clicking one opens its thread beside where it lives in The Kitty Litter, and answering takes it back. Each channel's **Notifications**, in its header, says what it tells you on the Mac and on the phone, or mutes it.

## Sub-features

- `notify-new` posts one for each new thing waiting on you, and never for what was asked before the app started.
- `notify-click` opens the thread it's about beside its channel, from whichever place The Kitty Litter was on, or in T3 for a thread The Kitty Litter doesn't show.
- `notify-finished` posts one for each finished session once it's turned on, and never says what it said. An inbox kitten's run that ships and asks gets one notification, the decision.
- `notify-withdraw` takes a notification back once what it was about is answered, and starting takes back every one from before.
- `channel-notifications` is each channel's **Notifications**, in its header: Mute, and Everything, Only when it needs you or Nothing, on this Mac and on your phone. A muted channel's header says Muted.
- `bubble-open` is the cat's own report when a session ends. Its **Open** shows the thread in The Kitty Litter, and only a thread The Kitty Litter doesn't follow says Open in T3. Activity's cards say **View thread** the same way.

## How to get to it (user POV)

- A notification comes by itself when an agent asks for something, and once **When a session finishes** is on in Settings, when a session finishes.
- Click it.

## Driving it with the demo

Preconditions:

- A fresh demo, with nothing waiting. Demo mode prints notifications instead of posting them, and `notification [thread]` stands in for clicking one about that thread, `demo-tidy` if it's left out. `notify-finished on` stands in for ticking the box in Settings.

Journey: `journeys/notifications.txt`.

- **Elsewhere.** `channels`, then `channel shades`. `channels.png` in `0-elsewhere` shows Shades selected.
- **New.** `approval command npm test`, `report decision` and `question`, with their waits. The output says `[demo] notified: Steve Pawsniak needs an approval, which opens demo-tidy`, `[demo] notified: Clawde needs a decision, which opens demo-login` and `[demo] notified: An agent has a question, which opens demo-research`, with nothing about the command, the report or the question.
- **Click.** `notification`, then `wait 2`. It stands in for clicking a notification about `demo-tidy`, the approval's thread. `channels.png` in `1-clicked` shows "Tidy up the pricing page" open beside Steve Pawsniak with the approval's Deny and Allow in it, and Activity's count of 3 in the sidebar: the approval, the question and the decision.
- **Withdraw.** `allow`, then `wait 1`. The output says `[demo] took back 1 notification` before `[demo] accept: npm test`, and `channels.png` in `2-answered` has a count of 2.

Journey: `journeys/notify-finished.txt`, which also covers the phone.

- **Off.** `finish demo-research` before `notify-finished on`. The output has the cat's report and no `[demo] notified`.
- **On.** `notify-finished on`, then `finish demo-tidy`. The output says `[demo] notified: Steve Pawsniak finished, which opens demo-tidy`, then `[demo] pushed to web.push.apple.com: {"title":"Steve Pawsniak finished","tag":"demo-tidy","key":"t:demo-tidy@c:%2Fdemo%2Fsteve"}`, with nothing from the report. `report shipped` says `[demo] notified: Clawde finished, which opens demo-icon`.
- **Click.** `notification demo-tidy` from Shades. `1-clicked/channels.png` shows "Tidy up the pricing page" open beside Steve Pawsniak.
- **Tap.** `phone open t:demo-tidy@c:%2Fdemo%2Fsteve` opens the page the push names, as tapping it does. `phone text` and `2-tapped` show the thread's own page, with Steve at the top and its conversation.
- **Settings.** `settings`, `settings notifications`, then `draw`. `3-settings/settings.png` shows Settings' Notifications page with When a session finishes switched on, since `notify-finished on` turned it on, and each channel with what it tells you.

Journey: `journeys/channel-notifications.txt`. `notifications <channel> [mute | mac <level> | phone <level>]` stands in for picking from a channel's Notifications menu, and prints the menu after, with `*` beside what's ticked. The channel is named as `channel` names it, and a level is `everything`, `needsYou` or `nothing`.

- **Menu.** `notifications clawde` prints Mute, then On this Mac and On your phone, each with `* Everything`. After `mac needsYou` and `phone nothing`, those two are ticked instead.
- **Needs you only.** `report shipped` gives no `[demo] notified` and no `[demo] pushed`, though `notify-finished on` would otherwise notify it. `report decision` says `[demo] notified: Clawde needs a decision, which opens demo-login`, with no `[demo] pushed`, since the phone is set to Nothing.
- **Muted.** `notifications steve mute` ticks Mute. `0-muted/channels.png` shows Steve Pawsniak with Muted at the top right beside "1 in progress". `finish demo-tidy` and `approval command npm test` give no `[demo] notified` and no `[demo] pushed`, and `windows` has the bubble not showing. `1-quiet/channels.png` still says Muted, with the approval as Needs you on Steve's thread and a count of 1 beside his channel.
- **Unmuted.** `notifications steve mute` again brings back Everything on both, and `2-unmuted/channels.png` says Notifications at the top right.

- **Open.** Journey `journeys/open.txt`. `finish demo-tidy`, `wait 8`, then `buttons` prints `button Open`, and nothing about T3. `1-report/bubble.png` shows Steve's report with Open under it. `bubble Open` presses it and prints `pressed Open`, and `2-opened/channels.png` shows "Tidy up the pricing page" open beside Steve Pawsniak, with no bubble left. `approval command swift test` and `report decision` put cards in Activity, and `3-activity/channels.png` shows the approval with Deny, Allow, Allow for this session and View thread, and Clawde's decision with Reply, Done and Open in T3, since the demo has nothing for The Kitty Litter to read in that thread.

## Gotchas

- A real notification needs the bundled app, so a demo never posts one, and `swift run` without `--demo` doesn't either. `testANotificationSaysWhoInItsTitleAndWhatInItsBody` in `PanelsTests` checks its title, body and thread.
- `report decision` takes about 6 seconds to be filed, the same as in the inbox journey.
- The question is from a thread no kitten owns, which is why it says "An agent".
- What's "already waiting" goes by when T3 says it was asked, not when it was listed, so it can't be shown with the demo's threads. `FlowTests` covers it, along with a restart and an answer that doesn't go through.
