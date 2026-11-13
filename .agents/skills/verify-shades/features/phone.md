# Phone

With **The Kitty Litter on my phone** on in Settings, the cat shows a code and a picture of it. A phone that scans it, or types the code into the page, gets The Kitty Litter in its browser, laid out the way Slack's phone app is: the list of places, Activity, Threads, then each kitten's channel under Kittens, and each thread on a page of its own, with the same buttons as the window. Each kitten is the window's own pixel cat, from `/cat/<light|dark>/<pose>/<jacket>.png`.

## Sub-features

- `phone-pair` shows the one-time code, and a phone that sends it is paired.
- `phone-places` lists Activity and Threads, then under Kittens each kitten's channel by name, as the window's sidebar does, with the window's counts, bold and dots, each kitten's cat posed for what it's doing on a Rimlight tile in its own colour, and icons drawn to match the window's on tiles lit teal to pink. A kitten that's only planned isn't there. Shades stays on the Mac, unless you've shown some of its work here, when it's first under Kittens, as its own cat.
- `phone-opal` draws every page as Opal on an iPhone: pure black, white words at 100, 80 and 62%, a 32-point bold large title that the bar takes, small and on glass, once it's scrolled under, Activity's cards lit in their kitten's colour with Allow the one violet button, kittens' messages lit at the edge in their colour and yours filled, 24-point sheets, and the box on glass. `journeys/phone-states.txt` draws every state at each text size.
- `phone-switch` shows a thread of the cat's own work, such as a fix, under Shades on the phone once **Show on phone** is pressed at the top of its thread on the Mac, with only your words and the agent's replies, and takes it off again with **Hide from phone**.
- `phone-cats` draws the window's cats wherever a kitten or the cat appears: the places, a channel's and a thread's header, beside each message, in reply bars, in Threads, and on Activity's headings and cards.
- `phone-picture` draws your picture, if you've given The Kitty Litter one, beside your messages and in place of your square, from what a paired phone is sent rather than an address of its own. `journeys/picture.txt` drives it, as [messages.md](messages.md) says, and `swift test --filter PhoneServerTests/testYourPictureGoesOnlyToAPairedPhone` checks nothing unpaired gets it.
- `phone-answer` allows or denies an approval, answers a question from its card, and replies to a report.
- `phone-send` starts a new thread from a kitten's channel, which opens on its own page, and replies in a thread, with its Also send to its kitten. Shades has no box on the phone, since what you say to the cat stays on the Mac. The box is iMessage's: **+** for a photo or PDF, an arrow inside the field that's armed only once there's something to send, and Return making a new line. What you send says "Sending…" until T3 has it, and what never got there has Try again. `journeys/delivery.txt` ends with it, as [The Kitty Litter](./messages.md) describes under Delivery.
- `phone-notify` sends each new thing in Activity to a subscribed phone, encrypted for it, saying only who and what kind.
- `phone-formatting` draws a message's lists, tables, quotes, code blocks with Copy and pull request chips from what the Mac read, and tapping a link shows its whole address before Open. See `messages-formatting` in [messages.md](messages.md), whose journey covers both.
- `phone-select` holds back what's new while you're selecting words, on the page's Opal colours: a phone's black, with violet for what you press and lilac for links.
- `phone-size` follows the phone's own text size and the Mac's Text size on top of it, makes everything you tap at least 44 points, says each place's state to VoiceOver as the window's sidebar does, offers **React** to a keyboard, and draws a message on its way at 55% with words that still read.
- `phone-search` finds a message by its words from the magnifier in the bar of every page, over what The Kitty Litter has read and only what a phone can open, and tapping one opens its page and scrolls to it. While it's open, its field has the bar with **Cancel** beside it, and going anywhere, Back included, puts it away. See `messages-search` in [messages.md](messages.md), whose journey covers both.

## How to get to it (user POV)

- Turn on **The Kitty Litter on my phone, over Tailscale** on Settings' The Kitty Litter page. The code shows.
- Scan it with the phone's camera, or open the address and type the code.
- Tap a place, then use the box at the bottom or a card's buttons.

## Driving it with the demo

Preconditions:

- A fresh demo. Its page stays on loopback, on a free port, and never goes on your tailnet. `phone open` loads it at a phone's size in a web view off every screen, and `draw` adds it as `phone.png`.
- The phone's commands press the page's own buttons inside the page, so nothing reaches the desktop. `phone text` prints what the page shows.

Journey: `journeys/phone.txt`.

