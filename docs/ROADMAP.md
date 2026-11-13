# Roadmap

The Kitty Litter starts small on purpose. Version one is four things done well: ask about your screen, fix what you're looking at, talk and dictate, and keep an eye on your agents. These are the ideas saved for later.

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
- **An inbox for everyone.** The inbox started with the kitten that looks after the system, and it works for any kitten that sets `inbox: true`. Next, make it the default for every kitten, and show a kitten's proposals as decision rows, so everything waiting on you is in one place. A digest of several finishes would do the same job, so it should become part of Activity in The Kitty Litter rather than sit beside it.
- **Threads that wake themselves.** A kitten's thread picks up again by itself when its own pull request fails CI or gets a review comment, so a fix doesn't wait on you to notice.
- **Steer or queue from The Kitty Litter.** Enter steers a kitten that's still working, by joining the run it's on, and Option-Enter queues the next task behind it. Today a message always waits for its own run.
- **Kittens on a schedule.** A kitten that runs at a set time, such as a weekly check on something it looks after, and reports to The Kitty Litter.
- **A way to fix every error.** A permission error in the bubble now has **Open System Settings**. "I can't reach T3 Code" could open T3 the same way, and the Ask box's line about Screen Recording could take you to its page too.
- **The cat's eyes as a tool.** Expose "see screen" and "cat say" as an MCP server, so any T3 agent can look at your screen or speak through the cat, and you can ask about your screen from inside T3.

## Smaller things

- A check on where a thread can send. The router has no way to now, but the frontier agent and kittens that see your screen need T3's tools. A `PreToolUse` hook in their folders could turn away messages and launches aimed at a kitten that isn't meant to see your screen, or T3 could take a rule for it.
- A screen block that follows a kitten instead of its folder. T3 can run Claude with `--settings` per provider instance, so a kitten's threads could share one wherever they work. Untested, because it needs a change to T3's settings.

- Say on a thread's reply bar how many of its replies are new, so a bold channel shows which thread it's bold for. Today a channel's New line, like Slack's, only goes over threads none of which you've seen and replies also sent to it, and a thread with only new replies shows its line in its pane.
- Leave a problem out of the bubble when The Kitty Litter already shows it under what you sent. A reply from Activity puts its report back but doesn't say why there yet, so for now the bubble says it too, and stays until you press Esc or click in another app.
- Show each private app in Settings by its name and icon rather than as a bundle ID you type. Today the box shows the whole list, but as bundle IDs.
- Answer an agent's question from the bubble. It shows the question and options now, and you answer in The Kitty Litter or T3.
- Fold a busy conversation in The Kitty Litter down to one row per thread, with how many replies it has and the latest, the way a Slack channel shows a thread. Today every thread's messages are shown in order, and its title and project mark where each one starts.
- Set a channel's notifications from the phone, and see which channels are muted in The Kitty Litter's sidebar. Both are set from the channel's header on the Mac now, and only its header says it's muted.
- Read a thread's whole history in The Kitty Litter when it opens on its own, even past each kitten's newest 30, instead of saying the rest is in T3.
- Show a reply's earlier notes in place, under the reply when you press "2 earlier notes". Today pressing it opens the thread in T3, since The Kitty Litter only keeps how many there were.
- Keep a question you asked Shades that only got passed on after a restart. Its talk with the router is archived, and T3 doesn't list archived threads, so The Kitty Litter would have to read it by the ID it kept.
- Send the phone only what changed in The Kitty Litter. It gets every row of the place it's on each time anything changes, about 170 KB for a conversation of 580 rows, and draws them all again, where the window only lays out what's near what you can see.
- Let the phone page's header and box scroll away at the largest text sizes. Both stay on screen, and at twice the usual size and Larger on the Mac they take most of a phone's height.
- Work out what The Kitty Litter shows off the main thread, or only for the threads that changed. It's about 12 ms each time anything changes with hundreds of threads, which is most of what's left when a message arrives.
- Stop The Kitty Litter's messages drawing again on every step of a scroll. Every message in sight, its words and its buttons redraw each step, in every build back to before Opal, though only where they've moved. Kept cards made it cheap again, but not drawing at all would make a long conversation scroll faster than it ever has.
- Draw the cat's bubble's card for less. It's drawn afresh at each new size, about 3 ms for a long answer and each time a streaming one grows, where its glow and body could be drawn at a lower resolution and stretched, since they're smooth.
- Find what Core Animation keeps after The Kitty Litter draws a long conversation. The app holds about 90 MB more than before Opal once a long thread has been scrolled, though its heap is the same, what's still on screen is only 11 MB more, and it comes down a little each time it closes. The sandbox an agent works in can't run `vmmap` or `footprint` on the demo to say which.
- Say why a picture of the phone page off screen takes about 23 ms where it took 3 before Opal. None of its glass, gradients, masks or shadows account for it, and a round trip to the page is unchanged.
- A light version of Opal Horizon, for Macs in light mode. The Kitty Litter is dark only today.
- A layered app icon made with Icon Composer, which needs Xcode 26, so it stays crisp in macOS's Tinted and Clear icon styles.
- Rename `Shades.app` itself, and its folder in Application Support and its Keychain items, to The Kitty Litter, once there's a way to prove macOS keeps its permissions and `install.sh`'s rollback handles the old name.
- Remember project nicknames, so the frontier agent can skip the search next time.
- Replace a rewrite in place in apps that only take paste, such as browsers, Slack and VS Code. Today the rewrite is copied there, since a paste can't be read back to prove it landed.
- Windows and Linux. Version one is macOS only because capture, the non-activating window and on-device speech are all native.
