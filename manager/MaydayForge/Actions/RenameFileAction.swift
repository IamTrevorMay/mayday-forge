import Foundation

struct RenameFileAction: ForgeAction {
    static let typeId = "rename-file"
    static let displayName = "Rename File"
    static let description = "Rename a file using a pattern ({date}, {name}, {ext}, {folder})"
    static let configFields: [ActionConfigField] = [
        ActionConfigField(key: "pattern", label: "Name Pattern", placeholder: "{date}_{name}.{ext}"),
    ]

    private let pattern: String

    init(config: [String: String]) {
        self.pattern = config["pattern"] ?? "{name}.{ext}"
    }

    func execute(trigger: TriggerEvent) async throws -> ActionResult {
        guard let sourcePath = trigger.path else {
            return .fail("No source file path in trigger")
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: sourcePath) else {
            return .fail("File not found: \(sourcePath)")
        }

        let vars = VariableHelper.build(from: trigger)
        let newName = VariableHelper.apply(pattern, vars: vars)
        let dir = (sourcePath as NSString).deletingLastPathComponent
        let newPath = (dir as NSString).appendingPathComponent(newName)

        guard newPath != sourcePath else {
            return .ok(["No rename needed — name unchanged"])
        }

        try fm.moveItem(atPath: sourcePath, toPath: newPath)
        let oldName = (sourcePath as NSString).lastPathComponent
        return .ok(["Renamed \(oldName) -> \(newName)"])
    }
}
