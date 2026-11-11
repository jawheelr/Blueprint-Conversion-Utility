import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        removeServicesMenu()
        configureWindows()
        DispatchQueue.main.async {
            self.removeServicesMenu()
            self.configureWindows()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        configureWindows()
    }

    private func configureWindows() {
        for window in NSApp.windows {
            window.title = ""
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.toolbarStyle = .unifiedCompact
            window.standardWindowButton(.documentIconButton)?.isHidden = true
        }
    }

    private func removeServicesMenu() {
        NSApp.servicesMenu = nil
        guard let applicationMenu = NSApp.mainMenu?.items.first?.submenu else { return }
        for item in applicationMenu.items.reversed() where item.title == "Services" {
            applicationMenu.removeItem(item)
        }
    }
}
