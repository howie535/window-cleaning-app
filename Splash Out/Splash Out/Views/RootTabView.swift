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
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: Customer.self, inMemory: true)
}
