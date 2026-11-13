# Kittens

A view of every kitten and how each is doing: working, needs you, idle, or not set up yet. It's Opal's floating glass over the cat, each kitten on a Rimlight tile in its own colour, its state in lilac, rose or mint beside a dot, and the kittens not set up yet under small capitals of their own.

## Sub-features

- `kittens-state` shows each kitten's state, with the ones taking work first.
- `kittens-open` opens whatever most needs looking at when you click a kitten, where Settings' Open threads in sends it, or the kitten's channel in The Kitty Litter if it hasn't done anything yet.

## How to get to it (user POV)

- Shift-click the cat.
- Choose Kittens from the cat's menu.

## Driving it with the demo

Preconditions:

- A fresh demo.

Journey: `journeys/kittens.txt`.

- **Open.** `kittens`, then `wait 1`. `kittens.png` in `0-open` shows KITTENS over Steve Pawsniak working in lilac, Pepper and Clawde idle in mint, then NOT SET UP YET over Cali and Furbit, faded.
- **Needs you.** `question demo-login` gives Clawde a question, and `esc` puts the bubble away. `1-needs-you/kittens.png` shows Clawde's Needs you in rose. `voiceover kittens` prints both labels and every kitten as an `AXButton`.
- **Open a kitten.** `voiceover press Pepper` presses Pepper, who has no thread, and `2-pepper/channels.png` shows #pepper in The Kitty Litter, with the kittens view gone.

## Gotchas

- `voiceover press <name>` presses a kitten, as VoiceOver does. A thread The Kitty Litter doesn't show, or any thread with Open threads in set to T3, prints `[demo] would open <thread> in T3`.
- A click anywhere on the real desktop closes the view, as it should, so a click while a journey runs can leave a picture without it.
- The kittens move while the view is open, so two pictures of the same state can differ by a frame. With `--reduce-motion` they hold still, as they do with Reduce Motion on.
