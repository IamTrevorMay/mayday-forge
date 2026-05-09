import SwiftUI

struct DashboardView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Mayday Forge")
                    .font(.largeTitle.bold())

                statsRow
                recentRunsSection
                availableActionsSection
            }
            .padding(24)
        }
        .navigationTitle("Dashboard")
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            StatCard(
                title: "Workflows",
                value: "\(appState.workflows.count)",
                icon: "bolt.horizontal",
                color: .blue
            )
            StatCard(
                title: "Active",
                value: "\(appState.workflows.filter(\.enabled).count)",
                icon: "play.circle",
                color: .green
            )
            StatCard(
                title: "Runs Today",
                value: "\(runsToday)",
                icon: "clock",
                color: .orange
            )
        }
    }

    @ViewBuilder
    private var recentRunsSection: some View {
        if !appState.engine.runLog.isEmpty {
            Text("Recent Runs")
                .font(.headline)

            ForEach(Array(appState.engine.runLog.prefix(5))) { record in
                RunRecordRow(record: record)
            }
        }
    }

    private var availableActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available Actions")
                .font(.headline)

            let infos = ActionRegistry.shared.allActionInfos()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 12) {
                ForEach(infos) { info in
                    ActionTypeCard(info: info)
                }
            }
        }
    }

    private var runsToday: Int {
        let calendar = Calendar.current
        return appState.engine.runLog.filter {
            calendar.isDateInToday($0.startedAt)
        }.count
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            Text(value)
                .font(.system(.title, design: .rounded, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ActionTypeCard: View {
    let info: ActionInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(info.displayName)
                .font(.headline)
            Text(info.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct RunRecordRow: View {
    let record: RunRecord

    var body: some View {
        HStack {
            Image(systemName: statusIcon)
                .foregroundStyle(statusColor)

            VStack(alignment: .leading) {
                Text(record.workflowName)
                    .font(.body.bold())
                Text(record.actionType)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(record.startedAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
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
}
