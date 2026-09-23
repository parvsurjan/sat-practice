import SwiftUI

@main
struct SATPrepApp: App {
    @State private var store = Store()
    @State private var tab = initialTab
    @Environment(\.scenePhase) private var scenePhase
    /// The day ("yyyy-MM-dd") the Question of the Day reminder was last dismissed.
    @AppStorage("qotdDismissedDay") private var qotdDismissedDay = ""
    @State private var showQOTD = false

    /// Today in the device's own calendar and time zone.
    private static func today() -> String {
        let d = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0)
    }

    static var initialTab: Int {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-startTab"), i + 1 < args.count {
            return ["practice": 0, "review": 1, "stats": 2][args[i + 1]] ?? 0
        }
        #endif
        return 0
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                PracticeView()
                    .tabItem { Label("Practice", systemImage: "pencil.and.list.clipboard") }
                    .tag(0)
                ReviewView()
                    .tabItem { Label("Review", systemImage: "bookmark") }
                    .tag(1)
                StatsView()
                    .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }
                    .tag(2)
            }
            .environment(store)
            .tint(BB.blue)
            .preferredColorScheme(.light)   // Bluebook is light-only; match it.
            // First open of each day: ask about the College Board's SAT Question of the Day.
            // Only dismissing it counts, so an unanswered prompt comes back next launch.
            .onChange(of: scenePhase, initial: true) {
                if scenePhase == .active && qotdDismissedDay != Self.today() { showQOTD = true }
            }
            .alert("SAT Question of the Day", isPresented: $showQOTD) {
                Button("Yes, done") { qotdDismissedDay = Self.today() }
                Button("Not yet", role: .cancel) { qotdDismissedDay = Self.today() }
            } message: {
                Text("Have you completed today's SAT Question of the Day?")
            }
        }
    }
}
