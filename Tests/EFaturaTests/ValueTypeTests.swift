import EFatura
import Foundation
import Testing

@Suite struct NIFTests {
    @Test func acceptsValidNumbers() {
        #expect(NIF("599999993") != nil)
        #expect(NIF("501234560") != nil)
        #expect(NIF("999999990")?.value == "999999990")
    }

    @Test func rejectsBadNumbers() {
        #expect(NIF("599999994") == nil)  // wrong check digit
        #expect(NIF("59999999") == nil)
        #expect(NIF("5999999930") == nil)
        #expect(NIF("PT599999993") == nil)
        #expect(NIF("099999999") == nil)
        #expect(NIF("") == nil)
    }

    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode([NIF("599999993")!])
        #expect(String(decoding: data, as: UTF8.self) == #"["599999993"]"#)
        #expect(try JSONDecoder().decode([NIF].self, from: data) == [NIF("599999993")!])
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([NIF].self, from: Data(#"["123"]"#.utf8))
        }
    }
}

@Suite struct CalendarDayTests {
    @Test func parsesAndFormats() {
        #expect(CalendarDay("2026-11-13")?.description == "2026-11-13")
        #expect(CalendarDay("2024-02-29") != nil)
        #expect(CalendarDay("2026-10-31+01:00") == CalendarDay(year: 2026, month: 10, day: 31))
        #expect(CalendarDay("2026-10-31Z") == CalendarDay(year: 2026, month: 10, day: 31))
    }

    @Test func rejectsImpossibleDates() {
        #expect(CalendarDay("2026-02-29") == nil)
        #expect(CalendarDay("2026-13-01") == nil)
        #expect(CalendarDay("2026-1-01") == nil)
        #expect(CalendarDay("13/11/2026") == nil)
        #expect(CalendarDay("2026-11-13T10:00:00") == nil)
    }

    @Test func orders() {
        #expect(CalendarDay("2025-12-31")! < CalendarDay("2026-01-01")!)
        #expect(CalendarDay("2026-01-31")! < CalendarDay("2026-02-01")!)
    }

    @Test func splitsAQuarterIntoMonths() {
        let ranges = CalendarDay.monthlyRanges(from: CalendarDay("2026-07-01")!, to: CalendarDay("2026-09-30")!)
        #expect(ranges.map { "\($0.lowerBound)…\($0.upperBound)" } == [
            "2026-07-01…2026-07-31", "2026-08-01…2026-08-31", "2026-09-01…2026-09-30",
        ])
    }

    @Test func splitsPartialMonthsAndYearEnd() {
        let ranges = CalendarDay.monthlyRanges(from: CalendarDay("2025-12-15")!, to: CalendarDay("2026-02-10")!)
        #expect(ranges.map { "\($0.lowerBound)…\($0.upperBound)" } == [
            "2025-12-15…2025-12-31", "2026-01-01…2026-01-31", "2026-02-01…2026-02-10",
        ])
        let single = CalendarDay.monthlyRanges(from: CalendarDay("2026-03-05")!, to: CalendarDay("2026-03-05")!)
        #expect(single.count == 1)
        #expect(CalendarDay.monthlyRanges(from: CalendarDay("2026-03-05")!, to: CalendarDay("2026-03-04")!).isEmpty)
    }
}

@Suite struct MoneyTests {
    @Test func convertsToCents() {
        #expect(Decimal(string: "133.10")!.cents == 13310)
        #expect(Decimal(string: "0.07")!.cents == 7)
        #expect(Decimal(string: "19.999")!.cents == 2000)
        #expect(Decimal(string: "9999999999999.99")!.cents == 999_999_999_999_999)
    }
}

@Suite struct CredentialsTests {
    @Test func buildsTheUsernameAndHidesThePassword() {
        let credentials = EFaturaCredentials(nif: NIF("599999993")!, subuser: "37", password: "hunter2")
        #expect(credentials.username == "599999993/37")
        #expect(credentials.nif == NIF("599999993"))
        #expect(!"\(credentials)".contains("hunter2"))
    }
}
