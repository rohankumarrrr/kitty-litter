---
name: verify-shades
description: Drive the Shades desktop cat in demo mode and have its windows (the cat, its bubble, the Ask box, The Kitty Litter, the kitten view) draw themselves to PNGs, with no clicks, no keystrokes and no screen capture. Use to prove a change to anything a person sees or does in The Kitty Litter before opening a pull request, and to reproduce a UI bug.
---

# Verify Shades

The surface is the app's windows. Demo mode fakes T3, the screen, the microphone and the keys. A file of demo commands drives it, and each window draws itself to a PNG from its own views.

Never send synthetic clicks or keystrokes. Never capture the screen with `screencapture`, `CGWindowListCreateImage`, ScreenCaptureKit or any screenshot tool. Clicks and keys land on the person's real desktop, and a capture reads it. Everything here goes through the app's own commands.

## Launch

A run is one command, which plays a journey file and quits when the file runs out:

```bash
swift run shades --demo --no-script --commands .agents/skills/verify-shades/journeys/<feature>.txt
```

- Run it exactly in that form, with no pipe, no redirect and no `cd`. Only the plain `swift run` form gets out of this repo's sandbox. A redirect such as `< steps.txt` keeps it in, and `swift` fails with `sandbox_apply: Operation not permitted`.
- Give the Bash call a 180000 ms timeout. A run builds first, then takes as long as its `wait` lines. A call that outlasts its timeout is moved to the background rather than stopped.
- Ready means the first line after the build is `Demo mode. Type a command, or use the menu bar item. Try: help`.
- `--no-script` stops the demo's own approval request 8 seconds in, so the run does only what the file says.

The cat and its windows show on the real desktop while it runs. They never make The Kitty Litter the active app. Nothing is sent anywhere, and nothing is saved except where The Kitty Litter's window was.

## Doctor

```bash
swift run shades --demo --no-script --commands .agents/skills/verify-shades/journeys/doctor.txt
```

It prints `front another app`, a `window <name> ...` line for each of `cat`, `bubble`, `input`, `kittens` and `channels`, then `state ... active=`. If it does, the build is worth driving. `front` says whether this copy of The Kitty Litter is in front, `front The Kitty Litter`, or `front another app`, and never names the other app, since what a journey prints goes on public pull requests. It must stay `another app` all run. If it says `The Kitty Litter`, a window made The Kitty Litter the active app, which breaks a rule in `AGENTS.md` and is a bug in its own right. `active=true` on its own isn't: AppKit says that while one of The Kitty Litter's panels has the keyboard, such as the Ask box or the box in The Kitty Litter, even though your app stays in front. If the first `front` of a run already says `The Kitty Litter`, macOS put the demo in front as it launched, such as when nothing else was in front, so that run can't show whether a window did it. A build error means fixing the build first.

## Drive

Find the feature in [features/README.md](features/README.md), run its journey from `journeys/`, then read the output and the pictures. To try something the map doesn't cover, write a journey file under `.verify/shades/` and run that. The commands, one a line:

- `wait <seconds>` holds back the lines after it. Each feature file says how long its steps take.
- `draw <folder>` has each window that's showing draw itself to `<folder>/<name>.png`, and prints `drew <name> <path>`. `input` is the Ask box, `channels` is The Kitty Litter and `pill` is the word over the cat.
- `windows` prints each window's frame, whether it's showing and whether it has the keyboard, then the cat's state and `active=`.
- `front` prints `The Kitty Litter` when this copy is in front, `another app` when anything else is, and `nothing` when nothing is. The `front=` on `key`, `highlight` and `tab` lines says the same. Your installed copy in front counts as another app.
- `record <file.gif> <window>...` records those windows, or `phone`, as a looping GIF until `record stop`, and keeps each frame as a picture in `.verify/shades/record/<name>/`. See [Recordings](#recordings).
- The rest, such as `ask`, `channels`, `channel`, `send`, `report`, `inbox`, `approval` and `allow`, are listed by `help` and defined in `handle` in `Sources/Shades/Demo/DemoDriver.swift`. Each calls the same controller method as the button it stands for.

## Evidence

A proof has three parts, and goes on the pull request as the command, the output lines and what each picture shows:

- The pictures, before and after the action, in `.verify/shades/<feature>/<step>/`. Read each one with the Read tool and say what it shows.
- The output. Lines starting `[demo] started`, `[demo] carried on in` and `[demo] forwarded to` say what was sent, to which thread and with how many attachments, and a forward says whether it was sent to steer or to queue. `[demo] accept:` and `[demo] decline:` are answered approvals. These are the side effects to check alongside the pictures.
- The `front` and `windows` lines at the end, with your own app still in front.

Drive the path a person takes, which is what the demo commands do. The demo's T3 is fake and every kitten's folder looks the same to it, so it can't show which folder a thread started in. Where that matters, such as your screen staying away from a kitten, use the `verify-screen-boundary` skill. To try a flow against real agents, use `--ask`, `--hand-off` or `--fix` with `--image`, as `Sources/Shades/App/DevFlags.swift` describes. Those talk to real T3, so name test threads `Shades test: ...` and archive them afterwards.

## Recordings

The README's GIFs are recorded the same way, with no screen capture. Each frame is the chosen windows drawing themselves, laid where they are on the screen over a drawn stand-in for the demo's pricing page, or over a plain ground when the cat isn't in it. The phone's page draws itself in its web view. Remake one with its journey, which writes `docs/images/<name>.gif`:

```bash
swift run shades --demo --no-script --commands .agents/skills/verify-shades/journeys/record/<name>.txt
```

There's one journey for each of `ask`, `point`, `drop`, `talk`, `approval`, `kittens`, `messages` and `phone`. The output ends `recorded docs/images/<name>.gif <frames> frames <size> KB`. Read a few of the pictures in `.verify/shades/record/<name>/` before keeping one, the last especially, since it's the frame the GIF holds before it loops.

While it records, clicks and typing elsewhere don't close the bubble, the Ask box or the kittens view, and the cat comes to a fixed spot instead of the real pointer. Otherwise the person using the Mac would close or move what's being recorded. Message rows can still show their hover buttons if the real pointer is over The Kitty Litter.

## Cleanup

A run quits when its file runs out, so there's usually nothing to stop. If one is still going, such as one a timeout moved to the background, stop that background task by the ID the harness gave you. `ps` and `pgrep` are refused in this repo's sandbox, so there's no PID to look up. Never kill by name, since the person's own copy of The Kitty Litter is running too. Leave `.verify/shades/` alone. It's gitignored, and it's the evidence. Before rerunning a journey, `rm -rf .verify/shades/<feature>` gives it a clean folder.
