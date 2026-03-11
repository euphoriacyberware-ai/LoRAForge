import AppKit

class SaveCompletionHelper: NSObject {
    private let completion: () -> Void

    init(completion: @escaping () -> Void) {
        self.completion = completion
    }

    @objc func document(_ document: NSDocument, didSave: Bool, contextInfo: UnsafeMutableRawPointer?) {
        if didSave {
            completion()
        }
        // Release the strong reference
        objc_setAssociatedObject(document, "saveHelper", nil, .OBJC_ASSOCIATION_RETAIN)
    }
}
