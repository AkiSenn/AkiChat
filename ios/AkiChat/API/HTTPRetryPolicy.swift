import Foundation

enum HTTPRetryPolicy {
    /// Only a rejected 429 is replayable. Never retry a started/partial response or a tool.
    static func delay(response: HTTPURLResponse, attempt: Int, now: Date = Date()) -> TimeInterval? {
        guard response.statusCode == 429, attempt < 2 else { return nil }
        var delay = pow(2, Double(attempt))
        if let header = response.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = Double(header.trimmingCharacters(in: .whitespacesAndNewlines)), seconds.isFinite {
                delay = seconds
            } else {
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
                if let date = formatter.date(from: header) { delay = date.timeIntervalSince(now) }
            }
        }
        guard delay <= 30 else { return nil } // Long cooldowns are returned to the user, not retried early.
        return max(0.25, delay)
    }
}
