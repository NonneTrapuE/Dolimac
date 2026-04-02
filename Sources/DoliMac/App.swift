import SwiftUI
import AppKit

@main
struct DolibarrBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // Aucune fenêtre principale — app 100% status bar
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var setupWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // Pas d'icône Dock

        // Vérifier si c'est le premier lancement
        if !AppState.shared.isInstalled {
            showSetupWizard()
        } else {
            statusBarController = StatusBarController()
        }
    }

    func showSetupWizard() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dolibarr — Installation"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: SetupWizardView {
                // Callback quand l'installation est terminée
                window.close()
                self.statusBarController = StatusBarController()
            }
        )
        setupWindowController = NSWindowController(window: window)
        setupWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
