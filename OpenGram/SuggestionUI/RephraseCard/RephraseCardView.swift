import SwiftUI

/// Rephrase card. Hosted inside a non-activating NSPanel by
/// `RephraseCardPanelController`. Uses the same card chrome as Harper
/// suggestion popovers so AI and Harper suggestions present consistently.
struct RephraseCardView: View {
    let viewModel: RephraseCardViewModel

    @State private var isHoveringPrimary = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            primaryReplacementButton
            explanationText
            footerRow
        }
        .padding(16)
        .frame(
            minWidth: SuggestionPopoverCardChrome.minCardWidth,
            idealWidth: 320,
            maxWidth: SuggestionPopoverCardChrome.maxCardWidth
        )
        .suggestionPopoverCardChrome()
        .padding(SuggestionPopoverCardChrome.shadowPadding)
    }

    private var primaryIssue: LLMStyleSuggestion? {
        viewModel.issues.first
    }

    private var originalText: String {
        primaryIssue?.originalText ?? viewModel.paragraph.text
    }

    private var revisedText: String {
        primaryIssue?.revisedText ?? viewModel.rephrase
    }

    private var messageText: String {
        if let explanation = primaryIssue?.explanation, !explanation.isEmpty {
            return explanation
        }
        return viewModel.header
    }

    // MARK: - Subviews

    private var primaryReplacementButton: some View {
        Button(action: viewModel.onAccept) {
            Text(revisedText)
                .font(.system(size: 15, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHoveringPrimary
                            ? Color(nsColor: .controlAccentColor).opacity(0.15)
                            : Color(nsColor: .controlAccentColor).opacity(0.08))
                )
                .foregroundColor(Color(nsColor: .controlAccentColor))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .onHover { hovering in
            isHoveringPrimary = hovering
            if hovering { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
    }

    private var explanationText: some View {
        Text(messageText)
            .font(.system(size: 13))
            .foregroundColor(Color(nsColor: .labelColor))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footerRow: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text("AI")
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)

            Spacer()

            Button("Dismiss") {
                viewModel.onDismiss()
            }
            .font(.system(size: 12))
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }
}
