import Foundation

struct WorkflowStore {
    private static var storeURL: URL {
        let container = FileManager.default.url(
            forUbiquityContainerIdentifier: nil
        ) ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!

        let dir = container.appendingPathComponent("MaydayForge", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("workflows.json")
    }

    static func load() -> [Workflow] {
        guard let data = try? Data(contentsOf: storeURL) else { return [] }
        return (try? JSONDecoder().decode([Workflow].self, from: data)) ?? []
    }

    static func save(_ workflows: [Workflow]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(workflows) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}
