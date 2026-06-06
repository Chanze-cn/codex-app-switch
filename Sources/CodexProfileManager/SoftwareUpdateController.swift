import Foundation
import Sparkle

@MainActor
final class SoftwareUpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    private var updaterController: SPUStandardUpdaterController!

    override init() {
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        OperationLogger.info(
            "update.install.willStart",
            message: "Sparkle will install update",
            metadata: ["version": item.displayVersionString]
        )
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        OperationLogger.info("update.relaunch.willStart", message: "Sparkle will relaunch the app")
        ApplicationInstanceManager.terminateOtherInstances(reason: "sparkleRelaunch")
    }
}
