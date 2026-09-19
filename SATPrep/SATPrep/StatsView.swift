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
                            HStack {
                                Text("Question bank covered").font(.subheadline)
                                Spacer()
                                Text("\(uniqueSeen) of \(store.questions.count)")
                                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                            }
                        }

                        BucketSection(title: "By difficulty",
                                      buckets: bucket(\.difficulty.rawValue)
                                        .sorted { (Difficulty(rawValue: $0.name)?.sortOrder ?? 0)
                                                < (Difficulty(rawValue: $1.name)?.sortOrder ?? 0) })

                        BucketSection(title: "By category",
                                      buckets: bucket(\.domain).sorted { $0.accuracy < $1.accuracy })

                        BucketSection(title: "By skill — weakest first",
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
    let title: String
    let buckets: [Bucket]

    var body: some View {
        Section(title) {
            ForEach(buckets) { b in
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
    }
}
