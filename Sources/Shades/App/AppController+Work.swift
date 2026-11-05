import Foundation
import ShadesCore

/// As much of your screen as a kitten gets to see.
struct SharedScreen {
    var snapshot: ScreenSnapshot?
    var leftOut: Bool
}

/// Something that can go to a kitten. Only your words and your yes make one, and it isn't
/// Codable, so nothing read from a folder can ever become one.
struct ReadyWork {
    enum Words {
        case yours(String, SharedScreen)
        /// What you said, and exactly what you saw when you said it.
        case yes(String, to: String)
    }

    let itemID: String
    let kittenID: String
    /// What goes on the list if the file has lost it.
    let listText: String
    let words: Words
    var tried = false
    /// Saved the first time it tries to go, so another try doesn't leave another copy behind.
    var screenshotPath: String?
}

/// A copy of something on a list, fixed when it's shown, so changing the file later changes nothing.
struct Offer: Equatable {
    let itemID, kittenID, caption, text: String
}

enum OfferAnswer: Equatable {
    case yes, no

    private static let yeses: Set<String> = ["yes", "yep", "yeah", "yes please", "yes, please", "go ahead", "do it", "start it"]
    private static let nos: Set<String> = ["no", "nope", "no thanks", "no, thanks", "skip it", "drop it"]
    /// These don't answer an offer, since a yes has to be plain, but they aren't a request either.
    private static let otherBareAnswers: Set<String> = [
        "ok", "okay", "sure", "yup", "y", "n", "nah", "not now", "sounds good", "go for it", "please do",
        "yes go ahead", "yes, go ahead", "yes do it", "yes, do it",
    ]

    static func plain(_ words: String) -> String {
        words.lowercased().trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?,;:…\"'")))
    }

    /// Something that only means anything as an answer to something.
    static func isBare(_ words: String) -> Bool {
        OfferAnswer(words) != nil || otherBareAnswers.contains(plain(words))
    }

    /// A closed list, so "yes, but only the main branch" is no answer, and goes to the router as usual.
    init?(_ words: String) {
        let said = Self.plain(words)
        if Self.yeses.contains(said) {
            self = .yes
        } else if Self.nos.contains(said) {
            self = .no
        } else {
            return nil
        }
    }
}

/// A kitten's list is a record, never permission. Everything sent comes from `ready`, and anything
/// on a list with nothing in `ready` behind it needs your yes first, however it got there.
extension AppController {
    /// Every kitten taking work. Safe to run any time.
    func tendWork() {
        guard threadListArrived else { return }
        for kitten in loadKittens() where !kitten.planned { tend(kitten) }
    }

    /// Brings one kitten's list up to date with its threads, starts what there's room for, and
    /// offers what needs a yes. Returns whether `announcing` went out.
    @discardableResult
    func tend(_ kitten: Kitten, announcing: String? = nil) -> Bool {
        let at = now()
        let before = workLists.load(for: kitten)
        var list = before
        if threadListArrived { followEndings(in: &list, at: at) }

        // A thread that's being reported on may yet turn out to have passed its work on, or pick up again.
        var room = KittenBoard.room(for: kitten, list: list, threads: latestThreads, now: at)
            - ready.filter { $0.kittenID == kitten.id && sending.contains($0.itemID) }.count
            - list.items.filter { $0.state == .working && $0.threadID.map(reporting.contains) == true }.count
        var wentOut = false
        for work in ready where work.kittenID == kitten.id && !sending.contains(work.itemID) && room > 0 {
            room -= 1
            wentOut = wentOut || work.itemID == announcing
            send(work, to: kitten, announcing: work.itemID == announcing && !work.tried)
        }

        tendOffers(from: kitten, list: list)
        if list != before { try? workLists.save(list, for: kitten) }
        if stage.isKittensVisible { stage.showKittens(kittenStatuses) }
        return wentOut
    }

