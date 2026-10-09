import SwiftUI
import WidgetKit
import AppIntents

struct SelectCalendarDate: AppIntent {
    static var title: LocalizedStringResource = "选择日历日期"
    static var openAppWhenRun = false
    @Parameter(title: "日期") var timestamp: Double
    init() {}
    init(_ date: Date) { timestamp = date.timeIntervalSince1970 }
    @MainActor func perform() async throws -> some IntentResult {
        guard validCalendarTimestamp(timestamp) else { return .result() }
        try CalendarStore.select(Date(timeIntervalSince1970: timestamp))
        return .result()
    }
}

struct SelectCalendarTaskPage: AppIntent {
    static var title: LocalizedStringResource = "翻页查看待办"
    static var openAppWhenRun = false
    @Parameter(title: "页码") var page: Int
    @Parameter(title: "日期") var timestamp: Double
    init() {}
    init(_ page: Int, date: Date) { self.page = page; timestamp = date.timeIntervalSince1970 }
    @MainActor func perform() async throws -> some IntentResult {
        guard page >= 0, validCalendarTimestamp(timestamp) else { return .result() }
        try CalendarStore.selectTaskPage(page, for: Date(timeIntervalSince1970: timestamp))
        return .result()
    }
}

struct CompleteCalendarEvent: AppIntent {
    static var title: LocalizedStringResource = "完成日程"
    static var openAppWhenRun = false
    @Parameter(title: "日程") var id: String
    @Parameter(title: "完成") var completed: Bool
    init() {}
    init(_ id: String, completed: Bool) { self.id = id; self.completed = completed }
    @MainActor func perform() async throws -> some IntentResult {
        guard !id.isEmpty, id.count < 1024 else { return .result() }
        do { try CalendarStore.setCompleted(id, to: completed) }
        catch { try CalendarStore.recordError(error) }
        return .result()
    }
}

struct DeleteCalendarEvent: AppIntent {
    static var title: LocalizedStringResource = "删除日程"
    static var openAppWhenRun = false
    @Parameter(title: "日程") var identifier: String
    @Parameter(title: "开始时间") var timestamp: Double
    @Parameter(title: "确认删除") var confirmed: Bool
    init() {}
    init(_ event: CalendarEvent, confirmed: Bool = false) {
        identifier = event.eventIdentifier; timestamp = event.start.timeIntervalSince1970; self.confirmed = confirmed
    }
    init(cancel: Bool) { identifier = ""; timestamp = 0; confirmed = false }
    @MainActor func perform() async throws -> some IntentResult {
        do {
            if identifier.isEmpty { try CalendarStore.requestDeletion(nil) }
            else {
                guard validCalendarTimestamp(timestamp), identifier.count < 1024 else { throw CalendarActionError.invalidDate }
                let start = Date(timeIntervalSince1970: timestamp)
                if confirmed { try CalendarStore.deleteEvent(identifier: identifier, start: start) }
                else { try CalendarStore.requestDeletion(eventOccurrenceID(identifier, start: start)) }
            }
        } catch { try CalendarStore.recordError(error) }
        return .result()
    }
}

struct CalendarEntry: TimelineEntry {
    let date: Date
    let selected: Date
    let snapshot: CalendarSnapshot
    var state = CalendarTaskState()
    var page = 0
}

struct CalendarProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarEntry {
        CalendarSettings.refreshLanguage()
        return CalendarEntry(date: Date(), selected: Date(), snapshot: CalendarSnapshot(updated: Date(), events: [], message: calendarText("当天无日程", "No events today")))
    }
    func getSnapshot(in context: Context, completion: @escaping (CalendarEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarEntry>) -> Void) {
        completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(60))))
    }
    private func entry() -> CalendarEntry {
        CalendarSettings.refreshLanguage()
        let selected = CalendarStore.selectedDate
        var state: CalendarTaskState
        do { state = try CalendarStore.taskState() }
        catch { state = CalendarTaskState(message: calendarText("完成标记读取失败：", "Unable to read completion marks: ") + error.localizedDescription) }
        return CalendarEntry(date: Date(), selected: selected, snapshot: CalendarStore.snapshot(for: selected), state: state, page: CalendarStore.selectedPage)
    }
}

