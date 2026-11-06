import Foundation

/// Colours for Messages, taken from a theme made for T3 Code, VS Code or Cursor, or iTerm2, so Messages can match
/// the rest of your Mac. Only the few colours Messages needs are kept, and the rest are worked out from them.
/// Kittens keep their own colours whatever the theme, so you can still tell them apart.
public struct ColorTheme: Equatable, Sendable {
    public var name: String
    public var isDark: Bool
    /// The window.
    public var paper: UInt32
    public var text: UInt32
    /// Times, names and anything else that stands back.
    public var soft: UInt32
    /// What the theme picks out, which tints your messages.
    public var accent: UInt32
    public var line: UInt32
    public var sidebar: UInt32
    /// Your messages, when the theme has a colour for them. Otherwise they're a tint of `accent`.
    public var mine: UInt32?

    public init(name: String, isDark: Bool, paper: UInt32, text: UInt32, soft: UInt32? = nil, accent: UInt32, line: UInt32? = nil, sidebar: UInt32? = nil, mine: UInt32? = nil) {
        self.name = name
        self.isDark = isDark
        self.paper = paper
        self.text = text
        self.soft = soft ?? Self.mix(paper, text, 0.55)
        self.accent = accent
        self.line = line ?? Self.mix(paper, text, 0.12)
        self.sidebar = sidebar ?? Self.mix(paper, text, isDark ? 0.04 : 0.03)
        self.mine = mine
    }

    public var hover: UInt32 { Self.mix(paper, text, 0.07) }
    public var press: UInt32 { Self.mix(paper, text, 0.13) }
    /// The cat's messages, and anyone's without a colour of their own.
    public var bubble: UInt32 { Self.mix(paper, text, isDark ? 0.14 : 0.09) }
    /// A tint of the accent rather than the accent itself, so it never looks like a kitten's colour.
    public var yours: UInt32 { mine ?? Self.mix(paper, accent, isDark ? 0.32 : 0.2) }

    /// The theme's own text if it reads well on `color`, or black or white otherwise.
    public func words(on color: UInt32) -> UInt32 {
        if Self.contrast(color, text) >= 4.5 { return text }
        return Self.contrast(color, 0x000000) >= Self.contrast(color, 0xffffff) ? 0x000000 : 0xffffff
    }

    /// `amount` of the way from `a` to `b`.
    public static func mix(_ a: UInt32, _ b: UInt32, _ amount: Double) -> UInt32 {
        [16, 8, 0].reduce(UInt32(0)) { mixed, shift in
            let channel = Double((a >> shift) & 0xff) * (1 - amount) + Double((b >> shift) & 0xff) * amount
            return mixed | UInt32(channel.rounded()) << shift
        }
    }

