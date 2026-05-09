import Foundation
import SwiftUI

@Observable
final class AppState {
    var selectedTab: SidebarTab = .dashboard
    var workflows: [Workflow] = []
    var runLog: [RunRecord] = []
    let engine = ForgeEngine()

    init() {
        workflows = WorkflowStore.load()
    }

    func saveWorkflows() {
        WorkflowStore.save(workflows)
    }
}

enum SidebarTab: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case workflows = "Workflows"
    case runLog = "Run Log"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .workflows: return "bolt.horizontal"
        case .runLog: return "list.bullet.rectangle"
        case .settings: return "gear"
        }
    }
}
