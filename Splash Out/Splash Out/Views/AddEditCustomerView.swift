import SwiftUI
import SwiftData

struct AddEditCustomerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let customer: Customer?

    @State private var name: String = ""
    @State private var address: String = ""
    @State private var phone: String = ""
    @State private var priceText: String = ""
    @State private var frequencyWeeks: Int = 4
    @State private var accessNotes: String = ""

    private var isEditing: Bool { customer != nil }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && Decimal(string: priceText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    TextField("Name", text: $name)
                    TextField("Address", text: $address, axis: .vertical)
                    TextField("Phone (with country code, e.g. 447700900123)", text: $phone)
                        .keyboardType(.phonePad)
                }
                Section("Cleaning") {
                    TextField("Price per clean", text: $priceText)
                        .keyboardType(.decimalPad)
                    Stepper("Every \(frequencyWeeks) week\(frequencyWeeks == 1 ? "" : "s")", value: $frequencyWeeks, in: 1...52)
                }
                Section("Access Notes") {
                    TextField("Gate code, key location, pets, parking, etc.", text: $accessNotes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(isEditing ? "Edit Customer" : "New Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid)
                }
            }
            .onAppear(perform: populateFieldsIfEditing)
        }
    }

    private func populateFieldsIfEditing() {
        guard let customer else { return }
        name = customer.name
        address = customer.address
        phone = customer.phone
        priceText = NSDecimalNumber(decimal: customer.price).stringValue
        frequencyWeeks = customer.frequencyWeeks
        accessNotes = customer.accessNotes
    }

    private func save() {
        let price = Decimal(string: priceText) ?? 0

        if let customer {
            customer.name = name
            customer.address = address
            customer.phone = phone
            customer.price = price
            customer.frequencyWeeks = frequencyWeeks
            customer.accessNotes = accessNotes
        } else {
            let newCustomer = Customer(
                name: name,
                address: address,
                phone: phone,
                price: price,
                frequencyWeeks: frequencyWeeks,
                accessNotes: accessNotes
            )
            modelContext.insert(newCustomer)
        }

        dismiss()
    }
}

#Preview {
    AddEditCustomerView(customer: nil)
        .modelContainer(for: Customer.self, inMemory: true)
}
