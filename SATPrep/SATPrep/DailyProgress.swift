import Foundation

/// Shared between the app and the Lock Screen widget via an App Group, so both read
/// and write the same "how many questions answered today" counter.
enum DailyProgress {
    static let appGroupID = "group.com.parvsurjan.SATPrep"
    static let goal = 20

    private static let defaults = UserDefaults(suiteName: appGroupID)
    private static let countKey = "dailyProgress.count"
    private static let dayKey = "dailyProgress.day"

    private static func todayKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Questions answered today. Resets itself once the calendar day rolls over.
    static var todayCount: Int {
        guard let defaults, defaults.string(forKey: dayKey) == todayKey() else { return 0 }
        return defaults.integer(forKey: countKey)
    }

    static func recordAnswer() {
        guard let defaults else { return }
        let today = todayKey()
        if defaults.string(forKey: dayKey) != today {
            defaults.set(today, forKey: dayKey)
            defaults.set(0, forKey: countKey)
        }
        defaults.set(defaults.integer(forKey: countKey) + 1, forKey: countKey)
    }
}
