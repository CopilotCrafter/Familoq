import UIKit
import CloudKit
import UserNotifications

/// Receives tapped family invitations (iCloud share links). SwiftUI has no
/// hook for these, so a small scene delegate forwards them to `ShareInbox`.
final class FamiloqAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Must be registered before launching ends (iOS rule).
        BackgroundRefresh.register()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Show reminder/event alerts also while Familoq is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = FamiloqSceneDelegate.self
        return configuration
    }
}

final class FamiloqSceneDelegate: NSObject, UIWindowSceneDelegate {
    /// App was not running: the invitation comes with the launch.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            ShareInbox.shared.pending = metadata
        }
    }

    /// App was running (or in the background).
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        ShareInbox.shared.pending = cloudKitShareMetadata
    }
}

/// A tapped invitation waits here until the app is activated and syncing.
@MainActor
final class ShareInbox: ObservableObject {
    static let shared = ShareInbox()
    @Published var pending: CKShare.Metadata?
}
