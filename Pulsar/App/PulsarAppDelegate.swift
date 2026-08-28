//
//  PulsarAppDelegate.swift
//  Pulsar
//

import UIKit
import UserNotifications

final class PulsarAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        PulsarWorkoutStartupTrace.lifecycle("applicationDidBecomeActive")
        PulsarWorkoutStartupTrace.diag("[Scene] applicationDidBecomeActive")
    }

    func applicationWillResignActive(_ application: UIApplication) {
        PulsarWorkoutStartupTrace.lifecycle("applicationWillResignActive")
        PulsarWorkoutStartupTrace.diag("[Scene] applicationWillResignActive")
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        PulsarWorkoutStartupTrace.lifecycle("applicationDidEnterBackground")
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        PulsarWorkoutStartupTrace.lifecycle("applicationWillEnterForeground")
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let route = PulsarDeepLinkRoute(
            notificationUserInfo: response.notification.request.content.userInfo
        )

        Task { @MainActor in
            if let route {
                PulsarDeepLinkRouter.shared.open(route)
            }
            completionHandler()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}
