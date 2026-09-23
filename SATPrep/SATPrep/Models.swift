import Foundation

enum Difficulty: String, Codable, CaseIterable, Identifiable, Hashable {
    case easy = "Easy", medium = "Medium", hard = "Hard"
    var id: String { rawValue }
    var sortOrder: Int { self == .easy ? 0 : (self == .medium ? 1 : 2) }
}

/// Which test a question bank came from. PSAT here covers PSAT/NMSQT and PSAT 10.
enum Exam: String, Codable, CaseIterable, Identifiable, Hashable {
    case sat = "SAT", psat = "PSAT"
    var id: String { rawValue }
}

/// One SAT or PSAT question as extracted from the source PDFs.
struct Question: Codable, Identifiable, Hashable {
    let id: String
    let exam: Exam
    let difficulty: Difficulty
    let domain: String
    let skill: String
    let stem: String
    let choices: [String]
    /// Index into `choices`.
    let correct: Int
    let explanation: String
    let figures: [String]

    /// `stem` with the underline markers removed, for previews and plain-text checks.
    var plainStem: String { Self.stripUnderlineMarkers(stem) }

    var correctLetter: String { Self.letter(correct) }

    /// The extractor wraps text that is underlined in the source PDF in these private-use scalars.
    static let underlineOn: Character = "\u{E000}"
    static let underlineOff: Character = "\u{E001}"
    static func stripUnderlineMarkers(_ s: String) -> String {
        s.filter { $0 != underlineOn && $0 != underlineOff }
    }

    static func letter(_ i: Int) -> String { String(UnicodeScalar(65 + i)!) }
}

/// Per-question progress. `wrongStreakNeeded` correct answers in a row retire a missed question.
struct QuestionProgress: Codable, Hashable {
    var seen = 0
    var correct = 0
    var wrong = 0
    /// Consecutive correct answers since the question was last missed.
    var streak = 0
    /// True once the question has been answered incorrectly at least once.
    var everWrong = false
    /// Retired from the review queue by answering it right twice in a row.
    var retired = false
    var bookmarked = false
    var lastAnswered: Date?

    var isInWrongQueue: Bool { everWrong && !retired }

    /// Days a Needs work question stays locked after each attempt, right or wrong.
    static let reviewIntervalDays = 14

    /// When a question in the review queue can next be attempted from Review: two weeks
    /// after it was last answered. Nil when it isn't in the queue.
    var reviewUnlocksAt: Date? {
        guard isInWrongQueue, let lastAnswered else { return nil }
        return Calendar.current.date(byAdding: .day, value: Self.reviewIntervalDays, to: lastAnswered)
    }

    func isReviewLocked(at now: Date = Date()) -> Bool {
        guard let unlocks = reviewUnlocksAt else { return false }
        return now < unlocks
    }
    var accuracy: Double { seen == 0 ? 0 : Double(correct) / Double(seen) }

    /// The single source of truth for the review-queue rules:
    /// a missed question joins the queue and only leaves after
    /// `masteryStreak` correct answers in a row; missing it again puts it back.
    mutating func apply(correct right: Bool, at date: Date = Date(), masteryStreak: Int = 2) {
        seen += 1
        lastAnswered = date
        if right {
            self.correct += 1
            streak += 1
            if everWrong && streak >= masteryStreak { retired = true }
        } else {
            wrong += 1
            streak = 0
            everWrong = true
            retired = false
        }
    }
}

struct AnswerEvent: Codable, Hashable, Identifiable {
    var id = UUID()
    let questionID: String
    let wasCorrect: Bool
    let date: Date
    /// Missing from history recorded before PSAT questions existed, which was all SAT.
    private let examRaw: Exam?
    var exam: Exam { examRaw ?? .sat }
    let difficulty: Difficulty
    let domain: String
    let skill: String

    init(questionID: String, wasCorrect: Bool, date: Date, exam: Exam,
         difficulty: Difficulty, domain: String, skill: String) {
        self.questionID = questionID; self.wasCorrect = wasCorrect; self.date = date
        self.examRaw = exam; self.difficulty = difficulty; self.domain = domain; self.skill = skill
    }

    private enum CodingKeys: String, CodingKey {
        case id, questionID, wasCorrect, date, examRaw = "exam", difficulty, domain, skill
    }
}

/// Everything persisted to disk.
struct SaveFile: Codable {
    var progress: [String: QuestionProgress] = [:]
    var history: [AnswerEvent] = []
}

/// A practice cycle covers the whole bank once.
enum Cycle {
    /// Complete when every question has been answered at least once and none are
    /// still in the review queue — i.e. everything missed has been cleared as well.
    static func isComplete(questionIDs: [String], progress: [String: QuestionProgress]) -> Bool {
        guard !questionIDs.isEmpty else { return false }
        return questionIDs.allSatisfy { id in
            let p = progress[id] ?? QuestionProgress()
            return p.seen > 0 && !p.isInWrongQueue
        }
    }
}
