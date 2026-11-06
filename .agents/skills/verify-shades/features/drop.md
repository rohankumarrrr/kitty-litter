# Drop

You drag a PDF, a picture or a link onto the cat. The Ask box opens, saying what it's looking at. You ask about it, or press Return for a summary, and it goes through the router like any question, with only what you dropped and no look at your screen. A kitten that doesn't see your screen can't take it, and the cat says so.

## Sub-features

- `drop-ask` opens the Ask box with "Looking at <name>" and "Ask about it, or just press Return".
- `drop-summary` sends "Summarize this." when you press Return with nothing typed.
- `drop-refused` says "<kitten> can't take files" when the router picks a kitten that doesn't see your screen, and sends it nothing.
- `drop-link` takes a web link, which goes where your screen may, the same as a file.
- `drop-unreadable` says "I can only read PDFs, pictures and links." for anything else, a `mailto:` link included.

## How to get to it (user POV)

- Drag a file from Finder, a picture or a link from a browser, or the thumbnail after a screenshot, and let go over the cat.

## Driving it with the demo

Preconditions:

- A fresh demo, with no bubble showing.

Journey: `journeys/drop.txt`. `drop` hands the cat a pasteboard the same way a drag does, so it goes through the real reading of the file. `drop pdf` makes up a one-page syllabus to drop, `drop <path>` drops a file and `drop <link>` drops a link. Each prints `dropped <name>, taken: true`.

- **Ask box.** `drop pdf`, then `wait 1`. `input.png` in `1-ask-box` says "Looking at syllabus.pdf" under "Ask about it, or just press Return", and `windows` shows `input ... key=true`.
- **Summary.** `submit` with nothing, then `wait 4`. `[demo] started demo-1 with 0 attachments` is the router, and `bubble.png` in `2-summarized` has the syllabus summary with Open in T3 and Copy.
- **Refused.** `drop pdf`, `submit Clawde should keep this`, then `wait 3`. Only `[demo] carried on in demo-1` is sent, and `bubble.png` in `3-cant-take-files` says "Clawde can't take files. Put a link or the text in your message instead."
- **Link to a kitten.** `esc` puts the last bubble away. `drop https://jobs.example.com/listing/123`, then `wait 1`. `input.png` in `4-link` says "Looking at jobs.example.com". `submit I need help with my resume for this`, then `wait 3`. `[demo] started demo-2 ... I need help with my resume for this / --- / Shades, the user's desktop cat, gave you this` is Steve's thread, and `bubble.png` in `5-to-a-kitten` says "Steve Pawsniak has this."
- **Unreadable.** `drop /nowhere/notes.zip`, then `wait 1`. `bubble.png` in `6-cant-read` says "I can only read PDFs, pictures and links." After `esc`, `drop mailto:someone@example.com` prints `taken: false`, and `bubble.png` in `7-cant-read-link` says the same.

## Gotchas

- The `[demo]` lines cut a prompt short, so they don't show the `<screen>` block with the file. `FlowTests` checks what's in it.
- The demo can't drag anything, so a real drag reaching the cat's window is only tried by a person. The cat's window lets the pointer through except over the cat's own pixels, and a drag has to be over those too.
- The demo router's summary is canned, so it describes the syllabus whatever you drop.
- The last `windows` says `active=true`. The same steps with `ask` in place of `drop` end that way too, and so does plain Ask on main after its box has opened more than once, so it's the Ask box and not the drop. Each step on its own, such as `drop pdf` then `submit`, ends with `active=false`.