    private func followEndings(in list: inout WorkList, at: Date) {
        for var item in list.items {
            let thread = latestThreads.first { $0.id == item.threadID }
            switch item.state {
            case .working:
                if let id = item.threadID, reporting.contains(id) { continue }
                switch KittenBoard.ending(of: item, threads: latestThreads, now: at) {
                case .report(let thread, let failed):
                    follow(thread, failed: failed, in: &list, at: at)
                case .stopped:
                    item.state = .stopped
                    item.changedAt = at
                    list.put(item)
                case nil:
                    break
                }
            case .stopped:
                guard let thread else { continue }
                if thread.status.isActive {
                    item.state = .working
                    item.changedAt = at
                    list.put(item)
                } else if thread.status == .completed, thread.updatedAt > item.changedAt {
                    // Someone picked it up again and finished it, perhaps while the app was closed.
                    follow(thread, failed: false, in: &list, at: at)
                }
            case .proposed, .waiting, .dropped:
                break
            }
        }
    }

    /// You only hear about an ending once. If that's been done, all that's left is the list,
    /// which couldn't be saved at the time.
    private func follow(_ thread: AgentThread, failed: Bool, in list: inout WorkList, at: Date) {
        if reportedAt[thread.id] == thread.updatedAt {
            list.endWork(in: thread.id, as: failed ? .stopped : nil, at: at)
        } else {
            reportOn(thread, failed: failed)
        }
    }

    private func tendOffers(from kitten: Kitten, list: WorkList) {
        let needsYes: (WorkItem) -> Bool = { item in
            [.proposed, .waiting, .stopped].contains(item.state)
                && !self.ready.contains { $0.itemID == item.id }
                && item.threadID.map(self.reporting.contains) != true
        }
        let before = notices.count
        notices.removeAll { notice in
            guard let offer = notice.offer, offer.kittenID == kitten.id else { return false }
            return !list.items.contains { $0.id == offer.itemID && needsYes($0) }
        }
        if notices.count != before { renderBubble() }

        guard !notices.contains(where: { $0.offer?.kittenID == kitten.id }),
              let item = list.items.first(where: { needsYes($0) && !putOff.contains($0.id) })
        else { return }
        let offer = Offer(itemID: item.id, kittenID: kitten.id, caption: CatWords.offerCaption(kitten, item), text: item.text)
        post(caption: offer.caption, text: CatWords.offerText(offer.text), threadID: nil, offer: offer)
    }

    // MARK: - Sending

    func updateList(of kitten: Kitten, _ change: (inout WorkList) -> Void) throws {
        var list = workLists.load(for: kitten)
        change(&list)
        try workLists.save(list, for: kitten)
    }

    /// On the list first, so a failed save means nothing goes out, and nothing's lost if a thread dies.
    func takeOn(_ item: WorkItem, words: ReadyWork.Words, for kitten: Kitten) {
        do {
            try updateList(of: kitten) { $0.put(item) }
        } catch {
            say(CatWords.cantWriteList(kitten))
            return
        }
        ready.append(ReadyWork(itemID: item.id, kittenID: kitten.id, listText: item.text, words: words))
        startOrSayItsWaiting(item.id, for: kitten)
    }

    func startOrSayItsWaiting(_ itemID: String, for kitten: Kitten) {
        guard !tend(kitten, announcing: itemID) else { return }
        let ahead = ready.prefix { $0.itemID != itemID }.filter { $0.kittenID == kitten.id }.count
        say(CatWords.onTheList(kitten, ahead: ahead))
    }

    /// As with a session, a kitten with full access doesn't get to see text from a page.
    func sharedScreen(with kitten: Kitten, from snapshot: ScreenSnapshot?) -> SharedScreen {
        let seesScreen = kitten.seesScreen && settings.frontierMode != .fullAccess
        return SharedScreen(snapshot: seesScreen ? snapshot : nil, leftOut: !seesScreen && snapshot != nil)
    }

    /// The one way anything reaches a new kitten thread, so a request sent later can't differ from one sent now.
    private func send(_ work: ReadyWork, to kitten: Kitten, announcing: Bool) {
        sending.insert(work.itemID)
        flow = Task {
            guard let projectID = await backend.projectID(atPath: kitten.folder) else {
                gaveUp(on: work.itemID, saying: CatWords.notSetUp(kitten))
                return
            }
            let text: String
            var title: String?
            var shared: ScreenSnapshot?
            switch work.words {
            case .yours(let words, let screen):
                // It may have waited a while, and what this kitten can see may have changed since.
                let current = sharedScreen(with: loadKittens().first { $0.id == kitten.id } ?? kitten, from: screen.snapshot)
                shared = current.snapshot
                let path = shared == nil ? nil : work.screenshotPath ?? saveScreenshot(of: shared)
                if let index = ready.firstIndex(where: { $0.itemID == work.itemID }) { ready[index].screenshotPath = path }
                text = Prompts.forKitten(
                    words: words,
                    snapshot: shared,
                    screenshotPath: path,
                    screenLeftOut: screen.leftOut || current.leftOut
                )
            case .yes(let words, let note):
                text = Prompts.approved(yes: words, note: note)
                // T3 would write its title from "yes", which says nothing about the work.
                title = "\(kitten.name): \(note.prefix { !$0.isNewline })"
            }
            startFrontier(
                title: title,
                text: text,
                snapshot: shared,
                projectID: projectID,
                name: kitten.name,
                announce: announcing,
                onStarted: { [weak self] threadID in self?.started(work, in: threadID, for: kitten) },
                onGaveUp: { [weak self] in self?.gaveUp(on: work.itemID, saying: CatWords.stillOnTheList(kitten)) }
            )
        }
    }

