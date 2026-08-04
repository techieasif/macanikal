import SwiftUI

@main
struct MacanikalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            ControlPanelView()
                .environmentObject(appDelegate.controller)
        } label: {
            Image(systemName: "keyboard.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When acting as a unit-test host, don't start the audio engine or
        // request the Input Monitoring permission.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        controller.start()
    }
}
