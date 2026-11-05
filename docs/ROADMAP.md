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

A kitten for the system itself, a self-check, rollback, work lists and proposals from kittens now exist. A defined way of taking corrections is next.

## Next ideas

- **Pointing at things.** Ask "where do I change this?" and the cat runs to the button and sits on it. The agent returns screen coordinates, and the cat's perching does the rest. This also suits step-by-step homework hints, where it shows you the next step without doing it for you.
- **Kittens out on the desktop.** Shift-clicking Shades already shows every kitten and how it's doing. Next, each working kitten could walk around the screen as its own small cat. Click one to open its thread.
- **Your own data in context.** Bring in the connectors your agents already have. "Can I afford this?" on a checkout page checks your budget app, and a job posting goes to your resume project. The no-project agent already finds projects on its own, so much of the routing exists.
- **Drop onto the cat.** Drag a PDF, link or screenshot onto it to summarize it or turn it into an issue.
- **Local screen memory.** An opt-in, on-device history for "where did I see that article?", plus a summary at the end of the day. It's the riskiest for privacy, so it comes last and never leaves your Mac.
- **The cat's eyes as a tool.** Expose "see screen" and "cat say" as an MCP server, so any T3 agent can look at your screen or speak through the cat, and you can ask about your screen from inside T3.

## Smaller things

- Priorities on a kitten's work list, so something urgent can go first.
- Cancel something waiting on a list by asking.
- Ask "what's on everyone's plate?" and hear about every kitten at once.
- A screen block that follows a kitten instead of its folder. T3 can run Claude with `--settings` per provider instance, so a kitten's threads could share one wherever they work. Untested, because it needs a change to T3's settings.

- Answer an agent's question from the bubble. It shows the question and options now, and you answer in T3.
- A layered app icon made with Icon Composer, which needs Xcode 26, so it stays crisp in macOS's Tinted and Clear icon styles.
- Remember project nicknames, so the frontier agent can skip the search next time.
- Replace text in place after a rewrite, starting with apps that expose selected text well.
- Windows and Linux. Version one is macOS only because capture, the non-activating window and on-device speech are all native.
