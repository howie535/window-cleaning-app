import SwiftUI
import SwiftData
import CoreLocation

struct AddEditCustomerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let customer: Customer?

    @Query(sort: \Customer.sequence) private var allCustomers: [Customer]

    @State private var name: String = ""
    @State private var address: String = ""
    @State private var phone: String = ""
    @State private var priceText: String = ""
    @State private var round: String = ""
    @State private var area: String = ""
    @State private var notesText: String = ""
    @State private var status: CustomerStatus = .notStarted
    @State private var everyOther = false
    @State private var frontOnly = false
    @State private var contact: ContactMethod = .whatsapp
    @State private var payMethod: PayMethod?
    @State private var placeAfter: Customer?
    @State private var isShowingPlace = false
    @State private var isShowingContactPicker = false
    @State private var saveToContacts = true
    @State private var contactsMessage: String?

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
                    if !isEditing {
                        Toggle("Also save to Contacts", isOn: $saveToContacts)
                    }
                }
                Section("Cleaning") {
                    LabeledField(label: "Price per Clean") {
                        TextField("0.00", text: $priceText)
                            .keyboardType(.decimalPad)
                    }
                }
                Section("Round") {
                    Picker("Status", selection: $status) {
                        ForEach(CustomerStatus.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.navigationLink)
                    Toggle("Every other clean", isOn: $everyOther)
                    Toggle("Front only", isOn: $frontOnly)
                    Picker("Contact by", selection: $contact) {
                        Text("WhatsApp").tag(ContactMethod.whatsapp)
                        Text("Ring").tag(ContactMethod.ring)
                    }
                    .pickerStyle(.segmented)
                    Picker("Pays by", selection: $payMethod) {
                        Text("Not set").tag(PayMethod?.none)
                        ForEach(PayMethod.allCases) { Text($0.label).tag(PayMethod?.some($0)) }
                    }
                    .pickerStyle(.navigationLink)
                    if !isEditing {
                        Button {
                            isShowingPlace = true
                        } label: {
                            HStack {
                                Text("Place in round").foregroundStyle(.primary)
                                Spacer()
                                Text(placeAfter.map { "After \($0.name)" } ?? "At the end")
                                    .foregroundStyle(.secondary)
                            }
                        }
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
            .alert("Contacts", isPresented: Binding(get: { contactsMessage != nil }, set: { if !$0 { contactsMessage = nil; dismiss() } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(contactsMessage ?? "")
            }
            .sheet(isPresented: $isShowingPlace) {
                PlaceInRoundView(customers: allCustomers, placeAfter: $placeAfter)
            }
            .sheet(isPresented: $isShowingContactPicker) {
                ContactPicker { contact in
                    saveToContacts = false   // already in Contacts
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
        status = customer.status
        everyOther = customer.everyOther
        frontOnly = customer.frontOnly
        contact = customer.contact
        payMethod = customer.payMethod
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
            customer.status = status
            customer.everyOther = everyOther
            customer.frontOnly = frontOnly
            customer.contact = contact
            customer.payMethod = payMethod
            target = customer
        } else {
            let newCustomer = Customer(
                name: name,
                address: address,
                phone: phone,
                price: price,
                round: round,
                area: area,
                status: status
            )
            newCustomer.notesText = notesText
            newCustomer.everyOther = everyOther
            newCustomer.frontOnly = frontOnly
            newCustomer.contact = contact
            newCustomer.payMethod = payMethod
            modelContext.insert(newCustomer)
            RoundOrder.place(newCustomer, after: placeAfter, among: allCustomers)
            target = newCustomer
        }

        if addressChanged {
            Task {
                let coordinate = await Geocoding.coordinate(for: target.address)
                target.latitude = coordinate?.latitude
                target.longitude = coordinate?.longitude
            }
        }

        if customer == nil, saveToContacts {
            // The customer is already saved; Contacts is a bonus, so a problem there only gets a message.
            let (savedName, savedPhone, savedAddress) = (name, phone, address)
            Task {
                switch await ContactsSaver.save(name: savedName, phone: savedPhone, address: savedAddress) {
                case .saved, .alreadyThere:
                    dismiss()
                case .notAllowed:
                    contactsMessage = "The customer is saved, but Splash Out isn't allowed to use Contacts. You can allow it in Settings > Privacy & Security > Contacts."
                case .failed(let reason):
                    contactsMessage = "The customer is saved, but couldn't be added to Contacts: \(reason)"
                }
            }
        } else {
            dismiss()
        }
    }
}

#Preview {
    AddEditCustomerView(customer: nil)
        .modelContainer(for: Customer.self, inMemory: true)
}
