import Foundation

protocol ForgeAction {
    static var typeId: String { get }
    static var displayName: String { get }
    static var description: String { get }
    static var configFields: [ActionConfigField] { get }

    init(config: [String: String])
    func execute(trigger: TriggerEvent) async throws -> ActionResult
}

struct ActionConfigField {
    let key: String
    let label: String
    let placeholder: String
    let required: Bool
    let fieldType: FieldType

    enum FieldType {
        case text
        case folderPicker
        case filePicker
    }

    init(key: String, label: String, placeholder: String = "", required: Bool = true, fieldType: FieldType = .text) {
        self.key = key
        self.label = label
        self.placeholder = placeholder
        self.required = required
        self.fieldType = fieldType
    }
}

struct TriggerEvent {
    let type: TriggerType
    let path: String?
    let timestamp: Date
    let metadata: [String: String]

    enum TriggerType {
        case fileCreated
        case fileModified
        case manual
        case scheduled
        case gitPush
        case appLaunch
    }

    init(type: TriggerType, path: String? = nil, timestamp: Date = Date(), metadata: [String: String] = [:]) {
        self.type = type
        self.path = path
        self.timestamp = timestamp
        self.metadata = metadata
    }

    var fileName: String? {
        guard let p = path else { return nil }
        return (p as NSString).lastPathComponent
    }

    var fileExtension: String? {
        guard let name = fileName else { return nil }
        return (name as NSString).pathExtension
    }

    var fileNameWithoutExtension: String? {
        guard let name = fileName else { return nil }
        return (name as NSString).deletingPathExtension
    }

    var parentFolder: String? {
        guard let p = path else { return nil }
        return (p as NSString).deletingLastPathComponent
    }
}

struct ActionResult {
    let success: Bool
    let output: [String]
    let error: String?

    static func ok(_ lines: [String] = []) -> ActionResult {
        ActionResult(success: true, output: lines, error: nil)
    }

    static func fail(_ error: String, output: [String] = []) -> ActionResult {
        ActionResult(success: false, output: output, error: error)
    }
}
