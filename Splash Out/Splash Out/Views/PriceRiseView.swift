import SwiftUI
import SwiftData

/// Every customer on the round with the date their price last went up, oldest first. Prices are changed by hand on
/// the customer's page (tap a row); a price that goes up there is logged as a rise with today's date.
struct PriceRiseView: View {
    @Environment(RoundClock.self) private var clock
    @Query(sort: \Customer.sequence) private var customers: [Customer]
    @Query private var settings: [AppSettings]

    var body: some View {
        let onRound = RoundMetrics.onRound(customers).filter { $0.price > 0 }
        let months = settings.first?.priceRiseDueAfterMonths ?? 24
        let noDate = onRound.filter { $0.priceSince == nil }
        let dated = onRound.filter { $0.priceSince != nil }.sorted { $0.priceSince! < $1.priceSince! }
        let due = dated.filter { PriceRise.isDue(priceSince: $0.priceSince, today: clock.today, dueAfterMonths: months, calendar: RoundCalendar.london) }
        let recent = dated.filter { c in !due.contains { $0 === c } }

        List {
            if !due.isEmpty {
                Section("No rise in \(months / 12) years (\(due.count))") { ForEach(due) { row($0) } }
            }
            if !noDate.isEmpty {
                Section {
                    ForEach(noDate) { row($0) }
                } header: {
                    Text("No date logged (\(noDate.count))")
                } footer: {
                    Text("Change their price on their page when it goes up, and the date is logged from then.")
                }
            }
            if !recent.isEmpty {
                Section("Risen recently (\(recent.count))") { ForEach(recent) { row($0) } }
            }
        }
        .navigationTitle("Price Rise")
    }

    private func row(_ customer: Customer) -> some View {
        NavigationLink { CustomerDetailView(customer: customer) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(customer.name).font(.headline)
                    Text(customer.priceSince.map { "Last rise \(RoundCalendar.shortWithYear($0))" } ?? "No date logged")
                        .font(.caption)
                        .foregroundStyle(customer.priceSince == nil ? .orange : .secondary)
                }
                Spacer()
                Text(customer.price.pounds).font(.headline)
            }
        }
    }
}
