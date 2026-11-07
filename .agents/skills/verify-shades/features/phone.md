# Phone

With **Messages on my phone** on in Settings, the cat shows a code and a picture of it. A phone that scans it, or types the code into the page, gets Messages in its browser, laid out the way Slack's phone app is: the list of places, Activity, Threads, #general, each kitten's channel, and each thread on a page of its own, with the same buttons as the window.

## Sub-features

- `phone-pair` shows the one-time code, and a phone that sends it is paired.
- `phone-places` lists Activity and Threads, then #general and each kitten's channel, with the window's counts and bold. The cat's DM stays on the Mac.
- `phone-answer` allows or denies an approval, answers a question from its card, and replies to a report.
- `phone-send` sends in #general through the router, starts a new thread from a kitten's channel, which opens on its own page, and replies in a thread, with its Also send to #channel.
- `phone-notify` sends each new thing in Activity to a subscribed phone, encrypted for it, saying only who and what kind.
- `phone-theme` gives the page Messages' theme, and holds back what's new while you're selecting words.

## How to get to it (user POV)

- Turn on **Messages on my phone, over Tailscale** in Settings and press Save. The code shows.
- Scan it with the phone's camera, or open the address and type the code.
- Tap a place, then use the box at the bottom or a card's buttons.

## Driving it with the demo

Preconditions:

- A fresh demo. Its page stays on loopback, on a free port, and never goes on your tailnet. `phone open` loads it at a phone's size in a web view off every screen, and `draw` adds it as `phone.png`.
- The phone's commands press the page's own buttons inside the page, so nothing reaches the desktop. `phone text` prints what the page shows.

Journey: `journeys/phone.txt`.

- **Pair.** `phone on`, `phone pair` and `draw`. The output says `[demo] phone page on http://127.0.0.1:<port>`, and `pairing.png` in `1-pairing` shows the code and its picture.
- **Places.** `phone open`, which opens the page with the code that's showing, as scanning its picture does. `phone.png` in `2-home` lists the places, each kitten in its colour.
- **Approve.** `approval command ...`, `report decision`, `phone go activity`, then `phone press Allow`. The output says `[demo] accept: npm run build && npm test` and `[demo] took back 1 notification`, and `4-allowed` shows only Clawde's decision left.
- **#general.** `phone go general` and `phone send Hello from my phone`. The output says `[demo] started demo-3`, the router's turn, and `phone text` ends with Shades' answer.
- **New thread.** `phone go steve` and `phone send ...`. `6-dm` is Steve's channel, each thread's parent with its reply bar. The output says `[demo] started demo-4` with your words, and `7-topic` shows them on the new thread's own page, with "Also send to #steve-pawsniak" under its box.

Journey: `journeys/phone-answers.txt`, in light mode.

- **Question.** `question`, then `phone press Press Start 2P`, `2-picked` showing it picked, and `phone press Send answer`. The output says `[demo] answered: Press Start 2P`.
- **Reply.** `phone press Reply` on Clawde's decision, then `phone send Yes, ship it`. The output says `[demo] forwarded to demo-login` with your words, and `4-replied` shows them in that thread.

Journey: `journeys/phone-notifications.txt`.

- **Subscribe.** `phone open` and `draw`. `1-home` shows the page's note that an iPhone needs it on the Home Screen, since the web view, like Safari on an iPhone, has no push. `phone subscribe` stands in for **Turn on**: the page sends a stand-in phone's subscription with its own `/push` request, and the output says `[phone] subscribed: 204`.
- **Notify.** `approval command ...` and `question`. The output says `[demo] notified: Steve Pawsniak needs an approval`, then `[demo] pushed to web.push.apple.com: {"title":"Steve Pawsniak needs an approval","tag":"demo-1"}`, which is what the stand-in phone opened from the encrypted push. The same follows for the question, and nothing says what was asked.

Journey: `journeys/phone-theme.txt`.

- **Theme.** `colors Cursor/Opal Horizon` before `phone on`, then `phone open steve`. `1-opal` shows the page dark, your bubbles in the violet tint, a violet Send button, and Steve's still his own colour.
- **Selecting.** `phone select feels cramped` does what dragging over those words, in a parent on Steve's channel, does, and prints `[phone] selected [feels cramped]`. A new thread started from the window doesn't reach the page's `phone text` while they're selected, and does after `phone unselect`. The web view's pictures don't show a selection.

End every journey with `front` and `windows`. The app in front stays whatever it was, and `active=false`.

## Gotchas

- Each place is a stream of its own, so moving between them reconnects. Give `phone go` and `phone send` two or three seconds before drawing.
- Tailscale itself isn't in the demo. `swift test --filter PhoneServerTests` runs the server on a free port and checks pairing and what it turns away over HTTP, and checks the helper that takes the page off with a stand-in for the `tailscale` tool.
- Neither a real push service nor a real phone is in the demo. `swift test --filter WebPushTests` checks the encryption against RFC 8291's own example, and the signature as a push service checks it.
