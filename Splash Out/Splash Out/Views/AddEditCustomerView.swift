import SwiftUI
import SwiftData
import CoreLocation

struct AddEditCustomerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let customer: Customer?
    /// A cancelled customer whose house has a new occupant: the address, round and price carry over, the person doesn't.
    var replacing: Customer?

    @Query(sort: \Customer.sequence) private var allCustomers: [Customer]

    @State private var name: String = ""
    @State private var address: String = ""
    @State private var phone: String = ""
    @State private var priceText: String = ""
    @State private var altPriceText: String = ""
    @State private var monthlyText: String = ""
    @State private var altPriceLabel: String = ""
    @State private var round: String = ""
    @State private var area: String = ""
    @State private var notesText: String = ""
    @State private var status: CustomerStatus = .notStarted
    @State private var everyOther = false
    @State private var frontOnly = false
    @State private var contact: ContactMethod = .whatsapp
    @State private var payMethod: PayMethod?
    /// nil = automatic (same street), true = always with the customer before, false = never.
    @State private var groupWithPrevious: Bool?
    @State private var placeAfter: Customer?
    /// Set once a place has been picked by hand; until then a new customer goes after the last one in their round and area.
    @State private var placeChosen = false
    @State private var isShowingPlace = false
    @State private var isShowingContactPicker = false
    @State private var saveToContacts = true
    @State private var isConfirmingOwedCancel = false
    @State private var cancelAnyway = false
    @State private var contactsMessage: String?

    private var isEditing: Bool { customer != nil }

    private var monthlyAmount: Decimal? { Decimal(string: monthlyText).flatMap { $0 > 0 ? $0 : nil } }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && (payMethod == .directDebit ? monthlyAmount != nil : Decimal(string: priceText) != nil)
            && (altPriceText.trimmingCharacters(in: .whitespaces).isEmpty || Decimal(string: altPriceText) != nil)
    }

    private var roundOptions: [String] {
        Array(Set(allCustomers.map(\.round).filter { !$0.isEmpty })).sorted()
    }

    /// Areas in the chosen round (all areas if no round is chosen).
    private var areaOptions: [String] {
        let pool = round.isEmpty ? allCustomers : allCustomers.filter { $0.round == round }
        return Array(Set(pool.map(\.area).filter { !$0.isEmpty })).sorted()
    }

    /// Where a new customer goes unless placed by hand: after the last customer in the same round and area
    /// (or the same round), otherwise at the end.
    private var suggestedPlace: Customer? {
        let others = allCustomers.filter { $0.id != replacing?.id }
        if !round.isEmpty {
            if !area.isEmpty, let last = others.last(where: { $0.round == round && $0.area == area }) { return last }
            if let last = others.last(where: { $0.round == round }) { return last }
        }
        return nil
    }

    private var effectivePlace: Customer? { placeChosen ? placeAfter : (replacing ?? suggestedPlace) }

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
                    PickOrTypeField(label: "Round", value: $round, options: roundOptions, placeholder: "e.g. Rhyl")
                    PickOrTypeField(label: "Area", value: $area, options: areaOptions, placeholder: "e.g. Kinmel Bay")
                    if !isEditing {
                        Toggle("Also save to Contacts", isOn: $saveToContacts)
                    }
                }
                Section {
                    if payMethod == .directDebit {
                        LabeledField(label: "Monthly Direct Debit (£)") {
                            TextField("0.00", text: $monthlyText)
                                .keyboardType(.decimalPad)
                        }
                        LabeledContent("Price per clean", value: monthlyAmount.map { DirectDebit.perClean(monthly: $0).formatted(.currency(code: "GBP")) } ?? "–")
                    } else {
                        LabeledField(label: "Price per Clean") {
                            TextField("0.00", text: $priceText)
                                .keyboardType(.decimalPad)
                        }
                    }
                } header: {
                    Text("Cleaning")
                } footer: {
                    if payMethod == .directDebit {
                        Text("Monthly × 12 ÷ a clean every 5 weeks. Change Pays by to set a price directly.")
                    }
                }
                Section {
                    LabeledField(label: "Second price (optional)") {
                        TextField("e.g. 10.00", text: $altPriceText)
                            .keyboardType(.decimalPad)
                    }
                    if !altPriceText.trimmingCharacters(in: .whitespaces).isEmpty {
                        LabeledField(label: "What's the second price for?") {
                            TextField("e.g. Front only", text: $altPriceLabel)
                        }
                    }
                } footer: {
                    Text("For customers who alternate, e.g. front only one time and full the next. Logging a clean then asks which, with the one not used last time first.")
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
                    Picker("Same day as the customer before", selection: $groupWithPrevious) {
                        Text("Automatic (same street)").tag(Bool?.none)
                        Text("Always").tag(Bool?.some(true))
                        Text("Never").tag(Bool?.some(false))
                    }
                    .pickerStyle(.navigationLink)
                    if !isEditing {
                        Button {
                            isShowingPlace = true
                        } label: {
                            HStack {
                                Text("Place in round").foregroundStyle(.primary)
                                Spacer()
                                Text(effectivePlace.map { "After \($0.name)" } ?? "At the end")
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
            .navigationTitle(isEditing ? "Edit Customer" : (replacing == nil ? "New Customer" : "New Occupant"))
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
            .keyboardDoneButton()
            .onAppear(perform: populateFieldsIfEditing)
            .alert("They still owe money", isPresented: $isConfirmingOwedCancel) {
                Button("Cancel anyway", role: .destructive) { cancelAnyway = true; save() }
                Button("Go back", role: .cancel) {}
            } message: {
                if let customer {
                    let owed = RoundMetrics.moneyOwed([customer])
                    Text("\(customer.name) owes \(owed.amount.formatted(.currency(code: "GBP"))) from \(owed.cleans) clean\(owed.cleans == 1 ? "" : "s"). That stays on Money Owed after they're cancelled.")
                }
            }
            .alert("Contacts", isPresented: Binding(get: { contactsMessage != nil }, set: { if !$0 { contactsMessage = nil; dismiss() } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(contactsMessage ?? "")
            }
            .sheet(isPresented: $isShowingPlace) {
                PlaceInRoundView(customers: allCustomers, placeAfter: $placeAfter) { placeChosen = true }
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
        if customer == nil, let old = replacing {
            address = old.address
            priceText = NSDecimalNumber(decimal: old.price).stringValue
            round = old.round
            area = old.area
            notesText = old.notesText
            frontOnly = old.frontOnly
            payMethod = old.payMethod
            status = .active
            placeAfter = old
            placeChosen = true
            if let alt = old.altPrice { altPriceText = NSDecimalNumber(decimal: alt).stringValue }
            altPriceLabel = old.altPriceLabel ?? ""
            return
        }
        guard let customer else { return }
        name = customer.name
        address = customer.address
        phone = customer.phone
        priceText = NSDecimalNumber(decimal: customer.price).stringValue
        if let alt = customer.altPrice { altPriceText = NSDecimalNumber(decimal: alt).stringValue }
        altPriceLabel = customer.altPriceLabel ?? ""
        round = customer.round
        area = customer.area
        notesText = customer.notesText
        status = customer.status
        everyOther = customer.everyOther
        frontOnly = customer.frontOnly
        contact = customer.contact
        payMethod = customer.payMethod
        if let monthly = customer.monthlyAmount { monthlyText = NSDecimalNumber(decimal: monthly).stringValue }
        groupWithPrevious = customer.groupWithPrevious
    }

    private func save() {
        if let customer, status == .cancelled, customer.status != .cancelled, !cancelAnyway,
           RoundMetrics.moneyOwed([customer]).cleans > 0 {
            isConfirmingOwedCancel = true
            return
        }
        let price = payMethod == .directDebit ? DirectDebit.perClean(monthly: monthlyAmount ?? 0) : (Decimal(string: priceText) ?? 0)
        let monthly: Decimal? = payMethod == .directDebit ? monthlyAmount : nil
        let altText = altPriceText.trimmingCharacters(in: .whitespaces)
        let altPrice: Decimal? = altText.isEmpty ? nil : Decimal(string: altText)
        let altLabel = altPriceLabel.trimmingCharacters(in: .whitespaces)
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
            customer.monthlyAmount = monthly
            customer.groupWithPrevious = groupWithPrevious
            customer.altPrice = altPrice
            customer.altPriceLabel = altLabel.isEmpty ? nil : altLabel
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
            newCustomer.monthlyAmount = monthly
            newCustomer.groupWithPrevious = groupWithPrevious
            newCustomer.altPrice = altPrice
            newCustomer.altPriceLabel = altLabel.isEmpty ? nil : altLabel
            let place = effectivePlace
            modelContext.insert(newCustomer)
            RoundOrder.place(newCustomer, after: place, among: allCustomers)
            target = newCustomer
        }

        if addressChanged {
            Task {
                target.latitude = nil
                target.longitude = nil
                await MapPositions.find(target)
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
