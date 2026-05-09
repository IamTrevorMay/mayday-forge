import Foundation

struct Workflow: Identifiable, Codable, Hashable {
    static func == (lhs: Workflow, rhs: Workflow) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    var id: UUID
    var name: String
    var enabled: Bool
    var trigger: WorkflowTrigger
    var actionType: String
    var actionConfig: [String: String]
    var createdAt: Date
    var lastRunAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        enabled: Bool = true,
        trigger: WorkflowTrigger,
        actionType: String,
        actionConfig: [String: String] = [:],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.trigger = trigger
        self.actionType = actionType
        self.actionConfig = actionConfig
        self.createdAt = createdAt
    }
}

enum WorkflowTrigger: Codable, Hashable {
    case manual
    case folderWatch(path: String, fileTypes: [String], namePattern: String, ignoreHidden: Bool)
    case schedule(cron: String)
    case gitPush(repoPath: String, branch: String)
    case appLaunch

    // Migration: decode old format without filters
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: String].self) {
            // Legacy simple format
            if let path = dict["folderWatch.path"] {
                self = .folderWatch(path: path, fileTypes: [], namePattern: "", ignoreHidden: true)
                return
            }
        }
        // New tagged enum format
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        if keyed.contains(.manual) {
            self = .manual
        } else if keyed.contains(.folderWatch) {
            let nested = try keyed.nestedContainer(keyedBy: FolderWatchKeys.self, forKey: .folderWatch)
            self = .folderWatch(
                path: try nested.decode(String.self, forKey: .path),
                fileTypes: (try? nested.decode([String].self, forKey: .fileTypes)) ?? [],
                namePattern: (try? nested.decode(String.self, forKey: .namePattern)) ?? "",
                ignoreHidden: (try? nested.decode(Bool.self, forKey: .ignoreHidden)) ?? true
            )
        } else if keyed.contains(.schedule) {
            let nested = try keyed.nestedContainer(keyedBy: ScheduleKeys.self, forKey: .schedule)
            self = .schedule(cron: try nested.decode(String.self, forKey: .cron))
        } else if keyed.contains(.gitPush) {
            let nested = try keyed.nestedContainer(keyedBy: GitPushKeys.self, forKey: .gitPush)
            self = .gitPush(
                repoPath: try nested.decode(String.self, forKey: .repoPath),
                branch: (try? nested.decode(String.self, forKey: .branch)) ?? "main"
            )
        } else if keyed.contains(.appLaunch) {
            self = .appLaunch
        } else {
            self = .manual
        }
    }

    private enum CodingKeys: String, CodingKey {
        case manual, folderWatch, schedule, gitPush, appLaunch
    }

    private enum FolderWatchKeys: String, CodingKey {
        case path, fileTypes, namePattern, ignoreHidden
    }

    private enum ScheduleKeys: String, CodingKey {
        case cron
    }

    private enum GitPushKeys: String, CodingKey {
        case repoPath, branch
    }
}

struct RunRecord: Identifiable {
    let id: UUID
    let workflowId: UUID
    let workflowName: String
    let actionType: String
    let startedAt: Date
    var finishedAt: Date?
    var status: RunStatus
    var output: [String]

    enum RunStatus: String {
        case running
        case success
        case failed
    }
}
