import Foundation

public struct ClaudeUsageLimit: Codable, Sendable, Equatable {
    public struct Detection: Equatable, Sendable {
        public let resetAt: Date?

        public init(resetAt: Date?) {
            self.resetAt = resetAt
        }
    }

    public static let defaultCooldown: TimeInterval = 15 * 60

    public var resetAt: Date?

    public init(resetAt: Date? = nil) {
        self.resetAt = resetAt
    }

    public func isActive(at now: Date) -> Bool {
        guard let resetAt else { return false }
        return resetAt > now
    }

    public func effectiveModel(for configured: ModelChoice, fallback: ModelChoice, at now: Date) -> ModelChoice {
        guard usesFallback(for: configured, at: now) else { return configured }
        return fallback
    }

    public func usesFallback(for configured: ModelChoice, at now: Date) -> Bool {
        configured.isClaude && isActive(at: now)
    }

    @discardableResult
    public mutating func noteLimit(resetAt candidate: Date?, now: Date) -> Bool {
        let target = candidate ?? now.addingTimeInterval(Self.defaultCooldown)
        guard target > now else { return false }
        if let current = resetAt, current >= target { return false }
        resetAt = target
        return true
    }

    @discardableResult
    public mutating func noteThreads(_ threads: [AgentThread], now: Date) -> Bool {
        var changed = false
        for thread in threads where thread.isClaude {
            if let reset = thread.usageLimitResetAt, reset > now {
                if noteLimit(resetAt: reset, now: now) { changed = true }
                continue
            }
            guard thread.status == .failed else { continue }
            guard let detected = Self.detect(
                errorClass: thread.lastErrorClass,
                message: thread.lastError,
                text: nil,
                resetAt: nil,
                reference: thread.updatedAt
            ) else { continue }
            let target = detected.resetAt ?? thread.updatedAt.addingTimeInterval(Self.defaultCooldown)
            if target > now, noteLimit(resetAt: target, now: now) { changed = true }
        }
        return changed
    }

    @discardableResult
    public mutating func clearIfReset(at now: Date) -> Bool {
        guard let resetAt, resetAt <= now else { return false }
        self.resetAt = nil
        return true
    }

    public static func detect(
        errorClass: String? = nil,
        message: String? = nil,
        text: String? = nil,
        resetAt: Date? = nil,
        reference: Date = Date(),
        defaultTimeZone: TimeZone = .current
    ) -> Detection? {
        let matched = errorClass == "usage_limit"
            || resetAt != nil
            || isLimitText(message)
            || isLimitText(text)
        guard matched else { return nil }
        let parsed = resetAt
            ?? parseReset(in: text, relativeTo: reference, defaultTimeZone: defaultTimeZone)
            ?? parseReset(in: message, relativeTo: reference, defaultTimeZone: defaultTimeZone)
        return Detection(resetAt: parsed)
    }

