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
            Text("WhatsApp couldn't be opened. Check it is installed and that the number \(customer.phone) is right.")
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
