import AppKit
import SwiftUI

@main
struct TapeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Tapeek", id: "main") {
            OnboardingView()
                .frame(minWidth: 520, minHeight: 420)
        }
        .defaultSize(width: 640, height: 480)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
