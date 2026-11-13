# Shades verification map

The maintained list of what a person can do with The Kitty Litter, and how to prove each in demo mode. Read this before driving the app, then use the matching feature file. Launch, doctor and cleanup are in [../SKILL.md](../SKILL.md).

## Baseline

- Every journey starts a fresh demo with `--no-script`, so it begins from the same state: four threads, five kittens (Cali and Furbit not set up yet), Clawde with an inbox and no screen, and nothing waiting on you.
- The demo's screen is Safari showing a pricing page. `ask <question>` uses a screen with no picture, so it sends 0 attachments, and with whatever `select <text>` last set as the selected text.
- The demo router picks by words in the question (`reply(to:)` in `Sources/Shades/Demo/Demo.swift`): "resume" or "interview" goes to Steve Pawsniak, "Clawde" goes to Clawde, a question starting "Summarize" gets a summary of the demo's syllabus, "fix", "change", "build", "refactor" or "rewrite" goes to the frontier agent, "tighten" rewrites the selected text, "follow" or "what you" carries on in the first session, "hello" gets a greeting, "long" gets a long answer, and anything else gets an answer about the pricing page. Before the hand-off words, "where" gets an answer that points at the Start free trial button, at Safari's Share button just under the menu bar if the question says "share", or at something the screen doesn't have if it says "logo".

## Proof

- Capture the action and the state after it, as a picture before and a picture after.
- Check the `[demo]` lines for what was sent, alongside the pictures.
- Start every journey with `front`, and end it with `front` and `windows`. The last `front` must say `another app` unless the first one already said `The Kitty Litter`. `active=true` is expected while a box has the keyboard.
- Record the feature and journey with each picture.
- If a journey can't reach a state, report the command you ran and what was missing. Don't report a different path as the one you were asked to prove.

## Feature files

Each starts with a title and a paragraph on what a person sees, then four sections in this order: `Sub-features`, `How to get to it (user POV)`, `Driving it with the demo`, and `Gotchas`.

## Features

- [Ask](./ask.md) covers asking the cat, its answer, pointing at things, passing to a kitten and handing off.
- [Drop](./drop.md) covers dropping a PDF, picture or link onto the cat, and where it may go.
- [The Kitty Litter](./messages.md) covers Activity, Threads, #general, a kitten's channel, a thread in the pane beside it, Also send to #channel, the DM with the cat, search, formatting and links, selecting and copying, and themes.
- [Inbox](./inbox.md) covers a kitten's report arriving, its row in The Kitty Litter, replying to it and clearing it.
- [Approvals](./approvals.md) covers an agent asking to run something, and allowing it.
- [Phone](./phone.md) covers The Kitty Litter on your phone: turning it on, pairing, reading and answering from the page, and its theme.
- [Notifications](./notifications.md) covers the macOS notification for something new in Activity or a finished session, clicking or tapping it to open its thread, taking it back, and each channel's notifications on the Mac and the phone.
- [Do Not Disturb](./dnd.md) covers the switch, the cat asleep, every pop-up staying quiet, and catching up in Activity.
- [Kittens](./kittens.md) covers the view of every kitten and how each is doing.
- [Keyboard](./keyboard.md) covers reaching and pressing every button in Settings and The Kitty Litter with Tab and Space while Keyboard navigation is on, the ring on the one Tab is on, and none of it giving a window the keyboard.
- [Mic](./mic.md) covers talking into the Ask box or The Kitty Litter's box with its mic, with no look at the screen.
- [VoiceOver](./voiceover.md) covers what VoiceOver says as the bubble changes, and pressing the cat, a kitten and the sidebar with it.
- [Check Myself](./check-myself.md) covers the self-check from the cat's menu, and what it says when T3 doesn't answer in time.
- [Settings](./settings.md) covers every setting in one place, from the menu or The Kitty Litter: models, keys, notifications, each channel's, theme, font, text size, where Open goes, the phone and the privacy list.
