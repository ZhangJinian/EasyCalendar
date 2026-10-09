import Foundation

@main
struct Check {
    static func main() throws {
        if CommandLine.arguments.contains("--host-preferences") {
            assert(Bundle.main.bundleIdentifier == CalendarSettings.domain)
            assert(CalendarSettings.defaults === UserDefaults.standard)
            assert(CalendarSettings.sharedDomain != CalendarSettings.domain)
            assert(CalendarLanguage.allCases.contains(CalendarSettings.language))
            assert(!calendarText("设置", "Settings").isEmpty)
            print("PASS: actual host bundle ID uses standard preferences without crashing")
            return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 1
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        }
        assert(CalendarLanguage.simplifiedChinese.usesChinese(preferredLanguages: ["en"]))
        assert(!CalendarLanguage.english.usesChinese(preferredLanguages: ["zh-Hans"]))
        assert(CalendarLanguage.system.usesChinese(preferredLanguages: ["zh-Hans", "en"]))
        assert(!CalendarLanguage.system.usesChinese(preferredLanguages: ["en", "zh-Hans"]))
        assert(!CalendarLanguage.system.usesChinese(preferredLanguages: []))
        assert(CalendarLanguage.simplifiedChinese.locale.identifier == "zh-Hans")
        assert(CalendarLanguage.english.locale.identifier == "en")
        assert(calendarAction(from: URL(string: "opencalendarwidget://settings")!)?.name == "settings")
        assert(calendarAction(from: URL(string: "opencalendarwidget://settings?date=1000")!) == nil)
        assert(calendarAction(from: URL(string: "opencalendarwidget://settings?language=en")!) == nil)
        let leap = date(2024, 2, 29)
        let cells = monthCells(leap, calendar: calendar)
        assert(cells.count == 42)
        assert(calendar.component(.weekday, from: cells[0]) == 1)
        assert(cells.filter { calendar.isDate($0, equalTo: leap, toGranularity: .month) }.count == 29)
        assert(calendar.isDate(shiftedMonth(date(2024, 1, 31), by: 1, calendar: calendar), inSameDayAs: leap))
        assert(calendar.isDate(shiftedMonth(date(2025, 1, 31), by: 1, calendar: calendar), inSameDayAs: date(2025, 2, 28)))
        assert(calendar.isDate(shiftedMonth(date(2024, 12, 31), by: 1, calendar: calendar), inSameDayAs: date(2025, 1, 31)))
        let spring = date(2024, 3, 10)
        let next = date(2024, 3, 11)
        assert(next.timeIntervalSince(spring) == 23 * 3600)
        assert(overlapsDay(start: spring, end: next, day: spring, calendar: calendar))
        assert(!overlapsDay(start: spring, end: next, day: next, calendar: calendar))
        assert(overlapsDay(start: spring, end: spring, day: spring, calendar: calendar))
        assert(!overlapsDay(start: next, end: next, day: spring, calendar: calendar))
        let overnight = CalendarEvent(id: "night", eventIdentifier: "night", readOnly: false, title: "跨天", start: date(2024, 3, 9, 23), end: date(2024, 3, 10, 1), allDay: false, color: "#0088ff")
        let allDay = CalendarEvent(id: "all", eventIdentifier: "all", readOnly: false, title: "全天", start: spring, end: next, allDay: true, color: "#0088ff")
        let snapshot = CalendarSnapshot(updated: spring, events: [overnight, allDay], message: nil)
        assert(snapshot.events(on: spring, calendar: calendar).map(\.id) == ["all", "night"])
        let decoded = try JSONDecoder().decode(CalendarSnapshot.self, from: JSONEncoder().encode(snapshot))
        assert(decoded.events(on: spring, calendar: calendar).map(\.id) == ["all", "night"])
        let holiday = CalendarEvent(id: "holiday", eventIdentifier: "holiday", readOnly: true, title: "节假日", start: spring, end: next, allDay: true, color: "#ffffff")
        let green = CalendarEvent(id: "green", eventIdentifier: "green", readOnly: false, title: "个人待办", start: spring, end: next, allDay: true, color: "#48b487")
        let colored = CalendarSnapshot(updated: spring, events: [holiday, allDay, overnight, green], message: nil)
        let dots = colored.indicatorColors(on: spring, calendar: calendar)
        assert(Set(dots) == Set(["#AC82CE", "#0088ff", "#48b487"]))
        assert(dots.count == 3) // Same calendar color gets one dot, even with multiple events.
        assert(colored.events(on: spring, calendar: calendar).filter(\.readOnly).map(\.id) == ["holiday"])
        var state = CalendarTaskState()
        state.setCompleted("all", to: true)
        state.setCompleted("green", to: true)
        state.setCompleted("all", to: true)
        assert(state.completed == Set(["all", "green"]))
        state.setCompleted("all", to: false)
        assert(state.completed == Set(["green"]))
        let request = DeleteRequest(id: "green", created: spring)
        assert(request.permits("green", now: spring.addingTimeInterval(59)))
        assert(!request.permits("all", now: spring))
        assert(!request.permits("green", now: spring.addingTimeInterval(60)))
        assert(!request.permits("green", now: spring.addingTimeInterval(-1)))
        state.deletion = request
        state.message = "sample error"
        let savedState = try JSONDecoder().decode(CalendarTaskState.self, from: JSONEncoder().encode(state))
        assert(savedState.completed == state.completed)
        assert(savedState.deletion?.id == "green")
        state.setCompleted("all", to: true)
        assert(state.deletion == nil && state.message == nil)
        assert(eventOccurrenceID("recurring", start: spring) != eventOccurrenceID("recurring", start: next))
        let dayInterval = try eventCreationInterval(start: spring, end: spring, allDay: true, calendar: calendar)
        assert(dayInterval.start == spring && dayInterval.end == next)
        do { _ = try eventCreationInterval(start: next, end: spring, allDay: false, calendar: calendar); assertionFailure("invalid end accepted") }
        catch CalendarActionError.invalidEnd {}
        assert(!validCalendarTimestamp(.nan) && !validCalendarTimestamp(.infinity))
        assert(calendarAction(from: URL(string: "opencalendarwidget://new?date=1000")!)?.name == "new")
        assert(calendarAction(from: URL(string: "opencalendarwidget://calendar?date=1000")!)?.date == Date(timeIntervalSince1970: 1000))
        for invalid in ["https://new?date=1000", "opencalendarwidget://delete?date=1000", "opencalendarwidget://new?date=nan", "opencalendarwidget://new", "opencalendarwidget://new?date=1&date=2"] {
            assert(calendarAction(from: URL(string: invalid)!) == nil)
        }
        let future = CalendarEvent(id: "future", eventIdentifier: "future", readOnly: false, title: "明天待办", start: next, end: date(2024, 3, 12), allDay: true, color: "#0088ff")
        let later = CalendarEvent(id: "later", eventIdentifier: "later", readOnly: false, title: "跨月待办", start: date(2024, 4, 1), end: date(2024, 4, 2), allDay: true, color: "#0088ff")
        let far = CalendarEvent(id: "far", eventIdentifier: "far", readOnly: false, title: "超出范围", start: date(2024, 4, 10), end: date(2024, 4, 11), allDay: true, color: "#0088ff")
        let futureHoliday = CalendarEvent(id: "futureHoliday", eventIdentifier: "futureHoliday", readOnly: true, title: "明天假期", start: next, end: date(2024, 3, 12), allDay: true, color: "#ffffff")
        let futureSnapshot = CalendarSnapshot(updated: spring, events: [later, far, futureHoliday, allDay, future], message: nil)
        assert(futureSnapshot.upcomingTasks(after: spring, calendar: calendar, completed: []).map(\.id) == ["future", "later"])
        assert(futureSnapshot.upcomingTasks(after: spring, calendar: calendar, completed: ["future"]).map(\.id) == ["later"])
        assert(futureSnapshot.upcomingTasks(after: date(2024, 4, 30), calendar: calendar, completed: []).isEmpty)
        var local = Calendar(identifier: .gregorian)
        local.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let selected = local.date(from: DateComponents(year: 2026, month: 10, day: 20))!
        let routed = calendarAction(from: URL(string: "opencalendarwidget://new?date=\(selected.timeIntervalSince1970)")!)!
        assert(local.isDate(routed.date, inSameDayAs: selected))
        assert(local.component(.day, from: routed.date) == 20)
        let firstPage = CalendarTaskPage(total: 5, availableHeight: 47, requested: 0)
        assert(firstPage.range == 0..<2 && firstPage.count == 3 && firstPage.index == 0)
        let lastPage = CalendarTaskPage(total: 5, availableHeight: 47, requested: 99)
        assert(lastPage.range == 4..<5 && lastPage.index == 2)
        assert(CalendarTaskPage(total: 5, availableHeight: 47, requested: -1).range == 0..<2)
        assert(CalendarTaskPage(total: 1, availableHeight: 47, requested: 2).index == 0)
        for height in [22.0, 46, 47, 72, 100] {
            var indices: [Int] = []
            let first = CalendarTaskPage(total: 7, availableHeight: height, requested: 0)
            for index in 0..<first.count {
                let page = CalendarTaskPage(total: 7, availableHeight: height, requested: index)
                indices += Array(page.range)
                assert(Double(page.range.count * 22 + max(0, page.range.count - 1) * 3) <= height)
            }
            assert(indices == Array(0..<7))
        }
        for height in [0.0, 21, -1, .nan, .infinity] {
            assert(CalendarTaskPage(total: 5, availableHeight: height, requested: 0).range.isEmpty)
        }
        assert(CalendarTaskPage(total: 0, availableHeight: 100, requested: 1).count == 0)
        let legacySelection = try JSONDecoder().decode(CalendarSelection.self, from: Data("{\"date\":1000,\"changed\":1000}".utf8))
        assert(legacySelection.page == nil) // Old selection files retain the date and default to page 1.
        let selection = CalendarSelection(date: selected, changed: Date(), page: 2)
        let restoredSelection = try JSONDecoder().decode(CalendarSelection.self, from: JSONEncoder().encode(selection))
        assert(restoredSelection.date == selected && restoredSelection.page == 2)
        print("PASS: language selection, settings URL validation, leap years, month boundaries, 42-day grid, DST, midnight exclusion, point events, overnight events, sorting, cache round trip, color mapping, completion state, guarded deletion, creation validation, selected-date URL routing, future task sorting/filtering, pagination coverage/height/clamping, selection migration")
    }
}