    private func started(_ work: ReadyWork, in threadID: String, for kitten: Kitten) {
        ready.removeAll { $0.itemID == work.itemID }
        sending.remove(work.itemID)
        threadOwners[threadID] = kitten.id
        // A put rather than a change, so a kitten that deleted the line can't lose it.
        let item = WorkItem(id: work.itemID, text: work.listText, state: .working, threadID: threadID, at: now())
        try? updateList(of: kitten) { $0.put(item) }
    }

    /// It stays in `ready`, and goes when the next look at the list finds it can. You hear about
    /// the first try that fails, whether or not it waited its turn, but not every one after.
    private func gaveUp(on itemID: String, saying line: String) {
        sending.remove(itemID)
        guard let index = ready.firstIndex(where: { $0.itemID == itemID }), !ready[index].tried else { return }
        ready[index].tried = true
        say(line)
    }

    // MARK: - Ending

    /// Every kitten whose list says this thread is its work. It's every one because a kitten can
    /// write anything on its own list, and a false claim mustn't leave the real item stranded.
    func listOwners(of thread: String) -> [Kitten] {
        loadKittens().filter { !$0.planned && workLists.load(for: $0).holds(thread: thread) }
    }

    func workEnded(in thread: String, failed: Bool) {
        for owner in listOwners(of: thread) {
            try? updateList(of: owner) { $0.endWork(in: thread, as: failed ? .stopped : nil, at: now()) }
            tend(owner)
        }
    }

    // MARK: - Your answer

    /// An offer only counts if it's showing both when you start and when you finish. One that
    /// appears mid-sentence, or gets covered before you're done, isn't what you were answering.
    var offerShowing: Offer? {
        guard case .notice? = currentBubble else { return nil }
        return notices.first?.offer
    }

    /// Only your typed or spoken words get here. No model is involved, and a marker can't answer.
    func takeWords(_ words: String, capture: Task<Capture, Never>?) {
        let offer = offerWhenAsked
        offerWhenAsked = nil
        if let offer, offerShowing == offer, let answer = OfferAnswer(words) {
            answerOffer(offer, answer, words: words)
        } else {
            ask(words, capture: capture)
        }
    }

    func answerOffer(_ offer: Offer, _ answer: OfferAnswer, words: String) {
        notices.removeAll { $0.offer == offer }
        renderBubble()
        guard let kitten = loadKittens().first(where: { $0.id == offer.kittenID && !$0.planned }) else {
            say(CatWords.lostTheSession)
            return
        }
        switch answer {
        case .yes:
            takeOn(
                WorkItem(id: offer.itemID, text: offer.text, state: .waiting, at: now()),
                words: .yes(words, to: offer.text),
                for: kitten
            )
        case .no:
            do {
                try updateList(of: kitten) { list in
                    guard var item = list.items.first(where: { $0.id == offer.itemID }) else { return }
                    item.state = .dropped
                    item.changedAt = now()
                    list.put(item)
                }
            } catch {
                say(CatWords.cantWriteList(kitten))
                return
            }
            say(CatWords.dropped)
            tend(kitten)
        }
    }

    /// Asking also brings back anything you put off, since you're clearly thinking about it now.
    func showList(of kitten: Kitten) {
        putOff.subtract(workLists.load(for: kitten).items.map(\.id))
        tend(kitten)
        reply = Reply(text: CatWords.list(of: kitten, workLists.load(for: kitten)), done: true)
        renderBubble()
    }
}
