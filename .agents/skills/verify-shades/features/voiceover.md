# VoiceOver

What VoiceOver hears from the cat's windows, and what it can press: the bubble's words as they show, the cat, each kitten, and The Kitty Litter's sidebar.

## Sub-features

- `voiceover-says` asks VoiceOver to say each new thing the bubble shows, in the bubble's own words. Approvals and questions go at high priority. A streaming answer waits until it's whole, nothing is said while you talk, and an answer that comes back after an approval isn't said again.
- `voiceover-cat` names the cat Ask Shades. VoiceOver's press does what a click does, and its show menu opens the right-click menu.
- `voiceover-kittens` presses a kitten, which opens what it's on, or its channel, as a click does.
- `voiceover-sidebar` has each place in The Kitty Litter's sidebar as a radio button, selected when it's showing, and Do Not Disturb as a checkbox.

## How to get to it (user POV)

- Turn on VoiceOver with ⌘F5. Find the cat with the Window Chooser (VO-F2 twice), then VO-Space to press it, or VO-Shift-M for its menu.

## Driving it with the demo

Preconditions:

- A fresh demo.

Journey: `journeys/voiceover.txt`.

- **What it finds.** `voiceover [window]` prints each element VoiceOver can reach in the cat, the bubble, the kittens view, the sidebar or the pairing panel, with its role, label, value and help. `voiceover cat` prints `voiceover cat AXButton [Ask Shades] help=[...]`.
- **Pressing.** `voiceover press <label>` and `voiceover menu <label>` are VO-Space and VO-Shift-M on the first element whose label starts with that. `voiceover press Ask Shades` opens the Ask box, as `windows` then shows, with `front` still your app.
- **What it says.** Every announcement prints as `voiceover says: <words>`, or `voiceover says at once:` for high priority, with ` / ` for each new line.

## Gotchas

- Nothing here can hear VoiceOver itself. The demo shows what was asked of it, and a person or Accessibility Inspector has to check what it says.
- Don't `bubble Copy` to hear "Copied". It writes to your real pasteboard. `VoiceOverTests` checks it instead.
- The pairing panel needs the phone page on, which needs to listen on loopback. Where it can't, `VoiceOverTests` checks the picture's label.
