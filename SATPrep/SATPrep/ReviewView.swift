import SwiftUI

struct ReviewView: View {
    @Environment(Store.self) private var store
    @State private var section: Section_ = .needsWork

    enum Section_: String, CaseIterable, Identifiable {
        case needsWork = "Needs work", bookmarked = "Bookmarked"
        var id: String { rawValue }
    }

    private var items: [Question] {
        section == .needsWork ? store.needsWorkByUnlock() : store.bookmarked
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
                            description: Text("Questions you miss land here. Each one unlocks two weeks after you last answered it; get it right twice in a row and it graduates out."))
                    } else {
                        ContentUnavailableView("No bookmarks", systemImage: "bookmark",
                            description: Text("Tap the bookmark icon on any question to save it here."))
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(items) { q in
                            let p = store.progress(q.id)
                            if section == .needsWork, p.isReviewLocked(), let unlocks = p.reviewUnlocksAt {
                                ReviewRow(question: q, progress: p, showStreak: true, unlocksAt: unlocks)
                            } else {
                                NavigationLink {
                                    ReviewQuestionView(question: q)
                                } label: {
                                    ReviewRow(question: q, progress: p,
                                              showStreak: section == .needsWork)
                                }
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
    /// Set when the question is locked in Needs work; the row is dimmed and shows the unlock date.
    var unlocksAt: Date? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ExamBadge(exam: question.exam)
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
            Text(question.plainStem)
                .font(.subheadline)
                .lineLimit(3)
                .foregroundStyle(.primary)
            HStack(spacing: 6) {
                Text("\(progress.correct) right · \(progress.wrong) wrong")
                if let unlocksAt {
                    Spacer()
                    Label("Unlocks \(unlocksAt.formatted(.dateTime.month(.abbreviated).day()))",
                          systemImage: "lock.fill")
                }
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .opacity(unlocksAt == nil ? 1 : 0.5)
    }
}

/// A single review attempt. Answering updates the same streak logic as normal practice.
struct ReviewQuestionView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let question: Question
    @State private var selection: Int?
    @State private var submitted = false
    @State private var retiredNow = false
    /// Captured before answering: only a question that was actually in the queue can graduate out of it.
    @State private var wasInQueue = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                QuestionCard(
                    question: question,
                    selection: $selection,
                    submitted: submitted,
                    isBookmarked: store.progress(question.id).bookmarked,
                    onBookmark: { store.toggleBookmark(question.id) }
                )
                if retiredNow {
                    Label("Two in a row — removed from Needs work.", systemImage: "graduationcap.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(BB.green)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(BB.greenWash, in: RoundedRectangle(cornerRadius: BB.cardRadius))
                } else if submitted, let unlocks = store.progress(question.id).reviewUnlocksAt {
                    Label("Locked until \(unlocks.formatted(date: .abbreviated, time: .omitted)) — try it again then.",
                          systemImage: "lock.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(BB.surfaceAlt, in: RoundedRectangle(cornerRadius: BB.cardRadius))
                }
            }
            .padding()
        }
        .background(BB.surface)
        .safeAreaInset(edge: .bottom) {
            AnswerBar(submitted: submitted,
                      hasSelection: selection != nil,
                      submitTitle: "Submit answer",
                      nextTitle: "Done",
                      onSubmit: submit,
                      onNext: { dismiss() })
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { wasInQueue = store.progress(question.id).isInWrongQueue }
    }

    private func submit() {
        guard let pick = selection, !submitted else { return }
        submitted = true
        store.record(question: question, chosen: pick)
        retiredNow = wasInQueue && store.progress(question.id).retired
    }
}
