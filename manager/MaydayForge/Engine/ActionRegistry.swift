import Foundation

struct ActionInfo: Identifiable {
    let id: String
    let displayName: String
    let description: String
    let configFields: [ActionConfigField]

    var typeId: String { id }
}

final class ActionRegistry {
    static let shared = ActionRegistry()

    private var actions: [String: any ForgeAction.Type] = [:]

    private init() {
        // File operations
        register(MoveFileAction.self)
        register(CopyFileAction.self)
        register(RenameFileAction.self)
        register(FilterAction.self)

        // Obsidian
        register(CreateObsidianNoteAction.self)
        register(AppendToFileAction.self)
        register(TagObsidianNoteAction.self)

        // Git
        register(GenerateChangelogAction.self)
        register(GitAutoCommitAction.self)

        // System
        register(RunShellCommandAction.self)
        register(SystemNotificationAction.self)
    }

    func register(_ type: any ForgeAction.Type) {
        actions[type.typeId] = type
    }

    func allActions() -> [any ForgeAction.Type] {
        Array(actions.values).sorted { $0.displayName < $1.displayName }
    }

    func allActionInfos() -> [ActionInfo] {
        actions.values.map { type in
            ActionInfo(
                id: type.typeId,
                displayName: type.displayName,
                description: type.description,
                configFields: type.configFields
            )
        }.sorted { $0.displayName < $1.displayName }
    }

    func actionInfo(for typeId: String) -> ActionInfo? {
        guard let type = actions[typeId] else { return nil }
        return ActionInfo(
            id: type.typeId,
            displayName: type.displayName,
            description: type.description,
            configFields: type.configFields
        )
    }

    func action(for typeId: String) -> (any ForgeAction.Type)? {
        actions[typeId]
    }

    func create(typeId: String, config: [String: String]) -> (any ForgeAction)? {
        guard let type = actions[typeId] else { return nil }
        return type.init(config: config)
    }
}
