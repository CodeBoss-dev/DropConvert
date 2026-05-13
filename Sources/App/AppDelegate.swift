import AppKit
import UserNotifications
import os

private let log = Logger(subsystem: "com.dropconvert", category: "AppDelegate")

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var statusBarController: StatusBarController?
    private var hotkeyManager: HotkeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self

        // Request notification permission once on first launch.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                log.error("notification permission error: \(error.localizedDescription)")
            } else {
                log.info("notification permission granted: \(granted)")
            }
        }

        let controller = StatusBarController()
        statusBarController = controller

        let hotkey = HotkeyManager()
        hotkey.onTriggered = { [weak controller] in
            controller?.handleHotkeyTriggered()
        }
        hotkeyManager = hotkey
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager = nil
        statusBarController = nil
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Deliver notifications even when the app is in the foreground (menu bar apps are always "foreground").
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Handle the "Reveal in Finder" action tap.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }

        guard response.actionIdentifier == NotificationID.revealAction,
              let path = response.notification.request.content.userInfo[NotificationID.outputPathKey] as? String
        else { return }

        let url = URL(fileURLWithPath: path)
        log.info("revealing in Finder: \(path)")
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
