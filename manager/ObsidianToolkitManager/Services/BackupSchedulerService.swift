import Foundation

@Observable
final class BackupSchedulerService {
    enum Status: String {
        case idle, running, success, error
    }

    private(set) var status: Status = .idle
    private(set) var lastError: String?
    private(set) var recentOutput: [String] = []
    private(set) var lastBackupLog: BackupLog?
    private var process: Process?

    static let plistLabel = "com.trevor.obsidian-toolkit.supabase-backup"

    struct BackupLog: Codable {
        var lastBackupAt: String?
        var finishedAt: String?
        var durationSeconds: Double?
        var summary: Summary?

        struct Summary: Codable {
            var totalProjects: Int?
            var totalTables: Int?
            var totalErrors: Int?

            enum CodingKeys: String, CodingKey {
                case totalProjects = "total_projects"
                case totalTables = "total_tables"
                case totalErrors = "total_errors"
            }
        }

        enum CodingKeys: String, CodingKey {
            case lastBackupAt = "last_backup_at"
            case finishedAt = "finished_at"
            case durationSeconds = "duration_seconds"
            case summary
        }
    }

    // MARK: - Read backup status

    func loadLastBackupLog(backupVaultPath: String) {
        let logPath = (backupVaultPath as NSString).appendingPathComponent("_backup_log.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: logPath)) else { return }
        lastBackupLog = try? JSONDecoder().decode(BackupLog.self, from: data)
    }

    // MARK: - Run backup manually

    func runBackup(
        pythonPath: String,
        toolkitPath: String,
        environment: [String: String],
        projects: [String]? = nil,
        dryRun: Bool = false
    ) {
        guard status != .running else { return }

        status = .running
        lastError = nil
        recentOutput = []

        let configPath = (toolkitPath as NSString).appendingPathComponent("config.json")
        var args = ["-m", "agents.supabase_backup", "--config", configPath]
        if dryRun {
            args.append("--dry-run")
        }
        if let projects, !projects.isEmpty {
            args.append("--projects")
            args.append(contentsOf: projects)
        }

        let proc = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: toolkitPath)
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe
        proc.environment = environment

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.appendOutput(line)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.appendOutput("[stderr] " + line)
            }
        }

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                if p.terminationStatus == 0 {
                    self?.status = .success
                } else {
                    self?.lastError = "Exited with code \(p.terminationStatus)"
                    self?.status = .error
                }
                self?.process = nil
            }
        }

        do {
            try proc.run()
            process = proc
        } catch {
            lastError = error.localizedDescription
            status = .error
        }
    }

    func stop() {
        guard let proc = process, proc.isRunning else { return }
        proc.terminate()
        status = .idle
    }

    // MARK: - launchd plist management

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(plistLabel).plist")
    }

    static func isScheduleInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func installSchedule(
        pythonPath: String,
        toolkitPath: String,
        environment: [String: String]
    ) throws {
        let configPath = (toolkitPath as NSString).appendingPathComponent("config.json")

        // Sunday 11 PM Pacific = Monday 07:00 UTC (during PDT)
        // We use Calendar interval with Weekday=1 (Sunday), Hour=23
        // launchd uses local time when no TimeZone is specified
        let plist: [String: Any] = [
            "Label": plistLabel,
            "ProgramArguments": [
                pythonPath,
                "-m", "agents.supabase_backup",
                "--config", configPath,
            ],
            "WorkingDirectory": toolkitPath,
            "EnvironmentVariables": environment,
            "StartCalendarInterval": [
                "Weekday": 0,  // Sunday
                "Hour": 23,
                "Minute": 0,
            ],
            "StandardOutPath": (toolkitPath as NSString).appendingPathComponent("output/backup_stdout.log"),
            "StandardErrorPath": (toolkitPath as NSString).appendingPathComponent("output/backup_stderr.log"),
            "RunAtLoad": false,
        ]

        let launchAgentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)

        // Load the plist
        let loadProc = Process()
        loadProc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        loadProc.arguments = ["load", plistURL.path]
        try loadProc.run()
        loadProc.waitUntilExit()
    }

    static func uninstallSchedule() throws {
        guard isScheduleInstalled() else { return }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["unload", plistURL.path]
        try proc.run()
        proc.waitUntilExit()

        try FileManager.default.removeItem(at: plistURL)
    }

    private func appendOutput(_ text: String) {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        recentOutput.append(contentsOf: lines)
        if recentOutput.count > 200 {
            recentOutput = Array(recentOutput.suffix(200))
        }
    }
}
