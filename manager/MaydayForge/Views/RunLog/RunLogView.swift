import SwiftUI

struct RunLogView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.engine.runLog.isEmpty {
                ContentUnavailableView(
                    "No Runs Yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Run a workflow to see results here.")
                )
            } else {
                List(appState.engine.runLog) { record in
                    RunLogRow(record: record)
                }
            }
        }
        .navigationTitle("Run Log")
    }
}

struct RunLogRow: View {
    let record: RunRecord
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(record.output, id: \.self) { line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.workflowName)
                        .font(.body.bold())
                    Text(record.actionType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let finished = record.finishedAt {
                    Text(duration(from: record.startedAt, to: finished))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(record.startedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusIcon: String {
        switch record.status {
        case .running: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch record.status {
        case .running: return .orange
        case .success: return .green
        case .failed: return .red
        }
    }

    private func duration(from start: Date, to end: Date) -> String {
        let interval = end.timeIntervalSince(start)
        if interval < 1 {
            return "<1s"
        } else if interval < 60 {
            return String(format: "%.1fs", interval)
        } else {
            return String(format: "%.0fm", interval / 60)
        }
    }
}