- **Pair.** `phone on`, `phone pair` and `draw`. The output says `[demo] phone page on http://127.0.0.1:<port>`, and `pairing.png` in `1-pairing` shows the code and its picture.
- **Places.** `phone open`, which opens the page with the code that's showing, as scanning its picture does. `phone.png` in `2-home` lists the places under the large title: a bell and two bubbles drawn like the window's on tiles lit teal and pink, then under Kittens each kitten by name as its pixel cat in its jacket on a tile lit in its colour, Steve Pawsniak running with a yellow dot, and Pepper and Clawde sitting with a red dot. Cali and Furbit, who are only planned, aren't there.
- **Approve.** `approval command ...`, `report decision`, `phone go activity`, then `phone press Allow`. `3-needs` shows the approval's card with Steve's cat, its eyes lit, and under In progress each kitten's cat as the window's rows draw it, with each issue's coloured dot. The output says `[demo] accept: npm run build && npm test` and `[demo] took back 1 notification`, and `4-allowed` shows only Clawde's decision left.
- **New thread.** `phone go steve` and `phone send ...`. `6-dm` is Steve's channel, with Steve's cat and "1 in progress" in its header, each thread's parent beside its cat, and its reply bar with small cats for who replied and your blue square. The output says `[demo] started demo-3` with your words, and `7-topic` shows them on the new thread's own page, with Steve's cat at the top and "Also send to Steve Pawsniak" under its box.

Journey: `journeys/phone-answers.txt`, in light mode.

- **Question.** `question`, which asks the font and then which pages, picking several. `phone press Press Start 2P`, `phone press Home` and `phone press Blog`, with `2-picked` showing all three picked and "Pick as many as you like." under the pages, then `phone press Send answer`. The output says `[demo] answered: Press Start 2P | home, blog`.
- **Reply.** `phone press Reply` on Clawde's decision, then `phone send Yes, ship it`. The output says `[demo] forwarded to demo-login` with your words, and `4-replied` shows them in that thread.

Journey: `journeys/phone-notifications.txt`.

- **Subscribe.** `phone open` and `draw`. `1-home` shows the page's note that an iPhone needs it on the Home Screen, since the web view, like Safari on an iPhone, has no push. `phone subscribe` stands in for **Turn on**: the page sends a stand-in phone's subscription with its own `/push` request, and the output says `[phone] subscribed: 204`.
- **Notify.** `approval command ...` and `question`. The output says `[demo] notified: Steve Pawsniak needs an approval`, then `[demo] pushed to web.push.apple.com: {"title":"Steve Pawsniak needs an approval","tag":"demo-1","key":"t:demo-tidy@c:%2Fdemo%2Fsteve"}`, which is what the stand-in phone opened from the encrypted push, with `"key"`, the thread's page a tap opens. The same follows for the question, and nothing says what was asked. Tapping one is in [Notifications](./notifications.md), under `journeys/notify-finished.txt`.

Journey: `journeys/phone-switch.txt`.

- **Off.** Two fixes, `submit Where could I find a keyboard like this?` and then `submit` with no words, print `[demo] started demo-1` and `[demo] started demo-2`. The first `phone text` is Activity, which calls the first one "Where could I find a keyboard like this?" rather than its "Fix: ..." title. `thread keyboard` opens `demo-1` beside Shades, and `1-off` shows **Show on phone** beside Open in T3. `phone go shades` gets the list of places, with no Shades in it.
- **On.** `header Show on phone` prints `pressed Show on phone`, and `2-on` shows the button saying **Hide from phone**. `phone go shades` now opens Shades, headed "Work you chose to show here", with only "Where could I find a keyboard like this?" and its reply bar, as `3-phone-dm` shows: none of the demo's talks, and not the second fix. `phone go t:demo-2@shades` gets the list of places, which now has Shades first under Kittens, as its own cat.
- **Thread.** `phone go t:demo-1@shades` is the thread's own page, headed "Shades" with no title, your words, the cat's "Done." and "Replies in this thread" over its box, in `4-phone-thread`. `phone send Is there a cheaper one?` prints `[demo] forwarded to demo-1 with 0 attachments: Is there a cheaper one?`.
- **Hide.** `header Hide from phone` sends the page back to the list of places, with no Shades in it, in `5-hidden`.

Journey: `journeys/phone-select.txt`.

- **Load older.** Journey `journeys/phone-older.txt`. `busy`, then `phone open pepper`, scrolled to the top, where the first row is "Load older messages". `phone js` runs a line of script on the page and prints what it comes to, here each row on the screen with how far down it is. After `phone press Load older messages`, the `after` line has a larger `scrollY`, with the lowest posts at the same heights as in `before`, since the older threads come in above them, and among them where one started between two you could see.
- **Colours.** `phone open steve`. `1-steve` shows the page on a phone's black, your bubbles on Opal's selected violet-black, each kitten's bubble black glass lit at its edge in its colour, the violet arrow in the box, and every cat drawn with the light outline the window uses on a dark page.
- **Selecting.** `phone select feels cramped` does what dragging over those words, in a parent on Steve's channel, does, and prints `[phone] selected [feels cramped]`. A new thread started from the window doesn't reach the page's `phone text` while they're selected, and does after `phone unselect`. The web view's pictures don't show a selection.

