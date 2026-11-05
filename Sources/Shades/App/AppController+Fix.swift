import CoreGraphics
import Foundation
import ShadesCore

/// Fix what I'm looking at: point, optionally say what's wrong, and an agent takes it from there.
extension AppController {
    func fixPressed() {
        flow = Task { await beginFix() }
    }

    func beginFix() async {
        guard !picking else { return }
        picking = true
        defer { picking = false }
        stage.hideInput()
        stage.hideInbox()
        guard let region = await context.pickRegion() else { return }
        stage.catRun(toRegion: region) {}
        let capture = await startLook(CaptureOptions(focusRegion: region)).value
        let snapshot = capture.snapshot ?? ScreenSnapshot(focusRegion: region)

        // With nothing to look at, a description is the only way it can help.
        let leftOut = settings.frontierMode == .fullAccess
        let canSee = !leftOut && !snapshot.isPrivate && snapshot.screenshotJPEG != nil
        let caption: String
        if let error = capture.error {
            caption = CatWords.problem(error, while: .seeing)
        } else if snapshot.isPrivate {
            caption = CatWords.privateApp
        } else if leftOut {
            caption = CatWords.fullAccessLeavesScreenOut
        } else if !canSee {
            caption = screenBlockedBy ?? CatWords.needsScreenRecording
        } else {
            caption = CatWords.fixCaption(modelName: frontierName)
        }
        fixIsOpen = true
        stage.showInput(InputRequest(
            placeholder: canSee ? CatWords.fixPlaceholder(talkKey: settings.talkKey) : CatWords.tellMeWhatsWrong,
            caption: caption,
            allowsEmpty: canSee,
            onSubmit: { [weak self] description in
                self?.fixIsOpen = false
                self?.sendFix(description, snapshot: snapshot)
            },
            onCancel: { [weak self] in
                self?.fixIsOpen = false
                self?.stage.catGoHome()
            }
        ))
    }

    func sendFix(_ description: String, snapshot: ScreenSnapshot) {
        let said = description.isEmpty ? nil : description
        // An agent with full access can do anything, so text from a page doesn't get to reach it.
        let shared = settings.frontierMode == .fullAccess ? nil : snapshot
        let path = saveScreenshot(of: shared)
        let what = said ?? shared?.appName.map { "Something in \($0)" } ?? "Something on screen"
        startFrontier(
            title: "Fix: \(what)",
            text: Prompts.fix(description: said, snapshot: shared, screenshotPath: path),
            snapshot: shared
        )
        // A moment at the spot to say it's on it, then back home, unless it's needed elsewhere.
        Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.settleSeconds * 1_000_000_000))
            if !catIsAway { stage.catGoHome() }
        }
    }
}
