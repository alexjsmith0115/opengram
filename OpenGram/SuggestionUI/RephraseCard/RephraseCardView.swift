import SwiftUI

/// Phase 18 rephrase card. Hosted inside a non-activating NSPanel by
/// `RephraseCardPanelController`. Visual contract: see .planning/phases/18-paragraph-rephrase-card/18-UI-SPEC.md.
/// D-02, D-04, D-05, D-13. Teal accent (Color.teal) per D-04.
struct RephraseCardView: View {
    let viewModel: RephraseCardViewModel

    /// Toggle state is per-card @State, not persisted. D-03.
    @State private var showFullDiff: Bool = false

    private static let cornerRadius: CGFloat = 10
    private static let accentBarWidth: CGFloat = 3

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .fill(Color(NSColor.windowBackgroundColor))

            // Leading teal accent bar (D-04)
            Rectangle()
                .fill(Color.teal)
                .frame(width: Self.accentBarWidth)

            VStack(alignment: .leading, spacing: 12) {
                header
                Divider()
                bodyContent
                Spacer(minLength: 0)
                actions
            }
            .padding(.leading, Self.accentBarWidth + 12)
            .padding(.trailing, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 360, idealWidth: 380, maxWidth: 520, minHeight: 180, idealHeight: 260)
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(viewModel.header)
                .font(.headline)
                .bold()
                .foregroundStyle(Color.teal)
            Spacer()
            Button(action: { showFullDiff.toggle() }) {
                Text(showFullDiff ? "Additions only" : "What changed?")
                    .underline()
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showFullDiff ? "Show additions only" : "Show full diff")
        }
    }

    // MARK: - Body

    private var bodyContent: some View {
        ScrollView {
            composedBody
                .font(.body)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Builds the Text composition from the diff segments per the current mode.
    /// D-05: additions-only hides `.removed`; full-diff shows everything with strikethrough + bold.
    /// Mint background (Color.mint.opacity(0.25)) on added tokens is applied via
    /// AttributedString.backgroundColor so the result stays a `Text` value
    /// (Text.background() returns `some View`, not Text).
    private var composedBody: Text {
        var composed = Text("")
        var first = true
        for segment in viewModel.segments {
            let piece: Text?
            switch segment {
            case .unchanged(let s):
                piece = Text(s).foregroundStyle(.primary)
            case .added(let s):
                piece = mintText(s, bold: showFullDiff)
            case .removed(let s):
                if showFullDiff {
                    piece = Text(s).strikethrough().foregroundStyle(.secondary)
                } else {
                    piece = nil
                }
            }
            guard let piece else { continue }
            if first {
                composed = piece
                first = false
            } else {
                composed = composed + Text(" ") + piece
            }
        }
        return composed
    }

    /// Returns a `Text` with mint background via `AttributedString.backgroundColor`.
    /// Equivalent to Color.mint.opacity(0.25) per D-05.
    private func mintText(_ string: String, bold: Bool) -> Text {
        var attr = AttributedString(string)
        attr.backgroundColor = NSColor.systemMint.withAlphaComponent(0.35)
        if bold {
            attr.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        }
        return Text(attr)
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 12) {
            Spacer()
            Button("Dismiss") {
                viewModel.onDismiss()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Button("Accept") {
                viewModel.onAccept()
            }
            .buttonStyle(.bordered)
            .tint(Color.teal)
            .keyboardShortcut(.defaultAction)
        }
    }
}