    /// As WCAG measures it, from 1 to 21.
    public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    public static func luminance(_ color: UInt32) -> Double {
        let channel = { (shift: UInt32) -> Double in
            let value = Double((color >> shift) & 0xff) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
}

// MARK: - Reading a theme file

extension ColorTheme {
    public struct Unreadable: Error, Equatable {}

    /// The biggest file worth reading. T3 Code's own limit is 32 KB, and VS Code themes with every token run larger.
    public static let largestFile = 512 * 1024

    /// Reads a T3 Code theme, a VS Code or Cursor colour theme, an iTerm2 profile (`.itermcolors` or a dynamic
    /// profile), or one this saved. `name` is the file's, for a theme that doesn't say what it's called.
    public static func read(_ data: Data, name: String) throws -> ColorTheme {
        guard data.count <= largestFile else { throw Unreadable() }
        let root: Any
        if let json = try? JSONSerialization.jsonObject(with: Data(JSONWithComments.plain(String(decoding: data, as: UTF8.self)).utf8)) {
            root = json
        } else if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) {
            root = plist
        } else {
            throw Unreadable()
        }
        guard let theme = theme(in: root, name: name) else { throw Unreadable() }
        return theme
    }

    /// Reads a theme file, after checking it's small enough to be one.
    public static func read(contentsOf file: URL) throws -> ColorTheme {
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= largestFile, let data = FileManager.default.contents(atPath: file.path) else { throw Unreadable() }
        return try read(data, name: file.deletingPathExtension().lastPathComponent)
    }

    private static func theme(in root: Any, name: String) -> ColorTheme? {
        guard let object = root as? [String: Any] else { return nil }
        if object["paper"] != nil { return saved(object) }
        if let appearance = object["appearance"] as? String, ["light", "dark"].contains(appearance) { return t3(object, isDark: appearance == "dark", name: name) }
        if let colors = object["colors"] as? [String: Any] { return vsCode(object, colors: colors, name: name) }
        if let profiles = object["Profiles"] as? [[String: Any]] {
            return profiles.lazy.compactMap { iTerm($0, name: $0["Name"] as? String ?? name) }.first
        }
        return iTerm(object, name: name)
    }

    /// T3 Code's own: a `canvas` and an `accent`, and `colors` laid over what it works out from them.
    private static func t3(_ object: [String: Any], isDark: Bool, name: String) -> ColorTheme? {
        var colors = object["colors"] as? [String: Any] ?? [:]
        if let variants = object["variants"] as? [String: Any], let own = variants[isDark ? "dark" : "light"] as? [String: Any] {
            colors.merge(own) { first, _ in first }
        }
        guard let paper = (colors["canvas"] ?? object["canvas"]).flatMap({ CSSColor.solid($0, over: nil) }) else { return nil }
        let over = { (key: String) -> UInt32? in colors[key].flatMap { CSSColor.solid($0, over: paper) } }
        let text = over("text") ?? (isDark ? mix(paper, 0xffffff, 0.9) : mix(paper, 0x000000, 0.87))
        return ColorTheme(
            name: themeName(object["name"], else: name),
            isDark: isDark,
            paper: paper,
            text: text,
            soft: over("textMuted") ?? over("mutedForeground"),
            accent: over("accent") ?? object["accent"].flatMap { CSSColor.solid($0, over: paper) } ?? over("focus") ?? 0x0071e3,
            line: over("border"),
            sidebar: over("sidebar"),
            mine: over("messageSurface")
        )
    }

    /// A VS Code or Cursor colour theme. What it leaves out is what VS Code's own dark or light theme has.
    private static func vsCode(_ object: [String: Any], colors: [String: Any], name: String) -> ColorTheme? {
        let type = (object["type"] as? String)?.lowercased()
        let declared: Bool? = type.map { $0 == "dark" || $0 == "hc-black" || $0 == "vs-dark" }
        let first = { (keys: [String], over: UInt32?) -> UInt32? in
            keys.lazy.compactMap { colors[$0].flatMap { CSSColor.solid($0, over: over) } }.first
        }
        let given = first(["editor.background", "sideBar.background", "panel.background"], nil)
        guard given != nil || first(["foreground", "editor.foreground"], 0) != nil else { return nil }
        let isDark = declared ?? given.map { luminance($0) < 0.2 } ?? true
        let paper = given ?? (isDark ? 0x1e1e1e : 0xffffff)
        let text = first(["editor.foreground", "foreground"], paper) ?? (isDark ? 0xd4d4d4 : 0x333333)
        return ColorTheme(
            name: themeName(object["name"], else: name),
            isDark: isDark,
            paper: paper,
            text: text,
            soft: first(["descriptionForeground", "sideBarTitle.foreground", "tab.inactiveForeground"], paper),
            accent: first(["button.background", "focusBorder", "activityBarBadge.background", "textLink.foreground"], paper) ?? 0x0078d4,
            line: first(["sideBar.border", "editorGroup.border", "panel.border", "contrastBorder"], paper),
            sidebar: first(["sideBar.background"], paper)
        )
    }

    /// An iTerm2 profile, as an `.itermcolors` file or one of a dynamic profile's.
    private static func iTerm(_ object: [String: Any], name: String) -> ColorTheme? {
        guard let paper = iTermColor(object["Background Color"], over: nil) else { return nil }
        let text = iTermColor(object["Foreground Color"], over: paper) ?? (luminance(paper) < 0.2 ? 0xe5e5e5 : 0x1d1d1d)
        // A cursor is often just the text colour, which wouldn't pick anything out.
        let accent = ["Cursor Color", "Link Color", "Ansi 4 Color"].lazy
            .compactMap { iTermColor(object[$0], over: paper) }
            .first { Self.isColorful($0) } ?? 0x0071e3
        return ColorTheme(name: name, isDark: luminance(paper) < 0.2, paper: paper, text: text, accent: accent)
    }

    private static func iTermColor(_ value: Any?, over: UInt32?) -> UInt32? {
        guard let parts = value as? [String: Any],
              let red = (parts["Red Component"] as? NSNumber)?.doubleValue,
              let green = (parts["Green Component"] as? NSNumber)?.doubleValue,
              let blue = (parts["Blue Component"] as? NSNumber)?.doubleValue
        else { return nil }
        let alpha = (parts["Alpha Component"] as? NSNumber)?.doubleValue ?? 1
        return CSSColor.composite(CSSColor.pack(red, green, blue), alpha: alpha, over: over)
    }

    private static func isColorful(_ color: UInt32) -> Bool {
        let channels = [16, 8, 0].map { Double((color >> UInt32($0)) & 0xff) }
        return (channels.max()! - channels.min()!) > 40
    }

    private static func themeName(_ value: Any?, else name: String) -> String {
        let given = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return String((given.isEmpty ? name : given).prefix(48))
    }
}

// MARK: - Saving it

extension ColorTheme {
    public static var file: URL { Settings.directory.appendingPathComponent("theme.json") }

