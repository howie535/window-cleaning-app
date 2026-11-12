import SwiftUI

struct WhatsAppButton: View {
    let customer: Customer

    @State private var showsUnavailableAlert = false

    private var message: String {
        "Hi \(customer.name), your windows are next on our round. What day works well this week?"
    }

    private var whatsAppURL: URL? {
        DayMessage.whatsAppURL(digits: customer.whatsAppDigits, text: message)
    }

    var body: some View {
        Button {
            openWhatsApp()
        } label: {
            Label("Message on WhatsApp", systemImage: "message")
                .font(.title3)
                .padding(.vertical, 6)
        }
        .alert("Can't Open WhatsApp", isPresented: $showsUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Couldn't open WhatsApp. Check the number: \(customer.phone).")
        }
    }

    private func openWhatsApp() {
        guard let whatsAppURL else {
            showsUnavailableAlert = true
            return
        }
        UIApplication.shared.open(whatsAppURL) { success in
            if !success {
                showsUnavailableAlert = true
            }
        }
    }
}
