import AppKit
import Foundation
import ShadesCore
import ShadesVoice

/// Tries the voice module from the command line. `probe-voice help` lists what it can do.
@main
struct Probe {
    static func main() {
        setlinebuf(stdout)
        let args = Array(CommandLine.arguments.dropFirst())
        Task {
            do {
                try await run(args)
                exit(0)
            } catch {
                print("Failed: \(error)")
                exit(1)
            }
        }
        // Telling which app is in front takes a live event loop, the same as in the app.
        if ["insert-test", "insert", "dictate"].contains(args.first ?? "") {
            NSApplication.shared.setActivationPolicy(.prohibited)
            NSApplication.shared.run()
        } else {
            dispatchMain()
        }
    }

    static func run(_ args: [String]) async throws {
        let rest = Array(args.dropFirst())
        switch args.first {
        case "permissions": Hardware.permissions()
        case "asr": try await Bench.compareRecognizers(rest)
        case "cleanup": try await Bench.compareCleanup(rest)
        case "vocabulary": try await Bench.compareVocabulary(rest)
        case "clipping": try await Bench.clipping(rest)
        case "partials": try await Bench.partials(rest)
        case "silence": try await Bench.silence(rest)
        case "bench": try await Bench.pipeline(rest)
        case "idle": try await Bench.idle(rest)
        case "download-test": try await Hardware.downloadTest()
        case "mic": try await Hardware.microphone(rest)
        case "keys": try await Hardware.keys(rest)
        case "keys-selftest": try await Hardware.keysSelfTest()
        case "insert": try await Hardware.insert(rest)
        case "dictate": try await Hardware.dictate(rest)
        case "insert-test": try await Hardware.insertTest()
        case "transcribe": try await Bench.transcribe(rest)
        default:
            print("""
            probe-voice permissions          what this process may do, without prompting
            probe-voice bench [--quick]      the whole pipeline on spoken clips, as a Markdown report
            probe-voice idle                 first press after sitting idle, up to 10 minutes
            probe-voice download-test        downloads the cleanup model to a temp folder with progress
            probe-voice asr <models...>      compare recognizers: ultra v3 v2
            probe-voice cleanup [names...]   compare cleanups: rules s1 s1-lists s1-lower s1-pre qwen
            probe-voice vocabulary           accuracy with and without vocabulary boosting
            probe-voice clipping             what a slow mic costs in lost first words
            probe-voice partials             live-text cost: batch re-decoding against a streaming model
            probe-voice silence              whether silence and noise come back as words
            probe-voice transcribe <file>    one file through the whole pipeline
            probe-voice mic --ask [--runs N] times the real microphone. Asks permission, so run it by hand
            probe-voice dictate [--no-insert] the real thing: hold fn or right Option, talk, let go. Asks permission
            probe-voice keys                 prints hold-key events until Control-C
            probe-voice keys-selftest        posts synthetic modifier events and checks they're seen
            probe-voice insert <text>        inserts text at the cursor after 3 seconds
            probe-voice insert-test          opens TextEdit on a temp file, inserts both ways, checks, and closes it
            """)
        }
    }
}
