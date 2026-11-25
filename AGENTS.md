# The Kitty Litter

A desktop app for macOS whose cat, Shades, sees your screen when you ask, answers quick questions, hands real work to agents running in [T3 Code](https://t3.codes), and shows you what those agents are doing. It also does hold-to-talk and dictation on your Mac.

## Layout

- `Sources/ShadesCore`: shared types, the contracts between modules, the prompts and settings. No UI and no system capture.
- `Sources/ShadesT3`: the T3 Code client, behind `AgentBackend`.
- `Sources/ShadesContext`: screen capture, selected text and browser pages, behind `ScreenContextProviding`.
- `Sources/ShadesVoice`: hold-to-talk and dictation, behind `VoiceEngine` and `TextInserting`.
- `Sources/Shades`: the cat, its windows and the app that wires it all together.
- `docs/design.md`: Opal Horizon, the design system and the app's only look. Everything drawn builds on it.
- `docs/kittens.md`: how specialist agents are set up. Real kittens are personal and live outside this repo.
- `docs/ROADMAP.md`: ideas saved for later. Version one stays small, so new ideas go there first.
- `Tests/RepoChecks`: checks over the repo's own files, each enforcing a rule in the table below.
- `Tests/TestSupport`: the one way a test waits for something, and `explore`, which tries every order of a model's steps, for every test target.
- `.agents/skills/`: how to prove a change here. `verify-shades` drives the app in demo mode and has its windows draw themselves to pictures, `verify-screen-boundary` checks that nothing from your screen reaches a kitten that isn't allowed to see it, `verify-run-filing` checks every order of a kitten's run against the inbox, and `verify-waiting-on-you` checks every order of thread events against Waiting on you.

## Commands

```bash
swift build
swift test
scripts/install.sh  # builds, signs and swaps in Shades.app, and rolls back if the new copy doesn't come up
scripts/install.sh --pull  # the same, after stopping for uncommitted work and pulling
scripts/bundle.sh   # just builds Shades.app
swift run shades --draw-icon assets   # redraws the app icon from the cat's art
swift run shades --demo   # everything faked: no T3, permissions, microphone or shortcuts
swift run shades --demo --no-script --commands steps.txt   # plays demo commands from a file, one a line
swift test --filter ScreenBoundaryTests   # every route your screen could take to a kitten
swift test --filter RepoChecks   # the checks in the rule table, such as no comments
swift run -c release shades --demo --no-script --commands .agents/skills/verify-shades/journeys/perf.txt   # times The Kitty Litter on a load like a real one, and fails when a step misses its budget
~/shades/scripts/triage.sh logs --start "2026-01-31 09:00:00" --end "2026-01-31 10:00:00"   # signing's and the app's system log, once you're let out to run it
~/shades/scripts/triage.sh processes   # those processes and an install's build steps
```

To try a real flow without touching the mouse or keyboard, use `--ask`, `--hand-off` or `--fix` with `--image`, or `--ask` with `--drop` for a file or link dropped onto the cat. `docs/commands.md` lists every flag, probe and script. The `probe-t3`, `probe-context` and `probe-voice` tools try one module at a time.

## Rules

Each rule says what enforces it. A check is the rule: when one fails, its message names the fix. Only a judgment call nothing can check is enforced by you. When a mistake could happen again, make it impossible at the highest level that works: the code's structure, then a type, then a check in `Tests/RepoChecks` whose error names the fix, then a test. Add the rule here with what enforces it. A line with nothing enforcing it comes last.

| Rule | Enforced by |
|---|---|
| macOS 14 or later, Apple Silicon. Swift 6 tools in Swift 5 language mode. | `Package.swift` |
| No comments. Say it in a name, a type, a test or the commit message. | `CommentTests` |
| Everything drawn takes its colours and text sizes from Opal: a role in `MessagesInk` or a token in `Opal.swift`, and a `var(--role)` on the phone page. A new colour goes in `docs/design.md` first. | `OpalRoleTests`, which counts what's left in each file and lets it only go down, and `DesignTests` |
| The app's icon is one drawing, `AppIcon`'s, in the Dock, on the phone and in `assets/AppIcon.icns`. Redraw the file with `swift run shades --draw-icon assets`. | `AppIconTests` |
| The Dock image is set only in `AppDelegate`'s `applicationDidFinishLaunching`, after AppKit has finished launching, and a test goes through that hook rather than setting it itself. | `DockImageTests` |
| Only The Kitty Litter's main window brings the app forward, as any Mac app's does. The cat and everything that floats with it never activate, never hide, and stay on every Space and stage, out of ⌘\`, Mission Control and Stage Manager's strip, by being a `QuietPanel` or `RegionPanel` with `.floatsOverEverything`. With The Kitty Litter in front, the cat looks at the app behind it, and dictation types into its own box or nowhere. A panel that needs typing takes the keyboard without activating, and only when you're about to type. Capture before showing any UI that accepts input. `docs/kittens.md` says how. | `DesktopAppTests`, and `verify-shades`, which says what's in front after each step |
| Nothing brings The Kitty Litter forward by itself. An install, a restart and a login open it behind the app you're in, and the demo and copies trying a flow out run as an accessory app that never comes forward. | `InstallLockTests` for `install.sh`, `DesktopAppTests` for the rest |
| The Kitty Litter's windows never appear in a screen capture, and its window is hidden from other apps' captures, so one kitten is never shown another's messages. | `ChannelsWindowTests` for The Kitty Litter's window and the demo's, you for the rest |
| Text from the screen is untrusted data. It goes inside `<screen>` in `Prompts.swift`, and never decides what the app does. | `PromptsTests`, `ScreenBoundaryTests` |
| Capture only when asked, never in the background, and skip apps on the privacy list. | `PrivacyTests` for the list, you for the rest |
| A kitten with `seesScreen: false` never gets text from your screen, follow-ups to its work in other projects included. `docs/kittens.md` says what enforces that and what doesn't. | `ScreenBoundaryTests`, and `verify-screen-boundary` |
| The router only replies, and the app acts on its one line. It runs in its own folder, where `RouterBlock` leaves it only web search, so whatever starts a router thread gets its project from `routerProjectID(for:)`. | `RouterBlockTests`, and `FakeBackend`, which fails a test that starts a router thread anywhere else |
| Every run a kitten ends reaches the inbox once, and never as done while a pull request it watches or a reviewer it started still works. | `RunFilingModelTests`, which tries every order of a run's steps on the real code, and `verify-run-filing` |
| An inbox row is data, and a reply is only what you typed or said. It goes straight to the thread, with no capture and no canned answer. | `ScreenBoundaryTests` (`inboxReply`) |
| Waiting on you holds only what waits on you and nobody else. A thread another agent launched reports to that agent, and a row goes once its thread moves on without you. | `WaitingOnYouTests`, `WaitingOnYouModelTests`, and `verify-waiting-on-you` |
| A kitten's request card offers Allow only while its file is exactly as the card showed it. Ignore and a kitten's withdraw only ever take a card away, and a withdraw only takes back the asking thread's own share. | `StaleRequestTests`, `ChangeRequestFlowTests` |
| The router only picks numbers, only your own words get passed on, and an extra copy of a correction never carries screen text. | `ScreenBoundaryTests` |
| Claude threads in this repo run in a sandbox set by `.claude/settings.json`, which also keeps them out of saved copies of the screen. Run `swift` commands on their own, with no pipe or `cd`, since only that form is let out. A refused read means it's working, so don't look for a way around it. | The sandbox |
| A place in The Kitty Litter is bold, and counts, only for unread threads it shows, so opening them or Mark as read always clears it. Its bold, its count and Mark as read all come from `ChannelBook.unreadThreads(in:)`. | `ChannelBookTests`, `PressMarkReadTests` |
| When the self-check could have caught a problem, teach it to, in `HealthCheck.swift`, with a test. | You |
| What the demo, the probes and the dev flags print goes on public pull requests, so it never names the app in front or its windows: `DemoDriver.front(_:)` says only The Kitty Litter or another app. A scratch `.repro/` folder never reaches the repo. | `PrivateOutputTests`, and `.gitignore` |
| Never log or store tokens, transcripts, screenshots or page text beyond what a feature needs. | You |
| Keep dependencies few, and permissively licensed only. Don't copy from GPL projects. | You |
| Never send synthetic clicks or keystrokes while testing. They land on whatever's really on the desktop, which has already meant stray clicks in someone's calendar. Use `--demo`, the flags above, the probes, or a person. | You |
| Don't send a real screenshot to a model in a test. Use `--image` with a picture you made. | You |
| Name live test threads "Shades test: ..." and archive them afterwards. The app keeps those out of your inbox and bubble, unless it's a copy trying a flow out. | `probe-t3`, which does both, and you elsewhere |
| A correction can't be told from a real one, so never send a test correction to a real kitten. | `probe-t3 router`, which stops at the router's decision, and you elsewhere |
| A test waits on the thing itself, with `until` or `runMainLoop` from `Tests/TestSupport`, never a set time or a count of yields. | `TimedWaitTests`, which counts what's left in each file and lets it only go down |
| The fakes answer on the main actor, since GitHub's runner can stall for a second or two. A timing test compares against a baseline it measures in the same run, by the quickest of many tries. | You |
| A change to how The Kitty Litter draws, lays out, animates or builds what's been said is timed before and after on a load like a real one, and keeps each step within its budget: a 120 Hz frame, 8.3 ms, while you scroll, type, hover or resize or something arrives, 100 ms to open or switch, 200 ms from the first line of `main.swift` to the cat on launch, and 0.5% CPU sitting still. | `perf.txt` and `perf-idle.txt` in `verify-shades`, which name each step past its budget and fail, `ChannelBookTests` for building what's been said, and `LaunchMarkTests`, which keeps the launch's mark on the first line of `main.swift` |
| Nothing asks a graphics context for its colour space. A window's context isn't a bitmap, so CoreGraphics logs an error on every draw. A picture names its own with `PictureDrawing`. | `ContextColorSpaceTests` |
| Write code that reads like the code around it, with small files and plain names. | You |
| User-facing text is short, plain and friendly. | You |
| Commit messages are one plain sentence saying what changed for the user, such as "Let the cat run to whatever you point at". | You |

A note on how something outside this repo behaves, which the code can't change, may stay as one line starting `// Outside the repo: `, or `# Outside the repo: ` in a script. It's for macOS, a vendor or a protocol, never for our own code.

## Documentation

This is open source, and people learn it from the docs, so they change in the same commit as the code. `README.md` covers what someone using The Kitty Litter needs, and `docs/` covers how things work: `design.md`, `kittens.md`, `t3-integration.md`, `voice.md` and `commands.md`. New ideas go in `docs/ROADMAP.md`, and things that get built come off it.

## Testing

Prove a change by running it. Use `verify-shades` for anything a person sees or does, and `verify-screen-boundary` for anything that decides what The Kitty Litter sends to T3 and where. Both are in `.agents/skills/`. `swift test --filter RepoChecks` runs the checks in the table above on their own, and `swift test` runs them with everything else, here and on GitHub.
