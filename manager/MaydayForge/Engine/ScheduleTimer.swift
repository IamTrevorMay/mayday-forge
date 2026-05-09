import Foundation

final class ScheduleTimer {
    private let cronExpression: String
    private let callback: (TriggerEvent) -> Void
    private var timer: DispatchSourceTimer?

    init(cron: String, callback: @escaping (TriggerEvent) -> Void) {
        self.cronExpression = cron
        self.callback = callback
    }

    func start() {
        let interval = parseInterval(cronExpression)

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let event = TriggerEvent(
                type: .scheduled,
                metadata: ["cron": self.cronExpression]
            )
            self.callback(event)
        }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Simple cron-like parser. Supports:
    /// - "5m", "10m", "30m" — every N minutes
    /// - "1h", "2h", "6h", "12h" — every N hours
    /// - "1d" — every day
    /// - "1w" — every week
    /// - Raw seconds as fallback: "300" = 5 minutes
    private func parseInterval(_ cron: String) -> TimeInterval {
        let trimmed = cron.trimmingCharacters(in: .whitespaces).lowercased()

        if trimmed.hasSuffix("m"), let n = Double(trimmed.dropLast()) {
            return n * 60
        }
        if trimmed.hasSuffix("h"), let n = Double(trimmed.dropLast()) {
            return n * 3600
        }
        if trimmed.hasSuffix("d"), let n = Double(trimmed.dropLast()) {
            return n * 86400
        }
        if trimmed.hasSuffix("w"), let n = Double(trimmed.dropLast()) {
            return n * 604800
        }
        if let seconds = Double(trimmed) {
            return max(seconds, 10) // minimum 10 seconds
        }

        return 3600 // default: 1 hour
    }
}