    public static func isLimitText(_ text: String?) -> Bool {
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return false }
        let lowered = raw.lowercased()
        if lowered.contains("usage_limit") || lowered.contains("usage limit") { return true }
        if lowered.contains("rate_limit") || lowered.contains("rate limit") { return true }
        if lowered.contains("api_error_429") { return true }
        if lowered.contains("hit your") && lowered.contains("limit") { return true }
        if lowered.contains("weekly limit") || lowered.contains("5-hour limit") || lowered.contains("session limit") { return true }
        return false
    }

    public static func parseReset(
        in text: String?,
        relativeTo reference: Date,
        defaultTimeZone: TimeZone = .current
    ) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        guard let resetsRange = text.range(of: #"\bresets\b"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let after = String(text[resetsRange.upperBound...])
        let line = after.split(whereSeparator: \.isNewline).first.map(String.init) ?? after

        if let iso = firstMatch(#"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})"#, in: line) {
            if let date = parseISO8601(iso) { return date }
        }

        var zone = defaultTimeZone
        var body = line
        if let tzRange = body.range(of: #"\(([^)]+)\)"#, options: .regularExpression) {
            let inner = String(body[tzRange]).dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
            if let resolved = TimeZone(identifier: inner) ?? TimeZone(abbreviation: inner) {
                zone = resolved
            }
            body.removeSubrange(tzRange)
        }

        body = body.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "·.,:-")))
        if let atPrefix = body.range(of: #"^at\s+"#, options: [.regularExpression, .caseInsensitive]) {
            body.removeSubrange(atPrefix)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone

        if let dated = parseMonthDayTime(body, calendar: calendar, reference: reference) {
            return dated
        }
        return parseTimeOnly(body, calendar: calendar, reference: reference)
    }

    private static func parseMonthDayTime(_ body: String, calendar: Calendar, reference: Date) -> Date? {
        let pattern = #"^([A-Za-z]+)\s+(\d{1,2})(?:,?\s*(\d{4}))?(?:,?\s*(?:at\s+)?)(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
              let monthText = capture(match, 1, in: body),
              let month = monthNumber(monthText),
              let day = capture(match, 2, in: body).flatMap(Int.init),
              let rawHour = capture(match, 4, in: body).flatMap(Int.init)
        else { return nil }

        let explicitYear = capture(match, 3, in: body).flatMap(Int.init)
        let minute = capture(match, 5, in: body).flatMap(Int.init) ?? 0
        let meridiem = capture(match, 6, in: body)?.lowercased()
        guard let hour = resolvedHour(rawHour, meridiem: meridiem), (0..<60).contains(minute) else { return nil }

        let baseYear = explicitYear ?? calendar.component(.year, from: reference)
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = baseYear
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let date = calendar.date(from: components) else { return nil }
        if explicitYear == nil, date <= reference {
            components.year = baseYear + 1
            return calendar.date(from: components)
        }
        return date
    }

    private static func parseTimeOnly(_ body: String, calendar: Calendar, reference: Date) -> Date? {
        let pattern = #"^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
              let rawHour = capture(match, 1, in: body).flatMap(Int.init)
        else { return nil }

        let minuteText = capture(match, 2, in: body)
        let meridiem = capture(match, 3, in: body)?.lowercased()
        guard minuteText != nil || meridiem != nil else { return nil }
        let minute = minuteText.flatMap(Int.init) ?? 0
        guard let hour = resolvedHour(rawHour, meridiem: meridiem), (0..<60).contains(minute) else { return nil }

        var components = calendar.dateComponents([.year, .month, .day], from: reference)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let today = calendar.date(from: components) else { return nil }
        if today <= reference {
            return calendar.date(byAdding: .day, value: 1, to: today)
        }
        return today
    }

    private static func resolvedHour(_ hour: Int, meridiem: String?) -> Int? {
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            if meridiem == "am" { return hour == 12 ? 0 : hour }
            return hour == 12 ? 12 : hour + 12
        }
        guard (0...23).contains(hour) else { return nil }
        return hour
    }

    private static func monthNumber(_ text: String) -> Int? {
        switch text.lowercased() {
        case "jan", "january": return 1
        case "feb", "february": return 2
        case "mar", "march": return 3
        case "apr", "april": return 4
        case "may": return 5
        case "jun", "june": return 6
        case "jul", "july": return 7
        case "aug", "august": return 8
        case "sep", "sept", "september": return 9
        case "oct", "october": return 10
        case "nov", "november": return 11
        case "dec", "december": return 12
        default: return nil
        }
    }

    private static func capture(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return String(text[range])
    }

    private static func parseISO8601(_ text: String) -> Date? {
        (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(text, strategy: Date.ISO8601FormatStyle()))
    }

    public static var fileURL: URL { Settings.directory.appendingPathComponent("claude-fallback.json") }

    public static func load(from file: URL = fileURL) -> ClaudeUsageLimit {
        guard let data = try? Data(contentsOf: file) else { return ClaudeUsageLimit() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(ClaudeUsageLimit.self, from: data)) ?? ClaudeUsageLimit()
    }

    public func save(to file: URL = fileURL) throws {
        if resetAt == nil {
            if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            }
            return
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: file, options: .atomic)
    }
}
