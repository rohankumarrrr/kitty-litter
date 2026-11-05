import CoreGraphics
import Foundation
import ShadesCore

/// What's in the speech bubble. Only one thing shows at a time.
enum BubbleContent: Equatable {
    case thinking(note: String?)
    case listening(String)
    case reply(text: String, done: Bool, threadID: String?, note: String?)
    case line(String, threadID: String?)
    case notice(caption: String, text: String, threadID: String?)
    case approval(ApprovalRequest, position: Int, total: Int)
    case inbox(String)
}

/// What the buttons in the bubble can ask for.
enum BubbleAction: Equatable {
    case open(threadID: String)
    case copy(String)
    case approval(ApprovalRequest, ApprovalDecision)
    case openInbox
}

/// What the buttons in the inbox can ask for. None of them can say anything for you.
enum InboxAction: Equatable {
    case reply(InboxEntry)
    case open(threadID: String)
    case done(id: String)
    case clear(InboxEntry.Kind)
}

/// One question for the user, typed into the small panel over the cat.
struct InputRequest {
    var placeholder: String
    var caption: String?
    /// Pressing Return with nothing is fine for some questions.
    var allowsEmpty: Bool
    var onSubmit: (String) -> Void
    var onCancel: () -> Void
}

/// How the flows reach the windows, so they can be tested without any.
@MainActor
protocol CatStage: AnyObject {
    // The cat
    func catWake()
    func catSay(_ word: String)
    /// A word that stays until it's replaced with `nil`.
    func catHold(_ word: String?)
    func catStatus(_ status: CatStatus)
    func catLevel(_ level: Float)
    func catAgentsBusy(_ busy: Bool)
    func catCelebrate()
    func catPet()
    /// Runs to the pointer, for when something needs you.
    func catComeToYou(arrived: @escaping () -> Void)
    /// Runs to a part of the screen and perches on it.
    func catRun(toRegion region: CGRect, arrived: @escaping () -> Void)
    func catGoHome()

    // The bubble
    func showBubble(_ content: BubbleContent?)

    // The input panel
    var isInputVisible: Bool { get }
    func showInput(_ request: InputRequest)
    func setInputText(_ text: String)
    /// Sends this as if it had been typed and Return pressed.
    func submitInput(_ text: String)
    func hideInput()

    // The kittens
    var isKittensVisible: Bool { get }
    /// Opens the view of all the kittens, or brings it up to date if it's open.
    func showKittens(_ statuses: [KittenStatus])
    func hideKittens()

    // Channels
    /// Opens the window, or brings it to the front if it's open. It never closes it.
    func showChannels(_ book: ChannelBook)
    func updateChannels(_ book: ChannelBook)

    // The inbox
    var isInboxVisible: Bool { get }
    /// Opens the inbox, or brings it up to date if it's open.
    func showInbox(_ entries: [InboxEntry])
    func hideInbox()

    // Everything else
    func showThreads(_ threads: [AgentThread], status: String)
    func toggleDashboard()
    func showSettings(_ settings: Settings, onSave: @escaping (Settings) -> Void)
    func copyToPasteboard(_ text: String)
}
