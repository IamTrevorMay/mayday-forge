import Foundation
import UserNotifications

struct SystemNotificationAction: ForgeAction {
    static let typeId = "notification"
    static let displayName = "System Notification"
    static let description = "Send a macOS notification with a custom title and message"
    static let configFields: [ActionConfigField] = [
        ActionConfigField(key: "title", label: "Title", placeholder: "Mayday Forge"),
        ActionConfigField(key: "body", label: "Message", placeholder: "Workflow completed for {filename}"),
        ActionConfigField(key: "sound", label: "Play Sound (yes/no)", placeholder: "yes", required: false),
    ]

    private let title: String
    private let body: String
    private let playSound: Bool

    init(config: [String: String]) {
        self.title = config["title"] ?? "Mayday Forge"
        self.body = config["body"] ?? ""
        self.playSound = (config["sound"] ?? "yes").lowercased() != "no"
    }

    func execute(trigger: TriggerEvent) async throws -> ActionResult {
        let vars = VariableHelper.build(from: trigger)
        let resolvedTitle = VariableHelper.apply(title, vars: vars)
        let resolvedBody = VariableHelper.apply(body, vars: vars)

        let content = UNMutableNotificationContent()
        content.title = resolvedTitle
        content.body = resolvedBody
        if playSound {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        let center = UNUserNotificationCenter.current()

        // Request permission if needed
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            try await center.requestAuthorization(options: [.alert, .sound])
        }

        try await center.add(request)

        return .ok(["Notification sent: \(resolvedTitle)"])
    }
}
