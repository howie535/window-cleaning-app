import SwiftUI
import SwiftData

/// Houses that may be harming the round: worth a price rise, or worth letting go.
struct RoundReviewView: View {
    @Environment(RoundClock.self) private var clock
    @Query private var customers: [Customer]
    @Query private var visits: [Visit]
    @State private var showAll = false

    var body: some View {
        let _ = VisitLookup.begin(visits)
        let review = RoundReview.rows(customers: customers, today: clock.today, threshold: showAll ? 1 : 3)
        let _ = VisitLookup.end()

        List {
            Section {
                LabeledContent("Average price", value: review.average.formatted(.currency(code: "GBP").precision(.fractionLength(2))))
                Toggle("Show every house with a reason", isOn: $showAll)
            } footer: {
                Text("Cheap for the round and on its own count most; skipping a lot and slow paying count less. Tap a house to see it.")
            }
            Section("\(review.rows.count) houses") {
                if review.rows.isEmpty {
                    Text("Nothing stands out.").foregroundStyle(.secondary)
                }
                ForEach(review.rows) { row in
                    NavigationLink { CustomerDetailView(customer: row.customer) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.customer.name).font(.headline)
                                Spacer()
                                Text(row.customer.price.pounds).font(.headline)
                            }
                            Text([row.customer.address, row.customer.area].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            HStack(spacing: 6) {
                                ForEach(row.reasons, id: \.self) { reason in
                                    Text(reason)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15), in: Capsule())
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Round review")
    }
}
