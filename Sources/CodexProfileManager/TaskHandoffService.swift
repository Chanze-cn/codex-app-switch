import AppKit
import Foundation

struct TaskHandoffService {
    func create(
        sourceProfileID: UUID?,
        targetProfileID: UUID,
        workspacePath: String,
        threadID: String?,
        summary: String,
        notes: String,
        unfinishedItems: [String]
    ) -> HandoffPackage {
        HandoffPackage(
            id: UUID(),
            sourceProfileID: sourceProfileID,
            targetProfileID: targetProfileID,
            workspacePath: workspacePath,
            gitBranch: gitBranch(at: workspacePath),
            threadID: threadID,
            summary: summary,
            notes: notes,
            unfinishedItems: unfinishedItems.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
            createdAt: Date()
        )
    }

    func copyPrompt(_ handoff: HandoffPackage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(handoff.prompt, forType: .string)
    }

    private func gitBranch(at path: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path, "branch", "--show-current"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
