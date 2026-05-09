import Foundation

final class GitPushWatcher {
    private let repoPath: String
    private let branch: String
    private let callback: (TriggerEvent) -> Void
    private var timer: DispatchSourceTimer?
    private var lastCommitHash: String?

    init(repoPath: String, branch: String = "main", callback: @escaping (TriggerEvent) -> Void) {
        self.repoPath = repoPath
        self.branch = branch
        self.callback = callback
    }

    func start() {
        lastCommitHash = currentCommitHash()

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 5, repeating: 5)
        timer.setEventHandler { [weak self] in
            self?.checkForNewCommits()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func checkForNewCommits() {
        let current = currentCommitHash()
        guard let current, current != lastCommitHash else { return }

        let message = commitMessage(for: current) ?? ""
        let event = TriggerEvent(
            type: .gitPush,
            path: repoPath,
            metadata: [
                "commit": current,
                "branch": branch,
                "message": message,
            ]
        )
        lastCommitHash = current
        callback(event)
    }

    private func currentCommitHash() -> String? {
        runGit(["rev-parse", branch])
    }

    private func commitMessage(for hash: String) -> String? {
        runGit(["log", "-1", "--pretty=%s", hash])
    }

    private func runGit(_ args: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: repoPath)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
