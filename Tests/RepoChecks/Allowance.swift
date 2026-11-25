import XCTest

struct Allowance {
    let name: String
    let left: [String: Int]

    func check(_ found: [String: [Match]], tooMany: (_ file: String, _ count: Int, _ allowed: Int) -> String) {
        for (file, matches) in found.sorted(by: { $0.key < $1.key }) {
            let allowed = left[file, default: 0]
            if matches.count > allowed {
                let lines = matches.map { "\(file):\($0.line): \($0.text)" }.joined(separator: "\n")
                XCTFail(tooMany(file, matches.count, allowed) + "\n" + lines)
            } else if matches.count < allowed {
                XCTFail("\(file) has \(matches.count) now, fewer than \(name) allows. Lower it to \(matches.count), so they can't come back.")
            }
        }
        for file in left.keys where found[file] == nil {
            XCTFail("\(file) is gone, so take it out of \(name).")
        }
    }
}
