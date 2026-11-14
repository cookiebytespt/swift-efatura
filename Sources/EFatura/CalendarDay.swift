/// A calendar date with no time or time zone, as e-Fatura uses for document and period dates.
/// Travels as `YYYY-MM-DD`.
public struct CalendarDay: Sendable, Hashable, Comparable, Codable, LosslessStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
              (1...CalendarDay.daysInMonth(month, year: year)).contains(day)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `YYYY-MM-DD`. A trailing XML Schema time zone (`Z`, `+01:00`) is accepted and ignored.
    public init?(_ string: String) {
        let head = string.prefix(10)
        let parts = head.split(separator: "-", omittingEmptySubsequences: false)
        guard head.count == 10, parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        let tail = string.dropFirst(10)
        guard tail.isEmpty || tail == "Z" || tail.first == "+" || tail.first == "-" else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public var description: String {
        func pad(_ value: Int, _ width: Int) -> String {
            let text = String(value)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public var firstOfMonth: CalendarDay {
        CalendarDay(year: year, month: month, day: 1)!
    }

    public var lastOfMonth: CalendarDay {
        CalendarDay(year: year, month: month, day: CalendarDay.daysInMonth(month, year: year))!
    }

    public static func daysInMonth(_ month: Int, year: Int) -> Int {
        switch month {
        case 4, 6, 9, 11: return 30
        case 2: return (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        default: return 31
        }
    }

    /// Splits `start...end` into pieces that each stay inside one calendar month,
    /// because AT refuses a query that covers more than a month.
    public static func monthlyRanges(from start: CalendarDay, to end: CalendarDay) -> [ClosedRange<CalendarDay>] {
        guard start <= end else { return [] }
        var ranges: [ClosedRange<CalendarDay>] = []
        var cursor = start
        while true {
            let monthEnd = cursor.lastOfMonth
            if monthEnd >= end {
                ranges.append(cursor...end)
                return ranges
            }
            ranges.append(cursor...monthEnd)
            cursor = cursor.month == 12
                ? CalendarDay(year: cursor.year + 1, month: 1, day: 1)!
                : CalendarDay(year: cursor.year, month: cursor.month + 1, day: 1)!
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let day = CalendarDay(string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected YYYY-MM-DD")
        }
        self = day
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
