import Foundation

final class FolderWatcher {
    private let path: String
    private let fileTypes: [String]
    private let namePattern: String
    private let ignoreHidden: Bool
    private let callback: (TriggerEvent) -> Void
    private var knownFiles: [String: Date] = [:]
    private var timer: DispatchSourceTimer?

    init(
        path: String,
        fileTypes: [String] = [],
        namePattern: String = "",
        ignoreHidden: Bool = true,
        callback: @escaping (TriggerEvent) -> Void
    ) {
        self.path = path
        self.fileTypes = fileTypes.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
        self.namePattern = namePattern
        self.ignoreHidden = ignoreHidden
        self.callback = callback
    }

    func start() {
        knownFiles = currentFileStates()

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            self?.checkForChanges()
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func checkForChanges() {
        let current = currentFileStates()

        for (file, modDate) in current {
            let fullPath = (path as NSString).appendingPathComponent(file)

            if knownFiles[file] == nil {
                // New file
                if matchesFilters(file) {
                    callback(TriggerEvent(type: .fileCreated, path: fullPath))
                }
            } else if let oldDate = knownFiles[file], modDate > oldDate {
                // Modified file
                if matchesFilters(file) {
                    callback(TriggerEvent(type: .fileModified, path: fullPath))
                }
            }
        }

        knownFiles = current
    }

    private func matchesFilters(_ fileName: String) -> Bool {
        // File type filter
        if !fileTypes.isEmpty {
            let ext = (fileName as NSString).pathExtension.lowercased()
            if !fileTypes.contains(ext) {
                return false
            }
        }

        // Name pattern filter (simple contains match, or regex if wrapped in /)
        if !namePattern.isEmpty {
            if namePattern.hasPrefix("/") && namePattern.hasSuffix("/") && namePattern.count > 2 {
                let pattern = String(namePattern.dropFirst().dropLast())
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                    let range = NSRange(fileName.startIndex..., in: fileName)
                    if regex.firstMatch(in: fileName, range: range) == nil {
                        return false
                    }
                }
            } else {
                if !fileName.localizedCaseInsensitiveContains(namePattern) {
                    return false
                }
            }
        }

        return true
    }

    private func currentFileStates() -> [String: Date] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else { return [:] }

        var states: [String: Date] = [:]
        for file in contents {
            if ignoreHidden && file.hasPrefix(".") { continue }
            let fullPath = (path as NSString).appendingPathComponent(file)
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let modDate = attrs[.modificationDate] as? Date {
                states[file] = modDate
            }
        }
        return states
    }
}
