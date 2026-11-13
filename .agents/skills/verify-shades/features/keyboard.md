# Keyboard

With Keyboard navigation on in System Settings › Keyboard, every button you can click in Settings and The Kitty Litter, and in the bubble once you've clicked into its words, can be reached with Tab and pressed with Space: every page's tab, menu row, segmented control, switch and box, Open settings folder and Done in Settings, the sidebar's Do Not Disturb, ⌘/ Shortcuts and Settings, Activity's Allow, Deny and answer buttons, a header's Notifications and Open in T3, the link bar's Open and Cancel, a box's Attach and mic, and "Also send to" under a kitten's thread. A pane's messages are one stop, as a list is on a Mac and as Slack's are: the arrow keys move between them, with a ring round the one you're on and its bar of icons showing, and Tab goes on into that message's buttons, or an approval's, before it leaves the pane. Space opens a thread's parent from there, and ⌘C copies what the message said. A message's words aren't stops of their own. The one Tab is on has a ring in Opal's violet, or inside it in white on the violet primary. Pressing any of them shows a fill a shade stronger than hovering. Tab only moves inside a window that already has the keyboard, so the bubble, the kittens view and the cat never take it, and a click leaves the keyboard where it was.

## Sub-features

- `keyboard-tab` moves through a window's buttons and boxes with Tab and Shift-Tab, and only while Keyboard navigation is on and the window already has the keyboard.
- `keyboard-list` makes a pane's messages, threads or approvals one stop for Tab, which the arrow keys move through, with Tab going into the one you're on. It keeps its place while you're away, and across a move to another place. Unlike the buttons, it's a stop with Keyboard navigation off too, as a Mac's lists are.
- `keyboard-space` presses the button Tab is on, or ticks the box, and Return never does.
- `keyboard-ring` draws the ring while the window has the keyboard, and takes it away when the window gives the keyboard up.
- `keyboard-box` keeps Tab for typing inside a box, and Ctrl-Tab leaves it.
- `keyboard-copied` puts Copy back however quickly it's pressed again.

## How to get to it (user POV)

- Turn on Keyboard navigation in System Settings › Keyboard.
- Open Settings, or click into The Kitty Litter, so it has the keyboard. Press Tab to move and Space to press.

## Driving it with the demo

Journey: `journeys/keyboard.txt`. `keyboard on` stands in for the system setting, which the demo leaves as it is. `tab`, `tab back`, `tab control` and `space` hand Tab, Shift-Tab, Ctrl-Tab or Space to whichever of the app's windows has the keyboard, the way the key arrives there, without posting anything to the system, and print `focus <window> <what has the keyboard> key= front=`, where `front=another app` means your app stayed in front.

- **Settings.** `settings messages`, then five Tabs go along the page tabs, Agents to Privacy, and the sixth prints `focus settings Font`. `1-font/settings.png` shows the ring round it. Tab goes on to Text size, a segmented control, whose arrow keys move along it. `setting Text size Large` picks as a click would and leaves the keyboard on Text size, so the next Tab is Open threads in, then the phone's switch, Open settings folder and `Done`. `tab back` comes back, and `2-done/settings.png` shows Done's ring inside it and Text size on Large. `space` on Done closes Settings, and `windows` shows `settings visible=false`. Space on a page's tab turns to it.
- **Activity.** After `approval`, `channels` and `key activity`, Tab goes through Do Not Disturb, ⌘/ Shortcuts, Settings, `MessageList`, which is the list on the approval, then Deny, Allow and Allow for this session. `3-allow/channels.png` shows the ring on Allow for this session, and `space` prints `[demo] acceptForSession: npm run build && npm test`.
- **A header.** `key 3` opens Shades, the first row under Kittens, with the keyboard, and the fourth Tab is `Notifications`, the bell in its toolbar, shown in `4-notifications/channels.png`.
- **Messages.** `key 4` opens Steve's channel, and the sixth Tab, after `1 in progress` and `Notifications`, is `MessageList`. `5-messages` shows the ring round the newest message, with its bar of icons. `arrow up` moves it to the one above, in `6-message-above`, and the next Tab lands on that message's `React`, in `7-its-buttons`. `tab control` there goes on to `Copy`, as Tab does, and the window keeps the keyboard.
- **Also send.** `thread reply pricing copy` presses Reply on that thread, which puts the keyboard in its box, and `draft Keep the FAQ` types. Tab types a tab there, so `tab control` leaves the box for `Attach a recent file`, then Tab goes to its mic, `Speak`, and `Also send to Steve Pawsniak`, where `space` ticks it, shown in `8-also-send/channels.png`. `tab back` comes back through the mic and Attach into the box.
- **The bubble.** Journey: `journeys/keyboard-bubble.txt`. After `ask` and `wait 4`, `words` clicks into the answer's words, which gives the bubble the keyboard, and prints `words key=true`. The first Tab is `focus bubble Copy` and the second `focus bubble Open in T3`, with its ring in `1-open-in-t3/bubble.png`. `space` prints `[demo] would open demo-1 in T3`. The journey never presses Copy, which would write to your real clipboard.
- **Off.** `keyboard off`, then `tab` skips every button and lands on a list or a box.
- Every `focus` line says `front=another app`, and `windows` never shows the bubble or kittens with `key=true`.

## Gotchas

- Space on any menu row opens its menu on the real desktop, where it waits for a click, so the demo refuses it and says to use `setting`. The journey presses Done and Allow instead, and never Open settings folder, which would open Finder on the real desktop.
- The list keeps the keyboard when you go to another place, as Slack's does. A toolbar's button doesn't, since the place's toolbar is made again, so after `key 4` from Notifications, Tab starts again from Do Not Disturb.
- Shift-Tab inside a box stays in it, as in any Mac text view of more than one line. Ctrl-Tab leaves.
- From macOS 27, a window's own Tab handling moves on only while it's the app's key window, as `NSApp.keyWindow` reports it. The demo's windows really are, so its `tab` lines press that path. A test's panel never reaches the screen, so a test that gives one the keyboard sets `Press.keyWindow` too, which `NSApp.keyWindow` then reports, as the bubble's panel in `PressWindowsTests` does.
- Opening The Kitty Litter while Settings has the keyboard can leave neither with it a second later, so the journey closes Settings first.
