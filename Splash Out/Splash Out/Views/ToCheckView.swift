import SwiftUI
import SwiftData

/// Everything worth a look, on one screen: paying under price, dates to check, frequent skips and the round review.
/// (Was three screens: Checks, Frequent Skips and Round review.)
struct ToCheckView: View {
    @Environment(RoundClock.self) private var clock
    @Query private var customers: [Customer]
    @Query private var visits: [Visit]
    @Query private var crews: [Crew]
    @Query private var workDays: [WorkDay]
    @Query private var settings: [AppSettings]
    @State private var showAll = false

    var body: some View {
        let stats = RoundStats(visits: visits, customers: customers, settings: settings.first, crews: crews, workDays: workDays)
        let under = stats.payingUnderPrice()
        let issues = stats.dataIssues()
        let skips = stats.frequentSkippers()
        let _ = VisitLookup.begin(visits)
        let review = RoundReview.rows(customers: customers, today: clock.today, threshold: showAll ? 1 : 3)
        let _ = VisitLookup.end()

        let quotes = customers.filter { $0.status == .quote }.sorted { $0.sequence < $1.sequence }

        List {
            if !quotes.isEmpty {
                Section {
                    ForEach(quotes) { quote in
                        NavigationLink { CustomerDetailView(customer: quote) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(quote.name).font(.headline)
                                Text(quote.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                } header: {
                    Text("Quotes to Do (\(quotes.count))")
                } footer: {
                    Text("Each shows on the Round when it's their turn.")
                }
            }
            ChecksSections(under: under, issues: issues)
            FrequentSkipsSections(rows: skips)
            RoundReviewSections(review: review, showAll: $showAll)
        }
        .sudsyBackground()
        .navigationTitle("To Check")
    }

    /// How many things need action (the count on More): quotes to do, paying under price, dates to check and frequent skips.
    /// The round review is a standing list to think about, not a task, so it isn't counted.
    static func count(stats: RoundStats) -> Int {
        stats.payingUnderPrice().count + stats.dataIssues().count + stats.frequentSkippers().count
            + stats.customers.filter { $0.status == .quote }.count
    }
}
