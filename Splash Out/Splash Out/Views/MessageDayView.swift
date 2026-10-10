import SwiftUI

/// Messages everyone booked for a day. WhatsApp only lets a person press Send, so this opens each chat with the
/// message ready and keeps track of who has been done: one tap per customer, then straight on to the next.
struct MessageDayView: View {
    let day: RoundPlanner.DayPlan

    @Environment(\.dismiss) private var dismiss
    @AppStorage(DayMessage.templateKey) private var template = DayMessage.defaultTemplate
    @State private var sent: Set<String> = []
    @State private var failure: String?

    private var storageKey: String { "messaged.\(RoundCalendar.dayString(day.date))" }

    private func text(for customer: Customer) -> String {
        DayMessage.text(template: template, name: customer.name, date: day.date)
    }

    private func isWhatsApp(_ customer: Customer) -> Bool {
        customer.contact == .whatsapp && !customer.whatsAppDigits.isEmpty
    }

    private var queue: [Customer] { day.customers.filter(isWhatsApp) }
    private var nextToSend: Customer? { queue.first { !sent.contains($0.id.uuidString) } }
    private var sentCount: Int { queue.filter { sent.contains($0.id.uuidString) }.count }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Message", text: $template, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Message")
                } footer: {
                    Text("{name} becomes the customer's name and {when} becomes \"tomorrow\" or \"on Tuesday\".")
                }

                Section {
                    if let next = nextToSend {
                        Button { send(next) } label: {
                            Label("Message next: \(next.name)", systemImage: "paperplane.fill")
                                .font(.title3)
                                .padding(.vertical, 6)
                        }
                    } else if !queue.isEmpty {
                        Label("Everyone has been messaged", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } footer: {
                    Text("Opens WhatsApp with the message ready. Press Send there, then come back and tap again. \(sentCount) of \(queue.count) done.")
                }

                Section("Customers (\(day.customers.count))") {
                    ForEach(day.customers) { customer in
                        row(customer)
                    }
                    if !sent.isEmpty {
                        Button("Start again", role: .destructive) {
                            sent = []
                            save()
                        }
                    }
                }
            }
            .navigationTitle(RoundCalendar.weekdayShort(day.date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                sent = Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
            }
            .alert("Can't open WhatsApp", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
        }
    }

    @ViewBuilder
    private func row(_ customer: Customer) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(customer.name).font(.headline)
                Text(customer.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if customer.phone.isEmpty {
                Text("No number").font(.caption).foregroundStyle(.orange)
            } else if customer.contact == .ring {
                if let url = URL(string: "tel:\(customer.phone.filter(\.isNumber))") {
                    Link(destination: url) { Label("Ring", systemImage: "phone") }
                }
            } else {
                Button { send(customer) } label: {
                    if sent.contains(customer.id.uuidString) {
                        Label("Sent", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Send", systemImage: "paperplane")
                    }
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func send(_ customer: Customer) {
        guard let url = DayMessage.whatsAppURL(digits: customer.whatsAppDigits, text: text(for: customer)) else { return }
        sent.insert(customer.id.uuidString)
        save()
        UIApplication.shared.open(url) { success in
            if !success { failure = "WhatsApp couldn't be opened for \(customer.name). Check it is installed and the number \(customer.phone) is right." }
        }
    }

    private func save() {
        UserDefaults.standard.set(Array(sent), forKey: storageKey)
    }
}
