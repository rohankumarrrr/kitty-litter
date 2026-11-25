import Foundation

// Outside the repo: S1-mini's model card warns that any wording but this format garbles its output.
enum S1Mini {
    static let fileName = "s1-mini-q4_k_m.gguf"
    static let revision = "34add00a48a2e5d24e5a4ee5405a99620a3a240c"
    static let sha256 = "3b41ebe2502cbd03e811d5d16b022f5ab551eda58d62597d152f89535003c634"
    static let byteCount: Int64 = 484_219_808
    static let url = URL(string: "https://huggingface.co/superwhisper/s1-mini-GGUF/resolve/\(revision)/\(fileName)")!

    enum Structure: String {
        case prose, lists
    }

    static let system = "You are a text normalizer for speech-to-text transcripts. The input begins with a control line specifying the styling, structure, and context settings; clean the transcript to match those settings and output only the cleaned text."

    static func prefix(structure: Structure) -> String {
        "<|im_start|>system\n\(system)<|im_end|>\n<|im_start|>user\n[Styling: semi-formal] [Structure: \(structure.rawValue)] [Context: general]\n"
    }

    static func prompt(transcript: String, structure: Structure) -> String {
        prefix(structure: structure) + transcript + "<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n"
    }

    // Outside the repo: this ceiling comes from S1-mini's model card.
    static func maxTokens(forInputWords words: Int) -> Int {
        Int(1.3 * 1.5 * Double(words)) + 32
    }
}
