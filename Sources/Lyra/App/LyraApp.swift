import SwiftUI
import AppKit
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSSetUncaughtExceptionHandler { exception in
            DiagnosticsLogger.logSync(
                "Uncaught exception: \(exception.name.rawValue) \(exception.reason ?? "")",
                category: "crash"
            )
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = image
        }
    }
}

@main
struct LyraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1200, height: 760)
        .commands {
            // Remove default New Window command for a cleaner music-app feel
            CommandGroup(replacing: .newItem) {}
        }
    }
}
