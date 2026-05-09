import Foundation

struct FilterAction: ForgeAction {
    static let typeId = "filter"
    static let displayName = "Filter (Conditional Gate)"
    static let description = "Only proceed if the trigger file matches conditions (type, name, size)"
    static let configFields: [ActionConfigField] = [
        ActionConfigField(key: "fileTypes", label: "Allowed File Types (comma-separated)", placeholder: "md, txt, pdf", required: false),
        ActionConfigField(key: "nameContains", label: "Name Must Contain", placeholder: "", required: false),
        ActionConfigField(key: "namePattern", label: "Name Regex (wrap in /)", placeholder: "/^draft-.*/", required: false),
        ActionConfigField(key: "minSizeKB", label: "Min Size (KB)", placeholder: "0", required: false),
        ActionConfigField(key: "maxSizeKB", label: "Max Size (KB)", placeholder: "", required: false),
    ]

    private let fileTypes: [String]
    private let nameContains: String
    private let namePattern: String
    private let minSizeKB: Int?
    private let maxSizeKB: Int?

    init(config: [String: String]) {
        self.fileTypes = (config["fileTypes"] ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty }
        self.nameContains = config["nameContains"] ?? ""
        self.namePattern = config["namePattern"] ?? ""
        self.minSizeKB = Int(config["minSizeKB"] ?? "")
        self.maxSizeKB = Int(config["maxSizeKB"] ?? "")
    }

    func execute(trigger: TriggerEvent) async throws -> ActionResult {
        guard let filePath = trigger.path else {
            return .fail("Filter requires a file path from trigger")
        }

        let fileName = (filePath as NSString).lastPathComponent
        let ext = (fileName as NSString).pathExtension.lowercased()

        // File type check
        if !fileTypes.isEmpty && !fileTypes.contains(ext) {
            return .fail("Filtered: .\(ext) not in [\(fileTypes.joined(separator: ", "))]")
        }

        // Name contains check
        if !nameContains.isEmpty && !fileName.localizedCaseInsensitiveContains(nameContains) {
            return .fail("Filtered: \"\(fileName)\" doesn't contain \"\(nameContains)\"")
        }

        // Regex check
        if namePattern.hasPrefix("/") && namePattern.hasSuffix("/") && namePattern.count > 2 {
            let pattern = String(namePattern.dropFirst().dropLast())
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(fileName.startIndex..., in: fileName)
                if regex.firstMatch(in: fileName, range: range) == nil {
                    return .fail("Filtered: \"\(fileName)\" doesn't match pattern \(namePattern)")
                }
            }
        }

        // Size checks
        if minSizeKB != nil || maxSizeKB != nil {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
               let size = attrs[.size] as? Int {
                let sizeKB = size / 1024
                if let min = minSizeKB, sizeKB < min {
                    return .fail("Filtered: \(sizeKB)KB < min \(min)KB")
                }
                if let max = maxSizeKB, sizeKB > max {
                    return .fail("Filtered: \(sizeKB)KB > max \(max)KB")
                }
            }
        }

        return .ok(["Passed: \(fileName)"])
    }
}
