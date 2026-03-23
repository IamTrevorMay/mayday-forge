import SwiftUI

struct BackupStatusCard: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.title2)
                    .foregroundStyle(iconColor)
                    .frame(width: 32, height: 32)

                Text("Supabase Backup")
                    .font(.headline)

                Spacer()

                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
            }

            if let log = appState.backupScheduler.lastBackupLog {
                VStack(alignment: .leading, spacing: 4) {
                    if let ts = log.lastBackupAt {
                        Text("Last: \(formattedDate(ts))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let summary = log.summary {
                        HStack(spacing: 12) {
                            Label("\(summary.totalProjects ?? 0) projects", systemImage: "server.rack")
                            Label("\(summary.totalTables ?? 0) tables", systemImage: "tablecells")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        if let errors = summary.totalErrors, errors > 0 {
                            Label("\(errors) errors", systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    if let duration = log.durationSeconds {
                        Text(String(format: "%.0fs", duration))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text("No backup yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                scheduleLabel

                Spacer()

                Button("Run Now") {
                    appState.backupScheduler.runBackup(
                        pythonPath: appState.pythonPath,
                        toolkitPath: appState.toolkitPath,
                        environment: appState.effectiveEnvironment
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.backupScheduler.status == .running)
            }

            if appState.backupScheduler.status == .running {
                ProgressView()
                    .controlSize(.small)
            }

            if let error = appState.backupScheduler.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        .onAppear {
            if let path = appState.config?.backupVaultPath {
                appState.backupScheduler.loadLastBackupLog(backupVaultPath: path)
            }
        }
    }

    private var iconColor: Color {
        switch appState.backupScheduler.status {
        case .idle: return .blue
        case .running: return .orange
        case .success: return .green
        case .error: return .red
        }
    }

    private var dotColor: Color {
        if appState.backupScheduler.status == .running { return .orange }
        if let log = appState.backupScheduler.lastBackupLog,
           let errors = log.summary?.totalErrors, errors > 0 {
            return .yellow
        }
        if appState.backupScheduler.lastBackupLog != nil { return .green }
        return .gray
    }

    private var scheduleLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: BackupSchedulerService.isScheduleInstalled()
                  ? "clock.badge.checkmark.fill" : "clock")
                .font(.caption)
            Text(BackupSchedulerService.isScheduleInstalled()
                 ? "Sundays 11 PM" : "Not scheduled")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func formattedDate(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: iso) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        return iso
    }
}
