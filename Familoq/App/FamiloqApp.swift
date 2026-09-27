import SwiftUI
import SwiftData

@main
struct FamiloqApp: App {
    @StateObject private var session = AppSession()
    @StateObject private var rateService = ExchangeRateService()
    @StateObject private var account = AccountService.live()
    private let container: ModelContainer

    init() {
        do {
            container = try PersistenceController.makeContainer()
        } catch {
            // A broken local store is unrecoverable at this point; crash
            // reports reach TestFlight so we learn about it.
            fatalError("Could not open the local database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(rateService)
                .environmentObject(account)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var rates: ExchangeRateService
    @EnvironmentObject private var account: AccountService

    var body: some View {
        Group {
            if let error = session.startupError {
                EmptyStateView(icon: "exclamationmark.triangle", title: "Something went wrong", message: error)
            } else {
                switch account.state {
                case .checking:
                    ProgressView("Loading…")
                case .needsInvitation:
                    // Level 1 gate: no family data is shown without an App Invitation.
                    OnboardingView()
                case .active:
                    if session.family != nil {
                        RootTabView()
                    } else if session.needsFamilySetup {
                        FamilySetupView()
                    } else {
                        ProgressView("Loading…")
                    }
                }
            }
        }
        .animation(.default, value: account.state)
        .task {
            await account.load()
            guard !session.isLoaded else { return }
            session.start(context: context)
            if LaunchOptions.seedDemoData, let family = session.family {
                DemoDataSeeder.seedIfEmpty(family: family, member: session.currentMember, context: context)
            }
            await refreshRates()
            await account.refreshIfDue()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await refreshRates()
                    await account.refreshIfDue()
                }
            }
        }
    }

    private func refreshRates() async {
        guard let family = session.family else { return }
        await rates.refreshPending(familyID: family.id, baseCurrency: family.baseCurrencyCode, context: context)
    }
}

struct RootTabView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        TabView(selection: $session.selectedTab) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "house.fill") }
                .tag(AppTab.dashboard)
            AddExpenseView()
                .tabItem { Label("Add", systemImage: "plus.circle.fill") }
                .tag(AppTab.add)
            ScanReceiptView()
                .tabItem { Label("Scan", systemImage: "doc.viewfinder") }
                .tag(AppTab.scan)
            ReportsView()
                .tabItem { Label("Reports", systemImage: "chart.bar.xaxis") }
                .tag(AppTab.reports)
            FamilyView()
                .tabItem { Label("Family", systemImage: "person.2.fill") }
                .tag(AppTab.family)
        }
    }
}
