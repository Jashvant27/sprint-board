import Foundation

/// The week rule. Weeks are ISO 8601 weeks (Monday to Sunday, week 1 holds 4 January) numbered
/// relative to the quarter: quarter = (ISO week − 1) / 13 + 1, capped at 4, and
/// quarter week = ISO week − 13 · (quarter − 1). So ISO weeks 1–13 are Q1, 14–26 Q2, 27–39 Q3 and
/// 40–52 Q4; the user's Q3 Week 13 (ISO 39) is followed by Q4 Week 1 (ISO 40), and Q4 Week 4 is
/// ISO week 43, the week of 2026-10-22. A 53-week ISO year ends with Q4 Week 14. The year is the
/// ISO week-based year, so the days of late December that fall in ISO week 1 belong to Q1 Week 1 of
/// the next year. "Next week" is always the week of Monday + 7 days: after Q4 Week 13 (or 14) comes
/// Q1 Week 1 of the next year.
extension WeekID {
    static var calendar: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        return c
    }

    init(date: Date) {
        let comps = WeekID.calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let isoWeek = comps.weekOfYear ?? 1
        let quarter = min(4, (isoWeek - 1) / 13 + 1)
        self.init(year: comps.yearForWeekOfYear ?? 1970, quarter: quarter, week: isoWeek - 13 * (quarter - 1))
    }

    /// "2026/Q4/4" or "2026/4/4"; "Q4/4" (this year); "4" (this quarter). "Week 4" is accepted too.
    init?(string: String, relativeTo now: WeekID = .current) {
        let parts = string.split(separator: "/").map { String($0).trimmingCharacters(in: .whitespaces) }
        func num(_ s: String) -> Int? {
            Int(s.replacingOccurrences(of: "Q", with: "").replacingOccurrences(of: "Week ", with: ""))
        }
        switch parts.count {
        case 1:
            guard let w = num(parts[0]) else { return nil }
            self.init(year: now.year, quarter: now.quarter, week: w)
        case 2:
            guard let q = num(parts[0]), let w = num(parts[1]) else { return nil }
            self.init(year: now.year, quarter: q, week: w)
        case 3:
            guard let y = num(parts[0]), let q = num(parts[1]), let w = num(parts[2]) else { return nil }
            self.init(year: y, quarter: q, week: w)
        default:
            return nil
        }
        guard (1...4).contains(quarter), (1...14).contains(week), year > 2000 else { return nil }
    }

    static var current: WeekID { WeekID(date: Date()) }

    var isoWeek: Int { week + 13 * (quarter - 1) }

    /// Monday 00:00 (local time) of this week.
    var monday: Date {
        WeekID.calendar.date(from: DateComponents(weekday: 2, weekOfYear: isoWeek, yearForWeekOfYear: year)) ?? Date()
    }

    var sunday: Date { WeekID.calendar.date(byAdding: .day, value: 6, to: monday) ?? monday }

    var next: WeekID { WeekID(date: WeekID.calendar.date(byAdding: .day, value: 7, to: monday) ?? monday) }
    var previous: WeekID { WeekID(date: WeekID.calendar.date(byAdding: .day, value: -7, to: monday) ?? monday) }

    var isCurrent: Bool { self == .current }

    /// "19 – 25 Oct 2026" or "28 Sep – 4 Oct 2026".
    var dateRange: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        let sameMonth = WeekID.calendar.component(.month, from: monday) == WeekID.calendar.component(.month, from: sunday)
        f.dateFormat = sameMonth ? "d" : "d MMM"
        let start = f.string(from: monday)
        f.dateFormat = "d MMM yyyy"
        return "\(start) – \(f.string(from: sunday))"
    }
}
