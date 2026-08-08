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
