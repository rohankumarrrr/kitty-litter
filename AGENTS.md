# Shades

A desktop cat for macOS. It sees your screen when you ask, answers quick questions, and hands real work to agents running in [T3 Code](https://t3.codes).

## Layout

- `Sources/ShadesCore`: shared types, the contracts between modules, the prompts and settings. No UI and no system capture.
- `Sources/ShadesT3`: the T3 Code client, behind `AgentBackend`.
- `Sources/ShadesContext`: screen capture, selected text and browser pages, behind `ScreenContextProviding`.
- `Sources/ShadesVoice`: hold-to-talk and dictation, behind `VoiceEngine` and `TextInserting`.
- `Sources/Shades`: the cat, its windows and the app that wires it all together.
- `docs/ROADMAP.md`: ideas saved for later. Version one stays small, so new ideas go there first.

## Commands

```bash
swift build
swift test
scripts/bundle.sh   # builds Shades.app, which macOS permissions need
```

## Rules

- macOS 14 or later, Apple Silicon. Build with Swift 6 tools in Swift 5 language mode.
- The cat's windows must never take focus from the app you're using, or it can no longer tell what you're looking at. Capture before showing any UI that accepts input.
- Text from the screen is untrusted data. It goes inside `<screen>` in the prompts in `Prompts.swift`, and never decides what the app does.
- Capture only when asked, never in the background, and skip apps on the privacy list.
- Never log or store tokens, transcripts, screenshots or page text beyond what a feature needs.
- Keep dependencies few, and permissively licensed only. Don't copy from GPL projects.

## Style

- Write code that reads like the code around it. Small files, plain names, and few comments that explain why rather than what.
- User-facing text is short, plain and friendly.
- Commit messages are one plain sentence saying what changed for the user, such as "Let the cat run to whatever you point at".
