import SwiftUI
import SwiftData
import CoreLocation

struct AddEditCustomerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let customer: Customer?

    @State private var name: String = ""
    @State private var address: String = ""
    @State private var phone: String = ""
    @State private var priceText: String = ""
    @State private var round: String = ""
    @State private var area: String = ""
    @State private var notesText: String = ""
    @State private var isShowingContactPicker = false

    private var isEditing: Bool { customer != nil }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && Decimal(string: priceText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        isShowingContactPicker = true
                    } label: {
                        Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus")
                    }
                }
                Section("Customer") {
                    LabeledField(label: "Name") {
                        TextField("", text: $name)
                    }
                    LabeledField(label: "Address") {
                        TextField("", text: $address, axis: .vertical)
                    }
                    LabeledField(label: "Phone") {
                        TextField("07700 900123", text: $phone)
                            .keyboardType(.phonePad)
                    }
                    LabeledField(label: "Round") {
                        TextField("e.g. Rhyl", text: $round)
                    }
                    LabeledField(label: "Area") {
                        TextField("e.g. Kinmel Bay", text: $area)
                    }
                }
                Section("Cleaning") {
                    LabeledField(label: "Price per Clean") {
                        TextField("0.00", text: $priceText)
                            .keyboardType(.decimalPad)
                    }
                }
                Section("Notes") {
                    TextField("Gate code, key location, pets, parking, etc. One note per line.", text: $notesText, axis: .vertical)
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
            .sheet(isPresented: $isShowingContactPicker) {
                ContactPicker { contact in
                    name = contact.splashOutFullName
                    let digits = contact.splashOutPhoneDigits
                    if !digits.isEmpty { phone = digits }
                    let formattedAddress = contact.splashOutFormattedAddress
                    if !formattedAddress.isEmpty { address = formattedAddress }
                }
            }
        }
    }

    private func populateFieldsIfEditing() {
        guard let customer else { return }
        name = customer.name
        address = customer.address
        phone = customer.phone
        priceText = NSDecimalNumber(decimal: customer.price).stringValue
        round = customer.round
        area = customer.area
        notesText = customer.notesText
    }

    private func save() {
        let price = Decimal(string: priceText) ?? 0
        let addressChanged = address != customer?.address
        let target: Customer

        if let customer {
            if price != customer.price {
                modelContext.insert(PriceChange(date: .now, oldPrice: customer.price, newPrice: price, reason: .correction, customer: customer))
                customer.priceSince = .now
            }
            customer.name = name
            customer.address = address
            customer.phone = phone
            customer.price = price
            customer.round = round
            customer.area = area
            customer.notesText = notesText
            target = customer
        } else {
            let newCustomer = Customer(
                name: name,
                address: address,
                phone: phone,
                price: price,
                sequence: nextSequence(),
                round: round,
                area: area
            )
            newCustomer.notesText = notesText
            modelContext.insert(newCustomer)
            target = newCustomer
        }

        if addressChanged {
            Task {
                let coordinate = await Geocoding.coordinate(for: target.address)
                target.latitude = coordinate?.latitude
                target.longitude = coordinate?.longitude
            }
        }

        dismiss()
    }

    /// New customers go at the end of the round until placed elsewhere.
    private func nextSequence() -> Int {
        var descriptor = FetchDescriptor<Customer>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        descriptor.fetchLimit = 1
        return ((try? modelContext.fetch(descriptor))?.first?.sequence ?? 0) + 1
    }
}

#Preview {
    AddEditCustomerView(customer: nil)
        .modelContainer(for: Customer.self, inMemory: true)
}
