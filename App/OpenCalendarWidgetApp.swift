import SwiftUI
import EventKit
import WidgetKit

@main
struct OpenCalendarWidgetApp {
    @MainActor static func main() {
        if CalendarSettings.publishLanguage(CalendarSettings.language) {
            WidgetCenter.shared.reloadTimelines(ofKind: CalendarStore.kind)
        } else { NSLog("Unable to synchronize widget language") }
        let app = NSApplication.shared
        let delegate = CalendarAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        let menu = NSMenu()
        let applicationMenu = NSMenuItem()
        applicationMenu.submenu = NSMenu(title: "EasyCalendar")
        let settingsItem = NSMenuItem(title: calendarText("设置…", "Settings…"), action: #selector(CalendarAppDelegate.openSettings), keyEquivalent: ",")
        settingsItem.target = delegate
        applicationMenu.submenu?.addItem(settingsItem)
        applicationMenu.submenu?.addItem(.separator())
        applicationMenu.submenu?.addItem(withTitle: calendarText("退出 EasyCalendar", "Quit EasyCalendar"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(applicationMenu)
        app.mainMenu = menu
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class CalendarAppDelegate: NSObject, NSApplicationDelegate {
    private var setupWindow: NSWindow?
    private var editorWindows: [NSWindow] = []

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        showSetup()
        return true
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showSetup()
        return false
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard let action = calendarAction(from: url) else { continue }
            if action.name == "new" { showEditor(date: action.date) }
            else if action.name == "settings" { showSetup() }
            else {
                guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { continue }
                NSWorkspace.shared.openApplication(at: applicationURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if let error { NSLog("打开日历失败：%@", error.localizedDescription) }
                }
            }
        }
    }
    @objc func openSettings() { showSetup() }
    private func showSetup() {
        if let setupWindow { setupWindow.makeKeyAndOrderFront(nil) }
        else {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SetupView { [weak self] in self?.showEditor(date: Date()) }.frame(width: 420)))
            window.title = "EasyCalendar"
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)
            setupWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    private func showEditor(date: Date) {
        // 每次链接创建新的表单状态，已有草稿窗口保持不变。
        editorWindows.removeAll { !$0.isVisible }
        let window = NSWindow()
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = calendarText("添加日程", "Add event")
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: NewEventView(date: date) { [weak window] in window?.close() })
        window.center()
        window.makeKeyAndOrderFront(nil)
        editorWindows.append(window)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SetupView: View {
    @AppStorage("language", store: CalendarSettings.defaults) private var language = CalendarLanguage.system.rawValue
    @State private var message: String?
    @State private var busy = false
    let addEvent: () -> Void
    private let store = EKEventStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("EasyCalendar").font(.title2.bold())
                    Text(calendarText("版本 ", "Version ") + "\(CalendarSettings.version) (\(CalendarSettings.build))")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            GroupBox(calendarText("语言", "Language")) {
                Picker(calendarText("界面语言", "Interface language"), selection: $language) {
                    ForEach(CalendarLanguage.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }.pickerStyle(.menu).padding(8)
            }
            GroupBox(calendarText("日历访问", "Calendar access")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(message ?? (EKEventStore.authorizationStatus(for: .event) == .fullAccess
                        ? calendarText("已授权。可以读取、添加和删除系统日历日程。", "Access granted. You can read, add, and delete calendar events.")
                        : calendarText("首次使用需要允许完全访问系统日历。", "Allow full calendar access before using the widget.")))
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(busy ? calendarText("正在读取…", "Loading…") : calendarText("授权并刷新日历", "Allow access & refresh")) { authorize() }.disabled(busy)
                        Button(calendarText("添加日程", "Add event"), action: addEvent)
                    }
                    Text(calendarText("右键桌面 → 编辑小组件，搜索 EasyCalendar。", "Right-click the desktop → Edit Widgets, then search for EasyCalendar."))
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            GroupBox(calendarText("关于", "About")) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(calendarText("独立的 macOS 原生日历小组件", "An independent native calendar widget for macOS"))
                    Text("GPL-3.0-only · SwiftUI / WidgetKit / EventKit")
                    Text(calendarText("完成状态保存在本机；新增和删除写入系统日历。没有自有服务器或分析统计。", "Completion marks stay on this Mac. Adding and deleting writes to Calendar. No app server or analytics."))
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
        }.padding(24).environment(\.locale, CalendarSettings.locale)
            .onChange(of: language) { _, value in
                if CalendarSettings.publishLanguage(CalendarLanguage(rawValue: value) ?? .system) {
                    WidgetCenter.shared.reloadTimelines(ofKind: CalendarStore.kind)
                    message = nil
                } else {
                    message = calendarText("语言已保存在应用中，但小组件同步失败，请重试。", "Language saved in the app, but widget synchronization failed. Please try again.")
                }
                let menu = NSApp.mainMenu?.items.first?.submenu
                menu?.items.first?.title = calendarText("设置…", "Settings…")
                menu?.items.last?.title = calendarText("退出 EasyCalendar", "Quit EasyCalendar")
            }
    }
    private func authorize() {
        busy = true; message = nil
        Task {
            do {
                let granted = EKEventStore.authorizationStatus(for: .event) == .fullAccess ? true : try await store.requestFullAccessToEvents()
                guard granted else { message = calendarText("未获得日历权限，可在系统设置中允许访问。", "Calendar access was denied. Allow it in System Settings."); busy = false; return }
                WidgetCenter.shared.reloadTimelines(ofKind: CalendarStore.kind)
                message = calendarText("已授权并请求刷新小组件。", "Access granted. Widget refresh requested.")
            } catch { message = calendarText("授权失败：", "Authorization failed: ") + error.localizedDescription }
            busy = false
        }
    }
}

struct NewEventView: View {
    @AppStorage("language", store: CalendarSettings.defaults) private var language = CalendarLanguage.system.rawValue
    let close: () -> Void
    @State private var title = ""
    @State private var start: Date
    @State private var end: Date
    @State private var allDay = true
    @State private var calendars: [EKCalendar] = []
    @State private var calendarIdentifier = ""
    @State private var message: String?
    @State private var busy = false
    private let store = EKEventStore()

    init(date: Date, close: @escaping () -> Void) {
        self.close = close
        let start = CalendarStore.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date)!
        _start = State(initialValue: start)
        _end = State(initialValue: start.addingTimeInterval(3600))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(calendarText("添加日程", "Add event")).font(.title2.bold())
            Form {
                TextField(calendarText("标题", "Title"), text: $title, prompt: Text(calendarText("输入待办或日程", "Enter a task or event")))
                Toggle(calendarText("全天", "All day"), isOn: $allDay)
                DatePicker(allDay ? calendarText("日期", "Date") : calendarText("开始", "Start"), selection: $start, displayedComponents: allDay ? .date : [.date, .hourAndMinute])
                if !allDay { DatePicker(calendarText("结束", "End"), selection: $end, displayedComponents: [.date, .hourAndMinute]) }
                Picker(calendarText("日历", "Calendar"), selection: $calendarIdentifier) {
                    ForEach(calendars, id: \.calendarIdentifier) { calendar in
                        HStack {
                            Circle().fill(Color(cgColor: calendar.cgColor)).frame(width: 7, height: 7)
                            Text(calendar.title)
                        }.tag(calendar.calendarIdentifier)
                    }
                }
            }
            if let message { Text(message).font(.caption).foregroundStyle(.red) }
            Text(calendarText("保存后会出现在系统日历和桌面待办中。", "Saved events appear in Calendar and the desktop widget.")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(calendarText("取消", "Cancel")) { close() }.keyboardShortcut(.cancelAction).disabled(busy)
                Button(busy ? calendarText("保存中…", "Saving…") : calendarText("添加", "Add")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || calendarIdentifier.isEmpty)
            }
        }.padding(24).frame(width: 400).environment(\.locale, CalendarLanguage(rawValue: language)?.locale ?? .autoupdatingCurrent)
            .onAppear {
                guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
                    message = calendarText("请关闭表单，先授权日历访问。", "Close this form and allow calendar access in Settings."); return
                }
                calendars = store.calendars(for: .event).filter { $0.allowsContentModifications && $0.type != .subscription && $0.type != .birthday }
                let preferred = store.defaultCalendarForNewEvents?.calendarIdentifier
                calendarIdentifier = calendars.first(where: { $0.calendarIdentifier == preferred })?.calendarIdentifier ?? calendars.first?.calendarIdentifier ?? ""
                if calendars.isEmpty { message = calendarText("没有可写入的日历，请先在系统日历中创建一个。", "No writable calendars. Create one in Calendar first.") }
            }
            .onChange(of: start) { _, value in if end <= value { end = value.addingTimeInterval(3600) } }
    }
    private func save() {
        busy = true; message = nil
        let values = (title, start, end, allDay, calendarIdentifier)
        Task {
            do {
                try await Task.detached {
                    try CalendarStore.createEvent(title: values.0, start: values.1, end: values.2, allDay: values.3, calendarIdentifier: values.4)
                }.value
                WidgetCenter.shared.reloadTimelines(ofKind: CalendarStore.kind)
                close()
            } catch { message = error.localizedDescription }
            busy = false
        }
    }
}
