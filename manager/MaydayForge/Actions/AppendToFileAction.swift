import Foundation

struct AppendToFileAction: ForgeAction {
    static let typeId = "append-to-file"
    static let displayName = "Append to File"
    static let description = "Append text to the end of a file (great for Obsidian daily notes and logs)"
    static let configFields: [ActionConfigField] = [
        ActionConfigField(key: "filePath", label: "Target File", placeholder: "/path/to/vault/Daily Notes/{date}.md", fieldType: .filePicker),
        ActionConfigField(key: "text", label: "Text to Append", placeholder: "- [ ] {name} added at {time}"),
        ActionConfigField(key: "createIfMissing", label: "Create if Missing (yes/no)", placeholder: "yes", required: false),
        ActionConfigField(key: "newlineBefore", label: "Add Newline Before (yes/no)", placeholder: "yes", required: false),
    ]

    private let filePath: String
    private let text: String
    private let createIfMissing: Bool
    private let newlineBefore: Bool

    init(config: [String: String]) {
        self.filePath = config["filePath"] ?? ""
        self.text = config["text"] ?? ""
        self.createIfMissing = (config["createIfMissing"] ?? "yes").lowercased() != "no"
        self.newlineBefore = (config["newlineBefore"] ?? "yes").lowercased() != "no"
    }

    func execute(trigger: TriggerEvent) async throws -> ActionResult {
        guard !filePath.isEmpty else { return .fail("No target file configured") }
        guard !text.isEmpty else { return .fail("No text to append") }

        let vars = VariableHelper.build(from: trigger)
        let resolvedPath = VariableHelper.apply(filePath, vars: vars)
        let resolvedText = VariableHelper.apply(text, vars: vars)
            .replacingOccurrences(of: "\\n", with: "\n")

        let fm = FileManager.default
        let dir = (resolvedPath as NSString).deletingLastPathComponent

        if !fm.fileExists(atPath: resolvedPath) {
            guard createIfMissing else {
                return .fail("File not found: \(resolvedPath)")
            }
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try resolvedText.write(toFile: resolvedPath, atomically: true, encoding: .utf8)
            return .ok(["Created file and wrote content: \(resolvedPath)"])
        }

        var existing = try String(contentsOfFile: resolvedPath, encoding: .utf8)
        if newlineBefore && !existing.hasSuffix("\n") {
            existing += "\n"
        }
        existing += resolvedText

        try existing.write(toFile: resolvedPath, atomically: true, encoding: .utf8)
        return .ok(["Appended to \((resolvedPath as NSString).lastPathComponent)"])
    }
}
