import AppKit
import SwiftUI

/// Main application delegate.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var notchPanelController: NotchPanelController?
    private var hookEventRouter: HookEventRouter?
    private var sessionWatcher: SessionWatcher?
    private let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = ClawdIcon.appIcon()

        setupMenuBar()
        setupNotchPanel()
        startServices()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SocketServer.shared.stop()
        sessionWatcher?.stop()
    }

    // MARK: - Setup

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            let icon = ClawdIcon.menuBarIcon()
            icon.size = NSSize(width: 18, height: 18)
            button.image = icon
        }

        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Show/Hide Panel", action: #selector(togglePanel), keyEquivalent: "p"))
        menu.addItem(NSMenuItem.separator())

        // Permission mode submenu
        let modeMenu = NSMenu()
        for mode in PermissionMode.allCases {
            let item = NSMenuItem(title: mode.rawValue, action: #selector(setPermissionMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = appState.permissionMode == mode ? .on : .off

            // Add description
            switch mode {
            case .observe:
                item.toolTip = "Just watch — Claude Code handles permissions normally"
            case .alwaysAllow:
                item.toolTip = "Auto-approve all tool calls (bypass permissions)"
            case .manual:
                item.toolTip = "Approve every tool call from Code Island UI"
            }
            modeMenu.addItem(item)
        }
        let modeItem = NSMenuItem(title: "Permission Mode", action: nil, keyEquivalent: "")
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Configure Hooks", action: #selector(configureHooks), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Remove Hooks", action: #selector(removeHooks), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Code Island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func setupNotchPanel() {
        notchPanelController = NotchPanelController(appState: appState)
        notchPanelController?.setup()
    }

    private func startServices() {
        SocketServer.shared.start()

        hookEventRouter = HookEventRouter(appState: appState)
        hookEventRouter?.start()

        sessionWatcher = SessionWatcher(appState: appState)
        sessionWatcher?.start()

        SettingsConfigurator.ensureHooksConfigured()

        print("[CodeIsland] All services started")
    }

    // MARK: - Actions

    @objc private func togglePanel() {
        appState.isExpanded.toggle()
    }

    @objc private func setPermissionMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let mode = PermissionMode(rawValue: rawValue) else { return }
        appState.permissionMode = mode
        rebuildMenu()  // Update checkmarks
    }

    @objc private func configureHooks() {
        SettingsConfigurator.ensureHooksConfigured()
    }

    @objc private func removeHooks() {
        SettingsConfigurator.removeHooks()
    }
}
