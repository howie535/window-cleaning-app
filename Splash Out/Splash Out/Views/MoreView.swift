import SwiftUI

/// Everything that isn't a daily screen.
struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Reports") {
                    NavigationLink { WeeklyView() } label: { Label("Weekly", systemImage: "calendar") }
                    NavigationLink { TaxYearView() } label: { Label("Tax Year", systemImage: "sterlingsign.square") }
                    NavigationLink { PriceRiseView() } label: { Label("Price Rise", systemImage: "arrow.up.right.circle") }
                    NavigationLink { FrequentSkipsView() } label: { Label("Frequent Skips", systemImage: "forward.circle") }
                    NavigationLink { ChecksView() } label: { Label("Checks", systemImage: "checkmark.shield") }
                }
                Section("Records") {
                    NavigationLink { DiaryView() } label: { Label("Diary", systemImage: "book") }
                    NavigationLink { TipsView() } label: { Label("Tips", systemImage: "heart") }
                    NavigationLink { ExportsView() } label: { Label("Exports", systemImage: "square.and.arrow.up") }
                }
                Section("Tools") {
                    NavigationLink { RouteBuilderView(embedded: true) } label: { Label("Route planner", systemImage: "map") }
                    NavigationLink { SettingsView(embedded: true) } label: { Label("Settings", systemImage: "gearshape") }
                }
            }
            .navigationTitle("More")
        }
    }
}
