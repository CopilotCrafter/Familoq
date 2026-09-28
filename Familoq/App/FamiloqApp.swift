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
            #if SCHEMA_BOOTSTRAP
            // Special one-time build for the CloudKit schema (docs/11).
            SchemaBootstrapView()
            #else
            RootView()
                .environmentObject(session)
                .environmentObject(rateService)
                .environmentObject(account)
                .environmentObject(sync)
                .environmentObject(shareInbox)
            #endif
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
                PlannerDemoData.seedIfEmpty(family: family, member: session.currentMember, context: context)
            }
            startSyncIfActive()
            bookScheduledExpenses()
            setUpBackgroundRefresh()
            await PlannerNotifications.reschedule(context: context)
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
            switchToJoinedFamilyIfArrived()
            Task { await PlannerNotifications.reschedule(context: context) }
        }
        .onChange(of: sync.joinState) { _, _ in
            session.refresh(context: context)
            switchToJoinedFamilyIfArrived()
        }
        .onChange(of: shareInbox.pending) { _, _ in
            acceptPendingInvitation()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await sync.refresh()
                    bookScheduledExpenses()
                    await PlannerNotifications.reschedule(context: context)
                    await refreshRates()
                    await account.refreshIfDue()
                }
            } else if phase == .background {
                sync.scanNow()
                BackgroundRefresh.schedule()
                Task { await PlannerNotifications.reschedule(context: context) }
            }
        }
    }

    /// After joining, the family's data can arrive a little later than the
    /// "joined" moment - switch to it as soon as it is on this iPhone.
    private func switchToJoinedFamilyIfArrived() {
        guard case .joined(let familyID) = sync.joinState else { return }
        guard session.families.contains(where: { $0.id == familyID }) else { return }
        if session.family?.id != familyID {
            session.switchTo(familyID: familyID, context: context)
        }
        sync.joinState = .idle
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

    /// What iOS runs when it wakes Familoq in the background.
    private func setUpBackgroundRefresh() {
        let sync = sync
        let context = context
        let account = account
        let session = session
        BackgroundRefresh.work = {
            guard account.isActive, sync.isRunning else { return }
            await sync.refresh()
            if let family = session.family {
                PlanningService.bookDue(familyID: family.id, baseCurrency: family.baseCurrencyCode, context: context)
            }
            await PlannerNotifications.reschedule(context: context)
        }
        BackgroundRefresh.schedule()
    }

    /// Recurring/planned expenses that are due become real expenses.
    private func bookScheduledExpenses() {
        guard account.isActive, let family = session.family else { return }
        PlanningService.bookDue(familyID: family.id, baseCurrency: family.baseCurrencyCode, context: context)
        if session.isOwner {
            // Built-in category names in the app language (e.g. German).
            CategoryNameLocalizer.apply(familyID: family.id, context: context)
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
            PlannerView()
                .tabItem { Label("Planner", systemImage: "checklist") }
                .tag(AppTab.planner)
            FamilyView()
                .tabItem { Label("Family", systemImage: "person.2.fill") }
                .tag(AppTab.family)
        }
        .overlay(alignment: .top) {
            if let notice = session.notice {
                NoticeBanner(text: notice)
                    .task(id: notice) {
                        try? await Task.sleep(for: .seconds(4))
                        withAnimation { session.notice = nil }
                    }
            }
        }
        .animation(.spring, value: session.notice)
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
                    Text(LocalizedStringKey(message))
                }
        default:
            EmptyView()
        }
    }
}
