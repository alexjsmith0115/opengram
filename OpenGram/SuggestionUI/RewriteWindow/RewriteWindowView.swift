import SwiftUI
import AppKit

struct RewriteWindowView: View {
    @Bindable var viewModel: RewriteWindowViewModel
    var onApply: () -> Void
    var onCancel: () -> Void
    var onOpenSettings: () -> Void
    var onOriginalMounted: (NSTextView) -> Void
    var onRevisedMounted:  (NSTextView) -> Void

    /// Last tone the user picked. Persisted across sessions; pre-selected
    /// visually on next open but does NOT auto-fire the LLM.
    @AppStorage("lastRewriteTone") private var lastRewriteToneRaw: String = RewriteTone.friendly.rawValue

    private var visuallySelectedTone: RewriteTone? {
        if let tone = viewModel.selectedTone { return tone }
        return RewriteTone(rawValue: lastRewriteToneRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Original")
            RewriteTextView(
                text: Binding(
                    get: { viewModel.original },
                    set: { viewModel.updateOriginal($0) }
                ),
                onTextViewMounted: onOriginalMounted
            )
            .frame(minHeight: 70, maxHeight: 140)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.10)))

            transformDivider

            sectionLabel("Revised")
            RewriteTextView(
                text: Binding(
                    get: { viewModel.revised },
                    set: { viewModel.revised = $0 }
                ),
                onTextViewMounted: onRevisedMounted
            )
            .frame(minHeight: 70, maxHeight: 140)
            .background(Color.accentColor.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.10)))
            .overlay(loadingOverlay)

            errorBanner

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(action: onApply) {
                    HStack(spacing: 4) {
                        Text("Replace")
                        Text("⌘↵").font(.caption2).opacity(0.7)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canApply)
            }
        }
        .padding(14)
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.leading, 2)
    }

    private var transformDivider: some View {
        VStack(spacing: 6) {
            HStack {
                Rectangle().fill(.black.opacity(0.08)).frame(height: 1)
                Text("Make it ↓")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Rectangle().fill(.black.opacity(0.08)).frame(height: 1)
            }
            HStack(spacing: 6) {
                ForEach(RewriteTone.allCases, id: \.self) { tone in
                    Button {
                        viewModel.selectTone(tone)
                        lastRewriteToneRaw = tone.rawValue
                    } label: {
                        Text(tone.displayName)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 10)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(visuallySelectedTone == tone ? .accentColor : .secondary)
                    .disabled(isLoading)
                }
            }
        }
    }

    private var loadingOverlay: some View {
        Group {
            if isLoading {
                ProgressView().controlSize(.small).padding(8)
            }
        }
    }

    private var isLoading: Bool {
        if case .loading = viewModel.status { return true }
        return false
    }

    @ViewBuilder
    private var errorBanner: some View {
        if case .error(let err, let attemptedTone) = viewModel.status {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(err.localizedDescription).font(.caption)
                Spacer()
                if attemptedTone != nil {
                    Button("Retry") { viewModel.retry() }.controlSize(.small)
                }
            }
            .padding(8)
            .background(Color.orange.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
