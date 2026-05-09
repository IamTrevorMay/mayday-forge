import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Section("About") {
                LabeledContent("App") {
                    Text("Mayday Forge")
                }
                LabeledContent("Actions Installed") {
                    Text("\(ActionRegistry.shared.allActionInfos().count)")
                }
                LabeledContent("Workflows") {
                    Text("\(appState.workflows.count)")
                }
            }

            Section("Storage") {
                LabeledContent("Config Location") {
                    let icloud = FileManager.default.url(forUbiquityContainerIdentifier: nil) != nil
                    HStack {
                        Image(systemName: icloud ? "icloud.fill" : "internaldrive")
                            .foregroundStyle(icloud ? .blue : .secondary)
                        Text(icloud ? "iCloud" : "Local (App Support)")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 400)
        .navigationTitle("Settings")
    }
}
