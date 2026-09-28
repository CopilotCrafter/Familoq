import SwiftUI
import LocalAuthentication

/// Face ID / passcode lock (this iPhone). No certificate or capability is
/// needed - only the Face ID usage text in Info.plist.
@MainActor
final class AppLock: ObservableObject {
    static let shared = AppLock()

    enum Scope: String, CaseIterable, Identifiable {
        case wholeApp, storageAndBackup
        var id: String { rawValue }
        var title: String {
            switch self {
            case .wholeApp: return "Whole app"
            case .storageAndBackup: return "Only Storage & Backup"
            }
        }
    }

    enum Delay: Int, CaseIterable, Identifiable {
        case immediately = 0, oneMinute = 60, fiveMinutes = 300, fifteenMinutes = 900
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .immediately: return "Immediately"
            case .oneMinute: return "After 1 minute"
            case .fiveMinutes: return "After 5 minutes"
            case .fifteenMinutes: return "After 15 minutes"
            }
        }
    }

    private let defaults = UserDefaults.standard

    var isEnabled: Bool {
        get { defaults.bool(forKey: "lock.enabled") }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "lock.enabled") }
    }

    var blurInSwitcher: Bool {
        get { defaults.object(forKey: "lock.blur") as? Bool ?? true }
        set { objectWillChange.send(); defaults.set(newValue, forKey: "lock.blur") }
    }

    /// The whole app is locked right now.
    @Published private(set) var isLocked = false
    /// Storage & Backup were unlocked in this session.
    @Published private(set) var sensitiveUnlocked = false
    @Published var lastError: String?
    private var backgroundedAt: Date?
    private var authenticating = false

    var scope: Scope {
        get { defaults.string(forKey: "lock.scope").flatMap(Scope.init(rawValue:)) ?? .wholeApp }
        set { objectWillChange.send(); defaults.set(newValue.rawValue, forKey: "lock.scope") }
    }

    var delay: Delay {
        get { Delay(rawValue: defaults.integer(forKey: "lock.delay")) ?? .immediately }
        set { objectWillChange.send(); defaults.set(newValue.rawValue, forKey: "lock.delay") }
    }

    private init() {
        isLocked = UserDefaults.standard.bool(forKey: "lock.enabled")
            && (UserDefaults.standard.string(forKey: "lock.scope") ?? Scope.wholeApp.rawValue) == Scope.wholeApp.rawValue
    }

    /// "Face ID", "Touch ID" or "Passcode".
    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return String(localized: "Passcode")
        }
    }

    var canUse: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    func didEnterBackground() {
        backgroundedAt = Date()
        sensitiveUnlocked = false
    }

    func didBecomeActive() {
        guard isEnabled, scope == .wholeApp else { return }
        if let backgroundedAt, Date().timeIntervalSince(backgroundedAt) >= Double(delay.rawValue) {
            isLocked = true
        }
        backgroundedAt = nil
        if isLocked { Task { await unlock() } }
    }

    /// Asks for Face ID (falls back to the passcode). Returns success.
    @discardableResult
    func authenticate(reason: String) async -> Bool {
        guard !authenticating else { return false }
        authenticating = true
        defer { authenticating = false }
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Cancel")
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
            lastError = nil
            return ok
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func unlock() async {
        if await authenticate(reason: String(localized: "Unlock Familoq")) {
            isLocked = false
        }
    }

    /// For Storage & Backup when the lock covers only those screens.
    func unlockSensitive() async {
        if await authenticate(reason: String(localized: "Open Storage & Backup")) {
            sensitiveUnlocked = true
        }
    }

    /// Turning the lock on requires one successful check first.
    func setEnabled(_ value: Bool) async {
        if value {
            guard await authenticate(reason: String(localized: "Turn on the Familoq lock")) else { return }
        }
        isEnabled = value
        isLocked = false
        sensitiveUnlocked = false
    }

    var needsSensitiveUnlock: Bool { isEnabled && scope == .storageAndBackup && !sensitiveUnlocked }
}

/// Full-screen lock shown above the app.
struct LockScreen: View {
    @ObservedObject var lock: AppLock

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(Color.accentColor)
                Text("Familoq is locked").font(.title3.weight(.semibold))
                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("Unlock with \(lock.biometryName)", systemImage: "faceid")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                if let error = lock.lastError {
                    Text(verbatim: error).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal)
                }
            }
        }
        .task { await lock.unlock() }
    }
}

/// Covers the app in the app switcher so amounts are not visible.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            Image(systemName: "lock.shield.fill").font(.system(size: 54)).foregroundStyle(.secondary)
        }
    }
}

/// Wraps Storage / Backup: asks for Face ID first when the lock covers them.
struct SensitiveGate<Content: View>: View {
    @ObservedObject private var lock = AppLock.shared
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        if lock.needsSensitiveUnlock {
            VStack(spacing: 16) {
                Image(systemName: "lock.fill").font(.largeTitle).foregroundStyle(.secondary)
                Button {
                    Task { await lock.unlockSensitive() }
                } label: {
                    Label("Unlock with \(lock.biometryName)", systemImage: "faceid")
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { await lock.unlockSensitive() }
        } else {
            content()
        }
    }
}

struct AppLockSettingsView: View {
    @ObservedObject private var lock = AppLock.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { lock.isEnabled }, set: { value in Task { await lock.setEnabled(value) } })) {
                    Label("Lock with \(lock.biometryName)", systemImage: "faceid")
                }
                .disabled(!lock.canUse)
                if !lock.canUse {
                    Text("Set up Face ID or a passcode in the iPhone Settings first.").font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text("Only on this iPhone. If Face ID does not work, your iPhone passcode unlocks Familoq.")
            }
            if lock.isEnabled {
                Section("Lock") {
                    Picker("What", selection: Binding(get: { lock.scope }, set: { lock.scope = $0 })) {
                        ForEach(AppLock.Scope.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
                    }
                    if lock.scope == .wholeApp {
                        Picker("When", selection: Binding(get: { lock.delay }, set: { lock.delay = $0 })) {
                            ForEach(AppLock.Delay.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
                        }
                    }
                }
            }
            Section {
                Toggle("Hide amounts in the app switcher", isOn: Binding(get: { lock.blurInSwitcher }, set: { lock.blurInSwitcher = $0 }))
            } footer: {
                Text("iOS also has its own lock: long-press the Familoq icon → Require Face ID.")
            }
        }
        .navigationTitle("Face ID lock")
    }
}
