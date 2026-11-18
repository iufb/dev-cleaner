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
        // Из Xcode и `swift run` запускается голый бинарник без .app: иконку из Info.plist
        // macOS не видит, поэтому ставим её в Dock сами.
        if Bundle.main.bundleURL.pathExtension != "app", let icon = AppIconArt.image() {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
