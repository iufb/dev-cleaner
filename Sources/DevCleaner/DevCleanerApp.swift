import SwiftUI
import AppKit

@main
struct DevCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = CleanerStore()

    var body: some Scene {
        WindowGroup("DevCleaner") {
            ContentView()
                .environment(store)
                .frame(minWidth: 940, minHeight: 600)
                .task { await store.scanAll() }
        }
        .windowToolbarStyle(.unified)
    }
}

/// Нужен, чтобы приложение, запущенное через `swift run`, вело себя как обычное
/// (иконка в Dock, окно на переднем плане).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
