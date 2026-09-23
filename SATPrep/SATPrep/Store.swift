import Foundation
import SwiftUI

/// Number of consecutive correct answers needed to retire a previously-missed question.
let masteryStreak = 2

@MainActor
@Observable
final class Store {
    private(set) var questions: [Question] = []
    private(set) var save = SaveFile()

    private var byID: [String: Question] = [:]
    private let saveURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        saveURL = dir.appendingPathComponent("satprep-progress.json")
        loadQuestions()
        loadSave()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedDemo") { seedDemo() }
        if ProcessInfo.processInfo.arguments.contains("-selfTestCycle") { runCycleSelfTest() }
        #endif
    }

    #if DEBUG
    /// Drives a whole cycle through the real record() path and reports what survived.
    /// Writes to Application Support so the harness can read the result back.
    func runCycleSelfTest() {
        resetAll()
        var log: [String] = []

        // Bookmark a handful so we can confirm the reset clears them too.
        for q in questions.prefix(5) { toggleBookmark(q.id) }

        // First pass over the whole bank, deliberately missing every 10th question.
        for (i, q) in questions.enumerated() {
            record(question: q, chosen: i % 10 == 0 ? (q.correct + 1) % 4 : q.correct)
        }
        let seen = save.progress.values.filter { $0.seen > 0 }.count
        log.append("first pass: seen=\(seen)/\(questions.count) needsWork=\(needsWork.count) bookmarks=\(save.progress.values.filter(\.bookmarked).count)")
        log.append("complete after first pass? \(Cycle.isComplete(questionIDs: questions.map(\.id), progress: save.progress)) (expected false)")

        // Now clear the review queue, one answer at a time, stopping the moment it resets.
        var answers = 0
        var didReset = false
        outer: for _ in 0..<4 {
            for q in needsWork {
                record(question: q, chosen: q.correct)
                answers += 1
                if save.progress.isEmpty { didReset = true; break outer }
            }
            if needsWork.isEmpty { break }
        }
        log.append("cleared queue in \(answers) further answers; reset fired = \(didReset)")
        log.append("after reset: progress=\(save.progress.count) history=\(save.history.count) needsWork=\(needsWork.count) bookmarked=\(bookmarked.count)")

        // A reset bank must look brand new.
        let clean = save.progress.isEmpty && save.history.isEmpty && needsWork.isEmpty && bookmarked.isEmpty
        let servesQuestions = nextQuestion(difficulties: [], domains: [], excluding: nil) != nil
        log.append("serves a question after reset? \(servesQuestions)")
        log.append(didReset && clean && servesQuestions ? "RESULT: PASS" : "RESULT: FAIL")

        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? log.joined(separator: "\n").write(to: dir.appendingPathComponent("selftest.txt"),
                                               atomically: true, encoding: .utf8)
    }

    /// Fills in plausible history so the Review and Stats screens can be inspected.
    private func seedDemo() {
        save = SaveFile()
        var rng = SystemRandomNumberGenerator()
        for q in questions.shuffled().prefix(60) {
            let right = Int.random(in: 0..<10, using: &rng) < 6
            record(question: q, chosen: right ? q.correct : (q.correct + 1) % 4)
            if Int.random(in: 0..<10, using: &rng) < 3 { toggleBookmark(q.id) }
        }
    }
    #endif

    // MARK: - Loading

    private func loadQuestions() {
        let url = Bundle.main.url(forResource: "questions", withExtension: "json")
            ?? Bundle.main.url(forResource: "questions", withExtension: "json", subdirectory: "Resources")
        guard let url, let data = try? Data(contentsOf: url) else {
            assertionFailure("questions.json missing from bundle")
            return
        }
        do {
            questions = try JSONDecoder().decode([Question].self, from: data)
            byID = Dictionary(uniqueKeysWithValues: questions.map { ($0.id, $0) })
        } catch {
            assertionFailure("questions.json failed to decode: \(error)")
        }
    }

    private func loadSave() {
        guard let data = try? Data(contentsOf: saveURL) else { return }
        if let decoded = try? JSONDecoder().decode(SaveFile.self, from: data) { save = decoded }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(save) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    // MARK: - Lookups

    func question(_ id: String) -> Question? { byID[id] }
    func progress(_ id: String) -> QuestionProgress { save.progress[id] ?? QuestionProgress() }

    var domains: [String] { Array(Set(questions.map(\.domain))).sorted() }
    var skills: [String] { Array(Set(questions.map(\.skill))).sorted() }

    // MARK: - Mutations

    func record(question: Question, chosen: Int) {
        var p = progress(question.id)
        let right = chosen == question.correct
        p.apply(correct: right, masteryStreak: masteryStreak)
        save.progress[question.id] = p
        save.history.append(AnswerEvent(questionID: question.id, wasCorrect: right, date: Date(),
                                        exam: question.exam,
                                        difficulty: question.difficulty, domain: question.domain,
                                        skill: question.skill))
        persist()
        resetIfCycleComplete()
    }

    /// Once the whole bank has been answered and nothing is left to review, start over
    /// from scratch so practice never runs out.
    private func resetIfCycleComplete() {
        guard Cycle.isComplete(questionIDs: questions.map(\.id), progress: save.progress) else { return }
        resetAll()
    }

    func toggleBookmark(_ id: String) {
        var p = progress(id)
        p.bookmarked.toggle()
        save.progress[id] = p
        persist()
    }

    func resetAll() {
        save = SaveFile()
        persist()
    }

    // MARK: - Queues

    var bookmarked: [Question] {
        questions.filter { progress($0.id).bookmarked }
    }

    /// Questions missed at least once and not yet retired by two correct answers in a row.
    var needsWork: [Question] {
        questions.filter { progress($0.id).isInWrongQueue }
    }

    /// Needs work ordered for the Review tab: questions ready now first, then locked ones
    /// by how soon they unlock.
    func needsWorkByUnlock(now: Date = Date()) -> [Question] {
        needsWork.sorted { a, b in
            let ua = progress(a.id).reviewUnlocksAt ?? .distantPast
            let ub = progress(b.id).reviewUnlocksAt ?? .distantPast
            let la = ua > now, lb = ub > now
            if la != lb { return !la }
            return la ? ua < ub : false
        }
    }

    /// Every question missed at least once, matching `filter`. Missing it is permanent
    /// (until reset) even after the question graduates out of Needs work.
    func everMissed(where filter: (Question) -> Bool) -> [Question] {
        questions.filter { progress($0.id).everWrong && filter($0) }
    }

    /// A question to practise next, honouring the filters and preferring unseen questions.
    func nextQuestion(exams: Set<Exam> = [], difficulties: Set<Difficulty>, domains: Set<String>,
                      excluding: String?) -> Question? {
        var pool = questions.filter {
            (exams.isEmpty || exams.contains($0.exam)) &&
            (difficulties.isEmpty || difficulties.contains($0.difficulty)) &&
            (domains.isEmpty || domains.contains($0.domain))
        }
        if pool.count > 1, let excluding { pool.removeAll { $0.id == excluding } }
        guard !pool.isEmpty else { return nil }
        let unseen = pool.filter { progress($0.id).seen == 0 }
        return (unseen.isEmpty ? pool : unseen).randomElement()
    }
}
