import SwiftUI

struct ReviewView: View {
    @Environment(Store.self) private var store
    @State private var section: Section_ = .needsWork

    enum Section_: String, CaseIterable, Identifiable {
        case needsWork = "Needs work", bookmarked = "Bookmarked"
        var id: String { rawValue }
    }

    private var items: [Question] {
        section == .needsWork ? store.needsWork : store.bookmarked
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $section) {
                    ForEach(Section_.allCases) { s in
                        Text("\(s.rawValue) (\(s == .needsWork ? store.needsWork.count : store.bookmarked.count))")
                            .tag(s)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.bottom, 8)

                if items.isEmpty {
                    Spacer()
                    if section == .needsWork {
                        ContentUnavailableView("Nothing to review", systemImage: "checkmark.circle",
                            description: Text("Questions you miss land here. Answer one right twice in a row and it graduates out."))
                    } else {
                        ContentUnavailableView("No bookmarks", systemImage: "bookmark",
                            description: Text("Tap the bookmark icon on any question to save it here."))
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(items) { q in
                            NavigationLink {
                                ReviewQuestionView(question: q)
                            } label: {
                                ReviewRow(question: q, progress: store.progress(q.id),
                                          showStreak: section == .needsWork)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Review")
        }
    }
}

struct ReviewRow: View {
    let question: Question
    let progress: QuestionProgress
    let showStreak: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                DifficultyBadge(difficulty: question.difficulty)
                TagBadge(text: question.skill)
                Spacer()
                if showStreak {
                    HStack(spacing: 3) {
                        ForEach(0..<masteryStreak, id: \.self) { i in
                            Image(systemName: i < progress.streak ? "circle.fill" : "circle")
                                .font(.system(size: 8))
                                .foregroundStyle(i < progress.streak ? BB.green : BB.rule)
                        }
                    }
                    .accessibilityLabel("\(progress.streak) of \(masteryStreak) correct in a row")
                }
            }
            Text(question.stem)
                .font(.subheadline)
                .lineLimit(3)
                .foregroundStyle(.primary)
            Text("\(progress.correct) right · \(progress.wrong) wrong")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// A single review attempt. Answering updates the same streak logic as normal practice.
struct ReviewQuestionView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let question: Question
    @State private var chosen: Int?
    @State private var retiredNow = false
    /// Captured before answering: only a question that was actually in the queue can graduate out of it.
    @State private var wasInQueue = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                QuestionCard(
                    question: question,
                    chosen: $chosen,
                    isBookmarked: store.progress(question.id).bookmarked,
                    onBookmark: { store.toggleBookmark(question.id) },
                    onSubmit: { i in
                        store.record(question: question, chosen: i)
                        retiredNow = wasInQueue && store.progress(question.id).retired
                    }
                )
                if retiredNow {
                    Label("Two in a row — removed from Needs work.", systemImage: "graduationcap.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(BB.green)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(BB.greenWash, in: RoundedRectangle(cornerRadius: BB.cardRadius))
                }
                if chosen != nil {
                    Button { dismiss() } label: {
                        Label("Done", systemImage: "checkmark")
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding()
        }
        .background(BB.surface)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { wasInQueue = store.progress(question.id).isInWrongQueue }
    }
}
