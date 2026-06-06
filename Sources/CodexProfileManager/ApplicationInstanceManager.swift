import AppKit
import Foundation

enum ApplicationInstanceManager {
    static func terminateOtherInstances(reason: String) {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let currentBundleURL = Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath()
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).filter { app in
            guard app.processIdentifier != currentPID else { return false }
            guard let bundleURL = app.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() else { return true }
            return bundleURL.path == currentBundleURL.path
        }
        guard !others.isEmpty else { return }

        OperationLogger.warning(
            "app.instances.terminateOthers",
            message: "Terminating other app instances",
            metadata: ["reason": reason, "count": "\(others.count)"]
        )
        for app in others {
            app.terminate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            for app in others where !app.isTerminated {
                app.forceTerminate()
            }
        }
    }
}
