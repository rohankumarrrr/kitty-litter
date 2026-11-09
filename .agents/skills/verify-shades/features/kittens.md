# Kittens

A view of every kitten and how each is doing: working, needs you, idle, or not set up yet.

## Sub-features

- `kittens-state` shows each kitten's state, with the ones taking work first.
- `kittens-open` opens whatever most needs looking at in T3 when you click a kitten.

## How to get to it (user POV)

- Shift-click the cat.
- Choose Kittens from the cat's menu.

## Driving it with the demo

Preconditions:

- A fresh demo.

Journey: `journeys/kittens.txt`.

- **Open.** `kittens`, then `wait 1`. `kittens.png` in `0-open` shows Steve Pawsniak working, Pepper and Clawde idle, and Cali and Furbit not set up yet.

## Gotchas

- Clicking a kitten has no demo command yet. In the demo, opening a thread prints `[demo] would open <thread> in T3`.
- The kittens move while the view is open, so two pictures of the same state can differ by a frame. With `--reduce-motion` they hold still, as they do with Reduce Motion on.
