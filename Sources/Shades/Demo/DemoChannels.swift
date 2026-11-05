import Foundation
import ShadesCore

/// Something to read in `--demo`, covering what a real channel can hold. The repo is public, so
/// it's all made up: pricing pages and pixel fonts, never anything real.
enum DemoChannels {
    private static let now = Date()

    private static func ago(minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

    private static func thread(
        _ id: String,
        _ title: String,
        project: String?,
        status: AgentStatus = .completed,
        settled: Bool = true,
        minutes: Double,
        pullRequest: ThreadPullRequest? = nil
    ) -> AgentThread {
        AgentThread(id: id, title: title, projectTitle: project, status: status, model: "claude-opus-5-5", updatedAt: ago(minutes: minutes), isSettled: settled, pullRequest: pullRequest, projectPath: Demo.kittens.first { $0.name == project }?.folder)
    }

    private static let clawdeMain = thread("demo-clawde-main", "Tidy the settings panel", project: "Clawde", minutes: 95, pullRequest: ThreadPullRequest(number: 31, state: "merged"))
    private static let steveFonts = thread("demo-steve-fonts", "Choose the heading font", project: "Steve Pawsniak", settled: false, minutes: 200)
    private static let pepperPlans = thread("demo-pepper-plans", "Compare the plan names", project: "Pepper", status: .waitingForAnswer, settled: false, minutes: 18)
    private static let clawdeAsksSteve = thread("demo-steve-from-clawde", "Check the button labels", project: "Steve Pawsniak", minutes: 60)
    private static let steveAsksClawde = thread("demo-clawde-from-steve", "Steve Pawsniak asked about fonts", project: "Clawde", minutes: 40)
    private static let pepperAsksSteve = thread("demo-steve-from-pepper", "Plan names for the pricing page", project: "Steve Pawsniak", minutes: 25)

    /// Threads you'd only find in the full list, on top of the live ones `DemoBackend` already has.
    static let threads: [AgentThread] = [
        clawdeMain,
        steveFonts,
        pepperPlans,
        clawdeAsksSteve,
        steveAsksClawde,
        pepperAsksSteve,
        thread("demo-steve-copy", "Steve Pawsniak: Rewrite the pricing copy", project: "site", settled: false, minutes: 12, pullRequest: ThreadPullRequest(number: 12, state: "open")),
        thread("demo-steve-yesterday", "Shrink the logo on small screens", project: "Steve Pawsniak", minutes: 1_500, pullRequest: ThreadPullRequest(number: 9, state: "merged")),
        thread("demo-clawde-menu", "Clawde: Add a menu item for the new window", project: "site", settled: false, minutes: 8),
        thread("demo-clawde-failed", "Clawde: Redraw the app icon", project: "Clawde", status: .failed, settled: false, minutes: 130),
        thread("demo-pepper-unknown", "Sum up the plan comparison", project: "Pepper", minutes: 300),
    ]

    /// What's waiting on you in the pictures: one of each kind, all made up.
    static let waiting = Waiting(
        approvals: [ApprovalRequest(id: "demo-approve", threadID: "demo-clawde-menu", threadTitle: "Clawde: Add a menu item for the new window", kind: .command, summary: "Run: swift test", createdAt: ago(minutes: 3))],
        questions: [AgentQuestion(
            id: "demo-ask",
            threadID: pepperPlans.id,
            threadTitle: pepperPlans.title,
            text: "Which plan name should lead the page?",
            options: ["Starter", "Basic", "Keep both"],
            form: AnswerForm(parts: [AnswerForm.Part(key: "plan", text: "Which plan name should lead the page?", options: ["Starter", "Basic", "Keep both"], values: ["Starter", "Basic", "Keep both"], takesOwnWords: true)])
        )],
        owners: ["demo-approve": "/demo/clawde", "demo-ask": "/demo/pepper"],
        reports: [
            InboxEntry(id: "demo-decision", kind: .decision, text: "The settings panel change is merged. Say ship it to install it.", threadID: clawdeMain.id, threadTitle: clawdeMain.title, at: ago(minutes: 90)),
            InboxEntry(id: "demo-shipped", kind: .shipped, text: "Shipped the smaller logo on small screens.", threadID: "demo-steve-yesterday", threadTitle: "Shrink the logo on small screens", at: ago(minutes: 1_400)),
        ]
    )

    private static func exchange(
        _ id: String,
        asker: Exchange.Asker = .you,
        minutes: Double,
        ask: String? = nil,
        reply: String? = nil,
        repliedMinutes: Double? = nil,
        notes: Int = 0,
        failure: String? = nil
    ) -> Exchange {
        Exchange(
            id: id,
            asker: asker,
            askedAt: ago(minutes: minutes),
            ask: ask,
            reply: reply,
            repliedAt: repliedMinutes.map(ago(minutes:)),
            earlierNotes: notes,
            failure: failure
        )
    }

    static let transcripts: [String: [Exchange]] = [
        "demo-tidy": [
            exchange(
                "tidy-1",
                minutes: 6,
                ask: "The pricing page feels cramped on a laptop. Can you tidy it up?",
                reply: "Moved the plans onto the new grid. Now checking the checkout button on small screens.",
                repliedMinutes: 2,
                notes: 1
            ),
        ],
        "demo-steve-yesterday": [
            exchange(
                "logo-1",
                minutes: 1_520,
                ask: "The logo wraps onto two lines on my phone.",
                reply: "Fixed. The logo now shrinks below 480 points, and it's in pull request 9.",
                repliedMinutes: 1_500
            ),
        ],
        "demo-steve-fonts": [
            exchange(
                "fonts-1",
                minutes: 220,
                ask: "Which pixel font should the headings use?",
                reply: "I'd use **Silkscreen**. It stays readable at 12 points, and it has a bold cut. *Press Start 2P* is wider than the column.",
                repliedMinutes: 200
            ),
        ],
        "demo-steve-copy": [
            exchange(
                "copy-1",
                minutes: 30,
                ask: "Rewrite the pricing copy so it sounds like a person wrote it.",
                reply: """
                Done. I went through each plan and rewrote it in plain words. Here's what changed.

                **Free** now says what you get, instead of what you don't. The line about "limited seats" is gone.

                **Pro** leads with the thing most people buy it for, which is sharing a project with someone else. The old heading was `Unlock collaboration`, and the new one is `Work on it together`.

                **Team** no longer has a paragraph on billing. That moved to [the billing page](https://example.com/billing), where people actually look for it.

                I also shortened the comparison table. It had eleven rows, and four of them said the same thing in different words.

                The button labels all say what happens next now, so Start free trial replaces Get started.

                Nothing else on the page changed, and I checked it at every width the site supports.

                The headings still use the system font, because the font question hasn't been settled. Once it has, that's a one line change.

                I left the testimonials alone. They're real quotes, so rewriting them isn't my call.

                The tests pass, and the preview looks right in both light and dark.

                It's in pull request 12, waiting for you to say "ship it". There's nothing else I need from you.

                One thing for later: the FAQ repeats some of the same promises, and it could use the same treatment.

                If you'd like that done too, say so and I'll start a new thread for it.

                I also noticed the page takes a while to load on a slow connection, which comes from the large hero image. That's a separate change, so I haven't touched it.
                """,
                repliedMinutes: 12,
                notes: 2
            ),
        ],
        "demo-steve-from-clawde": [
            exchange(
                "labels-1",
                asker: .agent(threadID: clawdeMain.id),
                minutes: 70,
                ask: "Could you check that the button labels on the pricing page still fit after the font change?",
                reply: "They fit. The longest is Start free trial, and it has 12 points to spare.",
                repliedMinutes: 60
            ),
        ],
        "demo-clawde-from-steve": [
            exchange(
                "fonts-question",
                asker: .agent(threadID: steveFonts.id),
                minutes: 45,
                ask: "Is there a rule about which fonts can ship with the app?",
                reply: "Only that they're permissively licensed. Silkscreen is fine.",
                repliedMinutes: 40
            ),
        ],
        "demo-steve-from-pepper": [
            exchange(
                "plans-1",
                asker: .agent(threadID: pepperPlans.id),
                minutes: 28,
                ask: "Are the plan names on the pricing page final?",
                reply: "Yes. Free, Pro and Team.",
                repliedMinutes: 25
            ),
        ],
        "demo-pepper-plans": [
            exchange(
                "plans-2",
                minutes: 20,
                ask: "Compare our plan names with what other sites call theirs.",
                reply: "Nearly everyone uses Free and Pro. Should I look at the top tier as well?",
                repliedMinutes: 18
            ),
        ],
        "demo-pepper-unknown": [
            exchange(
                "unknown-1",
                asker: .agent(threadID: nil),
                minutes: 310,
                ask: "Please sum up the plan comparison in two lines.",
                reply: "Free and Pro are standard. Team is called Business about half the time.",
                repliedMinutes: 300
            ),
        ],
        "demo-clawde-menu": [
            exchange(
                "menu-1",
                asker: .agent(threadID: clawdeMain.id),
                minutes: 20,
                ask: "A long brief that only matters to Clawde itself, so it never gets a row.",
                reply: "The menu item is in, after Kittens. It's on a branch, with the tests passing.",
                repliedMinutes: 8
            ),
        ],
        "demo-clawde-main": [
            exchange(
                "settings-1",
                minutes: 100,
                ask: "The settings panel looks crowded. Can you space it out?",
                reply: "Spaced it out and lined up the labels. That one's merged.",
                repliedMinutes: 95
            ),
        ],
        "demo-clawde-failed": [
            exchange(
                "icon-1",
                minutes: 135,
                ask: "Redraw the app icon from the cat's art.",
                failure: "The script stopped because the image folder wasn't there."
            ),
        ],
    ]
}
