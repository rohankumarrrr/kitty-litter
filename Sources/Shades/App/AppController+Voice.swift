import Foundation
import ShadesCore

/// Talk goes through the Ask flow. Dictate only ever goes to the cursor.
extension AppController {
    /// A box is up that what you say belongs in, so nothing needs a look at the screen.
    var boxTakesVoice: Bool { fixIsOpen || dropIsOpen }
    private var talkBoxIsStillUp: Bool { stage.isInputVisible && talkBox == boxesOpened }

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

    /// A box's mic was pressed. The first press talks into that box, as the talk key does while you type there, and the
    /// next one finishes what you said.
    func micPressed(in box: VoiceBox) {
        switch voiceMode {
        case nil:
            talkDown(into: box)
            finishAtTheLimit(box)
        // Only a take for a box finishes here, so a mic can't send a look the talk key took to the router.
        case .talk where hearing && boxTakesVoiceNow:
            voiceTask = Task { await talkUp() }
        default:
            break
        }
    }

    /// The engine turns the mic off once a take reaches its limit. With no key to let go of, the take finishes then, so
    /// the mic doesn't go on showing it's hearing you.
    private func finishAtTheLimit(_ box: VoiceBox) {
        guard voiceMode == .talk else { return }
        let take = takes
        Task { [weak self, longestMicTake] in
            try? await Task.sleep(nanoseconds: UInt64(longestMicTake * 1_000_000_000))
            guard let self, self.takes == take else { return }
            self.micPressed(in: box)
        }
    }

    /// `box` is the box whose mic was pressed. Without one, it's the talk key.
    func talkDown(into box: VoiceBox? = nil) {
        guard voiceMode == nil else { return }
        switch box {
        case nil:
            // Messages' box only counts if you're typing in it, not if it's open behind your work. When you are, it has
            // the keyboard, so it wins over a Fix or drop box left open behind it.
            talkToMessages = stage.isMessagesBoxTyping ? messagesClosings : nil
            talkBox = boxTakesVoice && talkToMessages == nil ? boxesOpened : nil
        case .ask:
            talkToMessages = nil
            talkBox = stage.isInputVisible ? boxesOpened : nil
        case .messages:
            talkToMessages = stage.isMessagesBoxTyping ? messagesClosings : nil
            talkBox = nil
        }
        // A mic is only ever for its own box, so it never looks at the screen.
        guard box == nil || boxTakesVoiceNow else { return }
        if talkToMessages != nil { stage.holdMessagesBox() }
        // The look happens as the key goes down: that's the moment you mean.
        if !boxTakesVoiceNow { talkLook = startLook(CaptureOptions()) }
        guard beginListening(.talk) else {
            talkLook = nil
            if talkToMessages != nil { stage.releaseMessagesBox() }
            talkToMessages = nil
            return
        }
        stage.catWake()
        if !boxTakesVoiceNow {
            stage.hideInput()
            heard = ""
            renderBubble()
        }
    }

    func talkUp() async {
        // A take that was cancelled, such as by its box closing, has nothing left to finish.
        guard hearing, voiceMode == .talk else { return }
        let take = takes
        let forMessages = talkToMessages != nil
        hearing = false
        stage.catLevel(0)
        heard = nil
        renderBubble()
        do {
            let transcript = try await voice.end()
            // Cancelled while it was worked out, or another take has started, which owns where words go now.
            guard take == takes else { return }
            voiceMode = nil
            refreshStatus()
            let text = transcript.cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            if talkBox != nil {
                // Saying it counts as pressing Return. If the box has gone, you meant never mind, not ask the cat.
                if !text.isEmpty, talkBoxIsStillUp { stage.submitInput(text) }
                return
            }
            if forMessages {
                // The same goes for Messages: if you've stopped typing there, closed it or cancelled, it isn't sent anywhere.
                let held = talkToMessages
                talkToMessages = nil
                if !text.isEmpty, let held, held == messagesClosings, stage.isMessagesBoxTyping {
                    stage.sendInMessages(text)
                } else {
                    stage.releaseMessagesBox()
                }
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
            guard take == takes else { return }
            voiceMode = nil
            talkLook = nil
            if talkToMessages != nil { stage.releaseMessagesBox() }
            talkToMessages = nil
            refreshStatus()
            say(CatWords.problem(error, while: .listening))
        }
    }

    /// A box what you say belongs in was up when the key went down, so nothing needs a look at the screen.
    private var boxTakesVoiceNow: Bool { talkBox != nil || talkToMessages != nil }

    /// The box that's hearing you, for its mic to show it.
    var listeningBox: VoiceBox? {
        guard hearing, voiceMode == .talk else { return nil }
        return talkToMessages != nil ? .messages : talkBox != nil ? .ask : nil
    }

    /// Every box over the cat goes up through here, numbered so words meant for one can't land in the next. What you're
    /// saying into it is forgotten when it closes, since there's nowhere left for it and no mic left to finish it with.
    func showBox(_ request: InputRequest) {
        // One that was still up, such as an Ask box opened while you were pointing for a Fix, closes first.
        if stage.isInputVisible { stage.hideInput() }
        boxesOpened += 1
        let box = boxesOpened
        var request = request
        let submit = request.onSubmit, cancel = request.onCancel
        request.onSubmit = { [weak self] text in
            self?.boxClosed(box)
            submit(text)
        }
        request.onCancel = { [weak self] in
            self?.boxClosed(box)
            cancel()
        }
        stage.showInput(request)
    }

    private func boxClosed(_ box: Int) {
        if hearing, talkBox == box { cancelListening() }
    }

    func dictateDown() {
        guard voiceMode == nil, beginListening(.dictate) else { return }
        stage.catHold(CatWords.listening)
    }

    func dictateUp() async {
        let take = takes
        hearing = false
        stage.catLevel(0)
        stage.catHold(nil)
        do {
            let transcript = try await voice.end()
            guard take == takes else { return }
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
            guard take == takes else { return }
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
        takes += 1
        hearing = true
        refreshStatus()
        return true
    }

    /// Esc while holding the key means forget it.
    func cancelListening() {
        takes += 1
        voice.cancel()
        hearing = false
        stage.catLevel(0)
        stage.catHold(nil)
        voiceMode = nil
        heard = nil
        talkLook = nil
        if talkToMessages != nil { stage.releaseMessagesBox() }
        talkToMessages = nil
        renderBubble()
    }

    func heardSoFar(_ text: String) {
        guard hearing, voiceMode == .talk else { return }
        if boxTakesVoiceNow {
            // Words for a box show in that box, if any, never over the cat as if you were asking it.
            if talkBoxIsStillUp { stage.setInputText(text) }
        } else {
            heard = text
            renderBubble()
        }
    }

    func levelHeard(_ level: Float) {
        if hearing { stage.catLevel(level) }
    }

    /// The first run downloads the speech models. Loading them from disk later is quick
    /// and needs no comment, so this only speaks up once it's clearly a download.
    func fetchingEars(_ fraction: Double?) {
        guard let fraction else {
            if fetchingEarsLine {
                fetchingEarsLine = false
                line = nil
                renderBubble()
            }
            return
        }
        let since = fetchingEarsSince ?? now()
        fetchingEarsSince = since
        // Anything else the cat is saying matters more than this.
        guard now().timeIntervalSince(since) > 2, fraction < 1, line == nil || fetchingEarsLine else { return }
        let text = CatWords.fetchingEars(fraction)
        guard line?.text != text else { return }
        fetchingEarsLine = true
        say(text)
    }
}
