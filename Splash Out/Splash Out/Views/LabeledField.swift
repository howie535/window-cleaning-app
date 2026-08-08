import SwiftUI

/// Wraps a field with a persistent caption label above it, so the field stays
/// identifiable once it has content (a placeholder alone disappears on input).
struct LabeledField<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
        }
    }
}
