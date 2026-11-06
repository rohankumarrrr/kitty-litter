# Shades verification map

The maintained list of what a person can do with Shades, and how to prove each in demo mode. Read this before driving the app, then use the matching feature file. Launch, doctor and cleanup are in [../SKILL.md](../SKILL.md).

## Baseline

- Every journey starts a fresh demo with `--no-script`, so it begins from the same state: four threads, five kittens (Cali and Furbit not set up yet), Clawde with an inbox and no screen, and nothing waiting on you.
- The demo's screen is Safari showing a pricing page. `ask <question>` uses a screen with no picture, so it sends 0 attachments, and with whatever `select <text>` last set as the selected text.
- The demo router picks by words in the question (`reply(to:)` in `Sources/Shades/Demo/Demo.swift`): "resume" or "interview" goes to Steve Pawsniak, "Clawde" goes to Clawde, a question starting "Summarize" gets a summary of the demo's syllabus, "fix", "change", "build", "refactor" or "rewrite" goes to the frontier agent, "tighten" rewrites the selected text, "follow" or "what you" carries on in the first session, "hello" gets a greeting, "long" gets a long answer, and anything else gets an answer about the pricing page.

## Proof

- Capture the action and the state after it, as a picture before and a picture after.
- Check the `[demo]` lines for what was sent, alongside the pictures.
- End every journey with `windows`, and check `active=false`.
- Record the feature and journey with each picture.
- If a journey can't reach a state, report the command you ran and what was missing. Don't report a different path as the one you were asked to prove.

## Feature files

Each starts with a title and a paragraph on what a person sees, then four sections in this order: `Sub-features`, `How to get to it (user POV)`, `Driving it with the demo`, and `Gotchas`.

## Features

- [Ask](./ask.md) covers asking the cat, its answer, passing to a kitten and handing off.
- [Drop](./drop.md) covers dropping a PDF, picture or link onto the cat, and where it may go.
- [Messages](./messages.md) covers Needs you, Everyone and a kitten's DM.
- [Inbox](./inbox.md) covers a kitten's report arriving, the inbox and clearing a row.
- [Approvals](./approvals.md) covers an agent asking to run something, and allowing it.
- [Notifications](./notifications.md) covers the macOS notification for something new in Needs you, clicking it and taking it back.
- [Kittens](./kittens.md) covers the view of every kitten and how each is doing.
