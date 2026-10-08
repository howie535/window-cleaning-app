import SwiftUI
import SwiftData

struct RootTabView: View {
    var body: some View {
        TabView {
            CustomerListView()
                .tabItem {
                    Label("Customers", systemImage: "person.2")
                }

            RouteBuilderView()
                .tabItem {
                    Label("Route", systemImage: "map")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: Customer.self, inMemory: true)
}
