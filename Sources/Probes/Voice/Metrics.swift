import Darwin
import Foundation

enum Metrics {
    /// Lowercase words with punctuation gone and spelled-out numbers as digits, so "Three," and "3" match.
    static func words(_ text: String) -> [String] {
        let lowered = text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "\n", with: " ")
        let tokens = lowered.split(whereSeparator: { $0.isWhitespace }).map { token -> String in
            var word = token.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols).subtracting(CharacterSet(charactersIn: "$%@")))
            word = word.replacingOccurrences(of: ",", with: "")
            return word
        }.filter { !$0.isEmpty }
        return tokens.map { numberWords[$0] ?? $0 }
    }

    private static let numberWords: [String: String] = [
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7",
        "eight": "8", "nine": "9", "ten": "10", "eleven": "11", "twelve": "12", "thirteen": "13", "fourteen": "14",
        "fifteen": "15", "sixteen": "16", "seventeen": "17", "eighteen": "18", "nineteen": "19", "twenty": "20",
        "thirty": "30", "forty": "40", "fifty": "50", "sixty": "60", "seventy": "70", "eighty": "80", "ninety": "90",
    ]

    static func edits(_ reference: [String], _ hypothesis: [String]) -> Int {
        if reference.isEmpty { return hypothesis.count }
        if hypothesis.isEmpty { return reference.count }
        var row = Array(0...hypothesis.count)
        for (i, r) in reference.enumerated() {
            var previous = row[0]
            row[0] = i + 1
            for (j, h) in hypothesis.enumerated() {
                let saved = row[j + 1]
                row[j + 1] = min(row[j + 1] + 1, row[j] + 1, previous + (r == h ? 0 : 1))
                previous = saved
            }
        }
        return row[hypothesis.count]
    }

    /// Whether `phrase` appears as whole words in `text`.
    static func contains(_ text: String, phrase: String) -> Bool {
        let haystack = " " + words(text).joined(separator: " ") + " "
        let needle = " " + words(phrase).joined(separator: " ") + " "
        return haystack.contains(needle)
    }

    static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int((p / 100 * Double(sorted.count - 1)).rounded())
        return sorted[rank]
    }

    /// Memory charged to this process, the number Activity Monitor shows.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}

/// Tallies word errors over many clips, so long clips count for more than short ones.
struct ErrorTally {
    private(set) var edits = 0
    private(set) var words = 0

    mutating func add(reference: [String], hypothesis: [String]) {
        edits += Metrics.edits(reference, hypothesis)
        words += reference.count
    }

    var rate: Double { words == 0 ? 0 : Double(edits) / Double(words) }
    var percent: String { String(format: "%.2f%%", rate * 100) }
}
