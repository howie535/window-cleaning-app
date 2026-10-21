import SwiftUI
import SwiftData

enum AppTab: Int, CaseIterable {
    case today, round, customers, owed, more
}

/// Which tab is showing. The heavy screens (Stats, Owed) read it and skip their sums while hidden: the tab bar keeps
/// them alive, so otherwise they recalculated in the background every time a clean was logged.
@MainActor @Observable
final class TabState {
    var selection: AppTab = .today
}

struct RootTabView: View {
    @State private var undoCenter = UndoCenter()
    @State private var clock = RoundClock()
    @State private var tabState = TabState()
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboarding.seen") private var onboardingSeen = false
    @State private var showTour = false
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView(selection: $tabState.selection) {
            TodayView()
                .tag(AppTab.today)
                .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }

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
        .environment(clock)
        .environment(tabState)
        .onAppear { if !onboardingSeen { showTour = true } }
        .fullScreenCover(isPresented: $showTour) { OnboardingView() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                clock.refresh()
                ChangeLog.backupIfNewVersion(context: modelContext)
                MapPositions.fillMissing(in: modelContext)
                AutoBackup.runIfDue(context: modelContext)
                Task { await CalendarSync.syncIfEnabled(context: modelContext) }
            }
            if phase == .background {
                MapPositions.stop()
                AutoBackup.run(context: modelContext)
            }
        }
        .background {
            // Keyboard shortcuts for a keyboard case: Command-1 to Command-5 switch tab.
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button("") { tabState.selection = tab }
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
