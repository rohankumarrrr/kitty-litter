# Do Not Disturb

While Do Not Disturb is on, nothing pops up by itself: no bubble for a report, a reply, a question, an approval or one of the cat's own lines, no macOS notification and no push to a phone. The cat curls up asleep, the menu item has a check, and the foot of The Kitty Litter's sidebar says "Do Not Disturb is on". Turning it off brings one bubble saying what came in, and its **Open** shows all of it at the top of Activity, in the order it came, each with its usual buttons.

## Sub-features

- `dnd-switch` turns it on and off from the cat's menu, the menu bar (the same menu) or the button at the foot of The Kitty Litter's sidebar. None of them makes The Kitty Litter the active app. It stays on through a restart.
- `dnd-asleep` is the cat curled up. Listening and thinking wake it, since that's you, and it curls up again a second after.
- `dnd-quiet` holds every pop-up that comes by itself. They all ask `mayPopUp` in `AppController+DoNotDisturb.swift` first, which keeps each one as an ID. What you start yourself, such as the Ask box, voice, Fix or a drop, answers as usual.
- `dnd-catch-up` is the one bubble when it's turned off, such as "While you were away: 2 replies, 1 approval, 1 question.", with **Open**. A click elsewhere doesn't lose it. Esc or Open does.
- `dnd-away` is "While you were away" at the top of Activity: a reply as its thread's latest message, an approval, question or report as its usual card, and a line from the cat as a note. Each shows there instead of again below. It goes once you've looked at Activity and closed The Kitty Litter.

## How to get to it (user POV)

- Right-click the cat, or click the menu bar item, and choose Do Not Disturb. Choose it again to turn it off.
- Or press Do Not Disturb at the bottom of The Kitty Litter's sidebar. It says "Do Not Disturb is on" while it is.

## Driving it with the demo

Preconditions:

- A fresh demo. Demo mode prints notifications instead of posting them, and doesn't save settings, so a restart can't be shown here. `DoNotDisturbTests` covers that.

Journey: `journeys/dnd.txt`.

- **On.** `notify-finished on`, as if Also when a session finishes were ticked in Settings, then `menuitems`, `menupress Do Not Disturb`, then `menuitems` again. The second list says `menu ✓ Do Not Disturb`, and `dnd` prints `dnd on cat=sleep away=1`, the one being the launch line in the first gotcha, or `away=0` without it. `0-on/cat.png` shows the cat curled up, with no `bubble.png` beside it.
- **Held.** `finish demo-tidy`, `approval command npm test`, `report decision` and `question`, with their waits. No `[demo] notified:` line comes, not even "Steve Pawsniak finished", and the only `[demo] started` line is Clawde's report being sorted for its inbox, with no summary for Steve's report. `dnd` prints `away=5`, and `windows` has `window bubble ... visible=false` and `state sleep`. `1-held/cat.png` is still asleep.
- **Switch in The Kitty Litter.** `channels`, then `channel general`. `2-switch/channels.png` shows "Do Not Disturb is on" above Shortcuts and Settings.
- **Off.** `sidebar Do Not Disturb is on`. `dnd` prints `dnd off cat=sit`, `menuitems` has no check, and `buttons` prints `button Open`. `3-catch-up/bubble.png` says "While you were away: 2 replies, 1 approval, 1 question, 1 note from me." with Open.
- **Open.** `bubble Open`. `4-activity/channels.png` shows Activity with "While you were away" first: the launch line as a note, Steve's thread with its latest reply, the approval with Deny, Allow and Allow for this session, Clawde's decision with Reply and Done, then the question with its choices, and no "Waiting on you" repeating them.

## Gotchas

- Your own copy of The Kitty Litter holds ⌃⌘B, so the demo says "Another app has ⌃⌘B" as it starts. A line the cat said by itself is put away when it's turned on, so that one's in the catch-up as a note. Without your copy running there's no such line, and the counts are one fewer.
- Opening Activity while it's still on shows what's come in so far, and closing The Kitty Litter after that counts as caught up.
- An approval held back waits in The Kitty Litter as if you'd pressed Esc. Clicking the cat still brings it up, since you're there.
- `report decision` takes about 6 seconds to be filed, the same as in the inbox journey.
