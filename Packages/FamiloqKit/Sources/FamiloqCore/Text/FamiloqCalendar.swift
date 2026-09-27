import Foundation

/// Calendar used across all Familoq modules.
public enum FamiloqCalendar {
    /// Gregorian calendar with Monday as first weekday (ISO 8601 / Germany).
    public static func make(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }
}
