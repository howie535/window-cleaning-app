import SwiftUI

struct WhatsAppButton: View {
    let customer: Customer

    @State private var showsUnavailableAlert = false

    private var message: String {
        if customer.isDue {
            "Hi \(customer.name), your windows are due for a clean — what day works well this week?"
        } else {
            "Hi \(customer.name), just checking in about your windows."
        }
    }

    private var whatsAppURL: URL? {
        var components = URLComponents(string: "https://wa.me/\(customer.whatsAppDigits)")
        components?.queryItems = [URLQueryItem(name: "text", value: message)]
        return components?.url
    }

    var body: some View {
        Button {
            openWhatsApp()
        } label: {
            Label("Message on WhatsApp", systemImage: "message")
        }
        .disabled(customer.whatsAppDigits.isEmpty)
        .alert("Can't Open WhatsApp", isPresented: $showsUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("WhatsApp isn't installed, or the phone number is missing a country code.")
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
