import Foundation
import EventKit
import AppKit

enum CalendarLanguage: String, CaseIterable {
    case system, simplifiedChinese = "zh-Hans", english = "en"
    var label: String {
        switch self {
        case .system: return calendarText("跟随系统", "System default")
        case .simplifiedChinese: return "简体中文"
        case .english: return "English"
        }
    }
    var locale: Locale {
        self == .system ? .autoupdatingCurrent : Locale(identifier: rawValue)
    }
    func usesChinese(preferredLanguages: [String] = Locale.preferredLanguages) -> Bool {
        self == .simplifiedChinese || (self == .system && (preferredLanguages.first ?? "en").hasPrefix("zh"))
    }
}

enum CalendarSettings {
    static let domain = "local.spacesands.OpenCalendarWidget"
    static let sharedDomain = "local.spacesands.EasyCalendar.SharedSettings"
    static let defaults = UserDefaults.standard
    static var language: CalendarLanguage {
        let value = Bundle.main.bundleIdentifier == domain
            ? defaults.string(forKey: "language")
            : CFPreferencesCopyValue("language" as CFString, sharedDomain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? String
        return CalendarLanguage(rawValue: value ?? "system") ?? .system
    }
    // 独立共享域位于用户偏好目录，不能用宿主沙盒中的默认偏好域代替。
    @discardableResult static func publishLanguage(_ language: CalendarLanguage) -> Bool {
        CFPreferencesSetValue("language" as CFString, language.rawValue as CFString, sharedDomain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        return refreshLanguage()
    }
    @discardableResult static func refreshLanguage() -> Bool {
        CFPreferencesSynchronize(sharedDomain as CFString, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }
    static var locale: Locale { language.locale }
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }
}

func calendarText(_ chinese: String, _ english: String) -> String {
    CalendarSettings.language.usesChinese() ? chinese : english
}

struct CalendarEvent: Codable, Identifiable {
    let id: String
    let eventIdentifier: String
    let readOnly: Bool
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let color: String
    var indicatorColor: String { readOnly ? "#AC82CE" : color }
}

struct DeleteRequest: Codable {
    let id: String
    let created: Date
    func permits(_ eventID: String, now: Date = Date()) -> Bool {
        id == eventID && (0..<60).contains(now.timeIntervalSince(created))
    }
}

struct CalendarTaskState: Codable {
    var completed: Set<String> = []
    var deletion: DeleteRequest?
    var message: String?
    mutating func setCompleted(_ id: String, to value: Bool) {
        if value { completed.insert(id) } else { completed.remove(id) }
        deletion = nil
        message = nil
    }
}

func eventOccurrenceID(_ identifier: String, start: Date) -> String {
    "\(identifier)-\(start.timeIntervalSince1970)"
}

func validCalendarTimestamp(_ timestamp: Double) -> Bool {
    timestamp.isFinite && timestamp >= -62135596800 && timestamp < 253402214400
}

func calendarAction(from url: URL) -> (name: String, date: Date)? {
    guard url.scheme?.lowercased() == "opencalendarwidget", let name = url.host,
        ["new", "calendar", "settings"].contains(name), let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    if name == "settings" {
        guard (components.queryItems ?? []).isEmpty else { return nil }
        return (name, Date())
    }
    let dates = (components.queryItems ?? []).filter { $0.name == "date" }
    guard dates.count == 1, let value = dates[0].value, let timestamp = Double(value), validCalendarTimestamp(timestamp) else { return nil }
    return (name, Date(timeIntervalSince1970: timestamp))
}

func eventCreationInterval(start: Date, end: Date, allDay: Bool, calendar: Calendar) throws -> DateInterval {
    guard validCalendarTimestamp(start.timeIntervalSince1970), validCalendarTimestamp(end.timeIntervalSince1970) else { throw CalendarActionError.invalidDate }
    if allDay {
        let day = calendar.startOfDay(for: start)
        return DateInterval(start: day, end: calendar.date(byAdding: .day, value: 1, to: day)!)
    }
    guard end > start else { throw CalendarActionError.invalidEnd }
    return DateInterval(start: start, end: end)
}

enum CalendarActionError: LocalizedError {
    case invalidDate, invalidEnd, emptyTitle, permission, readOnly, missingEvent, unconfirmed
    var errorDescription: String? {
        switch self {
        case .invalidDate: return calendarText("日期无效。", "Invalid date.")
        case .invalidEnd: return calendarText("结束时间需要晚于开始时间。", "End time must be later than start time.")
        case .emptyTitle: return calendarText("请输入日程标题。", "Enter an event title.")
        case .permission: return calendarText("请先允许日历访问。", "Allow calendar access first.")
        case .readOnly: return calendarText("这个日历不能修改，请选择其他日历。", "This calendar is read-only. Choose another calendar.")
        case .missingEvent: return calendarText("日程已被修改或删除，请刷新后重试。", "The event has changed or been deleted. Refresh and try again.")
        case .unconfirmed: return calendarText("删除确认已失效，请重新点击删除。", "Deletion confirmation expired. Select delete again.")
        }
    }
}

struct CalendarSnapshot: Codable {
    let updated: Date
    let events: [CalendarEvent]
    let message: String?

    func events(on day: Date, calendar: Calendar) -> [CalendarEvent] {
        events.filter { overlapsDay(start: $0.start, end: $0.end, day: day, calendar: calendar) }
            .sorted { ($0.allDay ? 0 : 1, $0.start, $0.id) < ($1.allDay ? 0 : 1, $1.start, $1.id) }
    }
    func upcomingTasks(after day: Date, calendar: Calendar, completed: Set<String>) -> [CalendarEvent] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))!
        let end = calendar.date(byAdding: .day, value: 30, to: tomorrow)!
        return events.filter { !$0.readOnly && !completed.contains($0.id) && $0.start >= tomorrow && $0.start < end }
            .sorted { ($0.start, $0.allDay ? 0 : 1, $0.id) < ($1.start, $1.allDay ? 0 : 1, $1.id) }
    }
    func indicatorColors(on day: Date, calendar: Calendar) -> [String] {
        var seen: Set<String> = []
        return Array(events(on: day, calendar: calendar).map(\.indicatorColor).filter { seen.insert($0).inserted }.prefix(4))
    }
}