    /// `nil` for Shades' own colours, including when the file can't be read.
    public static func load(from file: URL = file) -> ColorTheme? {
        guard let data = try? Data(contentsOf: file), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return saved(object)
    }

    /// Saves it where `load` looks, in the same few colours, easy to edit by hand. `nil` goes back to Shades' own.
    public static func save(_ theme: ColorTheme?, to file: URL = file) throws {
        guard let theme else {
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            return
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        var object: [String: Any] = [
            "name": theme.name,
            "appearance": theme.isDark ? "dark" : "light",
            "paper": hex(theme.paper),
            "text": hex(theme.text),
            "soft": hex(theme.soft),
            "accent": hex(theme.accent),
            "line": hex(theme.line),
            "sidebar": hex(theme.sidebar),
        ]
        if let mine = theme.mine { object["mine"] = hex(mine) }
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: file, options: .atomic)
    }

    public static func hex(_ color: UInt32) -> String {
        String(format: "#%06x", color & 0xffffff)
    }

    private static func saved(_ object: [String: Any]) -> ColorTheme? {
        let color = { (key: String) -> UInt32? in object[key].flatMap { CSSColor.solid($0, over: nil) } }
        guard let paper = color("paper"), let text = color("text") else { return nil }
        let isDark = (object["appearance"] as? String).map { $0 == "dark" } ?? (luminance(paper) < 0.2)
        return ColorTheme(
            name: themeName(object["name"], else: "Theme"),
            isDark: isDark,
            paper: paper,
            text: text,
            soft: color("soft"),
            accent: color("accent") ?? 0x0071e3,
            line: color("line"),
            sidebar: color("sidebar"),
            mine: color("mine")
        )
    }
}

// MARK: - Themes already on this Mac

extension ColorTheme {
    /// A theme another app has, for Messages to offer.
    public struct Found: Equatable, Sendable {
        public var theme: ColorTheme
        /// Which app it's from, such as "T3 Code".
        public var app: String
        public var file: URL

        public init(theme: ColorTheme, app: String, file: URL) {
            self.theme = theme
            self.app = app
            self.file = file
        }
    }

