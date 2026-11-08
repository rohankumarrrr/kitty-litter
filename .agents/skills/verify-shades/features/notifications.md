# Notifications

Each new approval, question or decision in Activity posts one macOS notification that says only who and what kind, such as "Steve Pawsniak needs an approval". Clicking it opens Messages on Activity, and answering takes it back.

## Sub-features

- `notify-new` posts one for each new thing waiting on you, and never for what was asked before the app started.
- `notify-click` opens Messages on Activity, from whichever place it was on.
- `notify-withdraw` takes a notification back once what it was about is answered, and starting takes back every one from before.
- `bubble-open` is the cat's own report when a session ends. Its **Open** shows the thread in Messages, and only a thread Messages doesn't follow says Open in T3. Activity's cards say **View thread** the same way.

## How to get to it (user POV)

- A notification comes by itself when an agent asks for something.
- Click it.

## Driving it with the demo

Preconditions:

- A fresh demo, with nothing waiting. Demo mode prints notifications instead of posting them, and `notification` stands in for clicking one.

Journey: `journeys/notifications.txt`.

- **Elsewhere.** `channels`, then `channel general`. `channels.png` in `0-elsewhere` shows #general selected.
- **New.** `approval command npm test`, `report decision` and `question`, with their waits. The output says `[demo] notified: Steve Pawsniak needs an approval`, `[demo] notified: Clawde needs a decision` and `[demo] notified: An agent has a question`, with nothing about the command, the report or the question.
- **Click.** `notification`, then `wait 2`. `channels.png` in `1-clicked` shows Activity selected, with a count of 3: the approval, the question and the decision.
- **Withdraw.** `allow`, then `wait 1`. The output says `[demo] took back 1 notification` before `[demo] accept: npm test`, and `channels.png` in `2-answered` has a count of 2.

- **Open.** Journey `journeys/open.txt`. `finish demo-tidy`, `wait 8`, then `buttons` prints `button Open`, and nothing about T3. `1-report/bubble.png` shows Steve's report with Open under it. `bubble Open` presses it and prints `pressed Open`, and `2-opened/channels.png` shows "Tidy up the pricing page" open beside #steve-pawsniak, with no bubble left. `approval command swift test` and `report decision` put cards in Activity, and `3-activity/channels.png` shows the approval with Deny, Allow, Allow for this session and View thread, and Clawde's decision with Reply, Done and Open in T3, since the demo has nothing for Messages to read in that thread.

## Gotchas

- A real notification needs the bundled app, so a demo never posts one, and `swift run` without `--demo` doesn't either.
- `report decision` takes about 6 seconds to be filed, the same as in the inbox journey.
- The question is from a thread no kitten owns, which is why it says "An agent".
- What's "already waiting" goes by when T3 says it was asked, not when it was listed, so it can't be shown with the demo's threads. `FlowTests` covers it, along with a restart and an answer that doesn't go through.
