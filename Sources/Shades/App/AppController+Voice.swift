import Foundation
import ShadesCore

/// Talk goes through the Ask flow. Dictate only ever goes to the cursor.
extension AppController {
    func keyPressed(_ key: HoldKey) {
        if key == settings.talkKey {
            talkDown()
        } else if key == settings.dictateKey {
            dictateDown()
        }
    }

    func keyReleased(_ key: HoldKey) {
        if key == settings.talkKey, voiceMode == .talk {
            voiceTask = Task { await talkUp() }
        } else if key == settings.dictateKey, voiceMode == .dictate {
            voiceTask = Task { await dictateUp() }
        }
    }

    func talkDown() {
        guard voiceMode == nil else { return }
        // The look happens as the key goes down: that's the moment you mean.
        if !fixIsOpen { talkLook = startLook(CaptureOptions()) }
        guard beginListening(.talk) else {
            talkLook = nil
            return
        }
        stage.catWake()
        if !fixIsOpen {
            stage.hideInput()
            heard = ""
            renderBubble()
        }
    }

    func talkUp() async {
        hearing = false
        stage.catLevel(0)
        heard = nil
        renderBubble()
        do {
            let transcript = try await voice.end()
            voiceMode = nil
            refreshStatus()
            let text = transcript.cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            if fixIsOpen {
                // Saying it counts as pressing Return.
                if !text.isEmpty { stage.submitInput(text) }
                return
            }
            let capture = talkLook
            talkLook = nil
            guard !text.isEmpty else {
                say(CatWords.didntCatch)
                return
            }
            ask(text, capture: capture)
        } catch {
            voiceMode = nil
            refreshStatus()
            say(CatWords.problem(error, while: .listening))
        }
    }

    func dictateDown() {
        guard voiceMode == nil, beginListening(.dictate) else { return }
        stage.catHold(CatWords.listening)
    }

    func dictateUp() async {
        hearing = false
        stage.catLevel(0)
        stage.catHold(nil)
        do {
            let transcript = try await voice.end()
            voiceMode = nil
            refreshStatus()
            let text = transcript.cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            do {
                try await inserter.insert(text)
            } catch {
                say(CatWords.problem(error, while: .typing))
            }
        } catch {
            voiceMode = nil
            refreshStatus()
            say(CatWords.problem(error, while: .listening))
        }
    }

    func beginListening(_ mode: VoiceMode) -> Bool {
        do {
            try voice.begin()
        } catch {
            say(CatWords.problem(voiceProblem ?? error, while: .listening))
            if voiceProblem != nil { prepareVoice() }
            return false
        }
        voiceMode = mode
        hearing = true
        refreshStatus()
        return true
    }

    /// Esc while holding the key means forget it.
    func cancelListening() {
        voice.cancel()
        hearing = false
        stage.catLevel(0)
        stage.catHold(nil)
        voiceMode = nil
        heard = nil
        talkLook = nil
        renderBubble()
    }

    func heardSoFar(_ text: String) {
        guard hearing, voiceMode == .talk else { return }
        if fixIsOpen {
            stage.setInputText(text)
        } else {
            heard = text
            renderBubble()
        }
    }

    func levelHeard(_ level: Float) {
        if hearing { stage.catLevel(level) }
    }
}
