# Voice

Hold a key and talk. Let go, and clean text lands where your cursor is, or goes to the cat. Everything runs on your Mac.

```
key down ─► listen-only event tap ─► microphone opens ─► 16 kHz audio
                                                            │
             live text every 0.4 s ◄── Parakeet Ultra ◄─────┤  (Neural Engine)
                                                            │
key up ─► hear the end of the last word ─► final pass ──────┘
              │
              ▼
   vocabulary check ─► rules ─► S1-mini ─► guard ─► layout and spelling ─► insert
   (only if a listed      (fillers,  (Metal)   (too different?
    word could apply)    corrections)           fall back)
```

All numbers below come from `probe-voice` on an M2 Pro with 16 GB, macOS 26.3, with other agents building on the same machine, so the load average was between about 2 and 5 at the checkpoints. Reproduce them with the commands in [Running the benchmark](#running-the-benchmark).

## What it can't tell you

Read these before trusting the numbers.

- **The speech is synthetic.** Every clip is macOS `say`, in six voices. Real people mumble, trail off and talk over fans, so expect real accuracy to be worse, and treat the accuracy tables as a comparison between options rather than a prediction.
- **The microphone was never opened.** It hadn't been granted, and opening it would have shown a prompt. Mic start time is unmeasured. Everything downstream of the mic was measured by playing files in real time through the real engine.
- **The rules were written while looking at the main corpus**, so their score there flatters them. The held-out set was written afterwards and never used for tuning, so that's the honest column.

## Choices

### Speech: Parakeet Ultra

| Model | WER | Technical terms | Clips under 15 s, p50 / p95 | Memory | Download | Minimum macOS |
|---|---:|---:|---:|---:|---:|---|
| Parakeet Ultra (chosen) | 2.47% | 6.89% | 53 / 69 ms | +66 MB | 613 MB | 14 |
| Parakeet TDT v3 | 2.44% | 6.89% | 51 / 68 ms | +58 MB | 470 MB | 14 |
| Parakeet TDT v2, English only | 2.92% | 7.85% | 53 / 64 ms | +76 MB | 451 MB | 14 |

Scored across 49 utterances in 6 voices, 294 clips, 24 minutes of audio, each model alone in its own process with vocabulary off. Memory is the process footprint, which may not include what the Neural Engine holds. These rows come from the run just before the final batch, and the recognizer didn't change in between. Ultra and v3 are tied here, and v2 is a little behind, so English-only v2 buys nothing. Ultra wins on FluidAudio's published LibriSpeech numbers (2.13% against 2.27% for v3), and its int8 encoder avoids the token flips FluidAudio traced to v3's 6-bit weights (their issue #760).

Bark 3.0 Clean drops fillers in the recognizer itself, which sounded ideal. It needs macOS 15, nearly doubled technical errors (12.66% against 6.89% in an earlier run), and left far more wrong than Ultra plus cleanup (see below), so it's out. It wasn't tried with S1-mini, since macOS 15 ruled it out anyway.

### Live text: re-read the audio with the same model

| Live text | Cost per update, p50 / p95 | Extra memory | WER at end of clip | Works with vocabulary |
|---|---:|---:|---:|---|
| Re-read every 0.4 s with Ultra (chosen) | 46 / 59 ms | None, same model | 2.15% | Yes, on the final pass |
| Parakeet EOU, 160 ms mode, alongside | Runs at 9x real time | +242 MB | 23.96% | No |
| Parakeet EOU, 320 ms mode, alongside | Runs at 30x real time | +73 MB | 15.73% | No |
| Parakeet EOU, 1280 ms mode, alongside | Runs at 64x real time | +108 MB | 13.60% | No |

The model's window is a fixed 15 seconds, so re-reading a growing clip costs about the same every time. At one update every 0.4 s that's busy about 12% of the time, it needs no second model, and its text is far better. EOU's speed is not worth text that's wrong one word in seven at best, and it needs another download. This compared two voices on clips under 15 s. EOU's memory was measured one mode after another in one process and moved around between runs, so treat it as rough. Past 12 seconds, the part already shown stops changing and the window moves on. The final text always comes from a fresh pass over all the audio, so this never affects what gets inserted.

### Cleanup: rules, then S1-mini by Superwhisper

| Cleanup, held-out set | Words wrong | Exactly right | Kept what mattered | Dropped what should go | Guard would reject | Time p50 / p95 |
|---|---:|---:|---:|---:|---:|---:|
| Raw transcript | 21.76% | 39.4% | 97.8% | 9.8% | 0.0% | none |
| Rules alone | 8.85% | 61.7% | 97.8% | 73.5% | 0.0% | under 1 ms |
| S1-mini alone | 5.19% | 72.8% | 97.8% | 93.9% | 0.0% | 39 / 66 ms |
| S1-mini, lowercased input | 2.63% | 67.2% | 97.8% | 100.0% | 3.3% | 52 / 81 ms |
| **Rules + S1-mini (ships)** | **2.99%** | **76.1%** | **97.8%** | **98.5%** | **0.0%** | **38 / 56 ms** |
| Qwen3 1.7B, prompted | 18.85% | 48.3% | 92.0% | 56.1% | 6.7% | 243 / 297 ms (see below) |
| Bark 3.0 Clean, as it comes | 17.21% | 17.2% | 93.1% | 59.8% | 0.0% | none |
| Bark 3.0 Clean + rules | 12.83% | 47.2% | 93.1% | 70.5% | 0.0% | under 1 ms |

| Cleanup, main corpus | Words wrong | Exactly right | Kept what mattered | Dropped what should go | Guard would reject | Time p50 / p95 |
|---|---:|---:|---:|---:|---:|---:|
| Raw transcript | 14.53% | 41.5% | 89.7% | 20.7% | 0.0% | none |
| Rules alone | 3.64% | 70.7% | 91.2% | 100.0% | 0.0% | under 1 ms |
| S1-mini alone | 4.59% | 67.7% | 91.2% | 93.9% | 0.0% | 40 / 69 ms |
| S1-mini, lowercased input | 3.26% | 63.6% | 90.4% | 96.5% | 0.0% | 58 / 107 ms |
| **Rules + S1-mini (ships)** | **2.98%** | **67.3%** | **91.2%** | **100.0%** | **0.0%** | **41 / 75 ms** |
| Qwen3 1.7B, prompted | 17.51% | 47.3% | 83.6% | 67.2% | 8.2% | 243 / 297 ms (see below) |

- **raw** is Parakeet's text, unchanged. It already has punctuation and capitals, but all the fillers and corrections too.
- **rules** is the deterministic pass. It's perfect on what it was written for and misses plenty of what it wasn't, which is the gap between the two tables.
- **S1-mini** is a 0.6B Qwen3 fine-tune trained only to turn transcripts into clean text. It isn't a chat model, and it answered none of the questions and requests in either corpus.
- **rules + S1-mini** is what ships. The rules remove what's certain, and the model handles punctuation, numbers and the corrections rules can't line up.
- **lowercased input** got fewer words wrong on the held-out set but more on the main corpus, got fewer sentences exactly right on both, and tripped the guard on 3.3% of held-out clips.
- **Qwen3 1.7B with a careful prompt** was far worse on every measure and over twice the download. Its time is inflated, because the probe re-reads its long prompt on every call. An earlier run with the prompt cached took 70 / 143 ms on the main corpus. **Bark Clean** without S1-mini was worse too. Apple's Foundation Models won't compile with this SDK, so they aren't used at all.

The held-out table is 180 clips and the main one 294, all from Ultra's transcripts with vocabulary off, and timed on clips under 15 s. Words wrong ignores case and punctuation. Exactly right doesn't, which is why it's far from 100% even when the words are fine.

**Drafting.** Greedy decoding has to run the model once per output token. Cleanup mostly copies, so `LlamaModel` guesses the next 8 tokens from the input and checks them in one batch. The output is identical, because the model still confirms every token, and it runs about twice as fast: 335 ms down to about 160 ms on a 64-token clip.

**Why llama.cpp.** It ships a prebuilt framework with its Metal shaders inside, so plain `swift build` works, and that was verified by loading it from an app bundle layout. MLX wasn't tried. Local Dictation's write-up says its shaders need Xcode's Metal compiler.

### The guard

Every cleaned result is compared with the raw transcript. It's thrown out if it adds words, grows, loses too much, or scrambles the order, so "What is the capital of France?" can't come back with Paris in it. Corrections get more room to delete, since that's their job. Numbers are exempt from "new words" because "twenty three" legitimately becomes 23.

If the model's text is rejected, the text falls back to the rules' version of the raw transcript, since rules only ever delete and rearrange. If that's rejected too, you get the raw transcript untouched. On the shipped path it never fired on either corpus, so that fallback is only exercised by unit tests with made-up bad output. It did fire on 7 to 8% of Qwen's real output.

### Vocabulary

| Setting | Technical WER | Other WER | Terms right | Final pass, p50 / p95 |
|---|---:|---:|---:|---:|
| Off | 6.89% | 1.67% | 80.7% | 50 / 147 ms |
| Boost 0, similarity 0.7 | 6.41% | 1.67% | 82.5% | 57 / 162 ms |
| **Boost 1.5, similarity 0.6 (ships)** | **2.40%** | **1.67%** | **94.7%** | **56 / 159 ms** |
| Boost 3, similarity 0.55 | 2.40% | 1.67% | 94.7% | 52 / 152 ms |
| Boost 4.5, similarity 0.5 | 2.40% | 1.67% | 94.7% | 51 / 153 ms |

Listed words get three treatments:

1. A CTC pass compares what was heard against the list by sound. It's skipped when no listed word could apply, so most takes pay nothing.
2. A gate rejects swaps where ordinary words get replaced by something merely similar. Without it, "2 plus 2" became "Opus 2" in all six voices.
3. A spelling pass fixes case and spacing: `git hub` to `GitHub`, `work tree` to `worktree`.

That table uses a 15-word list, and its timings include clips over 15 s. Higher boosts gain nothing on that list, and boost 3 turned "code" into "Codex" in 7 of 294 clips when Codex was on the list, so 1.5 ships. With a list of 15 other names, only one of them actually spoken, boost 1.5 changed one word in 294 clips: "Rowan" to "Rohan", which was right.

Words that are also everyday English (Pepper, Swift, Opus) never get their case forced, or "salt and pepper" would gain a capital. The recognizer and S1-mini usually capitalize them from context, but not always.

## The whole pipeline

294 clips in 6 voices, each played in real time through the real engine, with live text on, the 15-word vocabulary on and S1-mini loaded. This is the main corpus.

| Time | p50 | p95 | Max |
|---|---:|---:|---:|
| **Release to final text, clips under 15 s** | **198 ms** | **342 ms** | **550 ms** |
| Of which waiting for live text to finish | 0 ms | 20 ms | 44 ms |
| Of which recognition with vocabulary | 81 ms | 134 ms | 215 ms |
| Of which cleanup | 66 ms | 174 ms | 299 ms |
| Release to final text, clips 15 s and over | 540 ms | 744 ms | 748 ms |
| Pressing to first live text | 590 ms | 608 ms | 619 ms |

The typical take beats the 300 ms target and the slowest ones miss it, with other builds running at the same time. How much of that tail comes from those builds wasn't separated. Two things can make it slower in real use:

- These recordings end in silence, so the tail after release stays at its 30 ms minimum. A word still being spoken, or a noisy room, can add up to 120 ms.
- Inserting the text comes after this.

| Accuracy | |
|---|---:|
| Raw transcript WER | 1.78% over 4,044 words |
| Words wrong after cleanup | 2.28% |
| Exactly right, with case and punctuation | 70.4% |
| Kept what mattered | 94.9% |
| Dropped what should go | 100.0% |
| Final text came from S1-mini | 294 of 294 clips |

Words wrong after cleanup, by kind: corrections 0.00%, words that only look like corrections 0.00%, requests that must not be answered 0.00%, plain sentences 0.34%, lists 1.39%, fillers 2.46%, technical terms 2.56%, long takes 3.28%, numbers and addresses 8.57%. Most of what's left is the recognizer mishearing a synthetic voice, such as "the route causes" for "the root cause". The rules were tuned on this corpus, so the held-out table above is the fairer score for cleanup.

Memory was 344 MB after `prepare()` and peaked at 482 MB. That's the process footprint, which may not include what the Neural Engine holds.

**First press after sitting idle.** After a few idle minutes the first cleanup got slow, most likely because the GPU powers down. Key-down now wakes it after 20 seconds of idleness, so the wake happens while you talk.

| Idle before the press | Without the wake: total (cleanup) | With the wake: total (cleanup) |
|---:|---:|---:|
| 0 s | 192 ms (76 ms) | 201 ms (91 ms) |
| 30 s | 232 ms (135 ms) | 231 ms (117 ms) |
| 2 minutes | 270 ms (151 ms) | not re-run |
| 5 minutes | 471 ms (331 ms) | 236 ms (109 ms) |
| 10 minutes | 385 ms (266 ms) | not re-run |

Each cell is a single press, so read this as a direction rather than a precise figure. The press right after the 5-minute one took 215 ms, so the first press is no longer an outlier there. These clips were all over 2 s, so a very short press after a long idle hasn't been tested.

**Setup.** With models on disk, `prepare()` took 0.6 to 1.6 s. The first run also has to download and compile. FluidAudio's Core ML compile adds about a minute, S1-mini's very first load took 18.6 s, and its download took 239 s here, with the progress and checksum working. `onSetupProgress` reports all of it. Speech is usable as soon as its model loads, and the rules cover cleanup until S1-mini is ready.

| Download | Size | Where |
|---|---:|---|
| Parakeet Ultra | 613 MB | `~/Library/Application Support/FluidAudio/Models` |
| Parakeet CTC 110M, only if you have a vocabulary | 98 MB | same |
| S1-mini | 462 MB | `~/Library/Application Support/shades/models` |

## The first word

The microphone stays off until the key goes down, so nothing can be buffered in advance, and the only defence is opening it fast. Here's what a slow open costs, measured by cutting speech off the front of clips:

| Speech lost at the start | First word right | First word right with 100 ms of silence added | WER with that silence |
|---:|---:|---:|---:|
| 0 ms | 98.0% | 97.3% | 1.98% |
| 25 ms | 98.0% | 98.0% | 1.73% |
| 50 ms | 95.2% | 93.9% | 2.23% |
| 75 ms | 88.4% | 85.0% | 3.31% |
| 100 ms | 85.0% | 73.5% | 3.86% |
| 150 ms | 54.4% | 45.6% | 6.68% |
| 200 ms | 41.5% | 25.9% | 8.15% |
| 300 ms | 22.4% | 6.8% | 12.11% |

That's 147 clips in 3 voices, with the start of speech found by level.

So the budget is about 25 ms if you start talking the instant you press, and more if you pause first. By 100 ms about one first word in seven is wrong, and by 150 ms nearly half are. Adding silence in front never helped: it tied at 25 ms and hurt everywhere else, so the engine adds none. What the code does about it:

- **Core Audio's input unit instead of AVAudioEngine.** There's less to start, and the unit is built ahead of time, so a press only has to start it. `MicrophoneSource` builds it in `prepare()` once permission exists, without opening the mic. If the unit starts and delivers nothing within 0.5 s, or 3 s for a Bluetooth mic you chose yourself, the source falls back to AVAudioEngine for that take and from then on. Neither path has run against a real mic yet.
- **Never opening a Bluetooth mic if it can help it.** A headset's mic forces it into call mode, which loses a second or two of speech and ruins any music playing. If the default input is Bluetooth and the lid is open, the built-in mic is used.
- **The key doesn't wait to be sure.** `onPress` fires on key-down. A tap or shortcut gets called off afterwards, which means the orange dot can flicker for a moment if you use right Option for typing accents.
- **A signal for "I can hear you".** The first value on `levels` arrives with the first audio, so the cat can react right when the mic is really live.

The tail works the same way in reverse. After the key comes up the mic stays on until it's been quiet for 30 ms, for at most 150 ms, so a word still being spoken isn't cut.

## Hold keys

`KeyHoldMonitor` uses a listen-only `CGEventTap`, so every key still reaches your app. Left and right are told apart by key code and device flag, which also works when both are held.

| You do | What happens |
|---|---|
| Hold, then let go | `onPress` at key-down, `onRelease` at key-up |
| Let go within 150 ms | `onPress`, then `onCancel` |
| Press another key or click within 1 s | `onPress`, then `onCancel`. Option-E still types your accent |
| Press another key after 1 s | Nothing. You're mid-sentence and a stray key shouldn't lose it |
| Escape, any time | `onPress`, then `onCancel` |
| Hold it with another modifier already down | Nothing, it's a shortcut |
| A release that never arrives | A timer checks the physical key and ends the take normally. After 5 minutes the mic turns itself off regardless |

`probe-voice keys-selftest` confirmed the tap tells all seven keys apart using synthetic events. The gesture rules above are unit tested, and nothing has been tried with fingers yet.

Hold-to-talk fills the text box instead of going to the router when the box is waiting for your words, as when you're describing what to fix, or when you're typing in the box in Messages. No new look at the screen happens, and saying it counts as pressing Return. In Messages, what you say goes after anything you'd typed, to wherever the line over the box said when the key went down. That line stays put while you talk, so a question arriving can't take your words as its answer, and if where it pointed has gone by the time you let go, such as a question answered in T3, your words wait in the box instead. Your words don't show over the cat while they're going into a box. Messages only counts while its box has the keyboard, and then it wins over a Fix box left open behind it. Open behind your work, it doesn't change what the talk key does, and closing it while you talk sends your words nowhere, even if you open it again before letting go. Where your words go is decided when the key goes down, so if the box closes before you've finished, they go nowhere rather than to the router, and a question you started before opening the box stays a question.

Secure Keyboard Entry and password fields can hide key events from taps, which is why that timer exists. It may also mean hold keys don't start there, which is fine, since there's nowhere safe to type.

### Fn and the Globe key

macOS acts on the Globe key itself, under **System Settings > Keyboard > Press 🌐 key to**:

| Setting | `AppleFnUsageType` | When you let go |
|---|---:|---|
| Do Nothing | 0 | Nothing. This is what to use |
| Change Input Source | 1 | Can switch your keyboard layout |
| Show Emoji & Symbols | 2 | Can pop up the emoji picker over your text |
| Start Dictation | 3 | Can start Apple's dictation too |

A listen-only tap can't stop this, and swallowing the key wouldn't be right anyway. Other dictation apps, including PersonalWisper, tell people to choose Do Nothing, and so should we. `KeyHoldMonitor.globeAction` reads the setting (`nil` means it was never changed, as on this Mac) and `KeyHoldMonitor.openKeyboardSettings()` opens the pane, so onboarding can check it and offer to help. Nothing changes the setting on its own.

Whether a long hold avoids the action is unknown, because the physical key can't be pressed from here, so that's a check by hand. Many third-party keyboards handle Fn in firmware and macOS never sees it, so for those right Option or right Control is the choice.

## Inserting text

`TextInserter` looks at the focused field first. It refuses password fields. It reads the text around the cursor, adding a space after a word, and dropping a capital mid-sentence or a full stop mid-line.

Native text fields then get the text through Accessibility, which leaves your clipboard alone. The text is read back to prove it landed, because some apps report success and do nothing. Everything else gets a paste:

1. Every type of every clipboard item is saved.
2. The text goes on the clipboard marked `org.nspasteboard.TransientType` and `AutoGeneratedType`, so clipboard managers skip it.
3. A synthetic Command-V is sent from a private event source, so a key you're holding can't turn it into a different shortcut. The key is looked up on your current layout, so Dvorak works.
4. 0.6 s later the clipboard is put back, also marked transient, unless you've copied something new.

Web views, terminals and Electron apps go straight to paste (`pasteOnlyPrefixes`), since that list is where Accessibility is known to misbehave. Only TextEdit has been tested, so the list comes from what other projects report, and it's worth correcting with real use.

Tested in a real TextEdit window with `probe-voice insert-test`: Accessibility insert in 6 to 59 ms, spacing between sentences, replacing a selection, Command-Z undoing both an Accessibility insert and a paste, and the clipboard coming back intact.

A rewrite from the cat goes in the same way, through `replaceSelection`, with three differences. It only goes in if the field in front is in the same app and still has exactly the text that was selected when you asked. It never pastes, because a paste can't be read back to prove it landed, so apps on the paste-only list say no. And it doesn't fit the text to what's around it, only keeps the spaces and line breaks the selection had at each end. When it says no, the app copies the rewrite and says so. Undo takes it back in Cocoa text views. The insert test above saw that in TextEdit, and a script setting a Cocoa text view's selected text through `setAccessibilitySelectedText` saw one Undo put the original back, line break and all.

Two things to know from that test:

- **Undo can take back more than the last insert.** TextEdit sometimes merged inserts made close together, so one Command-Z removed two of them. It varied between runs.
- **The tool's "Paste inserted the text" check can fail wrongly.** It expects text that the undo step before it may have already removed. In the last run it printed FAIL with the paste landed correctly: `The build is green. Pasted with a transient clipboard.`

## Wiring it up

```swift
let engine = ParakeetVoiceEngine()
let inserter = TextInserter()
let keys = KeyHoldMonitor()

engine.onSetupProgress = { progress in /* stage and fraction, for a first-run bubble */ }
Task {
    try await engine.prepare()
    engine.setVocabulary(settings.vocabulary + projectNames)
}

// Called on the main thread.
keys.onPress = { key in
    // Take the screen snapshot here first for the talk key, before any UI.
    do { try engine.begin() } catch { /* error.localizedDescription is ready to show */ }
}
keys.onCancel = { _ in engine.cancel() }
keys.onRelease = { key in
    Task {
        let transcript = try await engine.end()
        guard !transcript.cleaned.isEmpty else { return }
        if key == settings.dictateKey {
            try await inserter.insert(transcript.cleaned)
        } else {
            // Ask the cat. `cleaned` is what you meant, and `raw` is what you said.
        }
    }
}
try keys.start(keys: [settings.talkKey, settings.dictateKey])

Task { for await text in engine.partials { /* the bubble. "" means a new take started */ } }
Task { for await level in engine.levels { /* 0 to 1 */ } }
```

`onCancel` isn't part of `KeyHoldMonitoring`, so hold on to the concrete type. `ShadesCore` didn't need to change.

### What the app has to do

**Info.plist**

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Shades listens only while you hold your talk or dictate key.</string>
```

macOS kills an app that opens the mic without this.

**Signing.** Hardened Runtime needs the `com.apple.security.device.audio-input` entitlement. The App Sandbox has to stay off, because the event tap and synthetic keystrokes don't work inside it.

**Bundling.** `llama` is a dynamic framework. Copy it, keeping its symlinks, and sign it:

```bash
ditto .build/release/llama.framework Shades.app/Contents/Frameworks/llama.framework
codesign --force --sign "$IDENTITY" Shades.app/Contents/Frameworks/llama.framework
```

Without it the app won't launch. `Package.swift` already sets the rpath for that location. This was tested by running the probe from that layout, ad-hoc signed, with the model working. FluidAudio's resource bundle is only used by its text-to-speech, so it doesn't need copying.

**Permissions**, none of which prompt until you ask:

| For | Check | Ask |
|---|---|---|
| Microphone | `MicrophoneSource.authorization` | `await MicrophoneSource.requestAccess()` |
| Hold keys (Input Monitoring) | `KeyHoldMonitor.hasPermission` | `KeyHoldMonitor.requestPermission()`, then usually a relaunch before `start(keys:)` works |
| Typing (Accessibility) | `TextInserter.hasPermission` | `TextInserter.requestPermission()` |

Grants belong to the app's signature, so a rebuild signed differently loses them. Use a stable signing identity while developing.

**Credits.** Add to the README, and use this exact name anywhere the model appears, since its licence requires it: **S1-mini by Superwhisper**. See [Licences](#licences).

## Check by hand

These need a person, a microphone and a real keyboard. Build first with `swift build -c release --product probe-voice`. Both commands that use the mic ask for permission on behalf of your terminal.

1. **Mic start.** `.build/release/probe-voice mic --ask --runs 10`. The orange dot should appear and go away ten times per backend, and be off before the first and after the last. Compare the two "first audio" numbers. Under 50 ms is what you want, and under 100 ms is fine. Write them down here, because they're the biggest unknown.
2. **The whole thing.** Click into a text field, run `.build/release/probe-voice dictate`, then hold fn or right Option and talk. It prints what it heard, the cleaned text, where the time went, and how fast the mic opened. Use `--no-insert` to only print.
3. **The first word.** Say "Testing one two" starting at the same instant you press. Do it ten times. If "Testing" goes missing more than once or twice, compare the mic number from step 1 with the table in [The first word](#the-first-word).
4. **The last word.** Let go right as you finish a word. Ten times. It should survive.
5. **Your own speech.** Try "let's meet at three, no, actually four", "um so I think we should uh ship it", "first install it, second run it, third test it", "new paragraph", and your project names.
6. **Fn.** Run `.build/release/probe-voice keys`.
   - With **Press 🌐 key to** on its current setting, hold fn for 2 s and let go. Does the picker or Apple's dictation appear? Note what the setting was.
   - Set it to **Do Nothing** and repeat. Nothing should appear.
   - Fn + arrow should print `press` then `cancel`, and the arrow should still work.
7. **Left and right**, in the same tool. Left Option, left Command and left Control should print nothing. Right ones print `press` and `release`. Right Option + E within a second should print `cancel` and still type an accent. A quick tap should print `press` then `cancel`.
8. **Other apps.** With `dictate` running, dictate into each of these, and check the text lands once, and that Command-Z removes it: Notes, Mail, Safari address bar, a text box on a web page, Chrome, Slack, VS Code, Terminal, T3 Code. Note where it inserts twice, not at all, or in the wrong place, and where one Command-Z takes back more than the last dictation.
9. **The clipboard.** Copy something, then dictate into Chrome. Paste it afterwards, and you should get what you copied. If you use a clipboard manager, the dictated text shouldn't be in its history.
10. **Password fields.** Dictate into a login form. It should refuse with a message and type nothing.
11. **Bluetooth.** With AirPods connected and music playing, dictate. The music should keep playing at full quality.
12. **Lid closed.** With an external mic and the lid closed, dictate. It should use the external mic.
13. **Going idle.** Leave it for 10 minutes and dictate once. It should feel the same as any other time.

## Running the benchmark

```bash
swift build -c release --product probe-voice
.build/release/probe-voice bench              # everything through the real engine, about 25 minutes
.build/release/probe-voice bench --quick      # two voices, about 8 minutes
.build/release/probe-voice asr ultra v3 v2
.build/release/probe-voice cleanup raw rules s1 s1-lower s1-pre
.build/release/probe-voice cleanup raw rules s1 s1-lower s1-pre --held-out
.build/release/probe-voice vocabulary
.build/release/probe-voice vocabulary --changes --distractors
.build/release/probe-voice clipping
.build/release/probe-voice partials
.build/release/probe-voice idle
.build/release/probe-voice insert-test        # opens TextEdit on a temp file, then closes it
.build/release/probe-voice keys-selftest      # posts synthetic modifier events
```

Clips are generated with `say` and `afconvert` in a temp folder. Nothing goes in the repo, and the probe keeps no audio or transcripts from a microphone anywhere.

## Licences

| What | Licence | Note |
|---|---|---|
| [FluidAudio](https://github.com/FluidInference/FluidAudio) | Apache 2.0 | Dependency |
| [llama.cpp](https://github.com/ggml-org/llama.cpp) | MIT | Prebuilt `b12121` framework, checksum pinned in `Package.swift` |
| [Parakeet Ultra](https://huggingface.co/FluidInference/parakeet-ultra-coreml), from [moondream/parakeet-ultra](https://huggingface.co/moondream/parakeet-ultra) and NVIDIA's Parakeet TDT 0.6B v3 | CC BY 4.0 | Downloaded on first use. Attribution required |
| [Parakeet CTC 110M](https://huggingface.co/FluidInference/parakeet-ctc-110m-coreml) | CC BY 4.0 | Downloaded when you have a vocabulary. Attribution required |
| [S1-mini by Superwhisper](https://huggingface.co/superwhisper/s1-mini), from [Qwen3-0.6B](https://huggingface.co/Qwen/Qwen3-0.6B) | Apache 2.0 plus a naming term | Downloaded on first use at a pinned revision and checked against its SHA-256. The model must keep the name "S1-mini" by "Superwhisper" wherever it's used. If you ever redistribute the weights yourself, the LICENSE and NOTICE go with them |

Used only for comparison and never shipped: Parakeet v2, v3, EOU and Bark 3.0 Clean (all CC BY 4.0), and Qwen3 1.7B (Apache 2.0).

The reference projects were read for ideas and none of their code was copied: [Local Dictation](https://github.com/ikamal97/local-dictation) (MIT), [Hold to Talk](https://github.com/edamame-labs/hold-to-talk) (Apache 2.0), [PersonalWisper](https://github.com/tt728091-cloud/personalwisper) (MIT), [betterwispr](https://github.com/opennookorg/betterwispr) (Apache 2.0) and [voz](https://github.com/Joelheile/voz) (MIT). The GPL projects weren't opened.
