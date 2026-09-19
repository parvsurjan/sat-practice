import SwiftUI

struct PracticeView: View {
    @Environment(Store.self) private var store

    @State private var current: Question?
    @State private var selection: Int?
    @State private var submitted = false
    @State private var showFilters = false
    @AppStorage("filterDifficulties") private var difficultiesRaw = ""
    @AppStorage("filterDomains") private var domainsRaw = ""

    private var difficulties: Set<Difficulty> {
        Set(difficultiesRaw.split(separator: "|").compactMap { Difficulty(rawValue: String($0)) })
    }
    private var domains: Set<String> {
        Set(domainsRaw.split(separator: "|").map(String.init))
    }

    var body: some View {
        NavigationStack {
            Group {
                if let q = current {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                Color.clear.frame(height: 0).id("top")
                                QuestionCard(
                                    question: q,
                                    selection: $selection,
                                    submitted: submitted,
                                    isBookmarked: store.progress(q.id).bookmarked,
                                    onBookmark: { store.toggleBookmark(q.id) }
                                )
                            }
                            .padding()
                        }
                        .background(BB.surface)
                        .safeAreaInset(edge: .bottom) {
                            AnswerBar(submitted: submitted,
                                      hasSelection: selection != nil,
                                      submitTitle: "Submit answer",
                                      nextTitle: "Next question",
                                      onSubmit: { submit(q) },
                                      onNext: {
                                          advance()
                                          proxy.scrollTo("top", anchor: .top)
                                      })
                        }
                    }
                } else {
                    ContentUnavailableView("No questions match",
                                           systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("Loosen the filters to keep practising."))
                }
            }
            .navigationTitle("Practice")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilters = true } label: {
                        Image(systemName: difficulties.isEmpty && domains.isEmpty
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showFilters) {
                FilterSheet(difficultiesRaw: $difficultiesRaw, domainsRaw: $domainsRaw)
                    .presentationDetents([.medium, .large])
            }
            .onChange(of: difficultiesRaw) { advance() }
            .onChange(of: domainsRaw) { advance() }
            .onAppear { if current == nil { advance() } }
        }
    }

    private func submit(_ q: Question) {
        guard let pick = selection, !submitted else { return }
        submitted = true
        store.record(question: q, chosen: pick)
    }

    private func advance() {
        selection = nil
        submitted = false
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-forceQuestion"), i + 1 < args.count,
           let forced = store.question(args[i + 1]) {
            current = forced
            if let j = args.firstIndex(of: "-autoAnswer"), j + 1 < args.count,
               let pick = Int(args[j + 1]) {
                selection = pick
                submitted = args.contains("-autoSubmit")
            }
            return
        }
        #endif
        current = store.nextQuestion(difficulties: difficulties, domains: domains,
                                     excluding: current?.id)
    }
}

struct FilterSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var difficultiesRaw: String
    @Binding var domainsRaw: String

    private func toggle(_ raw: inout String, _ value: String) {
        var set = Set(raw.split(separator: "|").map(String.init))
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
        raw = set.sorted().joined(separator: "|")
    }
    private func contains(_ raw: String, _ value: String) -> Bool {
        raw.split(separator: "|").contains(Substring(value))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Difficulty.allCases) { d in
                        row(title: d.rawValue, on: contains(difficultiesRaw, d.rawValue)) {
                            toggle(&difficultiesRaw, d.rawValue)
                        }
                    }
                } header: { Text("Difficulty") }
                  footer: { Text("Nothing selected means every difficulty.") }

                Section {
                    ForEach(store.domains, id: \.self) { d in
                        row(title: d, on: contains(domainsRaw, d)) { toggle(&domainsRaw, d) }
                    }
                } header: { Text("Category") }
                  footer: { Text("Nothing selected means every category.") }

                Section {
                    Button("Clear all filters", role: .destructive) {
                        difficultiesRaw = ""; domainsRaw = ""
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() } } }
        }
    }

    private func row(title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if on { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
        }
    }
}
