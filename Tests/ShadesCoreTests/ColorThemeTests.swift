import AppKit
import XCTest
@testable import ShadesCore

final class ColorThemeTests: XCTestCase {
    /// Opal Horizon as T3 Code seeds it: a name, light or dark, a canvas and an accent.
    static let t3 = ##"{ "version": 1, "name": "Opal Horizon", "appearance": "dark", "canvas": "#0C0A10", "accent": "#8A6CFF" }"##

    /// The same theme for Cursor, cut down, with the comments and trailing commas VS Code allows.
    static let cursor = ##"""
        {
          // Black opal colours.
          "name": "Opal Horizon",
          "type": "dark",
          "colors": {
            "editor.background": "#0C0A10",
            "editor.foreground": "#E7E4EC",
            "descriptionForeground": "#837D90", /* times and names */
            "sideBar.background": "#0A080D",
            "sideBar.border": "#FFFFFF0F",
            "button.background": "#7458E8",
          },
          "tokenColors": [],
        }
        """##

    /// And as an iTerm2 dynamic profile.
    static let iTerm = ##"""
        { "Profiles": [ { "Name": "Opal Horizon", "Guid": "0F5A1E7C",
          "Background Color": { "Red Component": 0.047058823529411764, "Green Component": 0.0392156862745098, "Blue Component": 0.06274509803921569, "Alpha Component": 1, "Color Space": "sRGB" },
          "Foreground Color": { "Red Component": 0.9058823529411765, "Green Component": 0.8941176470588236, "Blue Component": 0.9254901960784314, "Color Space": "sRGB" },
          "Cursor Color": { "Red Component": 0.7254901960784313, "Green Component": 0.6509803921568628, "Blue Component": 1, "Color Space": "sRGB" } } ] }
        """##

    /// A light theme like Night Owl Light, whose teal accent is too light to read as words on its window.
    static let tealLight = ##"{ "name": "Teal Light", "type": "light", "colors": { "editor.background": "#FBFBFB", "editor.foreground": "#403F53", "button.background": "#2AA298" } }"##

    private func read(_ text: String, name: String = "file") throws -> ColorTheme {
        try ColorTheme.read(Data(text.utf8), name: name)
    }

    func testOpalHorizonComesOutTheSameFromT3CursorAndITerm() throws {
        for (app, text) in [("T3", Self.t3), ("Cursor", Self.cursor), ("iTerm2", Self.iTerm)] {
            let theme = try read(text)
            XCTAssertEqual(theme.name, "Opal Horizon", app)
            XCTAssertTrue(theme.isDark, app)
            XCTAssertEqual(theme.paper, 0x0c0a10, app)
            XCTAssertGreaterThan(ColorTheme.contrast(theme.text, theme.paper), 12, "\(app)'s words read on its window")
            XCTAssertGreaterThan(ColorTheme.contrast(theme.soft, theme.paper), 3, "\(app)'s quieter words still read")
        }
        XCTAssertEqual(try read(Self.t3).accent, 0x8a6cff)
        XCTAssertEqual(try read(Self.cursor).accent, 0x7458e8)
        XCTAssertEqual(try read(Self.iTerm).accent, 0xb9a6ff, "the cursor, since it's a colour and not just the text's")
    }

    func testAVSCodeThemeKeepsItsOwnColoursAndLaysSeeThroughOnesOverTheWindow() throws {
        let theme = try read(Self.cursor)
        XCTAssertEqual(theme.text, 0xe7e4ec)
        XCTAssertEqual(theme.soft, 0x837d90)
        XCTAssertEqual(theme.sidebar, 0x0a080d)
        XCTAssertEqual(theme.line, ColorTheme.mix(0x0c0a10, 0xffffff, 15.0 / 255), "#FFFFFF0F over the window")
    }

    func testAT3ThemesOwnColoursGoOverWhatItsCanvasAndAccentGive() throws {
        let theme = try read(##"""
            { "name": "Mine", "appearance": "light", "canvas": "#ffffff", "accent": "#0071e3",
              "colors": { "text": "oklch(0.2 0 0)", "textMuted": "rgb(100 100 100)", "border": "oklch(0 0 0 / 10%)", "messageSurface": "#e8f0fe" },
              "variants": { "dark": { "canvas": "#000000" } } }
            """##)
        XCTAssertFalse(theme.isDark)
        XCTAssertEqual(theme.paper, 0xffffff, "the dark variant isn't this one")
        XCTAssertEqual(theme.soft, 0x646464)
        XCTAssertEqual(theme.line, 0xe6e6e6, "black at 10% over white")
        XCTAssertEqual(theme.yours, 0xe8f0fe, "its own colour for your messages")
        XCTAssertLessThan(ColorTheme.luminance(theme.text), 0.05)
    }

    func testOKLCHComesOutAsCSSDrawsIt() {
        XCTAssertEqual(CSSColor.parse("oklch(1 0 0)")?.0, 0xffffff)
        XCTAssertEqual(CSSColor.parse("oklch(0% 0 0)")?.0, 0x000000)
        XCTAssertEqual(CSSColor.parse("oklch(0.627955 0.257683 29.2339)")?.0, 0xff0000)
        XCTAssertEqual(CSSColor.parse("oklch(0.519752 0.176858 142.495)")?.0, 0x008000)
        XCTAssertEqual(CSSColor.parse("oklch(0.5 0.1 270 / 50%)")?.1, 0.5)
        XCTAssertEqual(CSSColor.parse("#abc")?.0, 0xaabbcc)
        XCTAssertEqual(CSSColor.parse("rgba(255, 0, 0, 0.25)")?.1, 0.25)
        XCTAssertNil(CSSColor.parse("var(--accent)"))
        XCTAssertNil(CSSColor.parse("#12345"))
    }

    func testAnITermColorsFileIsAPropertyList() throws {
        let plist = ##"""
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0"><dict>
              <key>Background Color</key><dict><key>Red Component</key><real>1</real><key>Green Component</key><real>1</real><key>Blue Component</key><real>1</real></dict>
              <key>Foreground Color</key><dict><key>Red Component</key><real>0</real><key>Green Component</key><real>0</real><key>Blue Component</key><real>0</real></dict>
              <key>Cursor Color</key><dict><key>Red Component</key><real>0</real><key>Green Component</key><real>0</real><key>Blue Component</key><real>0</real></dict>
              <key>Link Color</key><dict><key>Red Component</key><real>0</real><key>Green Component</key><real>0.4</real><key>Blue Component</key><real>0.8</real></dict>
            </dict></plist>
            """##
        let theme = try read(plist, name: "Paper")
        XCTAssertEqual(theme.name, "Paper", "from the file, since the colours don't say")
        XCTAssertFalse(theme.isDark)
        XCTAssertEqual(theme.accent, 0x0066cc, "the link, since a black cursor picks nothing out")
    }

    func testAnythingElseIsntATheme() {
        for text in [#"{ "name": "package", "version": "1.0.0" }"#, "not a theme", #"{ "appearance": "dark" }"#, "[1, 2]"] {
            XCTAssertThrowsError(try read(text), text)
        }
        XCTAssertThrowsError(try ColorTheme.read(Data(count: ColorTheme.largestFile + 1), name: "big"))
    }

    func testCommentMarksInsideWordsStay() {
        XCTAssertEqual(JSONWithComments.plain(#"{ "a": "http://x/*y*/", "b": [1, 2,], } // end"#), #"{ "a": "http://x/*y*/", "b": [1, 2] } "#)
    }

    func testYourMessagesAreATintAndTheirWordsRead() throws {
        for text in [Self.t3, Self.cursor, Self.iTerm] {
            let theme = try read(text)
            XCTAssertNotEqual(theme.yours, theme.accent, "a tint, so it never looks like a kitten's colour")
            XCTAssertGreaterThanOrEqual(ColorTheme.contrast(theme.words(on: theme.yours), theme.yours), 4.5)
            XCTAssertGreaterThanOrEqual(ColorTheme.contrast(theme.words(on: theme.bubble), theme.bubble), 4.5)
        }
    }

    func testLinksAndErrorsReadOnTheWindowAndKeepTheirColour() throws {
        let teal = try read(Self.tealLight)
        XCTAssertLessThan(ColorTheme.contrast(teal.accent, teal.paper), 4.5, "the accent itself doesn't read as words")
        XCTAssertGreaterThanOrEqual(ColorTheme.contrast(teal.link, teal.paper), 4.5)
        XCTAssertLessThan(ColorTheme.contrast(teal.link, teal.paper), 4.6, "only as dark as reading it takes")
        XCTAssertEqual(Self.hue(teal.link), Self.hue(teal.accent), accuracy: 1, "still teal")

        XCTAssertEqual(try read(Self.t3).link, 0x8a6cff, "Opal's accent already reads, so it's left alone")

        let shadesLight = ColorTheme(name: "Shades light", isDark: false, paper: 0xf9f9f9, text: 0x202020, accent: 0x0071e3)
        for theme in [teal, shadesLight] {
            XCTAssertGreaterThanOrEqual(ColorTheme.contrast(theme.danger, theme.paper), 4.5, theme.name)
            XCTAssertEqual(Self.hue(theme.danger), Self.hue(ColorTheme.red), accuracy: 1, "still red in \(theme.name)")
        }
    }

    func testAThemesOwnErrorColourIsUsedAndSaved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shades-theme-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("theme.json")
        let opal = try read(##"{ "name": "Opal Horizon", "appearance": "dark", "canvas": "#0C0A10", "accent": "#8A6CFF", "colors": { "error": "#FF7A9A", "errorForeground": "#FF97B1" } }"##)
        XCTAssertEqual(opal.danger, 0xff97b1, "the theme's colour for error words")

        try ColorTheme.save(opal, to: file)
        XCTAssertEqual(ColorTheme.load(from: file)?.danger, 0xff97b1, "still there after a restart")
    }

    private static func hue(_ color: UInt32) -> Double {
        let rgb = [16, 8, 0].map { CGFloat((color >> UInt32($0)) & 0xff) / 255 }
        return Double(NSColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1).hueComponent) * 360
    }

    func testItSavesAsAFewColoursAndComesBackTheSame() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shades-theme-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("theme.json")
        XCTAssertNil(ColorTheme.load(from: file))

        let theme = try read(Self.cursor)
        try ColorTheme.save(theme, to: file)
        XCTAssertEqual(ColorTheme.load(from: file), theme)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(saved["paper"] as? String, "#0c0a10", "easy to edit by hand")

        try ColorTheme.save(nil, to: file)
        XCTAssertNil(ColorTheme.load(from: file), "back to Shades' own")
    }

    func testItFindsWhatT3CursorVSCodeAndITermHaveOnceEachByTheNamesTheyShow() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("shades-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        func manifest(_ version: String, label: String) -> String {
            ##"{ "name": "opal-horizon", "publisher": "opal-local", "version": "\##(version)", "contributes": { "themes": [ { "label": "\##(label)", "uiTheme": "vs-dark", "path": "./themes/opal-horizon.json" } ] } }"##
        }
        let files = [
            ".t3/userdata/themes/opal-horizon.json": Self.t3,
            ".t3/userdata/themes/opal-horizon-copy.json": Self.t3,
            ".cursor/extensions/opal-local.opal-horizon-1.0.0/package.json": manifest("1.0.0", label: "Opal Horizon"),
            ".cursor/extensions/opal-local.opal-horizon-1.0.0/themes/opal-horizon.json": Self.cursor,
            ".cursor/extensions/opal-local.opal-horizon-0.9.0/package.json": manifest("0.9.0", label: "Opal Horizon, an old version"),
            ".cursor/extensions/opal-local.opal-horizon-0.9.0/themes/opal-horizon.json": Self.cursor,
            ".cursor/extensions/opal-local.opal-horizon-2.0.0/package.json": manifest("2.0.0", label: "Opal Horizon, removed"),
            ".cursor/extensions/opal-local.opal-horizon-2.0.0/themes/opal-horizon.json": Self.cursor,
            ".cursor/extensions/.obsolete": ##"{ "opal-local.opal-horizon-2.0.0": true }"##,
            ".vscode/extensions/someone.icons-1.0.0/package.json": ##"{ "name": "icons", "publisher": "someone", "version": "1.0.0", "contributes": { "iconThemes": [] } }"##,
            ".vscode/extensions/someone.icons-1.0.0/themes/icons.json": ##"{ "iconDefinitions": {} }"##,
            ".vscode/extensions/someone.sneaky-1.0.0/package.json": ##"{ "name": "sneaky", "publisher": "someone", "version": "1.0.0", "contributes": { "themes": [ { "label": "Elsewhere", "path": "../../../.t3/userdata/themes/opal-horizon.json" } ] } }"##,
            "Library/Application Support/iTerm2/DynamicProfiles/opal-horizon.json": Self.iTerm,
        ]
        for (path, text) in files {
            let file = home.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
        }
        let found = ColorTheme.installed(home: home, t3Home: home.appendingPathComponent(".t3"))
        XCTAssertEqual(found.map(\.app), ["T3 Code", "Cursor", "iTerm2"], "one of each: the copy, the old and removed versions, the icons and a theme outside its extension are left out")
        XCTAssertEqual(Set(found.map(\.theme.name)), ["Opal Horizon"])
        XCTAssertEqual(found[1].file.lastPathComponent, "opal-horizon.json")
        XCTAssertTrue(found[1].file.path.contains("opal-horizon-1.0.0"))
        XCTAssertEqual(ColorTheme.installed(home: home.appendingPathComponent("nobody"), t3Home: home.appendingPathComponent("nobody")), [])
    }
}
