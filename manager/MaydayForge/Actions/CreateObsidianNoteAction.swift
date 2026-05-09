import Foundation

struct CreateObsidianNoteAction: ForgeAction {
    static let typeId = "create-obsidian-note"
    static let displayName = "Create Obsidian Note"
    static let description = "Create a new markdown note in your Obsidian vault from a template"
    static let configFields: [ActionConfigField] = [
        ActionConfigField(key: "vaultPath", label: "Vault Path", placeholder: "/path/to/vault", fieldType: .folderPicker),
        ActionConfigField(key: "folder", label: "Subfolder", placeholder: "Inbox", required: false),
        ActionConfigField(key: "titlePattern", label: "Title Pattern", placeholder: "{date} {name}"),
        ActionConfigField(key: "template", label: "Template Body", placeholder: "---\\ntags: []\\n---\\n\\n# {name}"),
        ActionConfigField(key: "tags", label: "Tags (comma-separated)", placeholder: "inbox, auto", required: false),
    ]

    private let vaultPath: String
    private let folder: String
    private let titlePattern: String
    private let template: String
    private let tags: [String]

    init(config: [String: String]) {
        self.vaultPath = config["vaultPath"] ?? ""
        self.folder = config["folder"] ?? ""
        self.titlePattern = config["titlePattern"] ?? "{date} {name}"
        self.template = config["template"] ?? "---\ntags: []\n---\n\n# {name}\n"
        self.tags = (config["tags"] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func execute(trigger: TriggerEvent) async throws -> ActionResult {
        guard !vaultPath.isEmpty else {
            return .fail("Vault path not configured")
        }

        let fm = FileManager.default
        let vars = buildVariables(trigger: trigger)

        // Build title
        let title = applyVariables(titlePattern, vars: vars)
        let sanitizedTitle = title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")

        // Build destination path
        var destDir = vaultPath
        if !folder.isEmpty {
            destDir = (vaultPath as NSString).appendingPathComponent(folder)
        }
        try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)

        let filePath = (destDir as NSString).appendingPathComponent(sanitizedTitle + ".md")

        guard !fm.fileExists(atPath: filePath) else {
            return .fail("Note already exists: \(sanitizedTitle).md")
        }

        // Build content
        var content = applyVariables(template, vars: vars)

        // Inject tags into frontmatter if template has ---
        if !tags.isEmpty && content.hasPrefix("---") {
            let tagList = tags.map { "\"\($0)\"" }.joined(separator: ", ")
            content = content.replacingOccurrences(of: "tags: []", with: "tags: [\(tagList)]")
        }

        // Handle escaped newlines from config
        content = content.replacingOccurrences(of: "\\n", with: "\n")

        try content.write(toFile: filePath, atomically: true, encoding: .utf8)

        return .ok([
            "Created note: \(sanitizedTitle).md",
            "Location: \(filePath)",
        ])
    }

    private func buildVariables(trigger: TriggerEvent) -> [String: String] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: Date())

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeStr = timeFormatter.string(from: Date())

        var vars: [String: String] = [
            "date": dateStr,
            "time": timeStr,
            "datetime": "\(dateStr) \(timeStr)",
        ]

        if let name = trigger.fileNameWithoutExtension {
            vars["name"] = name
        } else {
            vars["name"] = "Untitled"
        }
        if let ext = trigger.fileExtension {
            vars["ext"] = ext
        }
        if let path = trigger.path {
            vars["path"] = path
        }
        if let folder = trigger.parentFolder {
            vars["folder"] = (folder as NSString).lastPathComponent
        }

        // Include trigger metadata
        for (key, value) in trigger.metadata {
            vars[key] = value
        }

        return vars
    }

    private func applyVariables(_ text: String, vars: [String: String]) -> String {
        var result = text
        for (key, value) in vars {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }
}
