import SwiftUI

/// Pick which customer a new customer goes after in round order (or the end of the round).
struct PlaceInRoundView: View {
    let customers: [Customer]
    @Binding var placeAfter: Customer?

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var matches: [Customer] {
        let ordered = customers.sorted { $0.sequence < $1.sequence }
        let term = search.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return ordered }
        return ordered.filter {
            $0.name.localizedCaseInsensitiveContains(term) || $0.address.localizedCaseInsensitiveContains(term)
                || $0.area.localizedCaseInsensitiveContains(term)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    placeAfter = nil
                    dismiss()
                } label: {
                    HStack {
                        Text("At the end of the round").foregroundStyle(.primary)
                        Spacer()
                        if placeAfter == nil { Image(systemName: "checkmark") }
                    }
                }

                Section("After...") {
                    ForEach(matches) { customer in
                        Button {
                            placeAfter = customer
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(customer.name).foregroundStyle(.primary)
                                    Text([customer.round, customer.area].filter { !$0.isEmpty }.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if placeAfter === customer { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Name, address or area")
            .navigationTitle("Place in round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
