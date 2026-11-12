import SwiftUI
import SwiftData

enum AppTab: Int, CaseIterable {
    case round, today, customers, owed, more
}

/// Which tab is showing. The heavy screens (Stats, Owed) read it and skip their sums while hidden: the tab bar keeps
/// them alive, so otherwise they recalculated in the background every time a clean was logged.
@MainActor @Observable
final class TabState {
    var selection: AppTab = .round
}

struct RootTabView: View {
    @State private var undoCenter = UndoCenter()
    @State private var clock = RoundClock()
    @State private var tabState = TabState()
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboarding.seen") private var onboardingSeen = false
    @State private var showTour = false
    /// A shake asking to undo the last action.
    @State private var shakeUndo: UndoCenter.Entry?
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView(selection: $tabState.selection) {
            // The Round comes first: it's the screen used all day.
            NextUpView()
                .tag(AppTab.round)
                .tabItem { Label("Round", systemImage: "list.bullet.clipboard") }

            StatsView()
                .tag(AppTab.today)
                .tabItem { Label("Stats", systemImage: "chart.bar.xaxis") }

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
        .onAppear { if !onboardingSeen && !LagTour.enabled { showTour = true } }
        .task { await LagTour.run(tabs: tabState, context: modelContext) }
        .task {
            // One-time merge of the 2025-6 worksheet history (does nothing once done), a few seconds after opening.
            try? await Task.sleep(for: .seconds(4))
            PriceHistoryImport.mergeBundledOnce(context: modelContext)
        }
        .fullScreenCover(isPresented: $showTour) { OnboardingView() }
        // Shake to undo, as in Apple's own apps: asks first, naming what it will undo.
        .onReceive(NotificationCenter.default.publisher(for: .sudsyDidShake)) { _ in shakeUndo = undoCenter.shakeable }
        .alert("Undo \(shakeUndo?.message ?? "")?", isPresented: Binding(get: { shakeUndo != nil }, set: { if !$0 { shakeUndo = nil } })) {
            Button("Cancel", role: .cancel) { shakeUndo = nil }
            Button("Undo") { undoCenter.performUndo(); shakeUndo = nil }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                clock.refresh()
                // Housekeeping waits a few seconds after opening, so it never holds up the first taps.
                let context = modelContext
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(4))
                    ChangeLog.backupIfNewVersion(context: context)
                    AutoBackup.runIfDue(context: context)
                    MapPositions.fillMissing(in: context)
                    try? await Task.sleep(for: .seconds(4))
                    await CalendarSync.syncIfDue(context: context)
                }
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
