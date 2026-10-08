import SwiftUI
import SwiftData

struct RootTabView: View {
    @State private var undoCenter = UndoCenter()

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
        .environment(undoCenter)
        .overlay(alignment: .bottom) {
            UndoBanner(undoCenter: undoCenter)
                .padding(.bottom, 90) // clears the tab bar
                .animation(.default, value: undoCenter.entry?.id)
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: Customer.self, inMemory: true)
}
