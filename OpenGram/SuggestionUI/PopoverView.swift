import SwiftUI

/// SwiftUI popover content for a grammar/spelling suggestion.
/// Displays the original text, primary replacement, explanation, source badge,
/// and action buttons. Add to Dictionary is only shown for .spelling suggestions.
@MainActor
struct PopoverView: View {
    let suggestion: Suggestion
    let onAccept: @MainActor () -> Void
    let onDismiss: @MainActor () -> Void
    let onAddToDictionary: (@MainActor () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            originalRow
            replacementHeading
            if suggestion.allReplacements.count > 1 {
                alternativesSection
            }
            explanationText
            HStack {
                sourceBadge
                Spacer()
            }
            actionButtons
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 16)
        .frame(minWidth: 280, maxWidth: 360)
    }

    // MARK: - Subviews

    private var originalRow: some View {
        HStack(alignment: .top, spacing: 4) {
            Text("Original:")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            Text(suggestion.original)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(Color(nsColor: .labelColor))
        }
    }

    private var replacementHeading: some View {
        Group {
            if let primary = suggestion.primaryReplacement {
                Text(primary)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(nsColor: .labelColor))
            }
        }
    }

    private var alternativesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Other suggestions:")
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            ForEach(suggestion.allReplacements.dropFirst(), id: \.self) { replacement in
                Text(replacement)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color(nsColor: .labelColor))
            }
        }
    }

    private var explanationText: some View {
        Text(suggestion.message)
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(Color(nsColor: .labelColor))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var sourceBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: badgeSymbol)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
            Text(badgeLabel)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
        }
    }

    private var badgeLabel: String {
        switch suggestion.source {
        case .harper: return "Harper"
        case .llm: return "AI"
        }
    }

    private var badgeSymbol: String {
        switch suggestion.source {
        case .harper: return "checkmark.circle"
        case .llm: return "sparkles"
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button("Accept", action: onAccept)
                .buttonStyle(AcceptButtonStyle())

            Button("Dismiss", action: onDismiss)
                .buttonStyle(DismissButtonStyle())

            if let addToDictionary = onAddToDictionary {
                Button("Add to Dictionary", action: addToDictionary)
                    .buttonStyle(AddToDictionaryButtonStyle())
            }
        }
    }
}

// MARK: - Button Styles

private struct AcceptButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlAccentColor).opacity(configuration.isPressed ? 0.8 : 1.0))
            .cornerRadius(6)
    }
}

private struct DismissButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(Color(nsColor: .secondaryLabelColor))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}

private struct AddToDictionaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(Color(nsColor: .labelColor))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }
}