struct CalendarTaskPage {
    let index: Int
    let count: Int
    let range: Range<Int>
    init(total: Int, availableHeight: Double, requested: Int) {
        guard total > 0, availableHeight.isFinite, availableHeight >= 22 else {
            index = 0; count = 0; range = 0..<0; return
        }
        let rows = max(1, Int(min(Double(total), floor((availableHeight + 3) / 25))))
        count = (total - 1) / rows + 1
        index = min(max(requested, 0), count - 1)
        let first = index * rows
        range = first..<(first + min(rows, total - first))
    }
}

struct CalendarSelection: Codable {
    let date: Date
    let changed: Date
    var page: Int? = nil
}

func overlapsDay(start: Date, end: Date, day: Date, calendar: Calendar) -> Bool {
    let lower = calendar.startOfDay(for: day)
    let upper = calendar.date(byAdding: .day, value: 1, to: lower)!
    return end > start ? start < upper && end > lower : start >= lower && start < upper
}

func monthCells(_ date: Date, calendar: Calendar) -> [Date] {
    let month = calendar.dateInterval(of: .month, for: date)!.start
    let leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
    let start = calendar.date(byAdding: .day, value: -leading, to: month)!
    return (0..<42).map { calendar.date(byAdding: .day, value: $0, to: start)! }
}

func shiftedMonth(_ date: Date, by offset: Int, calendar: Calendar) -> Date {
    let first = calendar.dateInterval(of: .month, for: date)!.start
    let target = calendar.date(byAdding: .month, value: offset, to: first)!
    let day = min(calendar.component(.day, from: date), calendar.range(of: .day, in: .month, for: target)!.count)
    return calendar.date(byAdding: .day, value: day - 1, to: target)!
}

