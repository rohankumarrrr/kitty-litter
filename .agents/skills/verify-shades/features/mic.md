# Mic

The mic at the right of the Ask box, and of the box in The Kitty Litter. Pressing it starts talking into that box, pressing it again sends what you said where typing it would, and it never looks at the screen.

## Sub-features

- `mic-ask` talks into the Ask box, plain, Fix or drop. What you say shows in the box as you say it, and finishing counts as pressing Return.
- `mic-messages` gives The Kitty Litter's box the keyboard, then talks into it, and what you said goes where the line over the box says.
- `mic-shows` lights the mic in the box's accent while it hears you. VoiceOver hears it as Speak, then Done speaking, and its help names the talk key.
- `mic-cancel` forgets what you said when the box closes, or on Esc, with nothing sent.

## How to get to it (user POV)

- Open the Ask box with ⌥Space or a click on the cat, or click into a box in The Kitty Litter, and press the mic.

## Driving it with the demo

Preconditions:

- A fresh demo.

Journey: `journeys/mic.txt`. The demo's voice hears "what's this button for" over about 2 seconds.

- **Ask box.** `ask` opens it and prints `[demo] looked at the screen`, the box's own look. `voiceover press Speak` starts listening, and `2-ask-listening` shows the words so far in the box and the mic lit. `voiceover press Done speaking` sends it, as `[demo] started demo-1 with 1 attachments`, the box's look, with no second `looked at the screen`.
- **Cancel.** The second `ask`, `voiceover press Speak`, then `esc` closes the box with nothing started.
- **The Kitty Litter.** `channels`, `channel general`, then `voiceover press Speak` gives the box the keyboard, as the `windows` line `channels ... key=true` shows, and `4-general-listening` shows the mic lit in the theme's accent. `voiceover press Done speaking` sends it as `[demo] started demo-2 with 0 attachments`.
- `front` stays `another app` throughout.

## Gotchas

- `voiceover press` prints the label after pressing, so pressing Speak prints `[Done speaking]`.
- The demo can't show the microphone itself. `FlowTests` counts that the mic opens once per press and closes with its box.
