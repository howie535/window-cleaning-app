import ContactsUI
import SwiftUI

struct ContactPicker: UIViewControllerRepresentable {
    var onPick: (CNContact) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (CNContact) -> Void

        init(onPick: @escaping (CNContact) -> Void) {
            self.onPick = onPick
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onPick(contact)
        }
    }
}

extension CNContact {
    var splashOutFullName: String {
        [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var splashOutPhoneDigits: String {
        guard let raw = phoneNumbers.first?.value.stringValue else { return "" }
        return UKPhoneNumber.toNationalFormat(raw)
    }

    var splashOutFormattedAddress: String {
        guard let postalAddress = postalAddresses.first?.value else { return "" }
        return CNPostalAddressFormatter.string(from: postalAddress, style: .mailingAddress)
            .replacingOccurrences(of: "\n", with: ", ")
    }
}

/// Saves a new customer into the phone's Contacts, so the number and address are there for calls, messages and maps.
enum ContactsSaver {
    enum Outcome {
        case saved
        case alreadyThere
        case notAllowed
        case failed(String)
    }

    /// Doesn't create a duplicate if a contact with the same phone number already exists.
    static func save(name: String, phone: String, address: String) async -> Outcome {
        let store = CNContactStore()
        do {
            guard try await store.requestAccess(for: .contacts) else { return .notAllowed }

            let digits = phone.filter(\.isNumber)
            if digits.count >= 6 {
                let request = CNContactFetchRequest(keysToFetch: [CNContactPhoneNumbersKey as CNKeyDescriptor])
                var found = false
                try store.enumerateContacts(with: request) { existing, stop in
                    if existing.phoneNumbers.contains(where: { UKPhoneNumber.toNationalFormat($0.value.stringValue).filter(\.isNumber) == digits }) {
                        found = true
                        stop.pointee = true
                    }
                }
                if found { return .alreadyThere }
            }

            let contact = CNMutableContact()
            let parts = name.split(separator: " ", maxSplits: 1).map(String.init)
            contact.givenName = parts.first ?? name
            contact.familyName = parts.count > 1 ? parts[1] : ""
            if !phone.isEmpty {
                contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: phone))]
            }
            if !address.isEmpty {
                let postal = CNMutablePostalAddress()
                postal.street = address
                contact.postalAddresses = [CNLabeledValue(label: CNLabelWork, value: postal)]
            }
            let save = CNSaveRequest()
            save.add(contact, toContainerWithIdentifier: nil)
            try store.execute(save)
            return .saved
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
