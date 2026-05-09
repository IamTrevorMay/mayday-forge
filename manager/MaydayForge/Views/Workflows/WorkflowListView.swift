import SwiftUI

struct WorkflowListView: View {
    @Environment(AppState.self) private var appState
    @State private var showingNewWorkflow = false
    @State private var selectedWorkflow: Workflow?

    var body: some View {
        @Bindable var state = appState

        List(selection: $selectedWorkflow) {
            ForEach(appState.workflows) { workflow in
                WorkflowRow(
                    workflow: workflow,
                    onToggle: { toggleWorkflow(workflow) },
                    onRun: { appState.engine.runManually(workflow) }
                )
                .tag(workflow)
            }
            .onDelete(perform: deleteWorkflows)
        }
        .navigationTitle("Workflows")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewWorkflow = true
                } label: {
                    Label("New Workflow", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewWorkflow) {
            WorkflowEditorView(
                workflow: nil,
                onSave: { workflow in
                    appState.workflows.append(workflow)
                    appState.saveWorkflows()
                    appState.engine.startWorkflow(workflow)
                }
            )
        }
        .sheet(item: $selectedWorkflow) { workflow in
            WorkflowEditorView(
                workflow: workflow,
                onSave: { updated in
                    if let idx = appState.workflows.firstIndex(where: { $0.id == updated.id }) {
                        appState.workflows[idx] = updated
                        appState.saveWorkflows()
                        appState.engine.startWorkflow(updated)
                    }
                }
            )
        }
    }

    private func toggleWorkflow(_ workflow: Workflow) {
        guard let idx = appState.workflows.firstIndex(where: { $0.id == workflow.id }) else { return }
        appState.workflows[idx].enabled.toggle()
        appState.saveWorkflows()

        if appState.workflows[idx].enabled {
            appState.engine.startWorkflow(appState.workflows[idx])
        } else {
            appState.engine.stopWorkflow(workflow.id)
        }
    }

    private func deleteWorkflows(at offsets: IndexSet) {
        for idx in offsets {
            appState.engine.stopWorkflow(appState.workflows[idx].id)
        }
        appState.workflows.remove(atOffsets: offsets)
        appState.saveWorkflows()
    }
}

struct WorkflowRow: View {
    let workflow: Workflow
    let onToggle: () -> Void
    let onRun: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(workflow.name)
                    .font(.body.bold())

                HStack(spacing: 8) {
                    Label(triggerLabel, systemImage: triggerIcon)
                    Text(actionLabel)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onRun()
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .help("Run now")

            Toggle("", isOn: Binding(
                get: { workflow.enabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private var triggerLabel: String {
        switch workflow.trigger {
        case .folderWatch(let path, let fileTypes, _, _):
            let folder = (path as NSString).lastPathComponent
            if fileTypes.isEmpty { return folder }
            return "\(folder) (.\(fileTypes.joined(separator: ", .")))"
        case .schedule(let cron):
            return "Every \(cron)"
        case .gitPush(_, let branch):
            return "Git: \(branch)"
        case .appLaunch:
            return "App Launch"
        case .manual:
            return "Manual"
        }
    }

    private var triggerIcon: String {
        switch workflow.trigger {
        case .folderWatch: return "folder.badge.gearshape"
        case .schedule: return "clock"
        case .gitPush: return "arrow.triangle.branch"
        case .appLaunch: return "power"
        case .manual: return "hand.tap"
        }
    }

    private var actionLabel: String {
        ActionRegistry.shared.actionInfo(for: workflow.actionType)?.displayName ?? workflow.actionType
    }
}
