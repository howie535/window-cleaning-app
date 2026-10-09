import SwiftUI
import SwiftData

enum AppTab: Int, CaseIterable {
    case today, round, customers, owed, more
}

struct RootTabView: View {
    @State private var undoCenter = UndoCenter()
    @State private var selection: AppTab = .today
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tag(AppTab.today)
                .tabItem { Label("Today", systemImage: "chart.bar.xaxis") }

            NextUpView()
                .tag(AppTab.round)
                .tabItem { Label("Round", systemImage: "list.bullet.clipboard") }

            CustomerListView()
                .tag(AppTab.customers)
                .tabItem { Label("Customers", systemImage: "person.2") }

            MoneyOwedView()
                .tag(AppTab.owed)
                .tabItem { Label("Owed", systemImage: "sterlingsign.circle") }

            MoreView()
                .tag(AppTab.more)
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(undoCenter)
        .background {
            // Keyboard shortcuts for a keyboard case: Command-1 to Command-5 switch tab.
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button("") { selection = tab }
                    .keyboardShortcut(KeyEquivalent(Character("\(tab.rawValue + 1)")), modifiers: .command)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
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
