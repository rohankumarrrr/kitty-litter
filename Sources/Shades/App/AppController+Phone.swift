import Foundation
import ShadesCore

/// Messages on your phone, over your tailnet. It's Messages itself, held open while a phone is looking, so what you
/// do there goes through `messagesAction` like the window, and never looks at your screen.
extension AppController {
    /// What Messages shows changed. A phone can keep it open while the window's closed, which then has nothing to show.
    func channelsChanged(_ book: ChannelBook) {
        if stage.isChannelsVisible { stage.updateChannels(book) }
        phone?.publish(book)
    }

    func startPhone() {
        guard phone == nil else { return }
        let link = PhoneLink(
            keys: phoneKeys,
            grace: phoneGrace,
            hold: { [weak self] in
                guard let self else { return nil }
                return self.channels.open(threads: self.latestThreads)
            },
            release: { [weak self] in
                guard let self, !self.stage.isChannelsVisible else { return }
                self.channels.close()
            },
            act: { [weak self] in self?.messagesAction($0) },
            now: now
        )
        link.onPaired = { [weak self] in
            self?.stage.showPairing(nil)
            self?.say(CatWords.phonePaired)
        }
        phone = link
        phoneTask = Task { [weak self] in
            do {
                let port = try await link.start(port: self?.phonePort ?? 0)
                guard let self, self.phone === link else { return link.stop() }
                self.phoneListening = port
                if await self.reachPhone(), !link.door.hasPhones { self.pairPhone() }
            } catch {
                guard let self, self.phone === link else { return }
                self.phone = nil
                self.say(CatWords.phoneProblem(error))
            }
        }
    }

    /// Off means off: the page goes from your tailnet, and every phone has to pair again.
    func stopPhone() {
        guard let link = phone else { return }
        phone = nil
        phoneAddress = nil
        link.stop()
        link.door.forgetPhones()
        stage.showPairing(nil)
        if let port = phoneListening {
            phoneListening = nil
            Task { [stopServingPhone] in await stopServingPhone(port) }
        }
    }

    /// Shows a new one-time code, and the address to open, which means asking Tailscale again if it hasn't said yet.
    func pairPhone() {
        guard let link = phone, phoneListening != nil else { return }
        Task {
            if phoneAddress == nil, !(await reachPhone()) { return }
            guard phone === link else { return }
            let pairing = link.door.openPairing(now: now())
            stage.showPairing(PhonePairingCard(address: phoneAddress, code: pairing.shown))
            try? await Task.sleep(nanoseconds: UInt64(max(pairing.until.timeIntervalSince(now()), 0) * 1_000_000_000))
            // Still showing the same code, which has run out.
            guard link.door.pairing == pairing else { return }
            link.door.closePairing()
            stage.showPairing(nil)
        }
    }

    func pairingClosed() {
        phone?.door.closePairing()
    }

    /// Whether the page is on your tailnet now. If it isn't, the cat says why.
    private func reachPhone() async -> Bool {
        guard let port = phoneListening else { return false }
        do {
            phoneAddress = try await servePhone(port)
            return true
        } catch {
            say(CatWords.phoneProblem(error))
            return false
        }
    }
}
