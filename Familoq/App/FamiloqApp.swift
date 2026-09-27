import SwiftUI
import SwiftData

@main
struct FamiloqApp: App {
    @UIApplicationDelegateAdaptor(FamiloqAppDelegate.self) private var appDelegate
    @StateObject private var session = AppSession()
    @StateObject private var rateService = ExchangeRateService()
    @StateObject private var account = AccountService.live()
    @StateObject private var sync = SyncCoordinator.live()
    @StateObject private var shareInbox = ShareInbox.shared
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
                .environmentObject(sync)
                .environmentObject(shareInbox)
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
    @EnvironmentObject private var sync: SyncCoordinator
    @EnvironmentObject private var shareInbox: ShareInbox

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
                    if session.needsMemberName, let family = session.family, sync.initialFetchDone,
                       sync.zoneRecord(for: family.id)?.isShared == true {
                        // Just joined: "What should the family call you?"
                        JoinNameView(family: family)
                    } else if session.family != nil {
                        RootTabView()
                            .id(session.family?.id)
                    } else if session.needsFamilySetup && !sync.initialFetchDone {
                        // Reinstall / new iPhone: the family may still be on its way from iCloud.
                        ProgressView("Looking for your family in iCloud…")
                    } else if session.needsFamilySetup {
                        FamilySetupView()
                    } else {
                        ProgressView("Loading…")
                    }
                }
            }
        }
        .animation(.default, value: account.state)
        .overlay { JoinProgressOverlay() }
        .task {
            await account.load()
            guard !session.isLoaded else { return }
            session.start(context: context)
            if LaunchOptions.seedDemoData, let family = session.family {
                DemoDataSeeder.seedIfEmpty(family: family, member: session.currentMember, context: context)
            }
            startSyncIfActive()
            await refreshRates()
            await account.refreshIfDue()
        }
        .onChange(of: account.state) { _, _ in
            if account.isActive {
                startSyncIfActive()
            } else {
                sync.stop()
            }
        }
        .onChange(of: sync.remoteChangeCount) { _, _ in
            session.refresh(context: context)
        }
        .onChange(of: sync.joinState) { _, state in
            if case .joined(let familyID) = state {
                session.refresh(context: context)
                session.switchTo(familyID: familyID, context: context)
            }
        }
        .onChange(of: shareInbox.pending) { _, _ in
            acceptPendingInvitation()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await sync.refresh()
                    await refreshRates()
                    await account.refreshIfDue()
                }
            } else if phase == .background {
                sync.scanNow()
            }
        }
    }

    private func startSyncIfActive() {
        guard let user = account.account?.userRecordName else { return }
        let session = session
        let context = context
        sync.willRemoveFamily = { familyID in
            session.familyWillBeRemoved(familyID, context: context)
        }
        sync.start(modelContainer: context.container, userRecordName: user)
        acceptPendingInvitation()
    }

    /// A tapped family invitation is accepted once the app is activated.
    private func acceptPendingInvitation() {
        guard account.isActive, sync.isRunning, let metadata = shareInbox.pending else { return }
        shareInbox.pending = nil
        Task { await sync.accept(metadata) }
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

/// "Joining family…" and join errors, above everything else.
private struct JoinProgressOverlay: View {
    @EnvironmentObject private var sync: SyncCoordinator

    var body: some View {
        switch sync.joinState {
        case .joining:
            ZStack {
                Color.black.opacity(0.25).ignoresSafeArea()
                ProgressView("Joining the family…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        case .failed(let message):
            Color.clear
                .alert("Could not join", isPresented: .constant(true)) {
                    Button("OK") { sync.joinState = .idle }
                } message: {
                    Text(message)
                }
        default:
            EmptyView()
        }
    }
}
