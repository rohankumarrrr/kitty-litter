import AppKit
import ShadesCore

extension MenuBar {
    func installMainMenu() {
        let main = mainMenu()
        NSApp.mainMenu = main
        NSApp.servicesMenu = main.items.first?.submenu?.item(withTitle: "Services")?.submenu
        NSApp.windowsMenu = main.item(withTitle: "Window")?.submenu
        NSApp.helpMenu = main.item(withTitle: "Help")?.submenu
    }

    func mainMenu() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(CatWords.appName, appMenu()))
        main.addItem(submenu("File", fileMenu()))
        main.addItem(submenu("Edit", editMenu()))
        main.addItem(submenu("View", viewMenu()))
        main.addItem(submenu("Window", windowMenu()))
        main.addItem(submenu("Help", helpMenu()))
        return main
    }

    func dockMenu() -> NSMenu {
        let dock = NSMenu()
        addAction("Ask…", to: dock) { [weak self] in self?.onAsk?() }
        addAction("Fix What I'm Looking At", to: dock) { [weak self] in self?.onFix?() }
        dock.addItem(.separator())
        addAction(CatWords.doNotDisturb, to: dock) { [weak self] in self?.onDoNotDisturb?() }.state = isDoNotDisturb?() == true ? .on : .off
        return dock
    }

    private func appMenu() -> NSMenu {
        let menu = NSMenu(title: CatWords.appName)
        menu.addItem(standard("About \(CatWords.appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: NSApp))
        menu.addItem(.separator())
        addAction("Settings…", to: menu) { [weak self] in self?.onSettings?() }.keyEquivalent = ","
        let pair = addAction(CatWords.pairItem, to: menu) { [weak self] in self?.onPairPhone?() }
        menu.addItem(.separator())
        let quiet = addAction(CatWords.doNotDisturb, to: menu) { [weak self] in self?.onDoNotDisturb?() }
        let lockdown = NSMenuItem(title: CatWords.lockdown, action: nil, keyEquivalent: "")
        lockdown.submenu = NSMenu()
        menu.addItem(lockdown)
        menu.addItem(.separator())
        menu.addItem(submenu("Services", NSMenu(title: "Services")))
        menu.addItem(.separator())
        menu.addItem(standard("Hide \(CatWords.appName)", #selector(NSApplication.hide(_:)), "h", target: NSApp))
        menu.addItem(standard("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option], target: NSApp))
        menu.addItem(standard("Show All", #selector(NSApplication.unhideAllApplications(_:)), target: NSApp))
        menu.addItem(.separator())
        menu.addItem(standard("Quit \(CatWords.appName)", #selector(NSApplication.terminate(_:)), "q", target: NSApp))
        menu.delegate = self
        refreshesOnOpen[menu] = { [weak self] in
            guard let self else { return }
            pair.isHidden = self.canPairPhone?() != true
            quiet.state = self.isDoNotDisturb?() == true ? .on : .off
            lockdown.isHidden = !self.showLockdown(on: lockdown)
        }
        return menu
    }

    private func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        addAction("Ask…", shortcut: .ask, to: menu) { [weak self] in self?.onAsk?() }
        addAction("Fix What I'm Looking At", shortcut: .fix, to: menu) { [weak self] in self?.onFix?() }
        menu.addItem(.separator())
        menu.addItem(standard("Close Window", #selector(NSWindow.performClose(_:)), "w"))
        return menu
    }

    private func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(standard("Undo", Selector(("undo:")), "z"))
        menu.addItem(standard("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(standard("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(standard("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(standard("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(standard("Select All", #selector(NSText.selectAll(_:)), "a"))
        return menu
    }

    private func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        addAction(CatWords.kittensTitle, to: menu) { [weak self] in self?.onKittens?() }
        menu.addItem(.separator())
        menu.addItem(standard("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(standard("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(standard("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(standard("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)), target: NSApp))
        return menu
    }

    private func helpMenu() -> NSMenu {
        let menu = NSMenu(title: "Help")
        for extra in extras { addAction(extra.title, to: menu, run: extra.action) }
        return menu
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        row.submenu = menu
        return row
    }

    private func standard(_ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
        let row = NSMenuItem(title: title, action: action, keyEquivalent: key)
        row.keyEquivalentModifierMask = modifiers
        row.target = target
        return row
    }
}
