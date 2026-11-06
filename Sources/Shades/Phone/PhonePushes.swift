import CryptoKit
import Foundation

/// Notifications on paired phones. Each says only who and what kind, as on the Mac, since a phone shows it on the
/// lock screen and its push service carries it. Where each phone takes them, and the key Shades signs them with, are
/// kept in the Keychain, since either would let something else send to your phone as Shades.
@MainActor
final class PhonePushes {
    /// Enough for every phone and browser you'd pair, and no more for a phone to pile up.
    private static let most = 8

    private let keys: PhoneKeyStoring
    /// Sends one request, and returns its status, or `nil` if it didn't get anywhere.
    private let send: (URLRequest) async -> Int?
    private var subscriptions: [WebPush.Subscription]
    private var signingKey: P256.Signing.PrivateKey?

    init(keys: PhoneKeyStoring, send: @escaping (URLRequest) async -> Int?) {
        self.keys = keys
        self.send = send
        subscriptions = keys.load(PhoneKeys.pushes).compactMap { try? JSONDecoder().decode(WebPush.Subscription.self, from: Data($0.utf8)) }
    }

    /// What a phone subscribes with, so its push service only takes notifications Shades signed.
    var publicKey: String {
        WebPush.string(signing.publicKey.x963Representation)
    }

    /// Whether it's somewhere a phone's notifications can go. Subscribing again replaces the one before.
    func subscribe(_ subscription: WebPush.Subscription) -> Bool {
        guard subscription.isValid else { return false }
        subscriptions.removeAll { $0.endpoint == subscription.endpoint }
        subscriptions = Array((subscriptions + [subscription]).suffix(Self.most))
        save()
        return true
    }

    /// Fire and forget. A phone whose push service says it's gone stops getting them.
    @discardableResult
    func push(_ alert: NeedsYouAlert, now: Date) -> Task<Void, Never>? {
        guard !subscriptions.isEmpty else { return nil }
        struct Payload: Encodable {
            var title: String
            var tag: String
        }
        guard let payload = try? JSONEncoder().encode(Payload(title: CatWords.notification(alert), tag: alert.id)) else { return nil }
        let requests = subscriptions.compactMap { subscription in
            (try? WebPush.request(payload, to: subscription, key: signing, now: now)).map { (subscription.endpoint, $0) }
        }
        return Task { [send] in
            for (endpoint, request) in requests {
                guard let status = await send(request), status == 404 || status == 410 else { continue }
                subscriptions.removeAll { $0.endpoint == endpoint }
                save()
            }
        }
    }

    private var signing: P256.Signing.PrivateKey {
        if let signingKey { return signingKey }
        let saved = keys.load(PhoneKeys.signing).first.flatMap(WebPush.data).flatMap { try? P256.Signing.PrivateKey(rawRepresentation: $0) }
        let key = saved ?? P256.Signing.PrivateKey()
        if saved == nil { keys.save(PhoneKeys.signing, [WebPush.string(key.rawRepresentation)]) }
        signingKey = key
        return key
    }

    private func save() {
        keys.save(PhoneKeys.pushes, subscriptions.compactMap { (try? JSONEncoder().encode($0)).map { String(decoding: $0, as: UTF8.self) } })
    }
}
