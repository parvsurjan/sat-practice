import SwiftUI

struct DifficultyBadge: View {
    let difficulty: Difficulty
    var color: Color {
        switch difficulty {
        case .easy: BB.easy
        case .medium: BB.medium
        case .hard: BB.hard
        }
    }
    var body: some View {
        Text(difficulty.rawValue.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.4)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 1))
            .foregroundStyle(color)
    }
}

struct TagBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(BB.surfaceAlt, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(BB.ruleSoft))
            .foregroundStyle(BB.inkSoft)
    }
}

/// A chart or table lifted from the source PDF. Always on white, like the real test.
struct FigureView: View {
    let name: String
    @State private var zoomed = false

    private var image: Image? {
        let base = (name as NSString).deletingPathExtension
        let url = Bundle.main.url(forResource: base, withExtension: "png")
            ?? Bundle.main.url(forResource: base, withExtension: "png", subdirectory: "figures")
            ?? Bundle.main.url(forResource: base, withExtension: "png", subdirectory: "Resources/figures")
        guard let url, let ui = UIImage(contentsOfFile: url.path) else { return nil }
        return Image(uiImage: ui)
    }

    var body: some View {
        if let image {
            image.resizable().scaledToFit()
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(BB.surface)
                .clipShape(RoundedRectangle(cornerRadius: BB.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: BB.cardRadius).stroke(BB.rule))
                .contentShape(Rectangle())
                .onTapGesture { zoomed = true }
                .accessibilityLabel("Figure. Double tap to enlarge.")
                .sheet(isPresented: $zoomed) {
                    NavigationStack {
                        ScrollView([.horizontal, .vertical]) {
                            image.resizable().scaledToFit()
                                .frame(minWidth: 340)
                                .padding()
                        }
                        .background(BB.surface)
                        .navigationTitle("Figure")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { zoomed = false }.tint(BB.blue)
                            }
                        }
                    }
                    .preferredColorScheme(.light)
                }
        } else {
            EmptyView()
        }
    }
}

/// Passage paragraphs, then the question prompt itself in bold.
struct StemView: View {
    let stem: String

    private var parts: (passage: [String], prompt: String?) {
        var paras = stem.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard let last = paras.last, last.hasSuffix("?") || last.hasSuffix(":") else {
            return (paras, nil)
        }
        paras.removeLast()
        return (paras, last)
    }

    var body: some View {
        let p = parts
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(p.passage.enumerated()), id: \.offset) { _, para in
                Text(para)
                    .font(.system(size: 17))
                    .foregroundStyle(BB.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let prompt = p.prompt {
                Text(prompt)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(BB.ink)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A Bluebook-style answer choice: outlined card, circled letter, optional cross-out.
struct ChoiceRow: View {
    let letter: String
    let text: String
    let state: ChoiceState
    let crossOutEnabled: Bool
    let isCrossedOut: Bool
    let onSelect: () -> Void
    let onCrossOut: () -> Void

    enum ChoiceState { case idle, selected, correct, wrong }

    private var accent: Color {
        switch state {
        case .idle: BB.rule
        case .selected: BB.blue
        case .correct: BB.green
        case .wrong: BB.red
        }
    }
    private var fill: Color {
        switch state {
        case .idle: BB.surface
        case .selected: BB.blueWash
        case .correct: BB.greenWash
        case .wrong: BB.redWash
        }
    }
    private var letterFilled: Bool { state != .idle }
    private var borderWidth: CGFloat { state == .idle ? 1 : 2 }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onSelect) {
                HStack(alignment: .top, spacing: 12) {
                    Text(letter)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(letterFilled ? .white : BB.ink)
                        .frame(width: 26, height: 26)
                        .background(letterFilled ? accent : Color.clear, in: Circle())
                        .overlay(Circle().stroke(letterFilled ? accent : BB.ink.opacity(0.55),
                                                 lineWidth: 1.5))
                    Text(text)
                        .font(.system(size: 16))
                        .foregroundStyle(isCrossedOut ? BB.inkSoft.opacity(0.65) : BB.ink)
                        .strikethrough(isCrossedOut, color: BB.inkSoft)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if state == .correct {
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .bold))
                            .foregroundStyle(BB.green)
                    } else if state == .wrong {
                        Image(systemName: "xmark").font(.system(size: 15, weight: .bold))
                            .foregroundStyle(BB.red)
                    }
                }
                .padding(.vertical, 13).padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if crossOutEnabled {
                Button(action: onCrossOut) {
                    Text(isCrossedOut ? "Undo" : "ABC")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(BB.inkSoft)
                        .strikethrough(!isCrossedOut, color: BB.inkSoft)
                        .frame(width: 46)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCrossedOut ? "Restore choice \(letter)" : "Cross out choice \(letter)")
            }
        }
        .background(fill, in: RoundedRectangle(cornerRadius: BB.choiceRadius))
        .overlay(RoundedRectangle(cornerRadius: BB.choiceRadius)
            .stroke(accent, lineWidth: borderWidth))
    }
}