enum CalendarStore {
    static let kind = "OpenCalendarWidget"
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .autoupdatingCurrent
        value.firstWeekday = 1
        return value
    }
    // shortcut: 所有小组件实例共用选中日期；需要独立实例时增加配置标识。
    private static var selection: CalendarSelection? {
        guard let url = try? fileURL("selection.json"), let data = try? Data(contentsOf: url),
            let selection = try? JSONDecoder().decode(CalendarSelection.self, from: data),
            validCalendarTimestamp(selection.date.timeIntervalSince1970),
            calendar.isDate(selection.changed, inSameDayAs: Date()) else { return nil }
        return selection
    }
    static var selectedDate: Date { selection?.date ?? Date() }
    static var selectedPage: Int { max(0, selection?.page ?? 0) }
    static func select(_ date: Date) throws {
        try JSONEncoder().encode(CalendarSelection(date: date, changed: Date(), page: 0)).write(to: fileURL("selection.json"), options: .atomic)
    }
    static func selectTaskPage(_ page: Int, for date: Date) throws {
        guard page >= 0, validCalendarTimestamp(date.timeIntervalSince1970), calendar.isDate(date, inSameDayAs: selectedDate) else { return }
        try JSONEncoder().encode(CalendarSelection(date: date, changed: Date(), page: page)).write(to: fileURL("selection.json"), options: .atomic)
    }
    private static func fileURL(_ name: String) throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = support.appendingPathComponent("OpenCalendarWidget/CalendarCache", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }
    static func taskState() throws -> CalendarTaskState {
        let url = try fileURL("tasks.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return CalendarTaskState() }
        return try JSONDecoder().decode(CalendarTaskState.self, from: Data(contentsOf: url))
    }
    // shortcut: 完成状态只由扩展主线程串行写入；引入其他进程写入时需加文件锁。
    static func saveTaskState(_ state: CalendarTaskState) throws {
        try JSONEncoder().encode(state).write(to: fileURL("tasks.json"), options: .atomic)
    }
    static func setCompleted(_ id: String, to value: Bool) throws {
        var state = try taskState()
        state.setCompleted(id, to: value)
        try saveTaskState(state)
    }
    static func requestDeletion(_ id: String?) throws {
        var state = try taskState()
        state.deletion = id.map { DeleteRequest(id: $0, created: Date()) }
        state.message = nil
        try saveTaskState(state)
    }
    static func recordError(_ error: Error) throws {
        var state = try taskState()
        state.message = error.localizedDescription
        state.deletion = nil
        try saveTaskState(state)
    }
    static func deleteEvent(identifier: String, start: Date) throws {
        let id = eventOccurrenceID(identifier, start: start)
        var state = try taskState()
        guard state.deletion?.permits(id) == true else { throw CalendarActionError.unconfirmed }
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw CalendarActionError.permission }
        let store = EKEventStore()
        let day = calendar.dateInterval(of: .day, for: start)!
        let candidates = store.events(matching: store.predicateForEvents(withStart: day.start, end: day.end, calendars: nil))
        guard let event = candidates.first(where: { $0.eventIdentifier == identifier && abs($0.startDate.timeIntervalSince(start)) < 0.5 }) else { throw CalendarActionError.missingEvent }
        guard event.calendar.allowsContentModifications else { throw CalendarActionError.readOnly }
        try store.remove(event, span: .thisEvent, commit: true)
        state.completed.remove(id)
        state.deletion = nil
        state.message = nil
        do { try saveTaskState(state) }
        catch { throw NSError(domain: "OpenCalendarWidget", code: 1, userInfo: [NSLocalizedDescriptionKey: calendarText("日程已删除，但本地标记保存失败：", "Event deleted, but saving local marks failed: ") + error.localizedDescription]) }
    }
    static func createEvent(title: String, start: Date, end: Date, allDay: Bool, calendarIdentifier: String) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw CalendarActionError.emptyTitle }
        let interval = try eventCreationInterval(start: start, end: end, allDay: allDay, calendar: calendar)
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw CalendarActionError.permission }
        let store = EKEventStore()
        guard let destination = store.calendar(withIdentifier: calendarIdentifier), destination.allowsContentModifications else { throw CalendarActionError.readOnly }
        let event = EKEvent(eventStore: store)
        event.title = title
        event.calendar = destination
        event.startDate = interval.start
        event.endDate = interval.end
        event.isAllDay = allDay
        try store.save(event, span: .thisEvent, commit: true)
    }
    static func snapshot(for date: Date) -> CalendarSnapshot {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            return CalendarSnapshot(updated: Date(), events: [], message: calendarText("请先打开 EasyCalendar 授权日历", "Open EasyCalendar to allow calendar access"))
        }
        let dates = monthCells(date, calendar: calendar)
        // shortcut: 未来待办查询限30天，扩大范围时仍保持单次EventKit读取。
        let end = max(calendar.date(byAdding: .day, value: 1, to: dates.last!)!, calendar.date(byAdding: .day, value: 31, to: calendar.startOfDay(for: date))!)
        let store = EKEventStore()
        let events = store.events(matching: store.predicateForEvents(withStart: dates[0], end: end, calendars: nil)).map { event in
            let color = NSColor(cgColor: event.calendar.cgColor)?.usingColorSpace(.sRGB) ?? .systemBlue
            return CalendarEvent(id: eventOccurrenceID(event.eventIdentifier ?? "event", start: event.startDate), eventIdentifier: event.eventIdentifier ?? "", readOnly: !event.calendar.allowsContentModifications || event.calendar.type == .subscription || event.calendar.type == .birthday, title: event.title ?? calendarText("无标题", "Untitled"), start: event.startDate, end: event.endDate, allDay: event.isAllDay,
                color: String(format: "#%02x%02x%02x", Int(min(max(color.redComponent, 0), 1) * 255), Int(min(max(color.greenComponent, 0), 1) * 255), Int(min(max(color.blueComponent, 0), 1) * 255)))
        }
        let snapshot = CalendarSnapshot(updated: Date(), events: events, message: nil)
        return snapshot
    }
}
