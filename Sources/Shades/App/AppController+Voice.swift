import Foundation
import ShadesCore

extension AppController {
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

    func micPressed(in box: VoiceBox) {
        switch voiceMode {
        case nil:
            talkDown(into: box)
            finishAtTheLimit(box)
        case .talk where hearing && boxTakesVoiceNow:
            voiceTask = Task { await talkUp() }
        default:
            break
        }
    }

    private func finishAtTheLimit(_ box: VoiceBox) {
        guard voiceMode == .talk else { return }
        let take = takes
        Task { [weak self, longestMicTake] in
            try? await Task.sleep(nanoseconds: UInt64(longestMicTake * 1_000_000_000))
            guard let self, self.takes == take else { return }
            self.micPressed(in: box)
        }
    }

    func talkDown(into box: VoiceBox? = nil) {
        guard voiceMode == nil else { return }
        switch box {
        case nil:
            talkToMessages = stage.isMessagesBoxTyping ? messagesClosings : nil
            talkBox = boxTakesVoice && talkToMessages == nil ? boxesOpened : nil
        case .ask:
            talkToMessages = nil
            talkBox = stage.isInputVisible ? boxesOpened : nil
        case .messages:
            talkToMessages = stage.isMessagesBoxTyping ? messagesClosings : nil
            talkBox = nil
        }
        guard box == nil || boxTakesVoiceNow else { return }
        if talkToMessages != nil { stage.holdMessagesBox() }
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
        guard hearing, voiceMode == .talk else { return }
        let take = takes
        let forMessages = talkToMessages != nil
        hearing = false
        stage.catLevel(0)
        heard = nil
        renderBubble()
        do {
            let transcript = try await voice.end()
            guard take == takes else { return }
            voiceMode = nil
            refreshStatus()
            let text = transcript.cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            if talkBox != nil {
                if !text.isEmpty, talkBoxIsStillUp { stage.submitInput(text) }
                return
            }
            if forMessages {
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

    private var boxTakesVoiceNow: Bool { talkBox != nil || talkToMessages != nil }

    var listeningBox: VoiceBox? {
        guard hearing, voiceMode == .talk else { return nil }
        return talkToMessages != nil ? .messages : talkBox != nil ? .ask : nil
    }

    func showBox(_ request: InputRequest) {
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
            if talkBoxIsStillUp { stage.setInputText(text) }
        } else {
            heard = text
            renderBubble()
        }
    }

    func levelHeard(_ level: Float) {
        if hearing { stage.catLevel(level) }
    }

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
        guard now().timeIntervalSince(since) > 2, fraction < 1, line == nil || fetchingEarsLine else { return }
        let text = CatWords.fetchingEars(fraction)
        guard line?.text != text else { return }
        fetchingEarsLine = true
        say(text)
    }
}
