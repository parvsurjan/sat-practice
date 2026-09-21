import SwiftUI

private struct Bucket: Identifiable {
    let name: String
    var correct = 0
    var total = 0
    var id: String { name }
    var accuracy: Double { total == 0 ? 0 : Double(correct) / Double(total) }
}

struct StatsView: View {
    @Environment(Store.self) private var store
    @State private var confirmReset = false

    private var history: [AnswerEvent] { store.save.history }

    private func bucket(_ key: (AnswerEvent) -> String) -> [Bucket] {
        var map: [String: Bucket] = [:]
        for e in history {
            let k = key(e)
            var b = map[k] ?? Bucket(name: k)
            b.total += 1
            if e.wasCorrect { b.correct += 1 }
            map[k] = b
        }
        return Array(map.values)
    }

    private var answered: Int { history.count }
    private var correct: Int { history.filter(\.wasCorrect).count }
    private var overall: Double { answered == 0 ? 0 : Double(correct) / Double(answered) }
    private var uniqueSeen: Int { store.save.progress.values.filter { $0.seen > 0 }.count }

    var body: some View {
        NavigationStack {
            Group {
                if answered == 0 {
                    ContentUnavailableView("No stats yet", systemImage: "chart.bar",
                        description: Text("Answer a few questions and your strengths and weak spots show up here."))
                } else {
                    List {
                        Section {
                            HStack(spacing: 12) {
                                StatTile(value: "\(Int(overall * 100))%", label: "Accuracy")
                                StatTile(value: "\(answered)", label: "Answered")
                                StatTile(value: "\(store.needsWork.count)", label: "Needs work")
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                            NavigationLink {
                                MissedListView(title: "All missed", questions: store.everMissed { _ in true })
                            } label: {
                                HStack {
                                    Text("All missed questions").font(.subheadline)
                                    Spacer()
                                    Text("\(store.everMissed { _ in true }.count)")
                                        .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                                }
                            }
                            HStack {
                                Text("Question bank covered").font(.subheadline)
                                Spacer()
                                Text("\(uniqueSeen) of \(store.questions.count)")
                                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                            }
                        }

                        BucketSection(title: "By difficulty",
                                      match: { name, q in q.difficulty.rawValue == name },
                                      buckets: bucket(\.difficulty.rawValue)
                                        .sorted { (Difficulty(rawValue: $0.name)?.sortOrder ?? 0)
                                                < (Difficulty(rawValue: $1.name)?.sortOrder ?? 0) })

                        BucketSection(title: "By category",
                                      match: { name, q in q.domain == name },
                                      buckets: bucket(\.domain).sorted { $0.accuracy < $1.accuracy })

                        BucketSection(title: "By skill — weakest first",
                                      match: { name, q in q.skill == name },
                                      buckets: bucket(\.skill).sorted { $0.accuracy < $1.accuracy })

                        Section {
                            Button("Reset all progress", role: .destructive) { confirmReset = true }
                        } footer: {
                            Text("Clears answers, bookmarks and review queues. Questions stay.")
                        }
                    }
                }
            }
            .navigationTitle("Stats")
            .alert("Reset all progress?", isPresented: $confirmReset) {
                Button("Reset", role: .destructive) { store.resetAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
    }
}

private struct StatTile: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 22, weight: .bold)).foregroundStyle(BB.blueDeep).minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(BB.surfaceAlt, in: RoundedRectangle(cornerRadius: BB.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: BB.cardRadius).stroke(BB.ruleSoft))
    }
}

/// Magnitude comparison: one hue, value always labeled in text ink so nothing is colour-alone.
private struct BucketSection: View {
    @Environment(Store.self) private var store
    let title: String
    let match: (String, Question) -> Bool
    let buckets: [Bucket]

    var body: some View {
        Section(title) {
            ForEach(buckets) { b in
                NavigationLink {
                    MissedListView(title: b.name, questions: store.everMissed { match(b.name, $0) })
                } label: {
                    row(b)
                }
            }
        }
    }

    private func row(_ b: Bucket) -> some View {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(b.name).font(.subheadline)
                        Spacer()
                        Text("\(Int(b.accuracy * 100))%")
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                        Text("(\(b.correct)/\(b.total))")
                            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(BB.ruleSoft).frame(height: 6)
                            Capsule().fill(BB.blue)
                                .frame(width: max(2, geo.size.width * b.accuracy), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(b.name): \(Int(b.accuracy * 100)) percent, \(b.correct) of \(b.total) correct")
    }
}

/// Every question ever missed in a group. Unlike Needs work, nothing leaves this list
/// until progress is reset, and reattempting from here never changes any data.
private struct MissedListView: View {
    @Environment(Store.self) private var store
    let title: String
    let questions: [Question]

    var body: some View {
        Group {
            if questions.isEmpty {
                ContentUnavailableView("Nothing missed", systemImage: "checkmark.circle",
                    description: Text("Questions you get wrong in this group will be listed here."))
            } else {
                List(questions) { q in
                    NavigationLink {
                        PracticeAttemptView(question: q)
                    } label: {
                        ReviewRow(question: q, progress: store.progress(q.id), showStreak: false)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Reattempt a missed question for practice. Records nothing: no stats, streaks or queues change.
private struct PracticeAttemptView: View {
    @Environment(\.dismiss) private var dismiss
    let question: Question
    @State private var selection: Int?
    @State private var submitted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Practice only — this won't affect your stats.", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(.secondary)
                QuestionCard(question: question, selection: $selection, submitted: submitted,
                             isBookmarked: false, onBookmark: {})
            }
            .padding()
        }
        .background(BB.surface)
        .safeAreaInset(edge: .bottom) {
            AnswerBar(submitted: submitted, hasSelection: selection != nil,
                      submitTitle: "Submit answer", nextTitle: "Done",
                      onSubmit: { if selection != nil { submitted = true } },
                      onNext: { dismiss() })
        }
        .navigationTitle("Reattempt")
        .navigationBarTitleDisplayMode(.inline)
    }
}
