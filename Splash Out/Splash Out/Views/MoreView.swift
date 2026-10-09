import SwiftUI

/// Everything that isn't a daily screen.
struct MoreView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Reports") {
                    NavigationLink { WeeklyView() } label: { Label("Weekly", systemImage: "calendar") }
                    NavigationLink { TaxYearView() } label: { Label("Tax Year", systemImage: "sterlingsign.square") }
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
