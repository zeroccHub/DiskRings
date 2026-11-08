#if canImport(AppKit)
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// Quit stays enabled at all times (a disabled Quit makes Cmd-Q beep).
    /// Appearance items show a radio-style checkmark and are always enabled,
    /// also during a delete.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(setAppearance(_:)),
           let id = menuItem.representedObject as? String, let pref = AppearancePreference(rawValue: id) {
            menuItem.state = pref == AppearancePreference.load() ? .on : .off
        }
        return true   // incl. #selector(NSApplication.terminate(_:)); controller items validate themselves
    }

    @objc func setAppearance(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let pref = AppearancePreference(rawValue: id) else { return }
        pref.save()
        Self.applyAppearance(pref)   // dynamic colours + viewDidChangeEffectiveAppearance redraw the theme
    }

    static let appearanceDidChangeNotification = Notification.Name("DiskRingsAppearanceDidChange")

    static func applyAppearance(_ pref: AppearancePreference) {
        switch pref.resolvedAppearance {
        case .none:
            NSApp.appearance = nil
        case .some(.aqua):
            NSApp.appearance = NSAppearance(named: .aqua)
        case .some(.darkAqua):
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        // Parent-driven home chrome refresh: CALayer fills freeze RGB unless re-applied.
        NotificationCenter.default.post(name: appearanceDidChangeNotification, object: nil)
    }

    private var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply the stored appearance BEFORE the window exists, so it opens in the right mode.
        Self.applyAppearance(AppearancePreference.load())
        BuildInfo.logAtStartup()
        let wc = MainWindowController()
        windowController = wc
        NSApp.mainMenu = MainMenuBuilder.build(target: wc, appDelegate: self)
        wc.showWindow(nil)
        wc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showAbout(_ sender: Any?) { BuildInfo.showAboutPanel() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Cmd-Q / Quit during a deletion: `.terminateLater`; the deletion stops
    /// after its current top-level item and the window controller then calls
    /// `NSApp.reply(toApplicationShouldTerminate: true)`.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        windowController?.shouldTerminate() ?? .terminateNow
    }
}

/// Programmatic main menu (no nib/storyboard resources).
@MainActor enum MainMenuBuilder {
    static func build(target wc: MainWindowController, appDelegate: AppDelegate) -> NSMenu {
        let main = NSMenu()

        // App menu
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: tr("menu.about"), action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "").target = appDelegate
        appMenu.addItem(.separator())
        let fda = appMenu.addItem(withTitle: tr("menu.openFDA"), action: #selector(MainWindowController.openFullDiskAccessSettings(_:)), keyEquivalent: "")
        fda.target = wc
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: tr("menu.hide"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        // Explicit target: validation never goes through the delete sheet's responder chain.
        let quit = appMenu.addItem(withTitle: tr("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appItem.submenu = appMenu

        // File
        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let fileMenu = NSMenu(title: tr("menu.file"))
        add(fileMenu, tr("menu.scanFolder"), #selector(MainWindowController.openFolder(_:)), "o", wc)
        add(fileMenu, tr("menu.rescan"), #selector(MainWindowController.rescan(_:)), "r", wc)
        add(fileMenu, tr("menu.stopScan"), #selector(MainWindowController.cancelScan(_:)), ".", wc)
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: tr("menu.closeWindow"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = fileMenu

        // Edit (standard items so text fields behave)
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: tr("menu.edit"))
        editMenu.addItem(withTitle: tr("menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: tr("menu.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        // View
        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: tr("menu.view"))
        add(viewMenu, tr("toolbar.back"), #selector(MainWindowController.goBack(_:)), "[", wc)
        add(viewMenu, tr("toolbar.forward"), #selector(MainWindowController.goForward(_:)), "]", wc)
        let up = add(viewMenu, tr("menu.goUp"), #selector(MainWindowController.goUp(_:)), ShortcutPolicy.goUpKey, wc)
        up.keyEquivalentModifierMask = [.command]
        // ⌘↓ enters the selected folder (P2-11; never ↩).
        let into = add(viewMenu, tr("menu.enterSelected"), #selector(MainWindowController.enterSelected(_:)), ShortcutPolicy.drillInKey, wc)
        into.keyEquivalentModifierMask = [.command]
        add(viewMenu, tr("menu.goRoot"), #selector(MainWindowController.goToRoot(_:)), "", wc)
        let disks = viewMenu.addItem(withTitle: tr("menu.disks"), action: #selector(MainWindowController.goHome(_:)), keyEquivalent: "1")
        disks.target = wc
        disks.keyEquivalentModifierMask = [.command]
        add(viewMenu, tr("menu.reveal"), #selector(MainWindowController.revealSelected(_:)), "", wc)
        add(viewMenu, tr("menu.quickLook"), #selector(MainWindowController.toggleQuickLook(_:)), "y", wc)
        viewMenu.addItem(.separator())
        add(viewMenu, tr("menu.sizeByLogical"), #selector(MainWindowController.toggleSunburstMetric(_:)), "", wc)
        let appearanceItem = viewMenu.addItem(withTitle: tr("menu.appearance"), action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu(title: tr("menu.appearance"))
        for pref in AppearancePreference.allCases {
            let item = appearanceMenu.addItem(withTitle: tr(pref.menuKey), action: #selector(AppDelegate.setAppearance(_:)), keyEquivalent: "")
            item.representedObject = pref.rawValue
            item.target = appDelegate
        }
        appearanceItem.submenu = appearanceMenu
        add(viewMenu, tr("menu.refreshVolumes"), #selector(MainWindowController.refreshVolumes(_:)), "", wc)
        viewItem.submenu = viewMenu

        // Delete menu (deletion list)
        let colItem = NSMenuItem()
        main.addItem(colItem)
        let colMenu = NSMenu(title: tr("menu.delete"))
        add(colMenu, tr("menu.addToList"), #selector(MainWindowController.collectSelected(_:)), "d", wc)   // also Space in the list
        add(colMenu, tr("menu.removeFromList"), #selector(MainWindowController.uncollectSelected(_:)), "", wc)
        add(colMenu, tr("menu.clearList"), #selector(MainWindowController.clearDeletionList(_:)), "", wc)
        colMenu.addItem(.separator())
        // ⌘⌫ opens the confirm sheet (never a bare ⌫ — README §6).
        let del = add(colMenu, tr("menu.moveToTrash"), #selector(MainWindowController.trashCollected(_:)), ShortcutPolicy.openConfirmKey, wc)
        del.keyEquivalentModifierMask = [.command]
        add(colMenu, tr("menu.deletePermanently"), #selector(MainWindowController.deleteCollectedPermanently(_:)), "", wc)
        colItem.submenu = colMenu

        // Window
        let winItem = NSMenuItem()
        main.addItem(winItem)
        let winMenu = NSMenu(title: tr("menu.window"))
        winMenu.addItem(withTitle: tr("menu.minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: tr("menu.zoom"), action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        winItem.submenu = winMenu
        NSApp.windowsMenu = winMenu

        return main
    }

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String, _ target: AnyObject) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }
}
#endif
