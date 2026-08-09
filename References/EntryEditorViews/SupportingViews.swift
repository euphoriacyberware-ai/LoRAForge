import SwiftUI

// MARK: - Flow layout

/// Lays subviews out left-to-right, wrapping to a new line when the proposed
/// width runs out. Used for both the caption tokens and the tag palette.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let projected = current.indices.isEmpty
                ? size.width
                : current.width + spacing + size.width

            if projected > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = projected
                current.height = max(current.height, size.height)
            }
        }

        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(maxWidth: maxWidth, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height }
            + CGFloat(max(0, rows.count - 1)) * spacing
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY

        for row in rows(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }
}

// MARK: - Tag chip

struct TagChip: View {
    let title: String
    var isSelected = false
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.callout)
                .lineLimit(1)

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(title)")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(isSelected ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.14))
        )
        .overlay(
            Capsule().strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1)
        )
        .foregroundStyle(isSelected ? Color.accentColor : .primary)
    }
}

// MARK: - Token field

/// Tag-based editing surface for the caption. Typing and pressing Return
/// commits a token; duplicates are ignored.
struct TokenField: View {
    @Binding var tokens: [String]
    var placeholder = "Add tag"

    @State private var draft = ""

    var body: some View {
        ScrollView {
            FlowLayout(spacing: 6) {
                ForEach(tokens, id: \.self) { token in
                    TagChip(title: token) { remove(token) }
                }

                TextField(placeholder, text: $draft)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 90)
                    .onSubmit(commit)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func commit() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        guard !value.isEmpty, !tokens.contains(value) else { return }
        tokens.append(value)
    }

    private func remove(_ token: String) {
        tokens.removeAll { $0 == token }
    }
}

// MARK: - Image slot

struct ImageSlotView: View {
    let slot: ImageSlot
    var isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.secondary.opacity(0.12))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = slot.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                                  lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(Rectangle())
    }
}

// MARK: - Shared styling

struct FieldContainer: ViewModifier {
    var isEnabled = true

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isEnabled ? Color.secondary.opacity(0.07) : Color.secondary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
            )
    }
}

extension View {
    func fieldContainer(isEnabled: Bool = true) -> some View {
        modifier(FieldContainer(isEnabled: isEnabled))
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
