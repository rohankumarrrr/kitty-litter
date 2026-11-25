import Foundation

enum Repo {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static func read(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    static func files(under places: [String], endingIn endings: [String]) throws -> [String] {
        var found: [String] = []
        for place in places {
            let url = root.appendingPathComponent(place)
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) else { continue }
            guard isFolder.boolValue else {
                found.append(place)
                continue
            }
            let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
            while let file = walker?.nextObject() as? URL {
                if endings.contains(where: file.lastPathComponent.hasSuffix) {
                    found.append(place + "/" + file.path.dropFirst(url.path.count + 1))
                }
            }
        }
        return found.sorted()
    }
}
