import CoreGraphics
import Foundation
import ShadesCore

/// What's in the speech bubble. Only one thing shows at a time.
enum BubbleContent: Equatable {
    case thinking(note: String?)
    case listening(String)
    /// `canReplace` offers a finished rewrite in place of what you'd selected.
    case reply(text: String, done: Bool, threadID: String?, note: String?, canReplace: Bool = false)
    case line(String, threadID: String?)
    case notice(caption: String, text: String, threadID: String?)
    case approval(ApprovalRequest, position: Int, total: Int)
    case inbox(String)
}

/// What the buttons in the bubble can ask for.
enum BubbleAction: Equatable {
    /// In T3, for a thread Messages doesn't show.
    case open(threadID: String)
    /// The thread in Messages, beside the place it lives.
    case show(threadID: String)
    case copy(String)
    case replace(String)
    case approval(ApprovalRequest, ApprovalDecision)
    /// Messages, at what needs you.
    case openMessages
}

/// What Messages can do with a report. None of it says anything for you.
enum InboxAction: Equatable {
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
    /// Curled up asleep while Do Not Disturb is on, so you can see why nothing's popping up.
    func catDoNotDisturb(_ on: Bool)
    /// Runs to the pointer, for when something needs you.
    func catComeToYou(arrived: @escaping () -> Void)
    /// Runs to a part of the screen and perches on it.
    func catRun(toRegion region: CGRect, arrived: @escaping () -> Void)
    func catGoHome()

    // The bubble
    func showBubble(_ content: BubbleContent?)
    /// The pointer resting on it, as when you're reading it.
    var isPointerOnBubble: Bool { get }

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

    // Messages
    var isChannelsVisible: Bool { get }
    /// Open where you can see it, rather than behind your work or on another Space.
    var isChannelsInFront: Bool { get }
    /// Opens the window, or brings it to the front if it's open, at `selection` if it's given.
    func showChannels(_ book: ChannelBook, selecting selection: ChannelSelection?)
    func updateChannels(_ book: ChannelBook)
    /// Closes it, which forgets every word.
    func hideChannels()
    /// You're typing in Messages' box, so what you say belongs there.
    var isMessagesBoxTyping: Bool { get }
    /// Keeps Messages' box pointing where it does now, while you say something into it.
    func holdMessagesBox()
    /// Sends this from Messages' box where it pointed when it was held, after anything typed, as if Return were pressed.
    func sendInMessages(_ text: String)
    /// You said nothing after all.
    func releaseMessagesBox()
    /// Messages in a theme's colours, or Shades' own with `nil`.
    func showTheme(_ theme: ColorTheme?)

    // Everything else
    /// For the menu bar: how things are going, and whether anything needs you.
    func showStatus(_ status: String, needsYou: Bool)
    /// Every setting in one place, under the menu bar icon, or over Messages when it was asked for from there.
    func showSettings(_ form: SettingsForm, overMessages: Bool)
    /// What Settings shows, if it's open, after a change made anywhere.
    func settingsChanged(_ form: SettingsForm)
    /// Messages' words at this size, and in this font, or the system's with `nil`.
    func showText(size: TextSize, font: String?)
    /// The code a phone pairs with, or `nil` to take it away.
    func showPairing(_ card: PhonePairingCard?)
    func copyToPasteboard(_ text: String)
}

/// What Settings shows: everything in the settings file, and the theme and channels that live elsewhere.
struct SettingsForm: Equatable {
    struct Channel: Equatable {
        var id: ChannelID
        var title: String
    }

    var settings: Settings
    /// The theme Messages is in, or `nil` for Shades' own colours.
    var theme: String?
    /// Every channel in Messages, in the sidebar's order, for what each tells you.
    var channels: [Channel]
}
