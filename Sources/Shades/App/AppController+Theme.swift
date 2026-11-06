import Foundation
import ShadesCore

/// Messages' colours, from a theme another app on your Mac already has, or a theme file dropped onto Messages.
/// Only Messages and the phone take them, and kittens keep their own.
extension AppController {
    enum ThemeChoice: Equatable {
        case file(URL)
        /// Shades' own colours.
        case plain
    }

    func themeChosen(_ choice: ThemeChoice) {
        switch choice {
        case .plain:
            use(nil)
        case .file(let file):
            guard let picked = try? ColorTheme.read(contentsOf: file) else { return say(CatWords.themeUnreadable) }
            use(picked)
        }
    }

    private func use(_ picked: ColorTheme?) {
        theme = picked
        stage.showTheme(picked)
        phone?.theme = picked
        do {
            try saveTheme(picked)
        } catch {
            say(CatWords.themeNotSaved)
        }
    }
}