Journey: `journeys/phone-size.txt`, in light mode, then Opal.

- **Labels.** The first `phone js` prints what VoiceOver says for each place, such as `steve-pawsniak, Needs you, 1 waiting`, and `[dot]` where a dot shows. Steve has a count after `approval`, so no dot.
- **Reach.** Each `every target at least 44` line measures every button, link and box on the page, and names any smaller. A reaction's pill is drawn 32 pixels tall and takes taps 6 above and below it, which `elementFromPoint` shows in the `chip` line.
- **On its way.** After `Try again`, the `on its way` line is the contrast of the message's words on its bubble, counting the words' own opacity: `7.85:1, its words at 0.62 on its fill at opacity 1`, your bubble at 55% with secondary words, never the whole bubble see-through. `3-sending` shows it.
- **React.** `phone press React` opens the sheet of marks from the foot and puts the keyboard on 👍, the first of 6, and 🎉 then shows under the message in `4-reacted`.
- **Size.** Small makes the body 15.69px and leaves the box at 16px, so an iPhone doesn't zoom in on it, and Larger makes it 22.23px, from 17px. `7-opal-larger-thread` has Mark unread and Search in the bar over the title, as at every size. `phone js document.documentElement.style.fontSize = '130%'` stands in for the phone's own size, and everything grows from it.

End every journey with `front` and `windows`. The app in front stays whatever it was, and `active=false`.

## Gotchas

- Each place is a stream of its own, so moving between them reconnects. Give `phone go` and `phone send` two or three seconds before drawing.
- `header` presses a button at the top of the open thread's pane, by its words. It prints `no header button [...]` when there's none, such as **Show on phone** in a kitten's thread, or while The Kitty Litter isn't on your phone.
- `phone go` takes a key as it is, so `phone go t:demo-steve-copy@c:%2Fdemo%2Fsteve` opens Steve's "Rewrite the pricing copy" thread with its replies, and `t:demo-tidy@c:%2Fdemo%2Fsteve` opens the one an `approval` waits in.
- `phone text` doesn't show the cats, since they're pictures. `swift test --filter PhoneServerTests` checks their address gives the window's art pixel for pixel, and nothing for any other address.
- A `draw` just before the file runs out can miss the phone, whose picture comes back a moment later. End with a `wait 2`.
- The demo's web view is off every screen, so it never moves a CSS transition or animation on: a sheet that faded in would draw invisible. The page has no timed motion for that reason, and its bar and sheets change at once.
- `journeys/phone-states.txt` draws home, Activity waiting and quiet, Threads, a kitten's channel, a thread, a failed send and one on its way, formatting, the link sheet, Search, what it found and finding nothing, at Small, Default, Large and Larger, then the pairing page and a wrong code, into `.verify/shades/phone-states/<size>/`. It takes about five minutes.
- What goes wrong shows at the bottom of the page's header, so it's in the picture however far down the page is. `phone js attach([new File(['hi'], 'notes.txt', { type: 'text/plain' })]); 'attached'` makes "The Kitty Litter can only read photos and PDFs.", and `phone off` with the page open makes "Can't reach your Mac". `phone link <words>` opens the sheet over a dimmed page, and `phone js document.activeElement.id` then prints `linkcancel`.
- The demo phone never has the keyboard, since it's off every screen, so `:focus` never applies there and **React** stays out of sight even with `document.activeElement` on it. An iPhone's Text Size, its safe areas turned sideways, and `-apple-system-body` aren't in the demo either, since it's a Mac's web view.
- Pair before anything else happens. A `phone open` that comes a moment after another code shows gets the pairing page.
- Tailscale itself isn't in the demo. `swift test --filter PhoneServerTests` runs the server on a free port and checks pairing and what it turns away over HTTP, and checks the helper that takes the page off with a stand-in for the `tailscale` tool.
- Neither a real push service nor a real phone is in the demo. `swift test --filter WebPushTests` checks the encryption against RFC 8291's own example, and the signature as a push service checks it.
- `swift test --filter PressPhoneTests` presses every button, sheet and link on the page the way a finger does, at its centre and only if nothing is over it, and from a keyboard with Return, Space and Escape, against a stand-in Mac that answers through the same `PhoneView` and `PhoneAsk` the real one uses. Add a control there when you add one to the page.
