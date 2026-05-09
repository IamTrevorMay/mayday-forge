import Foundation

struct RunShellCommandAction: ForgeAction {
    static let typeId = "run-shell"
    static let displayName = "Run Shell Command"
    static let description = "Execute a shell command with variable substitution ({file}, {folder}, {date}, etc.)"
    static let configFields: [ActionConfigField] = [
        ActionConfigField(key: "command", label: "Command", placeholder: "echo \"Processing {filename}\""),
        ActionConfigField(key: "workingDirectory", label: "Working Directory", placeholder: "{folder}", required: false, fieldType: .folderPicker),
        ActionConfigField(key: "shell", label: "Shell", placeholder: "/bin/zsh", required: false),
    ]

    private let command: String
    private let workingDirectory: String
    private let shell: String

    init(config: [String: String]) {
        self.command = config["command"] ?? ""
        self.workingDirectory = config["workingDirectory"] ?? ""
        self.shell = config["shell"] ?? "/bin/zsh"
    }

    func execute(trigger: TriggerEvent) async throws -> ActionResult {
        guard !command.isEmpty else { return .fail("No command configured") }

        let vars = VariableHelper.build(from: trigger)
        let resolvedCommand = VariableHelper.apply(command, vars: vars)
        let resolvedDir = workingDirectory.isEmpty ? nil : VariableHelper.apply(workingDirectory, vars: vars)

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-c", resolvedCommand]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if let dir = resolvedDir, FileManager.default.fileExists(atPath: dir) {
            process.currentDirectoryURL = URL(fileURLWithPath: dir)
        }

        // Inherit shell environment
        var env = ProcessInfo.processInfo.environment
        for (key, value) in vars {
            env["FORGE_\(key.uppercased())"] = value
        }
        process.environment = env

        try process.run()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        var output: [String] = ["$ \(resolvedCommand)"]

        if let stdout = String(data: stdoutData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !stdout.isEmpty {
            output.append(contentsOf: stdout.components(separatedBy: .newlines))
        }

        if process.terminationStatus != 0 {
            if let stderr = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !stderr.isEmpty {
                output.append(contentsOf: stderr.components(separatedBy: .newlines).map { "[stderr] \($0)" })
            }
            return .fail("Exit code: \(process.terminationStatus)", output: output)
        }

        return .ok(output)
    }
}
