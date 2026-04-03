import SwiftUI

/// UI for answering AskUserQuestion prompts from Claude Code.
/// Shows each question with selectable option buttons.
struct UserQuestionView: View {
    let question: UserQuestion
    let appState: AppState
    @State private var selections: [String: String] = [:]  // questionText -> selected label

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Text("?")
                    .font(RetroTheme.pixelFont(size: 12, weight: .bold))
                    .foregroundStyle(RetroTheme.cyan)
                    .pixelGlow(RetroTheme.cyan, radius: 4)

                Text("QUESTION")
                    .font(RetroTheme.pixelFont(size: 11, weight: .bold))
                    .foregroundStyle(RetroTheme.textPrimary)

                Spacer()

                Text(question.projectName.uppercased())
                    .font(RetroTheme.pixelFont(size: 8))
                    .foregroundStyle(RetroTheme.cyan.opacity(0.7))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(RetroTheme.cyan.opacity(0.1))
                    )
                    .pixelBorder(color: RetroTheme.cyan.opacity(0.3), cornerRadius: 2)
            }

            // Questions
            ForEach(Array(question.questions.enumerated()), id: \.offset) { idx, q in
                questionSection(q, index: idx)
            }

            // Submit button
            HStack {
                Spacer()
                Button {
                    withAnimation {
                        appState.resolveQuestion(question, answers: selections)
                    }
                } label: {
                    Text("SUBMIT")
                        .font(RetroTheme.pixelFont(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(allQuestionsAnswered ? RetroTheme.cyan.opacity(0.8) : RetroTheme.textMuted.opacity(0.3))
                        )
                        .pixelBorder(color: allQuestionsAnswered ? RetroTheme.cyan : RetroTheme.border, cornerRadius: 4)
                }
                .buttonStyle(.plain)
                .disabled(!allQuestionsAnswered)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(RetroTheme.cyan.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(RetroTheme.cyan.opacity(0.25), lineWidth: 1)
        )
    }

    private var allQuestionsAnswered: Bool {
        question.questions.allSatisfy { selections[$0.question] != nil }
    }

    @ViewBuilder
    private func questionSection(_ q: UserQuestion.ParsedQuestion, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Question header chip + text
            HStack(spacing: 4) {
                Text(q.header.uppercased())
                    .font(RetroTheme.pixelFont(size: 8, weight: .bold))
                    .foregroundStyle(RetroTheme.cyan)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(RetroTheme.cyan.opacity(0.15))
                    )

                Text(q.question)
                    .font(RetroTheme.pixelFont(size: 10))
                    .foregroundStyle(RetroTheme.textPrimary)
                    .lineLimit(2)
            }

            // Options
            ForEach(Array(q.options.enumerated()), id: \.offset) { optIdx, opt in
                let isSelected = selections[q.question] == opt.label
                Button {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        selections[q.question] = opt.label
                    }
                } label: {
                    HStack(spacing: 6) {
                        // Radio indicator
                        ZStack {
                            Circle()
                                .strokeBorder(isSelected ? RetroTheme.cyan : RetroTheme.textMuted, lineWidth: 1)
                                .frame(width: 10, height: 10)
                            if isSelected {
                                Circle()
                                    .fill(RetroTheme.cyan)
                                    .frame(width: 5, height: 5)
                            }
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(opt.label.uppercased())
                                .font(RetroTheme.pixelFont(size: 9, weight: .bold))
                                .foregroundStyle(isSelected ? RetroTheme.cyan : RetroTheme.textPrimary)
                            Text(opt.description)
                                .font(RetroTheme.pixelFont(size: 8))
                                .foregroundStyle(RetroTheme.textMuted)
                                .lineLimit(2)
                        }

                        Spacer()

                        // Keyboard shortcut hint
                        Text("⌘\(optIdx + 1)")
                            .font(RetroTheme.pixelFont(size: 8))
                            .foregroundStyle(RetroTheme.textMuted.opacity(0.5))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isSelected ? RetroTheme.cyan.opacity(0.1) : RetroTheme.cardBg.opacity(0.5))
                    )
                    .pixelBorder(
                        color: isSelected ? RetroTheme.cyan.opacity(0.4) : RetroTheme.border.opacity(0.2),
                        cornerRadius: 4
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
