import SwiftUI
import SwiftData

struct RootTabView: View {
    @State private var undoCenter = UndoCenter()
    @Environment(\.horizontalSizeClass) private var sizeClass

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
                .frame(maxWidth: 560)
                .padding(.bottom, sizeClass == .regular ? 24 : 90) // iPhone: clears the tab bar
                .animation(.default, value: undoCenter.entry?.id)
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: Customer.self, inMemory: true)
}
