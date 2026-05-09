import Foundation

@Observable
final class ForgeEngine {
    private var folderWatchers: [UUID: FolderWatcher] = [:]
    private var scheduleTimers: [UUID: ScheduleTimer] = [:]
    private var gitWatchers: [UUID: GitPushWatcher] = [:]
    private var appLaunchWorkflows: [Workflow] = []
    private(set) var runLog: [RunRecord] = []
    var onRunRecordAdded: ((RunRecord) -> Void)?

    func startAll() {
        // Fire app launch triggers
        for workflow in appLaunchWorkflows where workflow.enabled {
            let event = TriggerEvent(type: .appLaunch)
            Task { await executeWorkflow(workflow, trigger: event) }
        }
    }

    func startWorkflow(_ workflow: Workflow) {
        stopWorkflow(workflow.id)

        guard workflow.enabled else { return }

        switch workflow.trigger {
        case .folderWatch(let path, let fileTypes, let namePattern, let ignoreHidden):
            let watcher = FolderWatcher(
                path: path,
                fileTypes: fileTypes,
                namePattern: namePattern,
                ignoreHidden: ignoreHidden
            ) { [weak self] event in
                Task { [weak self] in
                    await self?.executeWorkflow(workflow, trigger: event)
                }
            }
            watcher.start()
            folderWatchers[workflow.id] = watcher

        case .schedule(let cron):
            let timer = ScheduleTimer(cron: cron) { [weak self] event in
                Task { [weak self] in
                    await self?.executeWorkflow(workflow, trigger: event)
                }
            }
            timer.start()
            scheduleTimers[workflow.id] = timer

        case .gitPush(let repoPath, let branch):
            let watcher = GitPushWatcher(repoPath: repoPath, branch: branch) { [weak self] event in
                Task { [weak self] in
                    await self?.executeWorkflow(workflow, trigger: event)
                }
            }
            watcher.start()
            gitWatchers[workflow.id] = watcher

        case .appLaunch:
            appLaunchWorkflows.removeAll { $0.id == workflow.id }
            appLaunchWorkflows.append(workflow)

        case .manual:
            break
        }
    }

    func stopWorkflow(_ id: UUID) {
        folderWatchers[id]?.stop()
        folderWatchers[id] = nil
        scheduleTimers[id]?.stop()
        scheduleTimers[id] = nil
        gitWatchers[id]?.stop()
        gitWatchers[id] = nil
        appLaunchWorkflows.removeAll { $0.id == id }
    }

    func runManually(_ workflow: Workflow) {
        Task {
            let event = TriggerEvent(type: .manual)
            await executeWorkflow(workflow, trigger: event)
        }
    }

    @MainActor
    private func executeWorkflow(_ workflow: Workflow, trigger: TriggerEvent) async {
        guard let action = ActionRegistry.shared.create(
            typeId: workflow.actionType,
            config: workflow.actionConfig
        ) else {
            let record = RunRecord(
                id: UUID(),
                workflowId: workflow.id,
                workflowName: workflow.name,
                actionType: workflow.actionType,
                startedAt: Date(),
                finishedAt: Date(),
                status: .failed,
                output: ["Unknown action type: \(workflow.actionType)"]
            )
            runLog.insert(record, at: 0)
            onRunRecordAdded?(record)
            return
        }

        var record = RunRecord(
            id: UUID(),
            workflowId: workflow.id,
            workflowName: workflow.name,
            actionType: workflow.actionType,
            startedAt: Date(),
            status: .running,
            output: []
        )
        runLog.insert(record, at: 0)

        do {
            let result = try await action.execute(trigger: trigger)
            record.output = result.output
            record.status = result.success ? .success : .failed
            if let error = result.error {
                record.output.append("Error: \(error)")
            }
        } catch {
            record.status = .failed
            record.output.append("Error: \(error.localizedDescription)")
        }

        record.finishedAt = Date()
        if let idx = runLog.firstIndex(where: { $0.id == record.id }) {
            runLog[idx] = record
        }
        onRunRecordAdded?(record)
    }

    func stopAll() {
        for (_, w) in folderWatchers { w.stop() }
        folderWatchers.removeAll()
        for (_, t) in scheduleTimers { t.stop() }
        scheduleTimers.removeAll()
        for (_, g) in gitWatchers { g.stop() }
        gitWatchers.removeAll()
        appLaunchWorkflows.removeAll()
    }
}
