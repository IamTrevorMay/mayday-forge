import Foundation

enum VariableHelper {
    static func build(from trigger: TriggerEvent) -> [String: String] {
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
        }
        if let ext = trigger.fileExtension {
            vars["ext"] = ext
        }
        if let fileName = trigger.fileName {
            vars["filename"] = fileName
        }
        if let path = trigger.path {
            vars["path"] = path
        }
        if let folder = trigger.parentFolder {
            vars["folder"] = (folder as NSString).lastPathComponent
        }

        for (key, value) in trigger.metadata {
            vars[key] = value
        }

        return vars
    }

    static func apply(_ text: String, vars: [String: String]) -> String {
        var result = text
        for (key, value) in vars {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }
}
