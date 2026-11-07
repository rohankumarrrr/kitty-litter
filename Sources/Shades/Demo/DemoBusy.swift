import Foundation
import ShadesCore

/// `busy` in the demo: hundreds of threads and long conversations, so Messages can be timed under a load like a real
/// one. It's all made up from a few plain lines, the same every run.
enum DemoBusy {
    private static let now = Date()
    private static let threadsPerKitten = 40
    private static let otherThreads = 500
    private static let talks = 30
    /// One of Steve's threads goes on and on.
    static let longThread = "busy-steve-long"

    private static let topics = [
        "Tidy the pricing page", "Rewrite the onboarding copy", "Check the button labels", "Compare plan names",
        "Shrink the hero image", "Fix the footer links", "Sort the FAQ", "Line up the settings panel",
        "Pick a heading font", "Clean up the changelog", "Space out the table", "Test the signup form",
    ]

    private static let asks = [
        "Can you take a look at this?",
        "What's left before this can go out?",
        "Does this still work on a small screen?",
        "Make it shorter, please.",
        "Why did the tests fail this time?",
        "Can you try the other font as well?",
    ]

    private static let lines = [
        "I moved the plans onto the new grid, and the checkout button fits on small screens now.",
        "The tests pass. The one that failed before was waiting on a timer, so it now waits for the page instead.",
        "**Free** says what you get, and **Pro** leads with sharing a project with someone else.",
        "The old heading was `Unlock collaboration`, and the new one is `Work on it together`.",
        "Nothing else on the page changed, and I checked it at every width the site supports.",
        "It's in a pull request, waiting for you to say *ship it*.",
        "The comparison table had eleven rows, and four of them said the same thing in different words.",
        "I left the testimonials alone, since they're real quotes.",
    ]

    static let threads: [AgentThread] = {
        var threads: [AgentThread] = []
        for kitten in Demo.kittens where !kitten.planned {
            for index in 0..<threadsPerKitten {
                let id = kitten.name == "Steve Pawsniak" && index == 0 ? longThread : "busy-\(kitten.folder.split(separator: "/").last ?? "")-\(index)"
                let status: AgentStatus = index % 9 == 1 ? .running : .completed
                threads.append(AgentThread(
                    id: id,
                    title: "\(topics[index % topics.count]) \(index + 1)",
                    projectTitle: kitten.name,
                    status: status,
                    model: "claude-opus-5-5",
                    updatedAt: now.addingTimeInterval(-Double(index) * 3_600 - 60),
                    isSettled: index % 3 != 0,
                    pullRequest: index % 4 == 0 ? ThreadPullRequest(number: 100 + index, state: index % 8 == 0 ? "open" : "merged") : nil,
                    projectPath: kitten.folder
                ))
            }
        }
        for index in 0..<otherThreads {
            threads.append(AgentThread(
                id: "busy-other-\(index)",
                title: "\(topics[index % topics.count]) elsewhere \(index + 1)",
                projectTitle: "project-\(index % 25)",
                status: .completed,
                model: "claude-opus-5-5",
                updatedAt: now.addingTimeInterval(-Double(index) * 1_800),
                isSettled: true,
                projectPath: "/demo/projects/project-\(index % 25)"
            ))
        }
        for index in 0..<talks {
            threads.append(AgentThread(
                id: "busy-talk-\(index)",
                title: asks[index % asks.count],
                projectTitle: "Shades router",
                status: .completed,
                model: "claude-opus-5-5",
                updatedAt: now.addingTimeInterval(-Double(index) * 5_400 - 120),
                isSettled: true,
                projectPath: DemoChannels.routerFolder
            ))
        }
        return threads
    }()

    static let transcripts: [String: [Exchange]] = {
        var transcripts: [String: [Exchange]] = [:]
        for (number, thread) in threads.enumerated() where !thread.id.hasPrefix("busy-other") {
            let isTalk = thread.id.hasPrefix("busy-talk")
            let count = thread.id == longThread ? 150 : isTalk ? 4 : 6 + number * 7 % 15
            let end = thread.updatedAt
            transcripts[thread.id] = (0..<count).map { index in
                let askedAt = end.addingTimeInterval(-Double(count - index) * 1_500)
                let isLast = index == count - 1
                return Exchange(
                    id: "\(thread.id)-\(index)",
                    asker: .you,
                    askedAt: askedAt,
                    ask: asks[(number + index) % asks.count],
                    reply: isLast && thread.status.isActive ? nil : reply(number + index),
                    repliedAt: isLast && thread.status.isActive ? nil : askedAt.addingTimeInterval(600),
                    earlierNotes: index % 5 == 0 ? 1 : 0
                )
            }
        }
        return transcripts
    }()

    /// One to six paragraphs, and now and then a long one that's cut short until you ask for more.
    private static func reply(_ seed: Int) -> String {
        let paragraphs = seed % 11 == 0 ? 16 : 1 + seed % 6
        return (0..<paragraphs).map { lines[(seed + $0 * 3) % lines.count] }.joined(separator: "\n\n")
    }
}
