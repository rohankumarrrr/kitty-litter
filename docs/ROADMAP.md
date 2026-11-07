# Roadmap

Shades starts small on purpose. Version one is four things done well: ask about your screen, fix what you're looking at, talk and dictate, and keep an eye on your agents. These are the ideas saved for later.

## Where this is heading

Shades as a conductor with a kitten for each area of your life or work. Shades decides what goes where and reports back, and each kitten owns its work from start to finish.

- **Kittens.** Each one is a short charter, kept on your Mac: what it covers, which repos and connectors it uses, how it ships, and what done means. Each task gets a fresh thread, and the router sends follow-ups to it.
- **Review before reporting.** A kitten passes its change to a reviewer with fresh context that has to actually run it, and they go back and forth a few times at most. Then Shades tells you what's been done, and what's still open.
- **"Ship it."** Your own words go to that kitten, which merges, watches CI and the PR, and checks production where it can.
- **Working together.** Something like a trip touches several kittens. Shades asks each one and combines the answers, so they don't need to talk among themselves and private data stays where it belongs.
- **The right model for the job.** Shades and its kittens use Opus for judgment, and something cheaper and faster for simple tasks.

Kittens themselves now exist, as described in [kittens.md](kittens.md). Review, shipping and working across several kittens are the parts still being proven, one kitten end to end before any others.

Your own data in context exists too, through kittens, the router and a kitten's `project`, and so does dropping a file onto the cat.

A kitten for the system itself, a self-check, rollback, a window for reading what kittens say and a defined way of taking corrections now exist. Work lists and proposals from kittens are next.

## Next ideas

- **Step-by-step hints.** The cat can already point at what you ask about. For homework, it could point at the next step each time you ask, without doing it for you.
- **Kittens out on the desktop.** Shift-clicking Shades already shows every kitten and how it's doing. Next, each working kitten could walk around the screen as its own small cat. Click one to open its thread.
- **Local screen memory.** An opt-in, on-device history for "where did I see that article?", plus a summary at the end of the day. It's the riskiest for privacy, so it comes last and never leaves your Mac.
- **An inbox for everyone.** The inbox started with the kitten that looks after the system, and it works for any kitten that sets `inbox: true`. Next, make it the default for every kitten, and show a kitten's proposals as decision rows, so everything waiting on you is in one place. A digest of several finishes would do the same job, so it should become part of Activity in Messages rather than sit beside it.
- **Threads that wake themselves.** A kitten's thread picks up again by itself when its own pull request fails CI or gets a review comment, so a fix doesn't wait on you to notice.
- **Steer or queue from Messages.** Enter steers a kitten that's still working, by joining the run it's on, and Option-Enter queues the next task behind it. Today a message always waits for its own run.
- **Kittens on a schedule.** A kitten that runs at a set time, such as a weekly check on something it looks after, and reports to Messages.
- **The cat's eyes as a tool.** Expose "see screen" and "cat say" as an MCP server, so any T3 agent can look at your screen or speak through the cat, and you can ask about your screen from inside T3.

## Smaller things

- A check on where a thread can send. The router has no way to now, but the frontier agent and kittens that see your screen need T3's tools. A `PreToolUse` hook in their folders could turn away messages and launches aimed at a kitten that isn't meant to see your screen, or T3 could take a rule for it.
- A screen block that follows a kitten instead of its folder. T3 can run Claude with `--settings` per provider instance, so a kitten's threads could share one wherever they work. Untested, because it needs a change to T3's settings.

- Answer an agent's question from the bubble. It shows the question and options now, and you answer in Messages or T3.
- Fold a busy conversation in Messages down to one row per thread, with how many replies it has and the latest, the way a Slack channel shows a thread. Today every thread's messages are shown in order, and its title and project mark where each one starts.
- Read a thread's whole history in Messages when it opens on its own, even past each kitten's newest 30, instead of saying the rest is in T3.
- Send the phone only what changed in Messages. It gets every row of the place it's on each time anything changes, about 170 KB for a conversation of 580 rows, and draws them all again, where the window only lays out what's near what you can see.
- Work out what Messages shows off the main thread, or only for the threads that changed. It's about 12 ms each time anything changes with hundreds of threads, which is most of what's left when a message arrives.
- A theme for the rest of the cat. Only Messages and its phone page take one now, so the bubble, the Ask box and the kitten view keep Shades' own colours, and a phone that's already open takes a new theme the next time it opens the page.
- Several choices at once for a question that takes them, from Messages. It takes one choice or your own words for now.
- A layered app icon made with Icon Composer, which needs Xcode 26, so it stays crisp in macOS's Tinted and Clear icon styles.
- Remember project nicknames, so the frontier agent can skip the search next time.
- Replace a rewrite in place in apps that only take paste, such as browsers, Slack and VS Code. Today the rewrite is copied there, since a paste can't be read back to prove it landed.
- Windows and Linux. Version one is macOS only because capture, the non-activating window and on-device speech are all native.
