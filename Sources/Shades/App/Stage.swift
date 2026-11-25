import CoreGraphics
import Foundation
import ShadesContext
import ShadesCore

enum BubbleContent: Equatable {
    case thinking(note: String?)
    case listening(String)
    case reply(text: String, done: Bool, threadID: String?, note: String?, canReplace: Bool = false)
    case line(String, threadID: String?)
    case notice(caption: String, text: String, threadID: String?, asks: Bool = false)
    case approval(ApprovalRequest, position: Int, total: Int)
    case inbox(String)
}

enum BubbleAction: Equatable {
    case open(threadID: String)
    case show(threadID: String)
    case copy(String)
    case replace(String)
    case approval(ApprovalRequest, ApprovalDecision)
    case openMessages
    case settings(Permissions.Pane)
}

enum InboxAction: Equatable {
    case open(threadID: String)
    case done(id: String)
    case ignore(id: String)
    case clear(InboxEntry.Kind)
    case allow(id: String)
    case deny(id: String)
}

struct InputRequest {
    var placeholder: String
    var caption: String?
    var attachment: String? = nil
    var allowsEmpty: Bool
    var onSubmit: (String) -> Void
    var onCancel: () -> Void
}

enum VoiceBox {
    case ask, messages
}

@MainActor
protocol CatStage: AnyObject {
    func catWake()
    func catSay(_ word: String)
    func catHold(_ word: String?)
    func catStatus(_ status: CatStatus)
    func catLevel(_ level: Float)
    func catAgentsBusy(_ busy: Bool)
    func catCelebrate()
    func catPet()
    func catDoNotDisturb(_ on: Bool)
    func catComeToYou(arrived: @escaping () -> Void)
    func catRun(toRegion region: CGRect, arrived: @escaping () -> Void)
    func catGoHome()

    func showBubble(_ content: BubbleContent?)
    var isPointerOnBubble: Bool { get }

    var isInputVisible: Bool { get }
    func showInput(_ request: InputRequest)
    func setInputText(_ text: String)
    func submitInput(_ text: String)
    func hideInput()
    func showListening(in box: VoiceBox?)

    var isKittensVisible: Bool { get }
    func showKittens(_ statuses: [KittenStatus])
    func hideKittens()

    var isChannelsOpen: Bool { get }
    var isChannelsInFront: Bool { get }
    func showChannels(_ book: ChannelBook, selecting selection: ChannelSelection?)
    func updateChannels(_ book: ChannelBook)
    func hideChannels()
    var isMessagesBoxTyping: Bool { get }
    func holdMessagesBox()
    func sendInMessages(_ text: String)
    func releaseMessagesBox()

    func isOwnWindow(at region: CGRect) -> Bool
    func showStatus(_ status: String, needsYou: Bool)
    func showNeedsYou(_ count: Int)
    var isFrontmost: Bool { get }
    func typeInOwnBox(_ text: String) -> Bool
    func showSettings(_ form: SettingsForm, overMessages: Bool)
    func settingsChanged(_ form: SettingsForm)
    func showText(size: TextSize, font: String?)
    func showPairing(_ card: PhonePairingCard?)
    func copyToPasteboard(_ text: String)
    func openSettings(_ pane: Permissions.Pane)
}

struct SettingsForm: Equatable {
    struct Channel: Equatable {
        var id: ChannelID
        var title: String
    }

    var settings: Settings
    var channels: [Channel]
}
