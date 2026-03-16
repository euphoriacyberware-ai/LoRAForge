import SwiftUI

struct JSONEditorView: View {
    @Binding var jsonString: String
    @State private var editText: String = ""
    @State private var validationError: String?
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.headline)
                Spacer()
                if let error = validationError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if !editText.isEmpty {
                    Label("Valid JSON", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            TextEditor(text: $editText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120, maxHeight: 300)
                .border(validationError != nil ? Color.red.opacity(0.5) : Color.secondary.opacity(0.3))
                .onChange(of: editText) {
                    validate()
                }

            HStack {
                Button("Format") {
                    formatJSON()
                }
                .disabled(validationError != nil)
                .font(.caption)

                Spacer()
            }
        }
        .onAppear {
            editText = jsonString
            validate()
        }
    }

    private func validate() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            validationError = nil
            jsonString = "{}"
            return
        }

        guard let data = trimmed.data(using: .utf8) else {
            validationError = "Invalid encoding"
            return
        }

        do {
            _ = try JSONSerialization.jsonObject(with: data)
            validationError = nil
            jsonString = trimmed
        } catch {
            validationError = error.localizedDescription
        }
    }

    private func formatJSON() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let formatted = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: formatted, encoding: .utf8) else { return }
        editText = str
    }
}

// MARK: - Preview

#if DEBUG
#Preview("JSON Editor") {
    JSONEditorView(
        jsonString: .constant("{\n  \"steps\": 20,\n  \"seed\": 0\n}"),
        label: "Configuration"
    )
    .frame(width: 400, height: 200)
    .padding()
}

#Preview("JSON Editor — Empty") {
    JSONEditorView(
        jsonString: .constant("{}"),
        label: "Override"
    )
    .frame(width: 400, height: 200)
    .padding()
}
#endif
