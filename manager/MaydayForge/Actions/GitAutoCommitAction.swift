import Foundation

struct GitAutoCommitAction: ForgeAction {
    static let typeId = "git-auto-commit"
    static let displayName = "Git Auto-Commit"
    static let description = "Stage and commit all changes in a repo with a configurable message"
    static let configFields: [ActionConfigField] = [
        ActionConfigField(key: "repoPath", label: "Repository Path", placeholder: "/path/to/repo", fieldType: .folderPicker),
        ActionConfigField(key: "message", label: "Commit Message", placeholder: "auto: {date} {time}"),
        ActionConfigField(key: "addAll", label: "Stage All Changes (yes/no)", placeholder: "yes", required: false),
    ]

    private let repoPath: String
    private let message: String
    private let addAll: Bool

    init(config: [String: String]) {
        self.repoPath = config["repoPath"] ?? ""
        self.message = config["message"] ?? "auto: {date} {time}"
        self.addAll = (config["addAll"] ?? "yes").lowercased() != "no"
    }

    func execute(trigger: TriggerEvent) async throws -> ActionResult {
        let path = repoPath.isEmpty ? (trigger.path ?? "") : repoPath
        guard !path.isEmpty else {
            return .fail("No repository path configured")
        }

        let vars = VariableHelper.build(from: trigger)
        let resolvedMessage = VariableHelper.apply(message, vars: vars)
        var output: [String] = []

        // Check for changes
        let status = runGit(["status", "--porcelain"], at: path)
        guard let status, !status.isEmpty else {
            return .ok(["No changes to commit in \(path)"])
        }

        output.append("Changes detected:")
        output.append(contentsOf: status.components(separatedBy: .newlines).prefix(10))

        // Stage
        if addAll {
            let _ = runGit(["add", "-A"], at: path)
            output.append("Staged all changes")
        }

        // Commit
        guard let commitOutput = runGit(["commit", "-m", resolvedMessage], at: path) else {
            return .fail("Git commit failed", output: output)
        }

        output.append(commitOutput)
        return .ok(output)
    }

    private func runGit(_ args: [String], at path: String) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