struct CalendarCard: View {
    let entry: CalendarEntry
    private var calendar: Calendar { CalendarStore.calendar }
    private var daily: [CalendarEvent] { entry.snapshot.events(on: entry.selected, calendar: calendar) }
    private var tasks: [CalendarEvent] { daily.filter { !$0.readOnly } }
    private var upcoming: [CalendarEvent] { entry.snapshot.upcomingTasks(after: entry.selected, calendar: calendar, completed: entry.state.completed) }
    private var displayedTasks: [CalendarEvent] { tasks.isEmpty ? upcoming : tasks }
    private var notices: [CalendarEvent] { daily.filter(\.readOnly) }
    private var monthTitle: String {
        let parts = calendar.dateComponents([.year, .month], from: entry.selected)
        return CalendarSettings.language.usesChinese() ? "\(parts.year!)年\(parts.month!)月" : entry.selected.formatted(.dateTime.month(.wide).year().locale(CalendarSettings.locale))
    }
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 4) {
                    HStack(spacing: 0) {
                        Button(intent: SelectCalendarDate(shiftedMonth(entry.selected, by: -1, calendar: calendar))) { Image(systemName: "chevron.left") }.accessibilityLabel(calendarText("上个月", "Previous month"))
                        Spacer(minLength: 0)
                        Button(intent: SelectCalendarDate(Date())) { Text(monthTitle).font(.system(size: 11, weight: .bold)) }.accessibilityLabel(calendarText("返回今天", "Return to today"))
                        Spacer(minLength: 0)
                        Button(intent: SelectCalendarDate(shiftedMonth(entry.selected, by: 1, calendar: calendar))) { Image(systemName: "chevron.right") }.accessibilityLabel(calendarText("下个月", "Next month"))
                    }.font(.system(size: 10, weight: .bold)).foregroundStyle(.blue).frame(height: 16)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 1) {
                        ForEach(0..<7, id: \.self) { index in
                            Text((CalendarSettings.language.usesChinese() ? ["日", "一", "二", "三", "四", "五", "六"] : ["S", "M", "T", "W", "T", "F", "S"])[index])
                                .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).frame(height: 11)
                        }
                        ForEach(monthCells(entry.selected, calendar: calendar), id: \.self) { date in
                            let selected = calendar.isDate(date, inSameDayAs: entry.selected)
                            let sameMonth = calendar.isDate(date, equalTo: entry.selected, toGranularity: .month)
                            Button(intent: SelectCalendarDate(date)) {
                                VStack(spacing: 0) {
                                    Text("\(calendar.component(.day, from: date))")
                                        .font(.system(size: 10, weight: .semibold)).frame(width: 18, height: 16)
                                        .background(selected ? Color.blue : .clear, in: RoundedRectangle(cornerRadius: 5))
                                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(calendar.isDateInToday(date) && !selected ? Color.blue : .clear, lineWidth: 1))
                                        .foregroundStyle(selected ? .white : sameMonth ? .primary : .secondary)
                                    HStack(spacing: 1) {
                                        ForEach(entry.snapshot.indicatorColors(on: date, calendar: calendar), id: \.self) { hex in
                                            Circle().fill(eventColor(hex)).frame(width: 2, height: 2)
                                        }
                                    }.frame(height: 2)
                                }.frame(maxWidth: .infinity).contentShape(Rectangle())
                            }.accessibilityLabel(date.formatted(Date.FormatStyle(date: .complete, time: .omitted).locale(CalendarSettings.locale)))
                                .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }.frame(width: (geometry.size.width - 12) * 0.48)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("\(calendar.component(.day, from: entry.selected))")
                            .font(.system(size: 25, weight: .bold)).frame(width: 36, height: 34)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(entry.selected, format: .dateTime.weekday(.wide))
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(.blue).lineLimit(1).minimumScaleFactor(0.6)
                            Text(CalendarSettings.language.usesChinese() ? "\(calendar.component(.month, from: entry.selected))月" : entry.selected.formatted(.dateTime.month(.abbreviated).locale(CalendarSettings.locale))).font(.system(size: 10)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        HStack(spacing: 3) {
                            Link(destination: actionURL("new")) {
                                Image(systemName: "plus").foregroundStyle(.blue).frame(width: 18, height: 20)
                                    .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                            }.accessibilityLabel(calendarText("在选中日期添加日程", "Add event on selected date"))
                            Link(destination: actionURL("calendar")) {
                                Image(systemName: "calendar").foregroundStyle(.secondary).frame(width: 18, height: 20)
                                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                            }.accessibilityLabel(calendarText("打开日历", "Open Calendar"))
                            Link(destination: actionURL("settings")) {
                                Image(systemName: "gearshape").foregroundStyle(.secondary).frame(width: 18, height: 20)
                                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                            }.accessibilityLabel(calendarText("打开设置", "Open settings"))
                        }.font(.system(size: 11, weight: .medium)).fixedSize()
                    }.frame(height: 34)
                    GeometryReader { content in taskContent(height: content.size.height) }
                        .frame(height: max(0, geometry.size.height - 39)).clipped()
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.buttonStyle(.plain)
        }.padding(12).containerBackground(.fill.tertiary, for: .widget)
            .environment(\.locale, CalendarSettings.locale)
            .transaction { $0.animation = nil }
    }
    private func taskContent(height: CGFloat) -> some View {
        let headerHeight: CGFloat = 14 + (notices.isEmpty ? 0 : 19) + (entry.state.message == nil ? 0 : 14) + (tasks.isEmpty ? 15 : 0)
        let page = CalendarTaskPage(total: displayedTasks.count, availableHeight: Double(height - headerHeight), requested: entry.page)
        return VStack(alignment: .leading, spacing: 3) {
            if let message = entry.snapshot.message {
                Text(message).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(3)
            } else {
                if !notices.isEmpty {
                    Text(notices.map(\.title).joined(separator: " · "))
                        .font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        .padding(.horizontal, 5).frame(maxWidth: .infinity, alignment: .leading).frame(height: 16)
                        .foregroundStyle(eventColor("#785899"))
                        .background(eventColor("#EEE5FA"), in: RoundedRectangle(cornerRadius: 4))
                }
                if let message = entry.state.message {
                    Text(message).font(.system(size: 9)).foregroundStyle(.red).lineLimit(1).frame(height: 11)
                        .accessibilityLabel(message)
                }
                if tasks.isEmpty {
                    Text(calendarText("当天无待办", "No tasks today")).font(.system(size: 10)).foregroundStyle(.secondary).frame(height: 12)
                }
                if !displayedTasks.isEmpty {
                    HStack(spacing: 2) {
                        Text(tasks.isEmpty ? calendarText("未来待办 · 30天内", "Upcoming · 30 days") : calendarText("待办", "Tasks"))
                            .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        if page.count > 1 {
                            Button(intent: SelectCalendarTaskPage(page.index - 1, date: entry.selected)) {
                                Image(systemName: "arrow.up").frame(width: 12, height: 11)
                            }.disabled(page.index == 0).accessibilityLabel(calendarText("上一页待办", "Previous task page"))
                            Text("\(page.index + 1)/\(page.count)").monospacedDigit().fixedSize()
                                .accessibilityLabel(calendarText("待办第\(page.index + 1)页，共\(page.count)页", "Task page \(page.index + 1) of \(page.count)"))
                            Button(intent: SelectCalendarTaskPage(page.index + 1, date: entry.selected)) {
                                Image(systemName: "arrow.down").frame(width: 12, height: 11)
                            }.disabled(page.index + 1 == page.count).accessibilityLabel(calendarText("下一页待办", "Next task page"))
                        }
                    }.font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).frame(height: 11)
                    ForEach(Array(displayedTasks[page.range])) { event in
                        taskRow(event).frame(height: 22)
                    }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func actionURL(_ action: String) -> URL {
        var components = URLComponents()
        components.scheme = "opencalendarwidget"
        components.host = action
        if action != "settings" { components.queryItems = [URLQueryItem(name: "date", value: String(entry.selected.timeIntervalSince1970))] }
        return components.url!
    }
    @ViewBuilder private func taskRow(_ event: CalendarEvent) -> some View {
        let completed = entry.state.completed.contains(event.id)
        if entry.state.deletion?.permits(event.id, now: entry.date) == true {
            HStack(spacing: 5) {
                Text(calendarText("删除此日程？", "Delete this event?")).font(.system(size: 10)).lineLimit(1)
                Spacer(minLength: 0)
                Button(calendarText("删除", "Delete"), intent: DeleteCalendarEvent(event, confirmed: true)).foregroundStyle(.red)
                Button(calendarText("取消", "Cancel"), intent: DeleteCalendarEvent(cancel: true)).foregroundStyle(.secondary)
            }.font(.system(size: 9)).frame(minHeight: 16)
                .accessibilityLabel(calendarText("确认删除日程：", "Confirm deletion: ") + event.title)
        } else {
            HStack(alignment: .center, spacing: 4) {
                Toggle(isOn: completed, intent: CompleteCalendarEvent(event.id, completed: !completed)) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(event.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                        if tasks.isEmpty {
                            Text(event.start.formatted(.dateTime.month(.twoDigits).day(.twoDigits).locale(CalendarSettings.locale)) + (event.allDay ? "" : " · " + event.start.formatted(.dateTime.hour().minute().locale(CalendarSettings.locale))))
                                .font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                        } else if !event.allDay {
                            Text("\(event.start.formatted(.dateTime.hour().minute().locale(CalendarSettings.locale)))–\(event.end.formatted(.dateTime.hour().minute().locale(CalendarSettings.locale)))")
                                .font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.toggleStyle(TaskCheckboxStyle(color: eventColor(event.color)))
                    .accessibilityLabel(tasks.isEmpty ? "\(event.title)，\(event.start.formatted(Date.FormatStyle(date: .complete, time: event.allDay ? .omitted : .shortened).locale(CalendarSettings.locale)))" : event.title)
                    .accessibilityValue(completed ? calendarText("已完成", "Completed") : calendarText("未完成", "Incomplete"))
                Button(intent: DeleteCalendarEvent(event)) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .medium)).foregroundStyle(.tertiary)
                        .frame(width: 14, height: 16).contentShape(Rectangle())
                }.accessibilityLabel(calendarText("删除", "Delete ") + event.title).disabled(event.eventIdentifier.isEmpty)
            }
        }
    }
    private func eventColor(_ hex: String) -> Color {
        guard let rgb = UInt32(hex.dropFirst(), radix: 16) else { return .blue }
        return Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
    }
}

struct TaskCheckboxStyle: ToggleStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .center, spacing: 5) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(configuration.isOn ? color : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(color, lineWidth: 1.3))
                    .overlay {
                        if configuration.isOn { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.white) }
                    }.frame(width: 12, height: 12)
                configuration.label.strikethrough(configuration.isOn)
                    .foregroundStyle(configuration.isOn ? .secondary : .primary)
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

@main
struct OpenCalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CalendarStore.kind, provider: CalendarProvider()) { CalendarCard(entry: $0) }
            .configurationDisplayName("EasyCalendar")
            .description(Text(calendarText("选择日期，查看系统日历中的当天日程。", "Select a date to view events from Calendar.")))
            .supportedFamilies([.systemMedium])
            .contentMarginsDisabled()
    }
}
