import Foundation

struct GenerateChangelogAction: ForgeAction {
    static let typeId = "generate-changelog"
    static let displayName = "Generate Changelog"
    static let description = "Scan a project folder and generate a CHANGELOG.md from git commits"
    static let configFields: [ActionConfigField] = [
        ActionConfigField(key: "projectPath", label: "Project Path", placeholder: "/path/to/project"),
        ActionConfigField(key: "outputFile", label: "Output File", placeholder: "CHANGELOG.md", required: false),
    ]

    private let projectPath: String
    private let outputFile: String

    init(config: [String: String]) {
        self.projectPath = config["projectPath"] ?? ""
        self.outputFile = config["outputFile"] ?? "CHANGELOG.md"
    }

    func execute(trigger: TriggerEvent) async throws -> ActionResult {
        let path = projectPath.isEmpty ? (trigger.path ?? "") : projectPath

        guard !path.isEmpty else {
            return .fail("No project path configured or provided by trigger")
        }

        guard FileManager.default.fileExists(atPath: path) else {
            return .fail("Project path not found: \(path)")
        }

        // Run git log to get commits
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["log", "--pretty=format:%H|%ai|%s", "--no-merges"]
        process.currentDirectoryURL = URL(fileURLWithPath: path)
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8), !output.isEmpty else {
            return .fail("No git history found in \(path)")
        }

        // Parse commits and group by date
        var sections: [(date: String, commits: [String])] = []
        var currentDate = ""
        var currentCommits: [String] = []

        for line in output.components(separatedBy: .newlines) where !line.isEmpty {
            let parts = line.split(separator: "|", maxSplits: 2)
            guard parts.count == 3 else { continue }

            let dateStr = String(parts[1].prefix(10))
            let message = String(parts[2])

            if dateStr != currentDate {
                if !currentCommits.isEmpty {
                    sections.append((date: currentDate, commits: currentCommits))
                }
                currentDate = dateStr
                currentCommits = []
            }
            currentCommits.append(message)
        }
        if !currentCommits.isEmpty {
            sections.append((date: currentDate, commits: currentCommits))
        }

        // Build changelog markdown
        var changelog = "# Changelog\n\n"
        for section in sections {
            changelog += "## \(section.date)\n\n"
            for commit in section.commits {
                changelog += "- \(commit)\n"
            }
            changelog += "\n"
        }

        // Write file
        let outputPath = (path as NSString).appendingPathComponent(outputFile)
        try changelog.write(toFile: outputPath, atomically: true, encoding: .utf8)

        return .ok([
            "Generated changelog with \(sections.count) date sections",
            "Written to \(outputPath)",
        ])
    }
}
