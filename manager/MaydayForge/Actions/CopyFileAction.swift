import Foundation

struct CopyFileAction: ForgeAction {
    static let typeId = "copy-file"
    static let displayName = "Copy File"
    static let description = "Copy a file to a destination folder (keeps original)"
    static let configFields: [ActionConfigField] = [
        ActionConfigField(key: "destination", label: "Destination Folder", placeholder: "/path/to/folder", fieldType: .folderPicker),
        ActionConfigField(key: "overwrite", label: "Overwrite if Exists (yes/no)", placeholder: "no", required: false),
    ]

    private let destination: String
    private let overwrite: Bool

    init(config: [String: String]) {
        self.destination = config["destination"] ?? ""
        self.overwrite = (config["overwrite"] ?? "no").lowercased() == "yes"
    }

    func execute(trigger: TriggerEvent) async throws -> ActionResult {
        guard let sourcePath = trigger.path else {
            return .fail("No source file path in trigger")
        }
        guard !destination.isEmpty else {
            return .fail("No destination configured")
        }

        let fm = FileManager.default
        let vars = VariableHelper.build(from: trigger)
        let resolvedDest = VariableHelper.apply(destination, vars: vars)
        let fileName = (sourcePath as NSString).lastPathComponent
        let destPath = (resolvedDest as NSString).appendingPathComponent(fileName)

        try fm.createDirectory(atPath: resolvedDest, withIntermediateDirectories: true)

        if fm.fileExists(atPath: destPath) {
            if overwrite {
                try fm.removeItem(atPath: destPath)
            } else {
                return .fail("File already exists: \(destPath)")
            }
        }

        try fm.copyItem(atPath: sourcePath, toPath: destPath)
        return .ok(["Copied \(fileName) -> \(destPath)"])
    }
}