    /// The themes T3 Code, Cursor, VS Code and iTerm2 keep in their usual places, once each. It only reads them, and
    /// only when asked.
    public static func installed(home: URL, t3Home: URL) -> [Found] {
        var found = files(in: t3Home.appendingPathComponent("userdata/themes", isDirectory: true)).compactMap { file in
            (try? read(contentsOf: file)).map { Found(theme: $0, app: "T3 Code", file: file) }
        }
        for (app, path) in [("Cursor", ".cursor/extensions"), ("VS Code", ".vscode/extensions")] {
            found += editorThemes(in: home.appendingPathComponent(path, isDirectory: true), app: app)
        }
        found += files(in: home.appendingPathComponent("Library/Application Support/iTerm2/DynamicProfiles", isDirectory: true)).compactMap { file in
            (try? read(contentsOf: file)).map { Found(theme: $0, app: "iTerm2", file: file) }
        }
        // Two copies of one theme, such as the same file in two places, are offered once.
        var seen: [(String, ColorTheme)] = []
        return found.filter { found in
            guard !seen.contains(where: { $0 == (found.app, found.theme) }) else { return false }
            seen.append((found.app, found.theme))
            return true
        }
    }

    private static func files(in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.sorted().filter { name in [".json", ".itermcolors", ".plist"].contains(where: name.lowercased().hasSuffix) }.map(folder.appendingPathComponent)
    }

    /// The colour themes each extension says it has, by the names the editor shows them under, from its newest
    /// version only, since the editor keeps old ones around for a while.
    private static func editorThemes(in extensions: URL, app: String) -> [Found] {
        struct Manifest: Decodable {
            struct Contributes: Decodable {
                struct Theme: Decodable {
                    var label: String?
                    var path: String
                }
                var themes: [Theme]?
            }
            var publisher: String?
            var name: String?
            var version: String?
            var contributes: Contributes?
        }
        let manager = FileManager.default
        let removed = manager.contents(atPath: extensions.appendingPathComponent(".obsolete").path)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }.map { Set($0.keys) } ?? []
        var newest: [String: (version: [Int], folder: URL, themes: [Manifest.Contributes.Theme])] = [:]
        for name in ((try? manager.contentsOfDirectory(atPath: extensions.path)) ?? []).sorted() where !removed.contains(name) {
            let folder = extensions.appendingPathComponent(name, isDirectory: true)
            guard let data = manager.contents(atPath: folder.appendingPathComponent("package.json").path), data.count <= largestFile,
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
                  let themes = manifest.contributes?.themes, !themes.isEmpty
            else { continue }
            let id = "\(manifest.publisher ?? "").\(manifest.name ?? name)".lowercased()
            let version = (manifest.version ?? "").split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
            if let kept = newest[id], !kept.version.lexicographicallyPrecedes(version) { continue }
            newest[id] = (version, folder, themes)
        }
        return newest.values.sorted { $0.folder.lastPathComponent < $1.folder.lastPathComponent }.flatMap { kept in
            kept.themes.compactMap { entry -> Found? in
                let file = kept.folder.appendingPathComponent(entry.path).standardizedFileURL
                // Only files in the extension's own folder.
                guard file.path.hasPrefix(kept.folder.standardizedFileURL.path + "/"), var theme = try? read(contentsOf: file) else { return nil }
                // A label like "%theme.dark%" is a lookup in a file of translations, so the theme's own name does instead.
                if let label = entry.label?.trimmingCharacters(in: .whitespaces), !label.isEmpty, !label.hasPrefix("%") { theme.name = String(label.prefix(48)) }
                return Found(theme: theme, app: app, file: file)
            }
        }
    }
}

// MARK: - Colours as CSS writes them

/// The colour formats themes use: hex, `rgb()` and `oklch()`, which is what T3 Code writes. A colour that isn't
/// solid is laid over the one under it, since Messages only draws solid colours.
enum CSSColor {
    static func solid(_ value: Any, over under: UInt32?) -> UInt32? {
        guard let text = value as? String, let (color, alpha) = parse(text) else { return nil }
        return composite(color, alpha: alpha, over: under)
    }

    static func composite(_ color: UInt32, alpha: Double, over under: UInt32?) -> UInt32? {
        guard alpha < 1 else { return color }
        // A see-through colour with nothing under it is no colour at all.
        guard let under, alpha > 0 else { return nil }
        return ColorTheme.mix(under, color, alpha)
    }

