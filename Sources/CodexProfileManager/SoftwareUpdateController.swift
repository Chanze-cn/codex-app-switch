import Foundation
import Sparkle

struct AvailableSoftwareUpdate: Equatable, Identifiable {
    let version: String
    let build: String
    let infoURL: URL?
    let discoveredAt: Date

    var id: String { "\(version)-\(build)" }
}

@MainActor
final class SoftwareUpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {
    private enum SparkleError {
        static let domain = "SUSparkleErrorDomain"
        static let noUpdateCode = 1001
    }

    private var updaterController: SPUStandardUpdaterController!
    private var hasStartedLaunchCheck = false
    private var dismissedUpdateID: String?

    @Published private(set) var availableUpdate: AvailableSoftwareUpdate?
    @Published private(set) var isCheckingForUpdate = false
    @Published private(set) var lastUpdateCheckAt: Date?
    @Published private(set) var lastUpdateCheckError: String?

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

    var visibleAvailableUpdate: AvailableSoftwareUpdate? {
        guard let availableUpdate, availableUpdate.id != dismissedUpdateID else { return nil }
        return availableUpdate
    }

    var statusText: String {
        if isCheckingForUpdate { return "正在检测新版本" }
        if let availableUpdate { return "发现新版本 \(availableUpdate.version)" }
        if let lastUpdateCheckAt {
            return "上次检查 \(lastUpdateCheckAt.formatted(date: .omitted, time: .shortened))"
        }
        return "尚未检查"
    }

    func startLaunchUpdateCheck() {
        guard !hasStartedLaunchCheck else { return }
        hasStartedLaunchCheck = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            probeForUpdates()
        }
    }

    func probeForUpdates() {
        guard canCheckForUpdates else {
            OperationLogger.warning(
                "update.probe.skipped",
                message: "Skipped update probe because another update session is active"
            )
            return
        }

        isCheckingForUpdate = true
        lastUpdateCheckError = nil
        OperationLogger.info("update.probe.started", message: "Checking for update information")
        updaterController.updater.checkForUpdateInformation()
    }

    func checkForUpdates() {
        dismissedUpdateID = nil
        lastUpdateCheckError = nil
        updaterController.checkForUpdates(nil)
    }

    func dismissAvailableUpdate() {
        dismissedUpdateID = availableUpdate?.id
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let update = AvailableSoftwareUpdate(
            version: item.displayVersionString,
            build: item.versionString,
            infoURL: item.infoURL,
            discoveredAt: Date()
        )
        availableUpdate = update
        lastUpdateCheckAt = Date()
        lastUpdateCheckError = nil
        OperationLogger.info(
            "update.probe.found",
            message: "Found available update",
            metadata: ["version": update.version, "build": update.build]
        )
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        availableUpdate = nil
        dismissedUpdateID = nil
        lastUpdateCheckAt = Date()
        lastUpdateCheckError = nil
        OperationLogger.info("update.probe.notFound", message: "No available update was found")
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        isCheckingForUpdate = false
        lastUpdateCheckAt = Date()
        if let error, !isExpectedNoUpdateError(error) {
            lastUpdateCheckError = error.localizedDescription
            OperationLogger.warning(
                "update.check.failed",
                message: "Update check finished with an error",
                error: error
            )
        }
    }

    private func isExpectedNoUpdateError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == SparkleError.domain && nsError.code == SparkleError.noUpdateCode
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
