# Shades

A desktop cat for macOS. It sees your screen when you ask, answers quick questions, hands real work to agents running in [T3 Code](https://t3.codes), and shows you what those agents are doing. It also does hold-to-talk and dictation on your Mac.

## Layout

- `Sources/ShadesCore`: shared types, the contracts between modules, the prompts and settings. No UI and no system capture.
- `Sources/ShadesT3`: the T3 Code client, behind `AgentBackend`.
- `Sources/ShadesContext`: screen capture, selected text and browser pages, behind `ScreenContextProviding`.
- `Sources/ShadesVoice`: hold-to-talk and dictation, behind `VoiceEngine` and `TextInserting`.
- `Sources/Shades`: the cat, its windows and the app that wires it all together.
- `docs/kittens.md`: how specialist agents are set up. Real kittens are personal and live outside this repo.
- `docs/ROADMAP.md`: ideas saved for later. Version one stays small, so new ideas go there first.
- `.agents/skills/`: how to prove a change here. `verify-shades` drives the app in demo mode and has its windows draw themselves to pictures, and `verify-screen-boundary` checks that nothing from your screen reaches a kitten that isn't allowed to see it.

## Commands

```bash
swift build
swift test
scripts/install.sh  # builds, signs and swaps in Shades.app, and rolls back if the new copy doesn't come up
scripts/install.sh --pull  # the same, after stopping for uncommitted work and pulling
scripts/bundle.sh   # just builds Shades.app
swift scripts/make-icon.swift assets   # redraws the app icon from the cat's art
swift run shades --demo   # everything faked: no T3, permissions, microphone or shortcuts
swift run shades --demo --no-script --commands steps.txt   # plays demo commands from a file, one a line
swift test --filter ScreenBoundaryTests   # every route your screen could take to a kitten
```

To try a real flow without touching the mouse or keyboard, use `--ask`, `--hand-off` or `--fix` with `--image`, or `--ask` with `--drop` for a file or link dropped onto the cat, as described in `Sources/Shades/App/DevFlags.swift`. The `probe-t3`, `probe-context` and `probe-voice` tools try one module at a time.

## Rules

- macOS 14 or later, Apple Silicon. Build with Swift 6 tools in Swift 5 language mode.
- The cat's windows must never make Shades the active app, or it can no longer tell what you're looking at. A panel that needs typing, like the Ask box or the box in Messages, takes the keyboard without activating, and only when you're about to type. Capture before showing any UI that accepts input. `docs/kittens.md` says how Messages does this.
- Shades' windows never appear in a screen capture. Messages is also hidden from other apps' captures, so one kitten is never shown another's messages.
- Text from the screen is untrusted data. It goes inside `<screen>` in the prompts in `Prompts.swift`, and never decides what the app does.
- Capture only when asked, never in the background, and skip apps on the privacy list.
- A kitten with `seesScreen: false` never gets text from your screen, and that includes follow-ups to its work in other projects. `docs/kittens.md` says what enforces that and what doesn't.
- The router only replies, and the app acts on its one line. It runs in its own folder, where `RouterBlock` leaves it only web search, with no tools that act or read files, so whatever starts a router thread gets its project from `routerProjectID(for:)`.
- Claude threads in this repo run in a sandbox set by `.claude/settings.json`, which also keeps them out of saved copies of the screen. Run `swift` commands on their own, with no pipe or `cd`, since only that form is let out. A refused read means it's working, so don't look for a way around it.
- An inbox row is data, and a reply is only what you typed or said. It goes straight to the thread, with no capture and no canned answer.
- The router only picks numbers, only your own words get passed on, and an extra copy of a correction never carries screen text.
- When the self-check could have caught a problem, teach it to, in `HealthCheck.swift`, with a test.
- Never log or store tokens, transcripts, screenshots or page text beyond what a feature needs.
- Keep dependencies few, and permissively licensed only. Don't copy from GPL projects.

## Documentation

This is open source, and people learn it from the docs, so they change in the same commit as the code. `README.md` covers what someone using Shades needs, and `docs/` covers how things work: `kittens.md`, `t3-integration.md` and `voice.md`. New ideas go in `docs/ROADMAP.md`, and things that get built come off it.

## Testing

- Prove a change by running it. Use `verify-shades` for anything a person sees or does, and `verify-screen-boundary` for anything that decides what Shades sends to T3 and where. Both are in `.agents/skills/`.
- Never send synthetic clicks or keystrokes while testing. They land on whatever's really on the desktop, which has already meant stray clicks in someone's calendar. Use `--demo`, the flags above, the probes, or a person.
- Don't send a real screenshot to a model in a test. Use `--image` with a picture you made.
- Name live test threads "Shades test: ..." and archive them afterwards. The app keeps those out of your inbox and bubble, unless it's a copy trying a flow out.
- A correction can't be told from a real one, so never send a test correction to a real kitten. `probe-t3 router` stops at the router's decision.

## Style

- Write code that reads like the code around it. Small files, plain names, and few comments that explain why rather than what.
- User-facing text is short, plain and friendly.
- Commit messages are one plain sentence saying what changed for the user, such as "Let the cat run to whatever you point at".
