import SwiftUI

/// Floating card displaying up to three LLM style suggestions.
/// Each row shows a category dot, inline diff, explanation, and an Apply button.
@MainActor
struct LLMSuggestionPanel: View {
    let suggestions: [LLMStyleSuggestion]
    let onApply: @MainActor (LLMStyleSuggestion) -> Void
    let onDismiss: @MainActor () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
                    SuggestionRow(suggestion: suggestion, onApply: { onApply(suggestion) })

                    if index < suggestions.count - 1 {
                        Divider()
                            .padding(.horizontal, 16)
                    }
                }

                Divider()

                HStack {
                    Spacer()
                    Button("Dismiss", action: onDismiss)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .frame(minWidth: 300, maxWidth: 420)
    }
}

// MARK: - Suggestion Row

@MainActor
private struct SuggestionRow: View {
    let suggestion: LLMStyleSuggestion
    let onApply: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(suggestion.category.dotColor)
                    .frame(width: 8, height: 8)
                Text(suggestion.category.label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(suggestion.category.dotColor)
            }

            InlineDiffView(original: suggestion.originalText, revised: suggestion.revisedText)

            Text(suggestion.explanation)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Apply", action: onApply)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(suggestion.category.dotColor)
                    )
                    .buttonStyle(.plain)
            }
        }
        .padding(16)
    }
}

// MARK: - Category Presentation

private extension LLMStyleSuggestion.Category {
    var dotColor: Color {
        switch self {
        case .tone:     return .purple
        case .clarity:  return .blue
        case .rephrase: return .green
        }
    }

    var label: String {
        switch self {
        case .tone:     return "Tone"
        case .clarity:  return "Clarity"
        case .rephrase: return "Rephrase"
        }
    }
}
