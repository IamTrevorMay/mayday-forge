import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        NavigationSplitView {
            List(SidebarTab.allCases, selection: $state.selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .listStyle(.sidebar)
        } detail: {
            switch appState.selectedTab {
            case .dashboard:
                DashboardView()
            case .workflows:
                WorkflowListView()
            case .runLog:
                RunLogView()
            case .settings:
                SettingsView()
            }
        }
        .frame(minWidth: 800, minHeight: 500)
    }
}
