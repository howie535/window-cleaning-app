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

extension View {
    /// A "Done" button above the keyboard, and dragging the form puts the keyboard away.
    func keyboardDoneButton() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                    .fontWeight(.semibold)
                }
            }
    }
}

/// Choose one of the existing values from a list, or type a new one ("New...").
struct PickOrTypeField: View {
    let label: String
    @Binding var value: String
    let options: [String]
    var placeholder = ""

    @State private var typing = false
    private static let newTag = "\u{1}new"

    var body: some View {
        Group {
            if typing || options.isEmpty {
                LabeledField(label: label) {
                    HStack {
                        TextField(placeholder, text: $value)
                        if !options.isEmpty {
                            Button("Choose from list") { typing = false; if !options.contains(value) { value = "" } }
                                .font(.footnote)
                                .buttonStyle(.borderless)
                        }
                    }
                }
            } else {
                Picker(label, selection: Binding(
                    get: { options.contains(value) ? value : "" },
                    set: { picked in
                        if picked == Self.newTag { value = ""; typing = true } else { value = picked }
                    }
                )) {
                    Text("None").tag("")
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                    Text("New...").tag(Self.newTag)
                }
                .pickerStyle(.navigationLink)
            }
        }
        .onAppear { if !value.isEmpty && !options.contains(value) { typing = true } }
    }
}
