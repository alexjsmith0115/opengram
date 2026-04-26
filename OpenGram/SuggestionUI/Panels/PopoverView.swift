import SwiftUI
import AppKit

enum SuggestionPopoverCardChrome {
    static let cornerRadius: CGFloat = 12
    static let shadowColor = Color.black.opacity(0.2)
    static let shadowRadius: CGFloat = 8
    static let shadowX: CGFloat = 0
    static let shadowY: CGFloat = 4
}

extension View {
    func suggestionPopoverCardChrome() -> some View {
        background(
            RoundedRectangle(cornerRadius: SuggestionPopoverCardChrome.cornerRadius)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(
                    color: SuggestionPopoverCardChrome.shadowColor,
                    radius: SuggestionPopoverCardChrome.shadowRadius,
                    x: SuggestionPopoverCardChrome.shadowX,
                    y: SuggestionPopoverCardChrome.shadowY
                )
        )
    }
}

/// Drives scale+fade animation lifecycle. Owned by OverlayController so it can
/// trigger the dismiss animation before calling orderOut(nil).
@MainActor
final class PopoverAnimationState: ObservableObject {
    @Published var isVisible = false
}

/// Grammarly-style floating card for grammar/spelling suggestions.
/// Inline diff, click-to-accept primary replacement, expandable alternatives,
/// and scale+fade animation driven by PopoverAnimationState (D-06 through D-10, D-17).
@MainActor
struct PopoverView: View {
    let suggestion: Suggestion
    let onAccept: @MainActor () -> Void
    let onAcceptAlternative: @MainActor @Sendable (String) -> Void
    let onDismiss: @MainActor () -> Void
    let onAddToDictionary: (@MainActor () -> Void)?

    @ObservedObject var animationState: PopoverAnimationState

    @State private var isHoveringPrimary = false
    @State private var isAlternativesExpanded = false

    init(
        suggestion: Suggestion,
        onAccept: @escaping @MainActor () -> Void,
        onAcceptAlternative: @escaping @MainActor @Sendable (String) -> Void,
        onDismiss: @escaping @MainActor () -> Void,
        onAddToDictionary: (@MainActor () -> Void)?,
        animationState: PopoverAnimationState = PopoverAnimationState()
    ) {
        self.suggestion = suggestion
        self.onAccept = onAccept
        self.onAcceptAlternative = onAcceptAlternative
        self.onDismiss = onDismiss
        self.onAddToDictionary = onAddToDictionary
        self.animationState = animationState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            inlineDiffRow
            primaryReplacementButton
            if suggestion.allReplacements.count > 1 {
                alternativesDisclosure
            }
            explanationText
            footerRow
        }
        .padding(16)
        .suggestionPopoverCardChrome()
        .frame(minWidth: 280, maxWidth: 360)
        .scaleEffect(animationState.isVisible ? 1.0 : 0.95)
        .opacity(animationState.isVisible ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.15)) {
                animationState.isVisible = true
            }
        }
    }

    // MARK: - Subviews

    /// Inline diff: original with red strikethrough → green replacement (D-07)
    private var inlineDiffRow: some View {
        HStack(spacing: 6) {
            Text(suggestion.original)
                .strikethrough(true, color: .red)
                .foregroundColor(.secondary)
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundColor(.secondary)
            if let primary = suggestion.primaryReplacement {
                Text(primary)
                    .foregroundColor(.green)
            }
        }
        .font(.system(size: 13))
    }

    /// Click-to-accept primary replacement (D-08). Hover highlight + pointing hand cursor.
    @ViewBuilder
    private var primaryReplacementButton: some View {
        if let primary = suggestion.primaryReplacement {
            Button(action: onAccept) {
                Text(primary)
                    .font(.system(size: 15, weight: .semibold))
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
            .onHover { hovering in
                isHoveringPrimary = hovering
                if hovering { NSCursor.pointingHand.push() }
                else { NSCursor.pop() }
            }
        }
    }

    /// Expandable alternatives (D-09). Only rendered when allReplacements has > 1 item.
    private var alternativesDisclosure: some View {
        DisclosureGroup(
            isExpanded: $isAlternativesExpanded,
            content: {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(suggestion.allReplacements.dropFirst(), id: \.self) { alt in
                        Button(action: { onAcceptAlternative(alt) }) {
                            Text(alt)
                                .font(.system(size: 12))
                                .foregroundColor(Color(nsColor: .labelColor))
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering { NSCursor.pointingHand.push() }
                            else { NSCursor.pop() }
                        }
                    }
                }
            },
            label: {
                Text("\(suggestion.allReplacements.count - 1) more suggestions")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        )
    }

    private var explanationText: some View {
        Text(suggestion.message)
            .font(.system(size: 13))
            .foregroundColor(Color(nsColor: .labelColor))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Source badge + Dismiss + Add to Dictionary (D-10).
    /// Badge label is category-aware: clarity suggestions show "Clarity" with
    /// the magnifying-glass icon; everything else falls back to source-based label
    /// ("Harper" for Harper rules, "AI" for LLM-sourced tone/rephrase).
    private var footerRow: some View {
        HStack {
            HStack(spacing: 4) {
                Image(systemName: badgeIcon)
                Text(badgeLabel)
            }
            .font(.system(size: 11))
            .foregroundColor(.secondary)

            Spacer()

            Button("Dismiss", action: onDismiss)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .buttonStyle(.plain)

            if let addToDictionary = onAddToDictionary {
                Button("Add to Dictionary", action: addToDictionary)
                    .font(.system(size: 12))
                    .foregroundColor(Color(nsColor: .labelColor))
                    .buttonStyle(.plain)
            }
        }
    }

    var badgeLabel: String {
        if suggestion.category == .clarity { return "Clarity" }
        return suggestion.source == .harper ? "Harper" : "AI"
    }

    var badgeIcon: String {
        if suggestion.category == .clarity { return "text.magnifyingglass" }
        return suggestion.source == .harper ? "checkmark.circle" : "sparkles"
    }
}
