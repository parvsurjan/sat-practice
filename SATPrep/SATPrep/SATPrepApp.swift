import SwiftUI

@main
struct SATPrepApp: App {
    @State private var store = Store()
    @State private var tab = initialTab

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
        }
    }
}
