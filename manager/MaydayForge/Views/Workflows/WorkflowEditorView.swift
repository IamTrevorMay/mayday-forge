import SwiftUI
import AppKit

struct WorkflowEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let existingWorkflow: Workflow?
    let onSave: (Workflow) -> Void

    @State private var name: String
    @State private var triggerType: TriggerChoice = .manual
    @State private var selectedActionType: String
    @State private var actionConfig: [String: String] = [:]

    // Folder watch config
    @State private var watchPath: String = ""
    @State private var watchFileTypes: String = ""
    @State private var watchNamePattern: String = ""
    @State private var watchIgnoreHidden: Bool = true

    // Schedule config
    @State private var scheduleInterval: String = ""

    // Git push config
    @State private var gitRepoPath: String = ""
    @State private var gitBranch: String = "main"

    enum TriggerChoice: String, CaseIterable {
        case manual = "Manual"
        case folderWatch = "Folder Watch"
        case schedule = "Schedule"
        case gitPush = "Git Push"
        case appLaunch = "App Launch"
    }

    init(workflow: Workflow?, onSave: @escaping (Workflow) -> Void) {
        self.existingWorkflow = workflow
        self.onSave = onSave

        if let w = workflow {
            _name = State(initialValue: w.name)
            _selectedActionType = State(initialValue: w.actionType)
            _actionConfig = State(initialValue: w.actionConfig)
            switch w.trigger {
            case .folderWatch(let path, let fileTypes, let namePattern, let ignoreHidden):
                _triggerType = State(initialValue: .folderWatch)
                _watchPath = State(initialValue: path)
                _watchFileTypes = State(initialValue: fileTypes.joined(separator: ", "))
                _watchNamePattern = State(initialValue: namePattern)
                _watchIgnoreHidden = State(initialValue: ignoreHidden)
            case .schedule(let cron):
                _triggerType = State(initialValue: .schedule)
                _scheduleInterval = State(initialValue: cron)
            case .gitPush(let repoPath, let branch):
                _triggerType = State(initialValue: .gitPush)
                _gitRepoPath = State(initialValue: repoPath)
                _gitBranch = State(initialValue: branch)
            case .appLaunch:
                _triggerType = State(initialValue: .appLaunch)
            case .manual:
                _triggerType = State(initialValue: .manual)
            }
        } else {
            _name = State(initialValue: "")
            _selectedActionType = State(initialValue: ActionRegistry.shared.allActionInfos().first?.id ?? "")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                workflowSection
                triggerSection
                triggerConfigSection
                actionSection
            }
            .formStyle(.grouped)

            buttonBar
        }
        .frame(minWidth: 500, minHeight: 500)
    }

    private var workflowSection: some View {
        Section("Workflow") {
            TextField("Name", text: $name)
        }
    }

    private var triggerSection: some View {
        Section("Trigger") {
            Picker("Type", selection: $triggerType) {
                ForEach(TriggerChoice.allCases, id: \.self) { choice in
                    Text(choice.rawValue).tag(choice)
                }
            }
        }
    }

    @ViewBuilder
    private var triggerConfigSection: some View {
        switch triggerType {
        case .folderWatch:
            Section("Folder Watch Settings") {
                FolderWatchConfigView(
                    watchPath: $watchPath,
                    fileTypes: $watchFileTypes,
                    namePattern: $watchNamePattern,
                    ignoreHidden: $watchIgnoreHidden
                )
            }
        case .schedule:
            Section("Schedule Settings") {
                TextField("Interval", text: $scheduleInterval)
                    .help("Examples: 5m, 1h, 6h, 1d, 1w")
                Text("Examples: 5m (5 minutes), 1h (1 hour), 1d (1 day), 1w (1 week)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .gitPush:
            Section("Git Push Settings") {
                GitPushConfigView(repoPath: $gitRepoPath, branch: $gitBranch)
            }
        case .appLaunch:
            Section("App Launch") {
                Text("This workflow will run automatically when Mayday Forge starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .manual:
            EmptyView()
        }
    }

    private var actionSection: some View {
        Section("Action") {
            actionPicker
            actionConfigFields
        }
    }

    private var actionPicker: some View {
        let infos = ActionRegistry.shared.allActionInfos()
        return Picker("Action Type", selection: $selectedActionType) {
            ForEach(infos) { info in
                Text(info.displayName).tag(info.id)
            }
        }
        .onChange(of: selectedActionType) { _, _ in
            actionConfig = [:]
        }
    }

    @ViewBuilder
    private var actionConfigFields: some View {
        let fields = ActionRegistry.shared.actionInfo(for: selectedActionType)?.configFields ?? []
        ForEach(fields, id: \.key) { field in
            ConfigFieldRow(
                field: field,
                value: Binding(
                    get: { actionConfig[field.key] ?? "" },
                    set: { actionConfig[field.key] = $0 }
                )
            )
        }

        // Show description of selected action
        if let info = ActionRegistry.shared.actionInfo(for: selectedActionType) {
            Text(info.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var buttonBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button(existingWorkflow == nil ? "Create" : "Save") {
                save()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(name.isEmpty)
        }
        .padding()
    }

    private func save() {
        let trigger: WorkflowTrigger
        switch triggerType {
        case .manual:
            trigger = .manual
        case .folderWatch:
            let types = watchFileTypes.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            trigger = .folderWatch(
                path: watchPath,
                fileTypes: types,
                namePattern: watchNamePattern,
                ignoreHidden: watchIgnoreHidden
            )
        case .schedule:
            trigger = .schedule(cron: scheduleInterval)
        case .gitPush:
            trigger = .gitPush(repoPath: gitRepoPath, branch: gitBranch.isEmpty ? "main" : gitBranch)
        case .appLaunch:
            trigger = .appLaunch
        }

        var workflow = existingWorkflow ?? Workflow(
            name: name,
            trigger: trigger,
            actionType: selectedActionType
        )
        workflow.name = name
        workflow.trigger = trigger
        workflow.actionType = selectedActionType
        workflow.actionConfig = actionConfig

        onSave(workflow)
        dismiss()
    }
}

// MARK: - Subviews (broken out to avoid compiler complexity)

private struct FolderWatchConfigView: View {
    @Binding var watchPath: String
    @Binding var fileTypes: String
    @Binding var namePattern: String
    @Binding var ignoreHidden: Bool

    var body: some View {
        HStack {
            TextField("Watch Folder", text: $watchPath)
            Button("Browse...") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                if panel.runModal() == .OK, let url = panel.url {
                    watchPath = url.path
                }
            }
        }
        TextField("File Types (comma-separated)", text: $fileTypes)
            .help("e.g., md, txt, pdf — leave empty for all types")
        TextField("Name Pattern", text: $namePattern)
            .help("Simple text match, or /regex/ for regex")
        Toggle("Ignore Hidden Files", isOn: $ignoreHidden)
    }
}

private struct GitPushConfigView: View {
    @Binding var repoPath: String
    @Binding var branch: String

    var body: some View {
        HStack {
            TextField("Repository Path", text: $repoPath)
            Button("Browse...") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                if panel.runModal() == .OK, let url = panel.url {
                    repoPath = url.path
                }
            }
        }
        TextField("Branch", text: $branch)
    }
}

private struct ConfigFieldRow: View {
    let field: ActionConfigField
    @Binding var value: String

    var body: some View {
        HStack {
            TextField(field.label, text: $value)
            browseButton
        }
    }

    @ViewBuilder
    private var browseButton: some View {
        switch field.fieldType {
        case .folderPicker:
            Button("Browse...") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                if panel.runModal() == .OK, let url = panel.url {
                    value = url.path
                }
            }
        case .filePicker:
            Button("Browse...") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                if panel.runModal() == .OK, let url = panel.url {
                    value = url.path
                }
            }
        case .text:
            EmptyView()
        }
    }
}
