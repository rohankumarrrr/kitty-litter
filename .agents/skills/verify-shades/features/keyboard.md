# Keyboard

With Keyboard navigation on in System Settings › Keyboard, every button you can click in Settings and The Kitty Litter can be reached with Tab and pressed with Space: Theme, Font, Done and Open the file in Settings, the sidebar's Do Not Disturb, Theme, ⌘/ Shortcuts and Settings, Activity's Allow, Deny and answer buttons, a header's Notifications and Open in T3, the link bar's Open and Cancel, and "Also send to #channel". The one Tab is on has a ring in the theme's accent, or inside it in its own ink when it's filled. Pressing any of them shows a fill a shade stronger than hovering. Tab only moves inside a window that already has the keyboard, so the bubble, the kittens view and the cat never take it, and a click leaves the keyboard where it was.

## Sub-features

- `keyboard-tab` moves through a window's buttons, boxes and selectable words with Tab and Shift-Tab, and only while Keyboard navigation is on and the window already has the keyboard.
- `keyboard-space` presses the button Tab is on, or ticks the box, and Return never does.
- `keyboard-ring` draws the ring while the window has the keyboard, and takes it away when the window gives the keyboard up.
- `keyboard-box` keeps Tab for typing inside a box, and Ctrl-Tab leaves it.
- `keyboard-copied` puts Copy back however quickly it's pressed again.

## How to get to it (user POV)

- Turn on Keyboard navigation in System Settings › Keyboard.
- Open Settings, or click into The Kitty Litter, so it has the keyboard. Press Tab to move and Space to press.

## Driving it with the demo

Journey: `journeys/keyboard.txt`. `keyboard on` stands in for the system setting, which the demo leaves as it is. `tab`, `tab back`, `tab control` and `space` hand Tab, Shift-Tab, Ctrl-Tab or Space to whichever of the app's windows has the keyboard, the way the key arrives there, without posting anything to the system, and print `focus <window> <what has the keyboard> key= front=`, where `front=another app` means your app stayed in front.

- **Settings.** `settings messages`, then `tab` prints `focus settings The Kitty Litter ▾`, which is Theme, and `1-theme/settings.png` shows the ring round it. Tab goes on to `SF Pro ▾` and `Done`, `tab back` comes back, and `2-done/settings.png` shows Done's ring inside it. `space` on Done closes Settings, and `windows` shows `settings visible=false`.
- **Activity.** After `approval`, `channels` and `key activity`, Tab goes through Do Not Disturb, Theme, ⌘/ Shortcuts, Settings, the approval's words, Deny and Allow. `3-allow/channels.png` shows the ring on Allow, and `space` prints `[demo] accept: npm run build && npm test`.
- **A header.** `channel general`, and the fifth Tab is `Notifications`, shown in `4-notifications/channels.png`.
- **Also send.** `channel steve`, `thread pricing copy`, `draft Keep the FAQ`. `tab back` from the window lands on `Also send to #steve-pawsniak`, the next goes into the box, `tab control` comes back out, and `space` ticks it, shown in `5-also-send/channels.png`.
- **Off.** `keyboard off`, then `tab` skips every button and lands on words or a box.
- Every `focus` line says `front=another app`, and `windows` never shows the bubble or kittens with `key=true`.

## Gotchas

- The system's own pop-ups, checkboxes and tabs in Settings follow the real setting, not `keyboard on`, so in the demo Tab skips them unless Keyboard navigation is really on.
- Space on Theme, Font or a channel's button opens its menu, which waits for a click, so the journey presses Done and Allow instead.
- Each message's words are a Tab stop, as selectable words are anywhere on macOS, so in a long channel Shift-Tab reaches the thread pane's controls sooner than Tab.
- Opening The Kitty Litter while Settings has the keyboard can leave neither with it a second later, so the journey closes Settings first.
