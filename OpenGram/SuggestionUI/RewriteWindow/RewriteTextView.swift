import SwiftUI
import AppKit

/// Wraps an NSTextView in a SwiftUI view, exposing the underlying text view via
/// a mount callback. Bypasses SwiftUI's TextEditor focus opacity so the
/// controller can take responder ownership deterministically.
struct RewriteTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true
    var onTextViewMounted: ((NSTextView) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let textView = scroll.documentView as? NSTextView else { return scroll }
        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.isRichText = false
        textView.isEditable = isEditable
        textView.allowsUndo = true
        textView.string = text
        textView.textContainerInset = NSSize(width: 6, height: 6)
        onTextViewMounted?(textView)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        if textView.string != text { textView.string = text }
        textView.isEditable = isEditable
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RewriteTextView
        init(_ parent: RewriteTextView) { self.parent = parent }

        func textDidChange(_ note: Notification) {
            guard let tv = note.object as? NSTextView else { return }
            parent.text = tv.string
        }

        // Tab / Shift-Tab cycle key-view loop instead of inserting a tab character.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertTab(_:)):
                textView.window?.selectNextKeyView(nil)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                textView.window?.selectPreviousKeyView(nil)
                return true
            default:
                return false
            }
        }
    }
}
