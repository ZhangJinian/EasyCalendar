import Foundation

// In-memory CFPreferences stand-ins exercise the production bridge without changing user settings.
private var pending: CFPropertyList?
private var saved: CFPropertyList?
private var canSynchronize = true
private var writes = 0

func CFPreferencesSetValue(_ key: CFString, _ value: CFPropertyList?, _ domain: CFString, _ user: CFString, _ host: CFString) {
    assert(key as String == "language" && domain as String == CalendarSettings.sharedDomain)
    assert(CFEqual(user, kCFPreferencesCurrentUser) && CFEqual(host, kCFPreferencesAnyHost))
    pending = value
    writes += 1
}
func CFPreferencesCopyValue(_ key: CFString, _ domain: CFString, _ user: CFString, _ host: CFString) -> CFPropertyList? {
    assert(key as String == "language" && domain as String == CalendarSettings.sharedDomain)
    return saved
}
func CFPreferencesSynchronize(_ domain: CFString, _ user: CFString, _ host: CFString) -> Bool {
    assert(domain as String == CalendarSettings.sharedDomain)
    if canSynchronize { saved = pending }
    return canSynchronize
}

@main
struct LanguageBridgeCheck {
    static func main() {
        assert(Bundle.main.bundleIdentifier != CalendarSettings.domain)
        assert(CalendarSettings.language == .system)
        assert(CalendarSettings.publishLanguage(.english))
        assert(writes == 1 && CalendarSettings.language == .english)
        assert(calendarText("当天无待办", "No tasks today") == "No tasks today")
        assert(calendarText("未来待办 · 30天内", "Upcoming · 30 days") == "Upcoming · 30 days")
        assert(CalendarSettings.locale.identifier == "en")
        assert(CalendarSettings.publishLanguage(.simplifiedChinese))
        assert(CalendarSettings.language == .simplifiedChinese)
        assert(calendarText("当天无待办", "No tasks today") == "当天无待办")
        canSynchronize = false
        assert(!CalendarSettings.publishLanguage(.english))
        assert(!CalendarSettings.refreshLanguage())
        assert(CalendarSettings.language == .simplifiedChinese)
        saved = "invalid" as NSString
        assert(CalendarSettings.language == .system)
        print("PASS: shared language domain, English/Chinese widget text, synchronization failure, invalid value fallback")
    }
}
