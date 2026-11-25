# Commands

Everything here is for working on The Kitty Litter. None of it is needed to use it.

## Trying a flow from the command line

These run a flow without touching the mouse or keyboard. With `--image`, whatever would see your screen sees that picture instead, as if it filled the main display, so an answer that points there sends the cat to the same spot. A hand-off or a Fix that carries the picture runs in Auto, or in Frontier's mode if that's stricter, and one without it runs in Frontier's mode. `--hand-off` goes the way a hand-off from the router does. They talk to real T3, so name test threads `Shades test: ...` and archive them afterwards. Like the demo, they stay out of sight: their windows draw themselves, but nothing shows on your screen, takes a click or takes your keyboard, and there's no menu bar item. Add `--show` to watch one.

```bash
shades --ask "What's on my screen?" --image page.jpg
shades --hand-off "Which of my projects is the budget app?" --image page.jpg
shades --fix "The total is wrong" --image page.jpg
shades --ask "Summarize this." --drop notes.pdf                        # a file or link dropped onto the cat, with no look at the screen
shades --ask "Research this" --then "And that part?" --image page.jpg    # waits for the agents first
shades --ask "Make this friendlier" --selection "Send it by Friday." --image page.jpg   # as if that were selected
shades --ask "Add a total to the invoice page" --image page.jpg --lockdown "Kitten Name"
```

`--ask` prints where the cat pointed once the answer's in, or that it didn't, and how long until work it handed on had a thread. `--lockdown` pins it to a kitten by name, as Lockdown does, for that run only.

For The Kitty Litter's window, none of which sends anything:

```bash
shades --channels                     # opens The Kitty Litter at launch, with --demo or for real
shades --demo --channels-image out    # draws it to PNGs from canned data, then quits
shades --channels-check               # reads real T3 once, prints only counts, then signs out
```

And the rest:

```bash
shades --picture photo.jpg                        # keeps a small copy of your picture in the app's folder, then quits
shades --draw-icon assets                         # draws AppIcon.icns into a folder from the app's own drawing, then quits
shades --demo --no-script --commands steps.txt    # drives the demo from a file of its commands, one a line, such as `wait 2` or `draw out`
shades --demo --show                              # shows the demo on your screen, with its menu bar item, for a person to watch
shades --demo --reduce-motion                     # as if Reduce Motion were on, whatever your Mac is set to
```

`Sources/Shades/App/DevFlags.swift` reads all of these.

## Probes

Each probe tries one module without the app.

`probe-t3` tries each capability against the real T3 server. Every thread it makes is titled `Shades test:` and gets archived, and every sign-in it makes gets revoked. It never prints a token, and never uses the installed app's Keychain entry.

```bash
probe-t3 connect                         # sign in, list threads and projects
probe-t3 keychain                        # first run and second run against a throwaway Keychain entry
probe-t3 keychain-launch <service> [forget]   # one launch, for testing across rebuilds
probe-t3 ask                             # new thread, streaming, follow-up, follow-up with an image
probe-t3 project                         # a thread bound to a project
probe-t3 watch                           # the live thread list following one thread
probe-t3 approval                        # one approval-required thread, answered in code within a moment
probe-t3 question                        # one thread asking two questions at once, one taking several choices
probe-t3 open                            # shows a thread in T3 Code and checks T3 navigated to it
probe-t3 restart                         # runs its own throwaway T3 server, restarts it mid-turn, and checks recovery
probe-t3 timing                          # how much time this client adds to a turn
probe-t3 settle                          # settles a finished thread, then checks a follow-up still works
probe-t3 steer                           # steers a running turn on Codex and Claude, then one that hasn't started
probe-t3 report <thread>                 # how fast a thread's last report can be read, and how long it is
probe-t3 router                          # what the router decides for made-up kittens and sessions, and nothing past that
probe-t3 sort                            # the real summary model sorting seven made-up reports, five of them the kind that never wait on you, and archives each

probe-t3 search <words>                  # how many threads T3's search names for those words, and how fast
probe-t3 picture [<thread> <path>]       # a made-up picture sent and read back, or a picture in a thread's folder
```

`probe-context` only ever prints timings, sizes, lengths, hostnames and permission status, because your screen may hold private things.

```bash
probe-context                            # one snapshot of whatever's in front
probe-context --runs 10                  # several, with min, median and max
probe-context --front <pid>              # brings that app forward first, then gives focus back
probe-context --front <pid> --freeze     # the same, with that app stopped, to see how a hang goes
probe-context --has <text>               # whether the page text contains this, for test pages only
probe-context --permissions              # permission status
probe-context --ask <bundle id>          # shows the automation dialog for a browser
probe-context --pick                     # the real region picker, for you to drag
probe-context --synthetic <dir>          # capture checks against a window of its own; add --screen 1 for the second display
probe-context --elements                 # what the cat could point at in a window of its own; add --screen 1 for the second display
probe-context --picker-test <dir>        # drives the picker with events handed to its own windows; add --real-mouse for one real drag
```

`probe-voice help` lists what the voice probe can do.

## Scripts

```bash
scripts/bundle.sh [output-folder]   # builds and signs Shades.app into build/, or the folder you give
scripts/install.sh                  # build and install, keeping the old copy and rolling back if the new one doesn't come up, and open it behind the app you're in
scripts/install.sh --pull           # stop if there's uncommitted work, pull, then build and install
scripts/install.sh --rollback       # put the last working copy back
scripts/install.sh --ad-hoc         # allow a build with no stable signature, losing permissions
scripts/install.sh --change-team    # allow a build not signed by the installed copy's team
scripts/make-dev-cert.sh            # a self-signed "Shades Dev" certificate in your login keychain
scripts/install-kitten-skills.sh [folder]   # the skills kittens work by, into ~/kittens/_skills or the folder you give
scripts/triage.sh logs --start "2026-01-31 09:00:00" --end "2026-01-31 10:00:00" [--process codesign]...
scripts/triage.sh processes
```

`scripts/bundle.sh` signs with the first identity it finds: `$SHADES_SIGN_IDENTITY` if you set it, then your Apple Development or Developer ID Application certificate, then "Shades Dev", then ad hoc with a warning. [Install](../README.md#install) says why the certificate matters. To remove "Shades Dev", run `security delete-identity -c "Shades Dev" ~/Library/Keychains/login.keychain-db`.

`scripts/triage.sh` reads only the processes [kittens.md](kittens.md) lists, and works for an agent only once its sandbox lets that one script out.
