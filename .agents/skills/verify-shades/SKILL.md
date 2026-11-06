---
name: verify-shades
description: Drive the Shades desktop cat in demo mode and have its windows (the cat, its bubble, the Ask box, Messages, the inbox, the kitten view) draw themselves to PNGs, with no clicks, no keystrokes and no screen capture. Use to prove a change to anything a person sees or does in Shades before opening a pull request, and to reproduce a UI bug.
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

The cat and its windows show on the real desktop while it runs. They never make Shades the active app. Nothing is sent anywhere, and nothing is saved except where the Messages window was.

## Doctor

```bash
swift run shades --demo --no-script --commands .agents/skills/verify-shades/journeys/doctor.txt
```

It prints `front <app>`, a `window <name> ...` line for each of `cat`, `bubble`, `input`, `kittens` and `channels`, then `state ... active=`. If it does, the build is worth driving. `front` is the app in front, which must stay whatever was in front before the run, never Shades. If it says Shades, a window made Shades the active app, which breaks a rule in `AGENTS.md` and is a bug in its own right. `active=true` on its own isn't: AppKit says that while one of Shades' panels has the keyboard, such as the Ask box or the box in Messages, even though your app stays in front. A build error means fixing the build first.

## Drive

Find the feature in [features/README.md](features/README.md), run its journey from `journeys/`, then read the output and the pictures. To try something the map doesn't cover, write a journey file under `.verify/shades/` and run that. The commands, one a line:

- `wait <seconds>` holds back the lines after it. Each feature file says how long its steps take.
- `draw <folder>` has each window that's showing draw itself to `<folder>/<name>.png`, and prints `drew <name> <path>`. `input` is the Ask box and `channels` is Messages.
- `windows` prints each window's frame, whether it's showing and whether it has the keyboard, then the cat's state and `active=`.
- `front` prints the app in front.
- The rest, such as `ask`, `channels`, `channel`, `send`, `report`, `inbox`, `approval` and `allow`, are listed by `help` and defined in `handle` in `Sources/Shades/Demo/DemoDriver.swift`. Each calls the same controller method as the button it stands for.

## Evidence

A proof has three parts, and goes on the pull request as the command, the output lines and what each picture shows:

- The pictures, before and after the action, in `.verify/shades/<feature>/<step>/`. Read each one with the Read tool and say what it shows.
- The output. Lines starting `[demo] started`, `[demo] carried on in` and `[demo] forwarded to` say what was sent, to which thread and with how many attachments. `[demo] accept:` and `[demo] decline:` are answered approvals. These are the side effects to check alongside the pictures.
- The `front` and `windows` lines at the end, with your own app still in front.

Drive the path a person takes, which is what the demo commands do. The demo's T3 is fake and every kitten's folder looks the same to it, so it can't show which folder a thread started in. Where that matters, such as your screen staying away from a kitten, use the `verify-screen-boundary` skill. To try a flow against real agents, use `--ask`, `--hand-off` or `--fix` with `--image`, as `Sources/Shades/App/DevFlags.swift` describes. Those talk to real T3, so name test threads `Shades test: ...` and archive them afterwards.

## Cleanup

A run quits when its file runs out, so there's usually nothing to stop. If one is still going, such as one a timeout moved to the background, stop that background task by the ID the harness gave you. `ps` and `pgrep` are refused in this repo's sandbox, so there's no PID to look up. Never kill by name, since the person's own Shades is running too. Leave `.verify/shades/` alone. It's gitignored, and it's the evidence. Before rerunning a journey, `rm -rf .verify/shades/<feature>` gives it a clean folder.
