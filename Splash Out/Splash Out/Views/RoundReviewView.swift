import SwiftUI
import SwiftData

/// Houses that may be harming the round: worth a price rise, or worth letting go (a part of To Check).
struct RoundReviewSections: View {
    let review: (rows: [RoundReview.Row], average: Decimal)
    @Binding var showAll: Bool

    var body: some View {
            Section {
                LabeledContent("Average price (full cleans)", value: review.average.formatted(.currency(code: "GBP").precision(.fractionLength(2))))
                Toggle("Show every house with a reason", isOn: $showAll)
            } header: {
                Text("Round Review")
            } footer: {
                InfoFooter(text: "Houses that may be holding the round back.", title: "How houses are picked", points: [
                    "Counts most: cheap for the round, or out on their own.",
                    "Counts less: skipping a lot (only in a group), or paying slowly.",
                    "Front-only houses are never counted as cheap."])
            }
            Section("Houses to Review (\(review.rows.count))") {
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
                                if row.frontOnly {
                                    Text("Front only")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.12), in: Capsule())
                                        .foregroundStyle(.blue)
                                }
                                ForEach(row.reasons, id: \.self) { reason in
                                    Text(reason)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15), in: Capsule())
                                        .foregroundStyle(Color.notPaidText)
                                }
                            }
                        }
                    }
                }
            }
    }
}