/// Renders a question, its choices, and — once answered — the result and rationale.
struct QuestionCard: View {
    let question: Question
    @Binding var chosen: Int?
    let isBookmarked: Bool
    let onBookmark: () -> Void
    let onSubmit: (Int) -> Void

    @State private var crossOutEnabled = false
    @State private var crossedOut: Set<Int> = []

    private var answered: Bool { chosen != nil }

    private func state(for i: Int) -> ChoiceRow.ChoiceState {
        guard let chosen else { return .idle }
        if i == question.correct { return .correct }
        if i == chosen { return .wrong }
        return .idle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Toolbar: metadata on the left, Bluebook's two tools on the right.
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    DifficultyBadge(difficulty: question.difficulty)
                    TagBadge(text: question.skill)
                    Spacer(minLength: 4)
                }
                HStack(spacing: 14) {
                    Button(action: onBookmark) {
                        Label {
                            Text("Mark for Review").font(.system(size: 13, weight: .semibold))
                        } icon: {
                            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                        }
                        .foregroundStyle(isBookmarked ? BB.blue : BB.inkSoft)
                    }
                    .buttonStyle(.plain)

                    Button { withAnimation(.easeInOut(duration: 0.15)) { crossOutEnabled.toggle() } } label: {
                        Text("ABC")
                            .font(.system(size: 13, weight: .bold))
                            .strikethrough(color: crossOutEnabled ? BB.blue : BB.inkSoft)
                            .foregroundStyle(crossOutEnabled ? BB.blue : BB.inkSoft)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .overlay(RoundedRectangle(cornerRadius: 4)
                                .stroke(crossOutEnabled ? BB.blue : BB.ruleSoft))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(crossOutEnabled ? "Turn off cross-out tool" : "Turn on cross-out tool")
                    Spacer()
                }
                Text(question.domain)
                    .font(.system(size: 12))
                    .foregroundStyle(BB.inkSoft)
            }

            Divider().overlay(BB.ruleSoft)

            ForEach(question.figures, id: \.self) { FigureView(name: $0) }

            StemView(stem: question.stem)

            VStack(spacing: 10) {
                ForEach(question.choices.indices, id: \.self) { i in
                    ChoiceRow(letter: Question.letter(i),
                              text: question.choices[i],
                              state: state(for: i),
                              crossOutEnabled: crossOutEnabled && !answered,
                              isCrossedOut: crossedOut.contains(i),
                              onSelect: {
                                  guard !answered else { return }
                                  chosen = i
                                  onSubmit(i)
                              },
                              onCrossOut: {
                                  if crossedOut.contains(i) { crossedOut.remove(i) }
                                  else { crossedOut.insert(i) }
                              })
                }
            }

            if let chosen {
                ResultPanel(question: question, chosen: chosen)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: chosen)
        .onChange(of: question.id) {
            crossedOut = []
            crossOutEnabled = false
        }
    }
}

struct ResultPanel: View {
    let question: Question
    let chosen: Int
    private var right: Bool { chosen == question.correct }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: right ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(right ? BB.green : BB.red)
                Text(right ? "Correct" : "Incorrect")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(right ? BB.green : BB.red)
                Spacer()
                Text("Correct answer: \(question.correctLetter)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BB.inkSoft)
            }
            Divider().overlay(BB.ruleSoft)
            Text("Rationale")
                .font(.system(size: 13, weight: .bold))
                .tracking(0.3)
                .foregroundStyle(BB.inkSoft)
            Text(question.explanation)
                .font(.system(size: 15))
                .foregroundStyle(BB.ink)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(right ? BB.greenWash : BB.redWash,
                    in: RoundedRectangle(cornerRadius: BB.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: BB.cardRadius)
            .stroke((right ? BB.green : BB.red).opacity(0.35)))
    }
}
