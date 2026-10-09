import SwiftUI
import SwiftData

struct RootTabView: View {
    @State private var undoCenter = UndoCenter()

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "chart.bar.xaxis") }

            NextUpView()
                .tabItem { Label("Round", systemImage: "list.bullet.clipboard") }

            CustomerListView()
                .tabItem { Label("Customers", systemImage: "person.2") }

            MoneyOwedView()
                .tabItem { Label("Owed", systemImage: "sterlingsign.circle") }

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .tabViewStyle(.sidebarAdaptable)
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
