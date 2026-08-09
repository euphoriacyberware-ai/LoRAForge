import SwiftUI

// SwiftUI's built-in `TextEditor` gives you no control over spell checking,
// grammar checking, or the smart-substitution behaviours that mangle prompts
// (curly quotes, em-dash substitution). This wraps the platform text view so
// each of those is an explicit parameter.

#if os(macOS)

struct SpellCheckingTextEditor: NSViewRepresentable {
    @Binding var text: String
    var isSpellCheckingEnabled = true
    var isEditable = true
    var font: NSFont = .preferredFont(forTextStyle: .body)

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.string = text
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.textContainer?.widthTracksTextView = true

        // Substitutions that quietly corrupt prompt syntax.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        apply(to: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        if textView.string != text {
            let ranges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = ranges
        }
        apply(to: textView)
    }

    private func apply(to textView: NSTextView) {
        textView.font = font
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.isContinuousSpellCheckingEnabled = isSpellCheckingEnabled
        textView.isGrammarCheckingEnabled = isSpellCheckingEnabled
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textColor = isEditable ? .labelColor : .secondaryLabelColor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

#else

struct SpellCheckingTextEditor: UIViewRepresentable {
    @Binding var text: String
    var isSpellCheckingEnabled = true
    var isEditable = true
    var font: UIFont = .preferredFont(forTextStyle: .body)

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.text = text
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        apply(to: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            let range = textView.selectedRange
            textView.text = text
            textView.selectedRange = range
        }
        apply(to: textView)
    }

    private func apply(to textView: UITextView) {
        textView.font = font
        textView.isEditable = isEditable
        textView.spellCheckingType = isSpellCheckingEnabled ? .yes : .no
        textView.autocorrectionType = isSpellCheckingEnabled ? .default : .no
        textView.textColor = isEditable ? .label : .secondaryLabel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }
    }
}

#endif

// MARK: - Monospaced convenience

extension SpellCheckingTextEditor {
    static func monospacedFont(size: CGFloat = 12) -> PlatformFont {
        PlatformFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

#if os(macOS)
typealias PlatformFont = NSFont
#else
typealias PlatformFont = UIFont
#endif