    static func parse(_ text: String) -> (UInt32, Double)? {
        let value = text.trimmingCharacters(in: .whitespaces).lowercased()
        if value.hasPrefix("#") { return hex(String(value.dropFirst())) }
        switch value {
        case "white": return (0xffffff, 1)
        case "black": return (0x000000, 1)
        default: break
        }
        guard let open = value.firstIndex(of: "("), value.hasSuffix(")") else { return nil }
        let function = value[..<open]
        let inside = value[value.index(after: open)..<value.index(before: value.endIndex)]
        let halves = inside.split(separator: "/", maxSplits: 1)
        let parts = halves[0].split { $0 == " " || $0 == "," }.map(String.init)
        var alpha = 1.0
        if halves.count == 2 {
            guard let given = number(String(halves[1]).trimmingCharacters(in: .whitespaces), percentOf: 1) else { return nil }
            alpha = given
        } else if parts.count == 4 {
            guard let given = number(parts[3], percentOf: 1) else { return nil }
            alpha = given
        }
        guard parts.count >= 3 else { return nil }
        switch function {
        case "rgb", "rgba":
            guard let red = number(parts[0], percentOf: 255), let green = number(parts[1], percentOf: 255), let blue = number(parts[2], percentOf: 255) else { return nil }
            return (pack(red / 255, green / 255, blue / 255), alpha)
        case "oklch":
            guard let lightness = number(parts[0], percentOf: 1), let chroma = number(parts[1], percentOf: 0.4), let hue = number(parts[2].replacingOccurrences(of: "deg", with: ""), percentOf: 360) else { return nil }
            return (oklch(lightness, chroma, hue), alpha)
        default:
            return nil
        }
    }

    private static func hex(_ digits: String) -> (UInt32, Double)? {
        guard digits.allSatisfy(\.isHexDigit) else { return nil }
        let full = digits.count <= 4 ? digits.map { "\($0)\($0)" }.joined() : digits
        guard full.count == 6 || full.count == 8, let value = UInt32(full, radix: 16) else { return nil }
        return full.count == 6 ? (value, 1) : (value >> 8, Double(value & 0xff) / 255)
    }

    /// A plain number, or a percentage of `whole`.
    private static func number(_ text: String, percentOf whole: Double) -> Double? {
        if text.hasSuffix("%") { return Double(text.dropLast()).map { $0 / 100 * whole } }
        return Double(text)
    }

    static func pack(_ red: Double, _ green: Double, _ blue: Double) -> UInt32 {
        [red, green, blue].reduce(UInt32(0)) { packed, channel in
            packed << 8 | UInt32((min(max(channel, 0), 1) * 255).rounded())
        }
    }

    /// From OKLCH to sRGB, as CSS Color 4 defines it, clipped to what sRGB can show.
    private static func oklch(_ lightness: Double, _ chroma: Double, _ hue: Double) -> UInt32 {
        let a = chroma * cos(hue * .pi / 180)
        let b = chroma * sin(hue * .pi / 180)
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        let linear = [
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
        ]
        let encoded = linear.map { value in value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055 }
        return pack(encoded[0], encoded[1], encoded[2])
    }
}

/// VS Code themes are JSON with comments and trailing commas, which JSONSerialization won't take.
enum JSONWithComments {
    static func plain(_ text: String) -> String {
        var out = ""
        var characters = Array(text)[...]
        var inString = false
        while let character = characters.popFirst() {
            if inString {
                out.append(character)
                if character == "\\", let next = characters.popFirst() {
                    out.append(next)
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            switch (character, characters.first) {
            case ("\"", _):
                inString = true
                out.append(character)
            case ("/", "/"):
                while let next = characters.first, next != "\n" { characters.removeFirst() }
            case ("/", "*"):
                characters.removeFirst()
                while let next = characters.popFirst() {
                    if next == "*", characters.first == "/" {
                        characters.removeFirst()
                        break
                    }
                }
            case ("}", _), ("]", _):
                // A comma with only space between it and the close is a trailing one.
                if let comma = out.lastIndex(where: { !$0.isWhitespace }), out[comma] == "," { out.remove(at: comma) }
                out.append(character)
            default:
                out.append(character)
            }
        }
        return out
    }
}
