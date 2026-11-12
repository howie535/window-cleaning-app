import SwiftUI
import SwiftData

/// Everything that isn't a daily screen. Rows that need attention show a count, so nothing has to be opened to check.
struct MoreView: View {
    @Environment(TabState.self) private var tabs: TabState?
    @Environment(RoundClock.self) private var clock

    var body: some View {
        NavigationStack {
            List {
                Section("Overview") {
                    NavigationLink { RoundSheetView() } label: { BadgeLabel(title: "Round Sheet", systemName: "tablecells.fill", color: .teal) }
                }
                Section("Reports") {
                    NavigationLink { WeeklyView() } label: { BadgeLabel(title: "Weekly & Daily", systemName: "calendar", color: .blue) }
                    NavigationLink { TaxYearView() } label: { BadgeLabel(title: "Tax Year", systemName: "sterlingsign", color: .green) }
                    // The counts are only worked out while More is showing (hidden tabs stay alive).
                    if tabs == nil || tabs?.selection == .more {
                        MoreCounts(today: clock.today)
                    } else {
                        NavigationLink { PriceRiseView() } label: { BadgeLabel(title: "Price Rise", systemName: "arrow.up.right", color: .orange) }
                        NavigationLink { ToCheckView() } label: { BadgeLabel(title: "To Check", systemName: "checklist", color: .red) }
                    }
                }
                Section("Records") {
                    NavigationLink { HistoryView() } label: { BadgeLabel(title: "History", systemName: "clock.arrow.circlepath", color: .gray) }
                    NavigationLink { DiaryView() } label: { BadgeLabel(title: "Diary", systemName: "book.fill", color: .purple) }
                    NavigationLink { ExpensesView() } label: { BadgeLabel(title: "Expenses", systemName: "cart.fill", color: .brown) }
                    NavigationLink { TipsView() } label: { BadgeLabel(title: "Tips", systemName: "heart.fill", color: .pink) }
                    NavigationLink { ExportsView() } label: { BadgeLabel(title: "Exports", systemName: "square.and.arrow.up", color: .blue) }
                }
                Section("Help") {
                    QuickTourButton()
                }
                Section("Tools") {
                    NavigationLink { RouteBuilderView(embedded: true) } label: { BadgeLabel(title: "Route Planner", systemName: "map.fill", color: .green) }
                    NavigationLink { SettingsView(embedded: true) } label: { BadgeLabel(title: "Settings", systemName: "gearshape.fill", color: .gray) }
                }
            }
            .sudsyBackground()
            .navigationTitle("More")
        }
    }
}

/// Price Rise and To Check, each with how many are waiting.
private struct MoreCounts: View {
    let today: Date
    @Query private var customers: [Customer]
    @Query private var visits: [Visit]
    @Query private var crews: [Crew]
    @Query private var workDays: [WorkDay]
    @Query private var settings: [AppSettings]

    var body: some View {
        let months = settings.first?.priceRiseDueAfterMonths ?? 24
        let rises = customers.filter { ($0.status == .active || $0.status == .leaving) && $0.price > 0 }
            .filter { PriceRise.isDue($0, today: today, dueAfterMonths: months) }.count
        let stats = RoundStats(visits: visits, customers: customers, settings: settings.first, crews: crews, workDays: workDays)
        let checks = ToCheckView.count(stats: stats)
        NavigationLink { PriceRiseView() } label: { BadgeLabel(title: "Price Rise", systemName: "arrow.up.right", color: .orange, count: rises) }
        NavigationLink { ToCheckView() } label: { BadgeLabel(title: "To Check", systemName: "checklist", color: .red, count: checks) }
    }
}
