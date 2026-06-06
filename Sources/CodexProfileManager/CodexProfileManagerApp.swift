import AppKit
import SwiftUI

@main
struct CodexProfileManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Codex 多账号管理器") {
            MainView(model: model)
                .frame(minWidth: 620, minHeight: 680)
        }
        .defaultSize(width: 680, height: 720)

        MenuBarExtra(model.menuBarLabel, systemImage: "person.2.circle") {
            MainView(model: model)
                .frame(width: 560, height: 680)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        ApplicationInstanceManager.terminateOtherInstances(reason: "appLaunched")
        NSApp.activate(ignoringOtherApps: true)
    }
}
